# Changelog

## v0.1.0

- Initial release: a workload identity pool and an OIDC provider that trust a Commandlyne org issuer, and one impersonation binding per agent onto a keyless service account the module creates (shared or per agent) or an existing one. Pool, provider and service account IDs have defaults you can override. Role grants are left to you, at any scope. Works with google provider 6.x and 7.x.
