#!/usr/bin/env bash
set -euo pipefail
VAULT_TOKEN=${VAULT_TOKEN:?}
vexec() { kubectl -n vault exec vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" "$@"; }

vexec vault secrets enable pki || true
vexec vault secrets tune -max-lease-ttl=87600h pki
vexec vault write pki/root/generate/internal common_name="myvault.local" ttl=87600h
vexec vault write pki/config/urls issuing_certificates="http://vault.vault.svc:8200/v1/pki/ca" crl_distribution_points="http://vault.vault.svc:8200/v1/pki/crl"
vexec vault write pki/roles/myapp-role allowed_domains="myapp.local" allow_subdomains=true allow_bare_domains=true max_ttl="24h"
echo "PKI setup complete."
