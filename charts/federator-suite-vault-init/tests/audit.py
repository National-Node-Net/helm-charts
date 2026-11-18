import json, os, pathlib, shutil, socket, subprocess, tempfile, time

ROOT = pathlib.Path(tempfile.mkdtemp(prefix="vault-path-audit-"))
REPO = pathlib.Path(__file__).resolve().parents[3]
MOCK = pathlib.Path(__file__).with_name("mock.py")
REAL_VAULT = shutil.which("vault")
REAL_CURL = shutil.which("curl")
if not REAL_VAULT or not REAL_CURL:
    raise SystemExit("Install vault, curl, helm, jq, and Mike Farah yq before running this audit")
CHART = REPO / "charts/federator-suite"
VALUES = ["common-values","kafka","valkey","vault","certificate-manager","opa","federator","valkey-ui","istio"]
BASE = ["helm","template","audit",str(CHART)]
for name in VALUES: BASE += ["-f",str(CHART/"values"/(name+".yaml"))]
BASE += ["--set","vault.devMode=true","--set","vault.secretsManager.secretName=audit-secret","--set","certificateManager.image.tag=test"]
BIN = ROOT/"bin"
BIN.mkdir(exist_ok=True)
for tool in ("vault","aws","az","gcloud","curl","cat","sleep"):
    target=BIN/tool
    if not target.exists(): target.symlink_to(MOCK)
MOCK.chmod(0o755)
results=[]
def check(name, passed, detail=""):
    results.append({"test":name,"passed":bool(passed),"detail":detail})
    print(("PASS " if passed else "FAIL ")+name+(": "+detail if detail else ""),flush=True)
def render(static=True, external=False, replicas=1):
    cmd=BASE+["--set","vault.setup.enabled=true","--set",f"vault.staticSecrets.enabled={str(static).lower()}","--set",f"valkey.external={str(external).lower()}","--set",f"vault.vault.server.ha.replicas={replicas}"]
    raw=subprocess.check_output(cmd,text=True)
    objects=[json.loads(line) for line in subprocess.check_output(["yq","-o=json","-I=0","."],input=raw,text=True).splitlines() if line]
    objects=[o for o in objects if isinstance(o,dict)]
    scripts=[o for o in objects if o.get("kind")=="ConfigMap" and o["metadata"]["name"]=="vault-setup-script"]
    selected=[o for o in scripts if "lib.sh" in o.get("data",{})][0]
    library=selected["data"]["lib.sh"]
    subprocess.run(["sh","-n"],input=library,text=True,check=True)
    (ROOT/"lib.sh").write_text(library.replace("/scripts/",str(ROOT)+"/").replace("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt","/etc/ssl/certs/ISRG_Root_X1.pem"))
    policy=[o for o in objects if o.get("kind")=="ConfigMap" and o["metadata"]["name"]=="vault-init-policys"][0]
    return selected["data"]["vault-setup.sh"],policy["data"],scripts

scripts={}
for static in (False,True):
    for external in (False,True):
        script,policies,duplicate=render(static,external)
        syntax=subprocess.run(["sh","-n"],input=script,text=True,capture_output=True)
        check(f"render/syntax static={static} external={external}",syntax.returncode==0)
        check(f"policy projection keys static={static} external={external}",("valkey-password.hcl" in policies)==(not external) and ("federator-suite-client-server-vault-reader.hcl" in policies)==static)
        scripts[static,external]=script
        for name,contents in policies.items(): (ROOT/name).write_text(contents)
check("only one setup ConfigMap in full chart",len(duplicate)==1,f"found {len(duplicate)} with name vault-setup-script")
def run(name,provider="local",state=None,script=None,env=None,expected=77):
    case=ROOT/name
    case.mkdir(exist_ok=True)
    initial=dict(state or {})
    (case/"state.json").write_text(json.dumps(initial))
    contents=(script or scripts[True,False]).replace("/scripts/",str(ROOT)+"/").replace("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt","/etc/ssl/certs/ISRG_Root_X1.pem")
    (case/"setup.sh").write_text(contents)
    environ=os.environ.copy()
    environ.update(PATH=str(BIN)+":"+environ["PATH"],AUDIT_CASE=str(case),AUDIT_REAL_VAULT=REAL_VAULT,AUDIT_REAL_CURL=REAL_CURL,HOSTNAME="audit-vault-0",CLOUD_PROVIDER=provider,GCP_PROJECT="audit-project",AZURE_VAULT_NAME="audit-vault")
    environ.update(env or {})
    result=subprocess.run(["sh",str(case/"setup.sh")],env=environ,text=True,capture_output=True,timeout=35)
    (case/"output.log").write_text(result.stdout+result.stderr)
    final=json.loads((case/"state.json").read_text())
    calls=[json.loads(line) for line in (case/"calls.jsonl").read_text().splitlines()] if (case/"calls.jsonl").exists() else []
    passed=result.returncode==expected if isinstance(expected,int) else result.returncode not in (0,77)
    check(name,passed,f"exit={result.returncode}")
    return result,final,calls

