output "service_accounts" {
  description = "Service accounts this module created, by service_account_id: email, member (for IAM grants), name and unique_id."
  value = { for id, sa in google_service_account.agent : id => {
    email     = sa.email
    member    = sa.member
    name      = sa.name
    unique_id = sa.unique_id
  } }
}

output "service_account_emails" {
  description = "Each agent's service account email, created or existing, by agent label."
  value       = local.sa_email
}

output "provider_name" {
  description = "Full resource name of the workload identity provider."
  value       = google_iam_workload_identity_pool_provider.commandlyne.name
}

output "onboarding_payloads" {
  description = "Per agent label: paste `terraform output -json` of one entry into that agent's Control Panel setup."
  value = { for k, a in var.agents : k => {
    subject               = a.subject
    provider              = google_iam_workload_identity_pool_provider.commandlyne.name
    service_account_email = local.sa_email[k]
    project_id            = var.project_id
  } }
}
