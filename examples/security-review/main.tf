# Read-only security review across a whole organization: IAM, findings,
# assets, network, org policy, KMS metadata and Artifact Registry
# vulnerability scans. Nothing here can change resources or read objects,
# secrets, table rows or Data Access logs. cloudasset.viewer and logging.viewer
# do expose resource configs and logs; see "Choosing roles" in the README.
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
  description = "Dedicated security project that hosts the pool and service account."
}

variable "organization_id" {
  type        = string
  description = "Numeric organization ID."
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

  project_id      = var.project_id
  issuer_uri      = var.issuer_uri
  subjects        = var.subjects
  organization_id = var.organization_id

  organization_roles = [
    "roles/browser",                              # folder/project hierarchy
    "roles/iam.securityReviewer",                 # IAM policies everywhere
    "roles/securitycenter.findingsViewer",        # Security Command Center findings
    "roles/cloudasset.viewer",                    # asset inventory + IAM search
    "roles/logging.viewer",                       # audit logs, excluding Data Access
    "roles/compute.networkViewer",                # VPCs, firewalls, routes, LBs
    "roles/orgpolicy.policyViewer",               # org policy constraints
    "roles/accesscontextmanager.policyReader",    # VPC Service Controls
    "roles/cloudkms.viewer",                      # key metadata, not key use
    "roles/containeranalysis.occurrences.viewer", # Artifact Registry vulnerability scans
  ]
}

# Paste into Control Panel: terraform output -json onboarding_payload
output "onboarding_payload" {
  description = "Values Control Panel needs to finish connecting."
  value       = module.agent_access.onboarding_payload
}
