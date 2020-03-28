import std.stdio;
import std.file : dirEntries, isDir, isFile, SpanMode, FileException;
import std.algorithm : sort;
import std.string : split;
import std.process : pipeProcess, Redirect, wait, ProcessException, ProcessPipes;
import vibe.http.server;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.core.core : runApplication;
import vibe.data.json;
import std.stdio;

immutable scriptDirectory = "scripts";

string[string] scripts; // List of available scripts.

string[string] getScripts(string directory)
{
    //TODO scriptname should be the name of the script minus file extensions.

    //The list of scripts should be optionally cached
    //and only updated if a script name is not found
    //when requested.
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

    //There might not be a scriptname if the request is to /
    auto scriptname = req.requestPath.toString()[1 .. $];

    writeln("Running ", scriptname);

    auto scriptPath = findScriptPath(scriptname);
    //This can be nothing.

    //This should handle the exception when a file is not marked executable, with a 404 response.
    // std.process.ProcessException@std/process.d(375): Not an executable file: scripts/not_executable

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
    /* We should pass the input to the script in an expected form. Json, perhaps. */
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

    writeln(output);

    //TODO this should be using a json object, rather than handcoded json.
    res.writeBody("{\"output\":\"" ~ output ~ "\", \"error\":\"" ~ err ~ "\"}",
            "application/json");
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
