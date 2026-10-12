# terraform-google-agent-access

This module lets [Commandlyne](https://commandlyne.ai) agents act as a service account in your Google Cloud project. It grants that account no roles: you decide what it can access, and at which scope. It uses [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation), so no service-account key is created, stored or uploaded.

## How it works

1. Commandlyne Control Panel signs a short-lived token (10 minutes) for one agent. The token's issuer is unique to your organization (`https://oidc.commandlyne.ai/org/oi_...`) and its subject is unique to the connection (`fc_...`).
2. Google STS accepts the token only if the issuer matches your provider **and** the subject is in the provider's `attribute_condition`.
3. STS then lets the agent impersonate the service account this module creates. The service account can do only what you grant it.

Control Panel signs tokens with a Cloud KMS key that can't be exported. Google fetches the public keys from the issuer URL.

## What this creates

All resources are in `project_id`:

| Resource | Notes |
|---|---|
| APIs: `iam`, `iamcredentials`, `sts`, `cloudresourcemanager` | Not disabled on destroy. |
| Workload identity pool `<prefix>-agents` | |
| OIDC provider `<prefix>-commandlyne` | `google.subject = assertion.sub`, plus `attribute_condition` limited to your subjects. |
| Service account `<prefix>-agent-access` | No keys. |
| `roles/iam.workloadIdentityUser` on the service account | One binding per subject. The module never binds the whole pool. |

`subjects` takes up to 100 agents, which keeps `attribute_condition` under Google's 4096-character limit.

## Prerequisites

The identity running `terraform apply` needs `roles/iam.workloadIdentityPoolAdmin`, `roles/iam.serviceAccountAdmin` and `roles/serviceusage.serviceUsageAdmin` on `project_id`.

Check these organization policies:

- **`constraints/iam.workloadIdentityPoolProviders`.** If you set it, add your issuer URI to its allowed values.
- **`constraints/iam.disableServiceAccountKeyCreation`.** Keep it enforced. This module never needs keys.

## Usage

1. In Control Panel, open the agent → **Connectors → gcloud → Service account (Workload Identity)**. Copy the issuer URI and subject.
2. Apply:

   ```hcl
   module "agent_access" {
     source = "github.com/commandlyne/terraform-google-agent-access?ref=v0.1.0"

     project_id = "my-project"
     issuer_uri = "https://oidc.commandlyne.ai/org/oi_..."
     subjects   = { secops = "fc_..." }
   }

   output "onboarding_payload" {
     value = module.agent_access.onboarding_payload
   }
   ```

3. Grant the service account the roles the agent needs (see below). It has no roles of its own until you do.
4. Paste the output of `terraform output -json onboarding_payload` into Control Panel, then click **Connect**.

Prefer a dedicated project for `project_id`: anyone who can act as service accounts there can act as this one.

## Grant access

Grant roles to `module.agent_access.service_account_email` like any other service account, at whichever scope fits. You need `setIamPolicy` on each scope you grant on.

```hcl
resource "google_project_iam_member" "agent" {
  project = "my-app-project"
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${module.agent_access.service_account_email}"
}
# Wider scopes: google_folder_iam_member (folder = "folders/123")
# or google_organization_iam_member (org_id = "123456789012").
```

Or with gcloud (`folders` / `organizations add-iam-policy-binding` for wider scopes):

```sh
gcloud projects add-iam-policy-binding my-app-project --role=roles/logging.viewer \
  --member="serviceAccount:cmdl-agent-access@my-project.iam.gserviceaccount.com"
```

Google bills the service account's calls to `project_id`, so enable there any API the agent calls (for example `cloudasset.googleapis.com`), or they fail with `SERVICE_DISABLED`.

[`examples/basic`](examples/basic) puts the module and a grant together.

### Choosing roles

Anyone who can talk to the agent can use these permissions, and text the agent reads (log entries, findings, issue descriptions) can try to steer it. Grant only what the agent's job needs, at the narrowest scope that works.

- Never grant basic roles (`owner`, `editor`, `viewer`). Avoid roles that let the account change IAM, create keys or tokens, or act as other service accounts (`iam.serviceAccountUser`, `iam.serviceAccountTokenCreator`, `*Admin`).
- Prefer viewer roles. If none fits, create a custom role with exactly the permissions needed.
- `roles/logging.viewer` reads every log except Data Access logs. That includes application logs, which sometimes contain sensitive values.
- `roles/cloudasset.viewer` returns full resource configs, such as Cloud Run environment variables and VM metadata (`startup-script`).
- `roles/artifactregistry.reader` lets the agent pull images, not only read their metadata.

## Revocation

- **One agent:** remove its entry from `subjects` and apply. That deletes its binding and drops it from the provider condition.
- **Every agent:** revoke the connections in Control Panel, which stops issuing tokens at once, or disable the provider in the console. Avoid `terraform destroy -target` on the provider: Google soft-deletes it for 30 days, so the next apply fails on the ID until you undelete it or change `resource_prefix`.

Tokens already issued stay valid until they expire: up to 10 minutes for the Commandlyne token and 1 hour for the Google access token.

## Audit

Turn on Data Access audit logs for `sts.googleapis.com` and `iamcredentials.googleapis.com`. Without them, token exchanges are not logged.

Each exchange logs the subject (`fc_...`). Control Panel shows which agent a subject belongs to.

```sh
gcloud logging read 'protoPayload.serviceName="sts.googleapis.com" OR protoPayload.serviceName="iamcredentials.googleapis.com"' --project=my-project --limit=20
```

## Costs

Workload Identity Federation, STS and IAM have no charge.

## Versioning

Versions follow semver. Pin a tag with `?ref=vX.Y.Z`. See [CHANGELOG.md](CHANGELOG.md).
