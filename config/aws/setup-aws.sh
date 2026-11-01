#!/usr/bin/env bash
set -euo pipefail
VAULT_TOKEN=${VAULT_TOKEN:?}
vexec() { kubectl -n vault exec vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" "$@"; }

vexec vault secrets enable aws || true
# Utiliser des variables d'environnement pour les vraies clés AWS si disponibles
vexec vault write aws/config/root \
  access_key="${AWS_ACCESS_KEY_ID:-AKIAFAKEFAKEFAKEFAKE}" \
  secret_key="${AWS_SECRET_ACCESS_KEY:-fakeSecretKeyFakeSecretKeyFakeSecretKey}" \
  region="${AWS_REGION:-us-east-1}"
vexec vault write aws/roles/myapp-aws-role \
  credential_type=iam_user \
  policy_document='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:ListBucket"],"Resource":["arn:aws:s3:::myapp-bucket"]}]}'
echo "AWS secrets engine setup complete (check credentials if testing against real AWS)."
