# lambbaa

Sometimes you just need to have an endpoint with a serving a simple GET or POST response.
Lambbaa makes it possible to quickly selfhost standalone simple scripts to respond to basic requests.

The Lambbaa server accepts POST and GET requests directed at a given scriptname
and passes any data over STDIN to the named script, returning the script's
stdout as the response.

e.g

    GET https://example.com/lambbaa/my_wibble_script

Lambbaa searches for an executable ( in any language ) called
`my_wibble_script`, runs the script, and sends it all the data from the GET request as a JSON
string. 

The script's stdout is returned as the GET response.

If no script is found, lambbaa simply returns a 404.

Post and GET requests are cached to avoid re-running scripts when it isnt nessecary.

## Writing Scripts

Currently, scripts must be placed in the 'scripts' directory under the lambaa executable.
This will change soon.

       lambaa.git/
           |
    lambaa scripts/
             | 
        script1.py script2.py

Scripts can have any name, with or without an extension.
Scripts with an extension will have their route truncated to remove it.
ie. a script called script.py will be available at 127.0.0.1:8080/script

Scripts will recieve the following JSON package through their stdin when a request is made to them:
{"requestMethod", "tls", "headers", "httpVersion", "peer", "files", "username", "password", "query", "contentType", "json"}
The data contained in these records is largely self-explainatory, but I should probably explain it at somepoint (TODO)

Scripts *must* reply to requests using the following JSON package, printed to their stdout:

Standard Output:
{"writeBody": true/false, "contentType": "string", "statusCode": int, "output": "body output string, or JSON object"}

Error Output:
{"error":"string", "statusCode":int}

If the JSON output of a script doesnt match either of the above schemas, lambaa will return 
error 500.

If a script does not write anything to it's stdout, OR it writes to stderr,
that output will be piped into a file of the same name as the script the logs/
directory ( at the same level as scripts/ ).

Scripts must be marked executable, but can be in any language.

Scripts placed in nested directories within the regular scripts directory is not supported at the moment.

