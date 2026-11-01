path "kv/data/myapp/config" {
  capabilities = ["read"]
}
path "pki/issue/myapp-role" {
  capabilities = ["create", "update"]
}
path "pki/cert/ca" {
  capabilities = ["read"]
}
