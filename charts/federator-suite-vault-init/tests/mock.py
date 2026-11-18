#!/usr/bin/python3
import base64, json, os, pathlib, subprocess, sys
from urllib.parse import urlsplit

tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ["AUDIT_CASE"])
state_path = root / "state.json"
state = json.loads(state_path.read_text())
def save():
    state_path.write_text(json.dumps(state))
def out(value):
    print(json.dumps(value) if not isinstance(value, str) else value)
def error(message="simulated failure"):
    print(message, file=sys.stderr)
    sys.exit(1)
def option(name, default=""):
    return args[args.index(name)+1] if name in args else default
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"tool":tool,"args":args,"address":os.getenv("VAULT_ADDR","")})+"\n")

if tool == "sleep":
    sys.exit(77 if args == ["3600"] else 0)
if tool == "cat":
    if args == ["/var/run/secrets/kubernetes.io/serviceaccount/token"]:
        out("test-kubernetes-token")
    else:
        sys.exit(subprocess.call(["/usr/bin/cat", *args]))
elif tool == "vault":
    if state.get("real"):
        os.execv(os.environ["AUDIT_REAL_VAULT"], [os.environ["AUDIT_REAL_VAULT"], *args])
    command = " ".join(args[:3])
    if args[0] == "status":
        peer = "internal" in os.environ.get("VAULT_ADDR", "")
        if state.get("unreachable") or (peer and state.get("peer_unreachable")): error()
        sealed = state.get("sealed", False)
        if state.get("never_unseal"): sealed = True
        out({"initialized":state.get("initialized",True),"sealed":sealed})
        sys.exit(2 if sealed else 0)
    if args[:2] == ["operator","init"]:
        state.update(initialized=True, sealed=False)
        save()
        out({"root_token":"test-root","unseal_keys_b64":["key1","key2","key3"] if "-key-shares=5" in args else [],"recovery_keys_b64":["recovery1"] if "-recovery-shares=5" in args else []})
    elif args[:2] == ["operator","unseal"]:
        out({"sealed":False})
    elif args[:3] == ["operator","raft","join"]:
        if state.get("join_failure"): error()
        out("joined")
    elif args[:2] == ["token","lookup"]:
        if state.get("sealed") or os.getenv("VAULT_TOKEN") != "test-root": error("token lookup failed")
        out("valid")
    elif args[:2] == ["secrets","list"]:
        out({"secret/":{},"node-net/":{}} if state.get("existing") else {})
    elif args[:2] == ["auth","list"]:
        out({"kubernetes/":{}} if state.get("existing") else {})
    elif args[:2] == ["kv","get"]:
        if state.get("kv_denied"): error("permission denied")
        value = state.get("kv", {})
        if state.get("existing") and not value:
            value = {"valkey_username":"default","valkey_password":"existing-valkey","sentinel_username":"default","sentinel_password":"existing-sentinel"}
        if not value: error("not found")
        out({"data":{"data":value}})
    elif args[:2] == ["kv","put"]:
        state["kv"] = dict(a.split("=",1) for a in args[2:] if "=" in a)
        save()
    elif args[0] == "read" and "-field=password" in args:
        out("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef")
    elif state.get("config_failure"):
        error("configuration failed")
elif tool in ("aws", "az", "gcloud"):
    if tool == "az" and args[0] == "login":
        if state.get("login_failure"): error("identity login failed")
        sys.exit(0)
    get = "get-secret-value" in args or "show" in args or "access" in args
    if get:
        if state.get("get_failure"): error()
        out(state.get("payload",'{"root_token":"test-root"}'))
    else:
        if state.get("set_failure"): error()
        payload = option("--secret-string") if tool == "aws" else option("--value") if tool == "az" else sys.stdin.read()
        json.loads(payload)
        state["payload"] = payload
        save()
elif tool == "curl":
    method = option("-X","GET")
    endpoint = next((a for a in args if a.startswith(("http://", "https://"))), "")
    path = urlsplit(endpoint).path
    if path.startswith("/v1/"):
        if state.get("real"):
            os.execv(os.environ["AUDIT_REAL_CURL"], [os.environ["AUDIT_REAL_CURL"], *args])
        def http_error(message="simulated HTTP failure"):
            out({"errors":[message]})
            print(message, file=sys.stderr)
            sys.exit(22)
        body = option("--data-binary", option("--data", "{}")) or "{}"
        if body.startswith("@"):
            body = pathlib.Path(body[1:]).read_text()
        data = json.loads(body)
        if path == "/v1/sys/seal-status":
            peer = "internal" in endpoint
            if state.get("unreachable") or (peer and state.get("peer_unreachable")): error("connection failed")
            out({"initialized":state.get("initialized",True),"sealed":state.get("sealed",False) or state.get("never_unseal",False)})
        elif path == "/v1/sys/init":
            state.update(initialized=True, sealed=False)
            save()
            out({"root_token":"test-root","keys_base64":[] if "recovery_shares" in data else ["key1","key2","key3"],"recovery_keys_base64":["recovery1"] if "recovery_shares" in data else []})
        elif path == "/v1/sys/unseal":
            out({"sealed":False})
        elif path == "/v1/sys/storage/raft/join":
            if state.get("join_failure"): http_error("Raft join failed")
            out({"data":{"joined":not state.get("join_rejected",False)}})
        elif path == "/v1/auth/token/lookup-self":
            if state.get("sealed") or "X-Vault-Token: test-root" not in args: http_error("token lookup failed")
            out({"data":{"id":"test-root"}})
        elif path == "/v1/sys/mounts":
            out({"data":{"secret/":{},"node-net/":{}} if state.get("existing") else {}})
        elif path == "/v1/sys/auth":
            out({"data":{"kubernetes/":{}} if state.get("existing") else {}})
        elif path == "/v1/secret/data/apps/valkey" and method == "GET":
            if state.get("kv_denied"): http_error("permission denied")
            value=state.get("kv",{})
            if state.get("existing") and not value:
                value={"valkey_username":"default","valkey_password":"existing-valkey","sentinel_username":"default","sentinel_password":"existing-sentinel"}
            if not value: http_error("not found")
            out({"data":{"data":value}})
        elif path == "/v1/secret/data/apps/valkey" and method == "POST":
            if state.get("config_failure"): http_error("configuration failed")
            state["kv"]=data["data"]
            save()
            out({"data":{"version":1}})
        elif path.endswith("/generate"):
            out({"data":{"password":"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"}})
        else:
            if state.get("config_failure"): http_error("configuration failed")
            out("")
        sys.exit(0)
    if method == "GET":
        if state.get("get_failure"): error()
        if state.get("missing_secret"):
            out({"kind":"Status","code":404})
        elif state.get("malformed_base64"):
            out({"data":{"vault-credentials":"%%%%"}})
        else:
            out({"data":{"vault-credentials":base64.b64encode(state.get("payload",'{"root_token":"test-root"}').encode()).decode()}})
    else:
        data = json.loads(option("-d"))
        name = data["metadata"]["name"]
        if state.get("set_failure") or (state.get("cm_failure") and "vault-token" in data["data"]):
            out("500"); sys.exit(0)
        if method == "POST" and state.get("conflict"):
            out("409"); sys.exit(0)
        for key,value in data["data"].items():
            decoded = base64.b64decode(value).decode()
            if key == "vault-credentials":
                json.loads(decoded)
                state["payload"] = decoded
            elif key == "vault-token":
                state["cm_token"] = decoded
        save()
        out("201" if method == "POST" else "200")
else:
    error("unexpected mock tool")
