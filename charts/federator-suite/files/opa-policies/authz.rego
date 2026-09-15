package federator.authz

import future.keywords.if

default allow := false # fail-closed: anything not explicitly allowed below is denied

allow if input.method == "GET" # only safe, read-only requests are allowed by default

# Query with POST /v1/data/federator/authz/allow:
#   {"input": {"method": "GET"}}  -> {"result": true}
#   {"input": {"method": "POST"}} -> {"result": false}
