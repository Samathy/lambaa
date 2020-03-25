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

