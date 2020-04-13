#!/usr/bin/env python
import json

reply = {"writeBody":True, "contentType":"text/plain", "statusCode": 200, "output": "This was successful"}

print(json.dumps(reply))
