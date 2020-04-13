import std.algorithm : sort;
import std.algorithm.searching : canFind;
import std.file : dirEntries, isDir, isFile, isSymlink, SpanMode, FileException;
import std.getopt;
import std.process : pipeProcess, Redirect, wait, ProcessException, ProcessPipes;
import std.range : empty;
import std.stdio;
import std.string : split, format;
import std.datetime: Clock, SysTime;
import vibe.http.server;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.status : HTTPStatus, httpStatusText;
import vibe.core.core : runApplication;
import vibe.data.json;
import vibe.core.args: setCommandLineArgs;

string scriptDirectory = "scripts";
string logDirectory = "logs";
ushort port = 8686;

immutable int[] noBodyStatusCodes = [100, 101, 102, 103, 201, 204, 205];

string[string] scripts; // List of available scripts.

string[] jsonStandardOutputFields = [
    "writeBody", "contentType", "statusCode", "output"
];
string[] jsonErrorOutputFields = ["error", "statusCode"];

enum jsonOutputType
{
    OK = 1,
    ERR = 2,
    INVALID = 3
}

string[string] getScripts(string directory)
{
    foreach (string file; dirEntries(directory, SpanMode.breadth))
    {
        if (isFile(file) || isSymlink(file))
        {
            scripts[file.split("/")[$ - 1].split(".")[0]] = file;
            continue;
        }

        else if (isDir(file))
        {
            auto scriptsInDirectory = getScripts(file);

            foreach (string scriptname; scriptsInDirectory.keys)
            {
                scripts[scriptname] = scriptsInDirectory[scriptname];
            }
            continue;
        }

    }

    return scripts;

}

string findScriptPath(string scriptname)
{
    if (scriptname in scripts)
    {
        return scripts[scriptname.split(".")[0]];
    }
    else
        scripts = getScripts(scriptDirectory);
    if (scriptname in scripts)
        return scripts[scriptname.split(".")[0]];
    else
        throw new FileException("No such file");
}

int validateJsonOutput(Json output)
{
    /* This currently only checks that fields exist, 
    not that they contain the right datatypes. */

    bool isStandard = true;
    foreach (field; jsonStandardOutputFields)
    {
        if (field !in output)
        {
            isStandard = false;
            break;
        }
    }

    if (isStandard)
    {
        return jsonOutputType.OK;
    }

    foreach (field; jsonErrorOutputFields)
    {
        if (field !in output)
        {
            return jsonOutputType.INVALID;
        }
    }

    return jsonOutputType.ERR;

}

unittest
{
    Json j = Json.emptyObject();
    j["writeBody"] = "";
    j["contentType"] = "";
    j["statusCode"] = 0;
    j["output"] = "";

    assert(validateJsonOutput(j) == jsonOutputType.OK);

    j = Json.emptyObject();
    j["error"] = "";
    j["statusCode"] = 0;

    assert(validateJsonOutput(j) == jsonOutputType.ERR);

    j = Json.emptyObject();
    j["statusCode"] = 0;

    assert(validateJsonOutput(j) == jsonOutputType.INVALID);

    j = Json.emptyObject();
    j["writeBody"] = "";
    j["contentType"] = "";
    j["output"] = "";

    assert(validateJsonOutput(j) == jsonOutputType.INVALID);

    j = Json.emptyObject();
    j["writeBody"] = "";
    j["contentType"] = "";
    j["statusCode"] = 0;
    j["output"] = "";
    j["error"] = "";

    assert(validateJsonOutput(j) == jsonOutputType.OK);

}

