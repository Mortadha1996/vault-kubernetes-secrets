# Vault on Kubernetes: Scoped Secrets

This project demonstrates how to securely inject secrets from HashiCorp Vault into a Kubernetes pod using the Vault Agent Injector, Kubernetes Auth, and a scoped policy. It also covers dynamic TLS certificates (PKI/mTLS) and dynamic AWS credentials.

## What this demonstrates

- **Kubernetes Auth**: The pod authenticates to Vault using its ServiceAccount token.
- **Scoped Policy**: The issued Vault token is limited to a single path (`kv/data/myapp/config`) and the PKI issue path, with a 1-hour TTL.
- **Agent Injection**: A sidecar container writes the secret to an in-memory volume at `/vault/secrets/config.env`.
- **Dynamic PKI (mTLS)**: The sidecar requests a short-lived TLS certificate (`CN=myapp.local`) and its private key, signed by Vault's internal CA.
- **Dynamic AWS Credentials**: Configuration of the AWS secrets engine to create temporary IAM users with a minimal policy.

## The three core tests (KV & Auth)

### 1. The secret arrives in the pod, but not in the manifest
```bash
kubectl -n demo exec deploy/myapp -c app -- cat /vault/secrets/config.env
# DB_PASSWORD=s3cr3t-demo
# API_KEY=demo-key

kubectl -n demo get deploy myapp -o yaml | grep -ci "s3cr3t"    # 0
kubectl -n demo get secrets                                      # No resources found
