mock_provider "google" {
  mock_resource "google_iam_workload_identity_pool" {
    defaults = { name = "projects/123/locations/global/workloadIdentityPools/cmdl-agents" }
  }
  mock_resource "google_service_account" {
    defaults = {
      name   = "projects/sec/serviceAccounts/cmdl-agent-access@sec.iam.gserviceaccount.com"
      member = "serviceAccount:cmdl-agent-access@sec.iam.gserviceaccount.com"
    }
  }
}

variables {
  project_id = "sec"
  issuer_uri = "https://oidc.commandlyne.ai/org/oi_0123456789abcdefghjkmnpqrs"
  subjects = {
    secops = "fc_0123456789abcdefghjkmnpqrs"
    audit  = "fc_abcdefghjkmnpqrs0123456789"
  }
  organization_id    = "111"
  organization_roles = ["roles/iam.securityReviewer"]
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

run "refuses_broad_roles" {
  command = plan
  variables {
    project_roles = { "sec" = ["roles/logging.viewer", "roles/editor"] }
  }
  expect_failures = [google_service_account.agent]
}

run "org_roles_need_org_id" {
  command = plan
  variables {
    organization_id = null
  }
  expect_failures = [google_service_account.agent]
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

run "refuses_unlisted_iam_roles_at_org_scope" {
  command = plan
  variables {
    organization_roles = ["roles/iam.organizationRoleViewer"] # only the iam.* rule matches
  }
  expect_failures = [google_service_account.agent]
}

run "refuses_run_as_roles_at_folder_scope" {
  command = plan
  variables {
    folder_roles = { "folders/1" = ["roles/compute.instanceAdmin.v1"] }
  }
  expect_failures = [google_service_account.agent]
}

run "refuses_data_roles_at_project_scope" {
  command = plan
  variables {
    project_roles = { "sec" = ["roles/storage.objectViewer"] }
  }
  expect_failures = [google_service_account.agent]
}

run "allows_read_only_roles" {
  command = plan
  variables {
    organization_roles = ["roles/iam.securityReviewer", "roles/securitycenter.findingsViewer", "roles/compute.networkViewer"]
    project_roles      = { "sec" = ["roles/artifactregistry.reader", "organizations/111/roles/customReader"] }
  }
}

run "rejects_duplicate_subjects" {
  command = plan
  variables {
    subjects = { a = "fc_0123456789abcdefghjkmnpqrs", b = "fc_0123456789abcdefghjkmnpqrs" }
  }
  expect_failures = [var.subjects]
}
