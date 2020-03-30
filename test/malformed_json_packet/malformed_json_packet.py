#!/usr/bin/env python
import json

jout = {"contentType":"application/json", "writeBody": True, } 
# We're missing the 'output' field of the json packet!

stdout.write(json.dumps(jout))
