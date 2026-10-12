output "service_account_emails" {
  description = "Service account email per agent label."
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
