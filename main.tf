resource "google_project_service" "apis" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",       # generateAccessToken for the impersonation step
    "sts.googleapis.com",                  # exchanges the Commandlyne token
    "cloudresourcemanager.googleapis.com", # required by Google's WIF setup
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "agents" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "Commandlyne agents"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "commandlyne" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.agents.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "Commandlyne Control Panel"

  attribute_mapping = { "google.subject" = "assertion.sub" }
  # Second gate next to the per-subject bindings: a token for any other agent is
  # rejected at the exchange, before IAM is consulted.
  attribute_condition = "assertion.sub in [${join(", ", [for s in values(var.agents) : "'${s.subject}'"])}]"

  oidc {
    issuer_uri = var.issuer_uri
  }
}

locals {
  # Accounts to create; agents repeating an ID share it. Existing ones are only bound.
  created  = toset([for a in values(var.agents) : a.service_account_id if a.existing_service_account_email == null])
  sa_email = { for k, a in var.agents : k => a.existing_service_account_email != null ? a.existing_service_account_email : google_service_account.agent[a.service_account_id].email }
}

resource "google_service_account" "agent" {
  for_each = local.created

  project      = var.project_id
  account_id   = each.key
  display_name = "Commandlyne agent access"
  description  = "Impersonated by Commandlyne agents via workload identity federation. No keys."

  depends_on = [google_project_service.apis]
}

# One binding per agent; never a principalSet over the whole pool. Removing an
# agent revokes it.
resource "google_service_account_iam_member" "agent_can_impersonate" {
  for_each = var.agents

  service_account_id = "projects/-/serviceAccounts/${local.sa_email[each.key]}" # IAM resolves the project from the email
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.agents.name}/subject/${each.value.subject}"
}
