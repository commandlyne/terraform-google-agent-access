# terraform-google-agent-access

This module lets [Commandlyne](https://commandlyne.ai) agents act as a service account in your Google Cloud organization. It uses [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation), so no service-account key is created, stored or uploaded.

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
| Your role grants | Organization, folder and project scopes. |

`subjects` takes up to 100 agents, which keeps `attribute_condition` under Google's 4096-character limit.

The module refuses roles that would let the agent widen its own access, mint credentials, run as other identities or read data contents. That covers the basic roles, every `roles/iam.*` role except the four viewer/reviewer roles, any role ending in `admin`, `editor`, `user`, `creator`, `invoker`, `accessor`, `decrypter`, `signer`, `login` or similar, Storage and BigQuery object/data roles, Secret Manager, and `logging.privateLogViewer`. The guard is a backstop, not a review: check every role you grant. If you need something it refuses, use a custom role.

## Prerequisites

The identity running `terraform apply` needs:

- On `project_id`: `roles/iam.workloadIdentityPoolAdmin`, `roles/iam.serviceAccountAdmin` and `roles/serviceusage.serviceUsageAdmin`.
- To grant `organization_roles`, `folder_roles` or `project_roles`: `roles/iam.securityAdmin`, or the matching `resourcemanager.*.setIamPolicy`, on each scope.

Check these organization policies:

- **`constraints/iam.workloadIdentityPoolProviders`.** If you set it, add your issuer URI to its allowed values.
- **`constraints/iam.disableServiceAccountKeyCreation`.** Keep it enforced. This module never needs keys.

## Usage

1. In Control Panel, open the agent → **Connectors → gcloud → Service account (Workload Identity)**. Copy the issuer URI and subject.
2. Apply:

   ```hcl
   module "agent_access" {
     source = "github.com/clawworker/terraform-google-agent-access?ref=v0.1.0"

     project_id      = "my-security-project"
     issuer_uri      = "https://oidc.commandlyne.ai/org/oi_..."
     subjects        = { secops = "fc_..." }
     organization_id = "123456789012"

     organization_roles = ["roles/iam.securityReviewer", "roles/cloudasset.viewer"]
   }

   output "onboarding_payload" {
     value = module.agent_access.onboarding_payload
   }
   ```

3. Paste the output of `terraform output -json onboarding_payload` into Control Panel, then click **Connect**.

[`examples/security-review`](examples/security-review) has a read-only role set for security review across a whole organization.

### Choosing roles

Anyone who can talk to the agent can use these permissions, and text the agent reads (log entries, findings, issue descriptions) can try to steer it. Grant read-only roles, and only the ones the agent's job needs.

- `roles/logging.viewer` reads every log except Data Access logs. That includes application logs, which sometimes contain sensitive values.
- `roles/cloudasset.viewer` returns full resource configs, such as Cloud Run environment variables and VM metadata (`startup-script`). If those hold secrets in your organization, use a custom role with only `cloudasset.assets.searchAllResources` and `cloudasset.assets.searchAllIamPolicies`.
- `roles/artifactregistry.reader` lets the agent pull images, not only read their metadata. The example leaves it out on purpose.

## Revocation

- **One agent:** remove its entry from `subjects` and apply. That deletes its binding and drops it from the provider condition.
- **Every agent:** revoke the connections in Control Panel, which stops issuing tokens at once, or disable the provider in the console. Avoid `terraform destroy -target` on the provider: Google soft-deletes it for 30 days, so the next apply fails on the ID until you undelete it or change `resource_prefix`.

Tokens already issued stay valid until they expire: up to 10 minutes for the Commandlyne token and 1 hour for the Google access token.

## Audit

Turn on Data Access audit logs for `sts.googleapis.com` and `iamcredentials.googleapis.com`. Without them, token exchanges are not logged.

Each exchange logs the subject (`fc_...`). Control Panel shows which agent a subject belongs to.

```sh
gcloud logging read 'protoPayload.serviceName="sts.googleapis.com" OR protoPayload.serviceName="iamcredentials.googleapis.com"' --project=my-security-project --limit=20
```

## Costs

Workload Identity Federation, STS and IAM have no charge.

## Versioning

Versions follow semver. Pin a tag with `?ref=vX.Y.Z`. See [CHANGELOG.md](CHANGELOG.md).
