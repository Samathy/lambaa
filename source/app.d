import std.stdio;
import std.file : dirEntries, isDir, isFile, SpanMode, FileException;
import std.algorithm : sort;
import std.string : split;
import std.process : pipeProcess, Redirect, wait, ProcessException, ProcessPipes;
import std.range : empty;
import vibe.http.server;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.status : HTTPStatus, httpStatusText;
import vibe.core.core : runApplication;
import vibe.data.json;

immutable scriptDirectory = "scripts";

string[string] scripts; // List of available scripts.

string[string] getScripts(string directory)
{
    string[string] scripts;

    foreach (string file; dirEntries(directory, SpanMode.breadth))
    {
        if (isFile(file))
        {
            scripts[file.split("/")[$ - 1].split(".")[0]] = file;
            continue;
        }
        else if (isDir(file))
        {
            auto scriptsInDirectory = getScripts(file);

            foreach (string scriptname; scriptsInDirectory)
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
        return scripts[scriptname.split(".")[0]];
    else
        scripts = getScripts(scriptDirectory);
    if (scriptname in scripts)
        return scripts[scriptname.split(".")[0]];
    else
        throw new FileException("No such file");
}

void handler(scope HTTPServerRequest req, scope HTTPServerResponse res)
{

    //TODO switch writelns to debugs

    if ( req.requestPath.toString() == "/" )
    {
        res.statusCode = HTTPStatus.notFound;
        res.statusPhrase = httpStatusText(res.statusCode);
        res.writeBody(res.statusPhrase);
        return;

    }
    auto scriptname = req.requestPath.toString()[1 .. $];

    writeln("Running ", scriptname);

    auto scriptPath = findScriptPath(scriptname);
    /*This can be nothing. We need to handle if the script isnt found a bit better.
      than just catching the exception. */

    ProcessPipes pipes;
    try
    {
        pipes = pipeProcess(scriptPath, Redirect.stdin | Redirect.stdout | Redirect.stderr);
    }
    catch (ProcessException)
    {
        writeln("Could not run script ", scriptname);
        res.statusCode = 404;
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

    //These two might be broken atm, they only seem to be storing the first line of output.
    string output;
    foreach (line; pipes.stdout.byLine)
        output ~= line.idup;

    string err;
    foreach (line; pipes.stdout.byLine)
        output ~= line.idup;

    //We need to have some handling here if the script has no output, 
    //or has only error output.

    //if the script has only error output. 
    //Send an internal sever error, and log the output.

    //We need to validate that the output json contains the data we expect it too.

    Json jsonOutput = Json.emptyObject();

    if (output.empty)
    {
        jsonOutput["statusCode"] = HTTPStatus.internalServerError;
        jsonOutput["writeBody"] = false; //XXX Remove when the below is re-ordered
    }
    else
        jsonOutput = parseJsonString(output);

    /* This should really be checking the status code _first_ rather than 
    relying on writeBody to indicate if an error occured. */
    if (jsonOutput["writeBody"].get!bool == true)
    {
        //What happens if the output is itself a json object?
        res.writeBody(jsonOutput["output"].get!string, jsonOutput["contentType"].get!string);
    }
    else
    {
        if ("statusCode" in jsonOutput)
            res.statusCode = jsonOutput["statusCode"].get!int;
        else
            res.statusCode = HTTPStatus.internalServerError;

        if ("error" in jsonOutput)
            res.writeBody(jsonOutput["error"].get!string);
        else
            res.statusPhrase = httpStatusText(res.statusCode);
        res.writeBody(res.statusPhrase);
        writeln(res.statusCode);
        writeln(res.statusPhrase);
    }

    return;
}

int main()
{

    auto settings = new HTTPServerSettings;
    settings.port = 8080;
    settings.bindAddresses = ["::1", "127.0.0.1"];

    auto router = new URLRouter;

    router.get("*", &handler);

    auto listener = listenHTTP(settings, router);

    scope (exit)
        listener.stopListening();

    runApplication();

    return 0;
}
