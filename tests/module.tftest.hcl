mock_provider "google" {
  mock_resource "google_iam_workload_identity_pool" {
    defaults = { name = "projects/123/locations/global/workloadIdentityPools/cmdl-agents" }
  }
  mock_resource "google_service_account" {
    defaults = { email = "cmdl-agent-access@sec.iam.gserviceaccount.com" }
  }
}

variables {
  project_id = "sec"
  issuer_uri = "https://oidc.commandlyne.ai/org/oi_0123456789abcdefghjkmnpqrs"
  agents = {
    a = { subject = "fc_0123456789abcdefghjkmnpqrs" }
    b = { subject = "fc_abcdefghjkmnpqrs0123456789" }
    c = { subject = "fc_bbcdefghjkmnpqrs0123456789", service_account_id = "cmdl-c-only" }
    d = { subject = "fc_cbcdefghjkmnpqrs0123456789", existing_service_account_email = "reader@other-proj.iam.gserviceaccount.com" }
  }
}

run "binds_each_agent_and_gates_the_exchange" {
  command = apply # mocked; pool name is only known after apply

  assert {
    condition     = google_iam_workload_identity_pool_provider.commandlyne.attribute_condition == "assertion.sub in ['fc_0123456789abcdefghjkmnpqrs', 'fc_abcdefghjkmnpqrs0123456789', 'fc_bbcdefghjkmnpqrs0123456789', 'fc_cbcdefghjkmnpqrs0123456789']"
    error_message = "attribute_condition must list exactly the configured subjects"
  }
  assert {
    condition     = google_service_account_iam_member.agent_can_impersonate["a"].member == "principal://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cmdl-agents/subject/fc_0123456789abcdefghjkmnpqrs"
    error_message = "binding must name a single subject, never a principalSet"
  }
  assert {
    condition     = keys(google_service_account.agent) == ["cmdl-agent-access", "cmdl-c-only"]
    error_message = "creates the default account once for a and b, a dedicated one for c, none for d"
  }
  assert {
    condition     = output.service_account_emails["a"] == output.service_account_emails["b"]
    error_message = "agents with the same service_account_id must share one account"
  }
  assert {
    condition     = google_service_account_iam_member.agent_can_impersonate["d"].service_account_id == "projects/-/serviceAccounts/reader@other-proj.iam.gserviceaccount.com"
    error_message = "existing account must be bound by its email"
  }
  assert {
    condition     = output.onboarding_payloads["d"].service_account_email == "reader@other-proj.iam.gserviceaccount.com" && output.onboarding_payloads["d"].subject == "fc_cbcdefghjkmnpqrs0123456789"
    error_message = "payload must carry the agent's subject and account"
  }
}

run "rejects_malformed_subject" {
  command = plan
  variables {
    agents = { secops = { subject = "vm-uuid-1234" } }
  }
  expect_failures = [var.agents]
}

run "rejects_duplicate_subjects" {
  command = plan
  variables {
    agents = { a = { subject = "fc_0123456789abcdefghjkmnpqrs" }, b = { subject = "fc_0123456789abcdefghjkmnpqrs" } }
  }
  expect_failures = [var.agents]
}

run "rejects_bad_service_account_id" {
  command = plan
  variables {
    agents = { a = { subject = "fc_0123456789abcdefghjkmnpqrs", service_account_id = "Cmdl_Agent" } }
  }
  expect_failures = [var.agents]
}

run "rejects_google_service_agent" {
  command = plan
  variables {
    agents = { a = { subject = "fc_0123456789abcdefghjkmnpqrs", existing_service_account_email = "service-123456@gcp-sa-artifactregistry.iam.gserviceaccount.com" } }
  }
  expect_failures = [var.agents]
}

run "rejects_foreign_issuer_shape" {
  command = plan
  variables {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  expect_failures = [var.issuer_uri]
}

run "rejects_google_reserved_pool_id" {
  command = plan
  variables {
    pool_id = "gcp-agents"
  }
  expect_failures = [var.pool_id]
}
