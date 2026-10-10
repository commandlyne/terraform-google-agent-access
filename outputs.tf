output "service_account_email" {
  description = "Service account the agents act as."
  value       = google_service_account.agent.email
}

output "provider_name" {
  description = "Full resource name of the workload identity provider."
  value       = google_iam_workload_identity_pool_provider.commandlyne.name
}

output "onboarding_payload" {
  description = "Paste `terraform output -json onboarding_payload` into Control Panel to finish connecting."
  value = {
    provider              = google_iam_workload_identity_pool_provider.commandlyne.name
    service_account_email = google_service_account.agent.email
    project_id            = var.project_id
  }
}
