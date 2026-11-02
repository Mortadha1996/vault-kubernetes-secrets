# Vault on Kubernetes: Scoped Secrets

A Kubernetes Secret is base64, not encryption. Anyone who can read Secrets in a namespace can decode them:

```bash
kubectl get secret db-password -o jsonpath='{.data.password}' | base64 -d
```

This repo shows what changes when the pod gets its secret from HashiCorp Vault instead. It runs on a local k3d cluster and every claim below comes with the command that proves it.

> **Dev mode.** Vault runs in dev mode (in-memory storage, known root token). That is fine for a lab and wrong for production. See [Dev mode is not production](#dev-mode-is-not-production).

---

## What this demonstrates

| Topic | What is shown |
|---|---|
| **Kubernetes auth** | The pod proves its identity with its ServiceAccount token. Vault verifies it with the Kubernetes API. |
| **Scoped policy** | The token Vault issues has a 1-hour TTL and can read one path only. |
| **Agent injection** | A sidecar writes the secret to an in-memory volume. It is not in the Deployment YAML, not in Git, not in a Kubernetes Secret. |
| **Rejection** | A different ServiceAccount using the same role is refused with a 403. |
| **Audit log** | Every read is logged: who, what, when. |
| **Short-lived TLS certificates** | Vault PKI issues a certificate valid for 24 hours. |

---

## How it works

```
 Pod (ServiceAccount: myapp)
   │  1. sends its ServiceAccount token
   ▼
 Vault ──2. asks the Kubernetes API: is this token valid, and whose is it? ──► Kubernetes
   │
   │  3. token valid + role "myapp" matches → issues a Vault token
   │     (TTL 1h, policy: read one path)
   ▼
 Vault Agent sidecar ──4. reads the secret──► /vault/secrets/config.env  (in-memory volume)
```

The application container never holds a Vault credential. It reads a file.

---

## Run it

Prerequisites: Docker, `kubectl`, `helm`, `k3d`.

```bash
# 1. Local cluster
k3d cluster create vault-lab
kubectl get nodes

# 2. Vault in dev mode, with the agent injector
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault -n vault --create-namespace \
  --set server.dev.enabled=true \
  --set server.dev.devRootToken=root \
  --set injector.enabled=true
kubectl -n vault get pods -w          # wait for vault-0 and the injector: Running

# 3. Configure Vault (secret, auth method, policy, role, audit)
#    See config/ for the exact commands and the policy file.

# 4. Deploy the demo application
kubectl apply -f manifests/
kubectl -n demo get pods -w           # 2/2 = app + vault-agent sidecar
```

If the pod stays at `1/1`, the injector was not ready when it started:

```bash
kubectl -n demo delete pod -l app=myapp
```

---

## Tests

### 1. The secret reaches the pod but not the manifest

```bash
kubectl -n demo exec deploy/myapp -c app -- cat /vault/secrets/config.env
# DB_PASSWORD=s3cr3t-demo
# API_KEY=demo-key

kubectl -n demo get deploy myapp -o yaml | grep -ci "s3cr3t"    # 0
kubectl -n demo get secrets                                      # No resources found
```

The values are demo values, not real credentials.

### 2. The right ServiceAccount gets a limited token

```bash
TOKEN=$(kubectl -n demo create token myapp)
kubectl -n vault exec vault-0 -- vault write auth/kubernetes/login role=myapp jwt="$TOKEN"
```

```
Key                                       Value
---                                       -----
token_duration                            1h
token_policies                            ["default" "myapp-policy"]
token_meta_service_account_name           myapp
token_meta_service_account_namespace      demo
token_meta_role                           myapp
```

(The token itself is removed.)

### 3. Another ServiceAccount is refused

```bash
kubectl -n demo create sa intruder
TOKEN=$(kubectl -n demo create token intruder)
kubectl -n vault exec vault-0 -- vault write auth/kubernetes/login role=myapp jwt="$TOKEN"
```

```
Error writing data to auth/kubernetes/login: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/auth/kubernetes/login
Code: 403. Errors:

* service account name not authorized
```

### 4. The audit log shows who read what

```bash
kubectl -n vault logs vault-0 | grep '"type":"request"' | tail -3
```

```
{"auth":{"display_name":"kubernetes-demo-myapp","policies":["default","myapp-policy"]},"request":{"operation":"read","path":"kv/data/myapp/config"},"time":"2026-11-01T16:09:55Z","type":"request"}
{"auth":{"display_name":"root","policies":["root"]},"request":{"operation":"update","path":"auth/kubernetes/login"},"time":"2026-11-01T16:11:19Z","type":"request"}
{"auth":{"display_name":"root","policies":["root"]},"request":{"operation":"update","path":"auth/kubernetes/login"},"time":"2026-11-01T16:11:24Z","type":"request"}
```

Abridged. The first line is the app reading its secret. The two `root` lines are my own login tests: I ran them from `vault-0` with the root token, so the log shows `root`, not the `intruder` ServiceAccount.

---

## Short-lived TLS certificates (Vault PKI)

Vault acts as an internal CA and signs a certificate on request. Check what was issued:

```bash
kubectl -n demo exec deploy/myapp -c app -- cat /vault/secrets/tls.crt \
  | openssl x509 -noout -subject -issuer -dates
```

```
subject=CN = myapp.local
issuer=CN = myvault.local
notBefore=Nov  1 20:39:15 2026 GMT
notAfter=Nov  2 20:39:45 2026 GMT
```

`myvault.local` is the lab's own root CA.

> Issuing a certificate is not mutual TLS. mTLS means both sides present a certificate and verify the other's. This repo shows issuance and short expiry. It does not (yet) show a connection that fails without a client certificate and succeeds with one.

---

## What this does not protect against

If an attacker gets code execution inside the pod, they can read that pod's secret and log in to Vault again for as long as the pod runs. The token expiring after an hour does not stop that.

What changes:

- the blast radius is one role and one path
- credentials expire and can be revoked
- there is an audit trail of who read what
- the value is not in Git, in the manifest, or in etcd as a Kubernetes Secret

---

## Dev mode is not production

| This lab | Production needs |
|---|---|
| In-memory storage, lost on restart | Integrated Raft storage in HA |
| Auto-unsealed | Auto-unseal through a KMS or HSM |
| Root token set to `root` | No long-lived root token; operators authenticate through an auth method |
| No TLS on Vault | TLS everywhere |
| Audit log to the pod's stdout | Audit logs shipped off the cluster and retained |

---

## Next

- [ ] Dynamic AWS credentials (Vault AWS secrets engine): first attempt failed with `InvalidClientTokenId`, the IAM key given to Vault was invalid
- [ ] A connection that fails without a client certificate and succeeds with one (real mTLS)
- [ ] Integrated Raft storage with auto-unseal
- [ ] Secret rotation without restarting the pod

---

## Author

**Mortadha Riahi**, Infrastructure & Platform Engineer

[LinkedIn](https://www.linkedin.com/in/mortadha-riahi/) · [AWS HA architecture](https://github.com/Mortadha1996/aws-ha-architecture) · [Secrets detection pipeline](https://github.com/Mortadha1996/secrets-detection-pipeline) · [LLM inference platform](https://github.com/Mortadha1996/llm-inference-platform)
