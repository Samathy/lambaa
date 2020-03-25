import std.stdio;
import std.file : dirEntries, isDir;
import std.algorithm : sort;
import std.string : split;
import vibe.http.server;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.core.core : runApplication;
import std.stdio;

void handler ( scope HTTPServerRequest req, scope HTTPServerResponse res)
{

    auto scriptname = req.requestPath.toString()[1 .. $];

    writeln("Running ", scriptname);

    //get script name from request
    //Search for script by name
    //Potential caching here.
    //run script
    //return stdout from script

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
