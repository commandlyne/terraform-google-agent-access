locals {
  # The SA must not be able to widen its own access (IAM, pool, role, org policy
  # admin), mint credentials, run as other identities, or read data contents.
  # Custom roles are the escape hatch for a real need.
  refused_role_patterns = [
    "^roles/(owner|editor|viewer)$",
    "^roles/iam\\.",
    "(?i)(admin|editor|owner|writer|user|developer|creator|invoker|accessor|decrypter|encrypter|signer|login)(\\.v1)?$",
    "^roles/(storage|bigquery)\\.(object|data|legacy)",
    "^roles/secretmanager\\.",
    "^roles/logging\\.privateLogViewer$",
  ]
  allowed_iam_roles = ["roles/iam.securityReviewer", "roles/iam.roleViewer", "roles/iam.serviceAccountViewer", "roles/iam.workloadIdentityPoolViewer"]

  folder_grants = merge([
    for folder, roles in var.folder_roles : { for r in roles : "${folder} ${r}" => { folder = folder, role = r } }
  ]...)
  project_grants = merge([
    for project, roles in var.project_roles : { for r in roles : "${project} ${r}" => { project = project, role = r } }
  ]...)

  all_roles = concat(var.organization_roles, flatten(values(var.folder_roles)), flatten(values(var.project_roles)))
  refused_roles = distinct([
    for r in local.all_roles : r
    if !contains(local.allowed_iam_roles, r) && anytrue([for p in local.refused_role_patterns : can(regex(p, r))])
  ])
}

resource "google_project_service" "apis" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com", # generateAccessToken for the impersonation step
    "sts.googleapis.com",            # exchanges the Commandlyne token
    "cloudresourcemanager.googleapis.com",
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

  lifecycle {
    precondition {
      condition     = length(local.refused_roles) == 0
      error_message = "Refusing to grant ${join(", ", local.refused_roles)}: read-only roles only (see README). Use a narrower predefined or a custom role."
    }
    precondition {
      condition     = length(var.organization_roles) == 0 || var.organization_id != null
      error_message = "organization_id is required when organization_roles is set."
    }
  }
}

# One binding per agent; never a principalSet over the whole pool. Removing an
# entry from var.subjects revokes that agent.
resource "google_service_account_iam_member" "agent_can_impersonate" {
  for_each = var.subjects

  service_account_id = google_service_account.agent.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.agents.name}/subject/${each.value}"
}

resource "google_organization_iam_member" "agent" {
  for_each = toset(var.organization_roles)

  org_id = var.organization_id
  role   = each.value
  member = google_service_account.agent.member
}

resource "google_folder_iam_member" "agent" {
  for_each = local.folder_grants

  folder = each.value.folder
  role   = each.value.role
  member = google_service_account.agent.member
}

resource "google_project_iam_member" "agent" {
  for_each = local.project_grants

  project = each.value.project
  role    = each.value.role
  member  = google_service_account.agent.member
}
