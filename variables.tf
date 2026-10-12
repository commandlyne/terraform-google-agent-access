variable "project_id" {
  type        = string
  description = "Project that hosts the workload identity pool and the service accounts this module creates. Prefer a dedicated project."
}

variable "issuer_uri" {
  type        = string
  description = "Your organization's issuer URI, shown in Commandlyne Control Panel (https://oidc.<domain>/org/oi_...)."

  validation {
    condition     = can(regex("^https://[a-z0-9.-]+/org/oi_[0-9a-z]{26}$", var.issuer_uri))
    error_message = "issuer_uri must be the https://.../org/oi_... value shown in Control Panel."
  }
}

variable "agents" {
  type = map(object({
    subject                        = string
    service_account_id             = optional(string, "cmdl-agent-access")
    existing_service_account_email = optional(string)
  }))
  description = <<-EOT
    Agents allowed to act as a service account, by label. For each:
    subject: the fc_... value from the agent's gcloud connector in Control Panel.
    service_account_id: the part of the email before @, created in project_id. Agents with the same ID share one account.
    existing_service_account_email: bind this existing account instead; nothing is created and service_account_id is ignored.
  EOT

  validation {
    # 100 keeps attribute_condition under its 4096-char limit.
    condition = (length(var.agents) > 0 && length(var.agents) <= 100
      && length(distinct([for a in values(var.agents) : a.subject])) == length(var.agents)
    && alltrue([for a in values(var.agents) : can(regex("^fc_[0-9a-z]{26}$", a.subject))]))
    error_message = "agents must map 1-100 labels to distinct fc_... subjects from Control Panel."
  }
  validation {
    condition     = alltrue([for a in values(var.agents) : can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", a.service_account_id))])
    error_message = "service_account_id must be 6-30 lowercase letters, digits or hyphens, starting with a letter."
  }
  validation {
    # HCL's || doesn't short-circuit, hence the conditional.
    condition = alltrue([for a in values(var.agents) : a.existing_service_account_email == null ? true : (
      can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z][a-z0-9-]{4,28}[a-z0-9]\\.iam\\.gserviceaccount\\.com$", a.existing_service_account_email))
    && !strcontains(a.existing_service_account_email, "@gcp-sa-"))])
    error_message = "existing_service_account_email must be a user-managed service account (name@project.iam.gserviceaccount.com)."
  }
}

variable "pool_id" {
  type        = string
  default     = "cmdl-agents"
  description = "Workload identity pool ID. Changing it replaces the pool and breaks every Control Panel connection using it; a deleted ID stays reserved for 30 days."

  validation {
    condition     = can(regex("^[a-z0-9-]{4,32}$", var.pool_id)) && !startswith(var.pool_id, "gcp-")
    error_message = "pool_id must be 4-32 lowercase letters, digits or hyphens, not starting with \"gcp-\"."
  }
}

variable "provider_id" {
  type        = string
  default     = "cmdl-commandlyne"
  description = "Workload identity provider ID. Same caveats as pool_id."

  validation {
    condition     = can(regex("^[a-z0-9-]{4,32}$", var.provider_id)) && !startswith(var.provider_id, "gcp-")
    error_message = "provider_id must be 4-32 lowercase letters, digits or hyphens, not starting with \"gcp-\"."
  }
}