def is_valkey_write(call):
    return call["tool"]=="curl" and "POST" in call["args"] and any(arg.endswith("/v1/secret/data/apps/valkey") for arg in call["args"])

for provider in ("local","aws","azure","gcp"):
    r,state,calls=run(provider+"-initialize",provider,{"initialized":False,"sealed":False})
    check(provider+"-uses-http-without-vault-cli",not any(c["tool"]=="vault" for c in calls))
    check(provider+"-stored-original-credentials",json.loads(state.get("payload","{}")).get("root_token")=="test-root")
    if provider=="local": check("local-set-also-writes-certificate-token",state.get("cm_token")=="test-root")
    r,state,calls=run(provider+"-already-initialized",provider,{"existing":True})
    check(provider+"-existing-valkey-not-overwritten",not any(is_valkey_write(c) for c in calls))
    run(provider+"-get-failure",provider,{"get_failure":True},expected="failure")
    run(provider+"-set-failure",provider,{"initialized":False,"set_failure":True},expected="failure")
    run(provider+"-invalid-json",provider,{"payload":"bad-json"},expected="failure")
    run(provider+"-missing-root-token",provider,{"payload":"{}"},expected="failure")
run("local-conflict-updates",state={"initialized":False,"conflict":True})
run("local-missing-secret",state={"missing_secret":True},expected="failure")
run("local-invalid-base64",state={"malformed_base64":True},expected="failure")
run("local-second-secret-write-fails",state={"initialized":False,"cm_failure":True},expected="failure")
run("local-restart-sealed",state={"sealed":True,"existing":True},expected=77)
run("azure-missing-vault",provider="azure",env={"AZURE_VAULT_NAME":""},script=scripts[True,False].replace("PLACEHOLDER_KEYVAULT_NAME",""),expected="failure")
run("gcp-missing-project",provider="gcp",env={"GCP_PROJECT":""},script=scripts[True,False].replace("PLACEHOLDER_PROJECT",""),expected="failure")
r,state,calls=run("gcp-project-from-resource-name",provider="gcp",env={"GCP_PROJECT":"","SECRETS_MANAGER_SECRET_NAME":"projects/audit-project/secrets/audit-secret"},script=scripts[True,False].replace("PLACEHOLDER_PROJECT",""))
run("bad-provider",provider="invalid",expected="failure")
run("missing-backend-name",env={"SECRETS_MANAGER_SECRET_NAME":""},script=scripts[True,False].replace('audit-secret',''),expected="failure")
run("nonzero-ordinal",env={"HOSTNAME":"audit-vault-1"})
run("vault-unreachable-timeout",state={"unreachable":True},expected="failure")
run("auto-unseal-timeout",provider="aws",state={"initialized":False,"never_unseal":True},expected="failure")
run("bad-root-token",state={"payload":'{"root_token":"wrong"}'},expected="failure")
run("vault-configuration-failure",state={"config_failure":True},expected="failure")
for static in (False,True):
    for external in (False,True):
        run(f"optional-static-{static}-external-{external}",script=scripts[static,external])
for field in ("valkey_username","valkey_password","sentinel_username","sentinel_password"):
    value={"valkey_username":"user","valkey_password":"keep-valkey","sentinel_username":"sentinel","sentinel_password":"keep-sentinel"}
    del value[field]
    r,state,calls=run("partial-"+field,state={"kv":value})
    check("preserve-other-fields-"+field,all(state["kv"].get(k)==v for k,v in value.items()))
r,state,calls=run("valkey-read-permission-denied",state={"kv_denied":True})
check("valkey-read-error-does-not-write-new-passwords",not any(is_valkey_write(c) for c in calls))
peer_script=render(replicas=3)[0]
for mode in ({},{"peer_unreachable":True},{"join_failure":True}):
    name="raft-"+("join-failure" if mode.get("join_failure") else "unreachable" if mode else "success")
    run(name,state=mode,script=peer_script)

