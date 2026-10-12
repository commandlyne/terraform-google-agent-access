mock_provider "google" {
  mock_resource "google_iam_workload_identity_pool" {
    defaults = { name = "projects/123/locations/global/workloadIdentityPools/cmdl-agents" }
  }
  mock_resource "google_service_account" {
    defaults = { name = "projects/sec/serviceAccounts/cmdl-agent-access@sec.iam.gserviceaccount.com" }
  }
}

variables {
  project_id = "sec"
  issuer_uri = "https://oidc.commandlyne.ai/org/oi_0123456789abcdefghjkmnpqrs"
  subjects = {
    secops = "fc_0123456789abcdefghjkmnpqrs"
    audit  = "fc_abcdefghjkmnpqrs0123456789"
  }
}

run "binds_each_subject_and_gates_the_exchange" {
  command = apply # mocked; pool name is only known after apply

  assert {
    condition     = google_iam_workload_identity_pool_provider.commandlyne.attribute_condition == "assertion.sub in ['fc_abcdefghjkmnpqrs0123456789', 'fc_0123456789abcdefghjkmnpqrs']"
    error_message = "attribute_condition must list exactly the configured subjects"
  }
  assert {
    condition     = google_service_account_iam_member.agent_can_impersonate["secops"].member == "principal://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cmdl-agents/subject/fc_0123456789abcdefghjkmnpqrs"
    error_message = "binding must name a single subject, never a principalSet"
  }
  assert {
    condition     = length(google_service_account_iam_member.agent_can_impersonate) == 2
    error_message = "one binding per subject"
  }
}

run "rejects_malformed_subject" {
  command = plan
  variables {
    subjects = { secops = "vm-uuid-1234" }
  }
  expect_failures = [var.subjects]
}

run "rejects_foreign_issuer_shape" {
  command = plan
  variables {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  expect_failures = [var.issuer_uri]
}

run "rejects_duplicate_subjects" {
  command = plan
  variables {
    subjects = { a = "fc_0123456789abcdefghjkmnpqrs", b = "fc_0123456789abcdefghjkmnpqrs" }
  }
  expect_failures = [var.subjects]
}

run "rejects_google_reserved_prefix" {
  command = plan
  variables {
    resource_prefix = "gcp-x"
  }
  expect_failures = [var.resource_prefix]
}
