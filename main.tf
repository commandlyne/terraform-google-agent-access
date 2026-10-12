resource "google_project_service" "apis" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",       # generateAccessToken for the impersonation step
    "sts.googleapis.com",                  # exchanges the Commandlyne token
    "cloudresourcemanager.googleapis.com", # most gcloud commands need it on the SA's own project
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "agents" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.resource_prefix}-agents"
  display_name              = "Commandlyne agents"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "commandlyne" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.agents.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.resource_prefix}-commandlyne"
  display_name                       = "Commandlyne Control Panel"

  attribute_mapping = { "google.subject" = "assertion.sub" }
  # Second gate next to the per-subject bindings: a token for any other agent is
  # rejected at the exchange, before IAM is consulted.
  attribute_condition = "assertion.sub in [${join(", ", [for s in values(var.subjects) : "'${s}'"])}]"

  oidc {
    issuer_uri = var.issuer_uri
  }
}

resource "google_service_account" "agent" {
  project      = var.project_id
  account_id   = "${var.resource_prefix}-agent-access"
  display_name = "Commandlyne agent access"
  description  = "Impersonated by Commandlyne agents via workload identity federation. No keys."

  depends_on = [google_project_service.apis]
}

# One binding per agent; never a principalSet over the whole pool. Removing an
# entry from var.subjects revokes that agent.
resource "google_service_account_iam_member" "agent_can_impersonate" {
  for_each = var.subjects

  service_account_id = google_service_account.agent.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.agents.name}/subject/${each.value}"
}
