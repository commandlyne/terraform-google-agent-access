# The module only lets the agent act as a service account. What that account
# can do is up to you: grant roles outside the module, at any scope.
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.11"
    }
  }
}

variable "project_id" {
  type        = string
  description = "Project that hosts the pool and service account."
}

variable "issuer_uri" {
  type        = string
  description = "Issuer URI from Control Panel."
}

variable "subjects" {
  type        = map(string)
  description = "label => fc_... subject from Control Panel."
}

provider "google" {
  project = var.project_id
}

module "agent_access" {
  source = "../.."

  project_id = var.project_id
  issuer_uri = var.issuer_uri
  subjects   = var.subjects
}

# Example grant: read-only access to one project. Use google_folder_iam_member
# or google_organization_iam_member for wider scopes.
resource "google_project_iam_member" "agent_viewer" {
  project = var.project_id
  role    = "roles/browser"
  member  = "serviceAccount:${module.agent_access.service_account_email}"
}

# Paste into Control Panel: terraform output -json onboarding_payload
output "onboarding_payload" {
  description = "Values Control Panel needs to finish connecting."
  value       = module.agent_access.onboarding_payload
}