void handler(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
    //TODO switch writelns to debugs

    writeln(format("[%s] ", req.timeCreated.toString()));
    writeln(format(req.toString()));
    writeln(format("Peer: %s", req.peer));

    void endLog()
    {
        writeln(format("[%s] Request for %s complete ", Clock.currTime.toUTC(), req.peer));
    }

    scope(exit)
        endLog();


    string scriptPath;
    auto scriptname = req.requestPath.toString()[1 .. $];

    writeln("Running ", scriptname);

    if (req.requestPath.toString() == "/")
    {
        try{
            scriptPath = findScriptPath("home");
        }
        catch (FileException)
        {
            res.statusCode = HTTPStatus.notFound;
            res.statusPhrase = httpStatusText(res.statusCode);
            res.writeBody(res.statusPhrase);
            return;
        }

    }
    else
    {
        try
        {
            scriptPath = findScriptPath(scriptname);
        }
        catch (FileException)
        {
            writeln("No scripts called " ~ scriptname);
            res.statusCode = HTTPStatus.notFound;
            res.statusPhrase = httpStatusText(res.statusCode);
            res.writeBody(res.statusPhrase);
            return;
        }
    }

    ProcessPipes pipes;
    try
    {
        pipes = pipeProcess(scriptPath, Redirect.stdin | Redirect.stdout | Redirect.stderr);
    }
    catch (ProcessException)
    {
        writeln("Could not run script ", scriptname);
        res.statusCode = HTTPStatus.notFound;
        res.statusPhrase = httpStatusText(res.statusCode);
        res.writeBody(res.statusPhrase);
        return;
    }

    scope (exit)
        wait(pipes.pid);

    /* Script input should be optionally cached, checked against previous inputs, 
      and the expected output given if matches found. */
    if (req.method.POST)
    {
        Json input = Json.emptyObject();
        input["requestMethod"] = req.method;
        input["tls"] = req.tls;
        input["headers"] = serializeToJson(req.headers);
        input["httpVersion"] = req.httpVersion;
        input["peer"] = req.peer;
        input["files"] = serializeToJson(req.files);
        input["username"] = req.username;
        input["password"] = req.password;
        input["query"] = serializeToJson(req.query);
        input["contentType"] = req.contentType;
        input["json"] = req.json;

        pipes.stdin.write(input.toString());
    }

    string output;
    foreach (line; pipes.stdout.byLine)
        output ~= line.idup;

    string err;
    foreach (line; pipes.stderr.byLine)
        err ~= line.idup;

    Json jsonOutput = Json.emptyObject();

    if (output.empty || err.length > 0)
    {
        writeln(format("Script %s outputted an error", scriptname));
        if (err.length > 0)
        {
            string errorLogFile = logDirectory ~ "/" ~ scriptname;
            auto log = File(errorLogFile, "a");
            log.write(format("[%s] %s \n", req.timeCreated.toString(), err));
            log.write(format(req.toString()));
            log.close();
        }
        res.statusCode = HTTPStatus.internalServerError;
        res.statusPhrase = httpStatusText(res.statusCode);
        res.writeBody(res.statusPhrase);
        return;
    }
    else
        jsonOutput = parseJsonString(output);

    int jsonValidationResult = validateJsonOutput(jsonOutput);

    /* Some http statuses don't require a body. Some statuses do.
       e.g the errors still require a body.
       We need to do some checking of the returned statusCode
       so that we can send a body, or not as required */
    if (jsonValidationResult == jsonOutputType.ERR)
    {
        res.statusCode = jsonOutput["statusCode"].get!int;

        if (!canFind(noBodyStatusCodes, res.statusCode))
        {
            if (!jsonOutput["error"].get!string.empty)
                res.writeBody(jsonOutput["error"].get!string);
            else
                res.statusPhrase = httpStatusText(res.statusCode);

            res.writeBody(res.statusPhrase);
        }
        else
        {
            res.writeVoidBody();
        }

    }
    else if (jsonValidationResult == jsonOutputType.OK)
    {
        if (jsonOutput["writeBody"].get!bool == true)
        {
            try
            {
                if (jsonOutput["contentType"] == "application/json")
                {
                    jsonOutput["output"].toString();
                    res.writeBody(jsonOutput["output"].toString(),
                            jsonOutput["contentType"].get!string);
                }
                else
                {
                    res.writeBody(jsonOutput["output"].get!string,
                            jsonOutput["contentType"].get!string);
                }

                res.statusCode = jsonOutput["statusCode"].get!int;
                res.statusPhrase = httpStatusText(res.statusCode);
            }
            catch (JSONException e)
            {
                writeln("Caught Json Exception while writing response.\n",
                        "This normally means that the script sent ",
                        "badly formed json back to the lambaa server.");
                writeln(format("\"%s\"", e.message));
                res.statusCode = HTTPStatus.internalServerError;
                res.statusPhrase = httpStatusText(res.statusCode);
                res.writeBody(res.statusPhrase);
                return;
            }
            catch (Throwable e)
            {
                writeln("Caught exception while writing response");
                writeln(e.message);
                res.statusCode = HTTPStatus.internalServerError;
                res.statusPhrase = httpStatusText(res.statusCode);
                res.writeBody(res.statusPhrase);
                return;
            }

        }
        else
        {
            res.statusCode = jsonOutput["statusCode"].get!int;
            res.statusPhrase = httpStatusText(res.statusCode);
            res.writeBody(res.statusPhrase);
        }

    }
    else if (jsonValidationResult == jsonOutputType.INVALID)
    {
        writeln("Script output is not valid");
        res.statusCode = HTTPStatus.internalServerError;
        res.statusPhrase = httpStatusText(res.statusCode);
        res.writeBody(res.statusPhrase);
        return;

    }

    return;
}

int main(string[] args)
{
    writeln(scriptDirectory);
    writeln(port);
    writeln(logDirectory);

    auto help = getopt(args, "port", &port, "script-directory",
            &scriptDirectory, "log-directory", &logDirectory);

    if (help.helpWanted)
    {
        defaultGetoptPrinter("lamba server", help.options);
    }

    writeln("Looking for scripts in: " ~ scriptDirectory);
    writeln("Logging to: " ~ logDirectory);
    
    setCommandLineArgs = args;



    auto settings = new HTTPServerSettings;
    settings.port = port;
    settings.bindAddresses = ["::1", "127.0.0.1"];

    auto router = new URLRouter;

    router.get("*", &handler);

    auto listener = listenHTTP(settings, router);

    scope (exit)
        listener.stopListening();

    runApplication();

    return 0;
}