# Real Vault: fresh Shamir init and an actual seal/restart, with only Kubernetes mocked.
sock=socket.socket(); sock.bind(("127.0.0.1",0)); port=sock.getsockname()[1]; sock.close()
config=ROOT/"vault.hcl"
config.write_text('disable_mlock = true\nstorage "inmem" {}\nlistener "tcp" {\n address = "127.0.0.1:'+str(port)+'"\n tls_disable = true\n}\napi_addr = "http://127.0.0.1:'+str(port)+'"\n')
server_log=(ROOT/"server.log").open("w")
server=subprocess.Popen([REAL_VAULT,"server","-config="+str(config)],stdout=server_log,stderr=server_log)
try:
    vault_env=dict(os.environ,VAULT_ADDR="http://127.0.0.1:"+str(port))
    for attempt in range(60):
        if subprocess.run([REAL_VAULT,"status"],env=vault_env,capture_output=True).returncode==2: break
        time.sleep(.1)
    real_script=scripts[True,False].replace("http://localhost:8200",vault_env["VAULT_ADDR"])
    r,state,calls=run("real-vault-fresh-init",state={"real":True},script=real_script)
    payload=state.get("payload","")
    root_token=json.loads(payload)["root_token"]
    vault_env["VAULT_TOKEN"]=root_token
    before=subprocess.check_output([REAL_VAULT,"kv","get","-format=json","-mount=secret","apps/valkey"],env=vault_env,text=True)
    r,state,calls=run("real-vault-repeat-run",state={"real":True,"payload":payload},script=real_script)
    after=subprocess.check_output([REAL_VAULT,"kv","get","-format=json","-mount=secret","apps/valkey"],env=vault_env,text=True)
    check("real-vault-repeat-does-not-rotate-passwords",json.loads(before)["data"]["data"]==json.loads(after)["data"]["data"])
    subprocess.run([REAL_VAULT,"operator","seal"],env=vault_env,check=True,capture_output=True)
    run("real-vault-sealed-restart",state={"real":True,"payload":payload},script=real_script,expected=77)
finally:
    server.terminate()
    server.wait(timeout=10)
    server_log.close()

# Exercise the cloud init payload against a real auto-unseal implementation.
# Transit supplies the seal locally; cloud credential storage stays mocked.
def free_port():
    sock=socket.socket()
    sock.bind(("127.0.0.1",0))
    port=sock.getsockname()[1]
    sock.close()
    return port

transit_port=free_port()
auto_port=free_port()
transit_address="http://127.0.0.1:"+str(transit_port)
auto_address="http://127.0.0.1:"+str(auto_port)
transit_log=(ROOT/"transit.log").open("w")
auto_log=(ROOT/"auto-unseal.log").open("w")
transit=subprocess.Popen([REAL_VAULT,"server","-dev","-dev-listen-address=127.0.0.1:"+str(transit_port),"-dev-root-token-id=test-transit-token"],stdout=transit_log,stderr=transit_log)
auto=None
try:
    transit_env=dict(os.environ,VAULT_ADDR=transit_address,VAULT_TOKEN="test-transit-token")
    for attempt in range(60):
        if subprocess.run([REAL_VAULT,"status"],env=transit_env,capture_output=True).returncode==0: break
        time.sleep(.1)
    subprocess.run([REAL_VAULT,"secrets","enable","transit"],env=transit_env,check=True,capture_output=True)
    subprocess.run([REAL_VAULT,"write","-f","transit/keys/autounseal"],env=transit_env,check=True,capture_output=True)
    auto_config=ROOT/"auto-unseal.hcl"
    auto_config.write_text('disable_mlock = true\nstorage "inmem" {}\nlistener "tcp" {\n address = "127.0.0.1:'+str(auto_port)+'"\n tls_disable = true\n}\napi_addr = "'+auto_address+'"\nseal "transit" {\n address = "'+transit_address+'"\n token = "test-transit-token"\n key_name = "autounseal"\n mount_path = "transit/"\n disable_renewal = "true"\n}\n')
    auto=subprocess.Popen([REAL_VAULT,"server","-config="+str(auto_config)],stdout=auto_log,stderr=auto_log)
    for attempt in range(60):
        if subprocess.run([REAL_VAULT,"status"],env=dict(os.environ,VAULT_ADDR=auto_address),capture_output=True).returncode==2: break
        time.sleep(.1)
    auto_script=scripts[True,False].replace("http://localhost:8200",auto_address)
    r,state,calls=run("real-vault-auto-unseal-init",provider="aws",state={"real":True},script=auto_script)
    credentials=json.loads(state.get("payload","{}"))
    check("real-auto-unseal-recovery-key-schema",len(credentials.get("recovery_keys_b64",[]))==5 and credentials.get("unseal_keys_b64")==[])
finally:
    if auto is not None:
        auto.terminate()
        auto.wait(timeout=10)
    transit.terminate()
    transit.wait(timeout=10)
    auto_log.close()
    transit_log.close()

(ROOT/"results.json").write_text(json.dumps(results,indent=2))
print(f"RESULT: {sum(r['passed'] for r in results)}/{len(results)} checks passed; evidence in {ROOT}",flush=True)

raise SystemExit(0 if all(result["passed"] for result in results) else 1)
