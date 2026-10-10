variable "project_id" {
  type        = string
  description = "Project that hosts the workload identity pool and the service account. Prefer a dedicated security project."
}

variable "issuer_uri" {
  type        = string
  description = "Your organization's issuer URI, shown in Commandlyne Control Panel (https://oidc.<domain>/org/oi_...)."

  validation {
    condition     = can(regex("^https://[a-z0-9.-]+/org/oi_[0-9a-z]{26}$", var.issuer_uri))
    error_message = "issuer_uri must be the https://.../org/oi_... value shown in Control Panel."
  }
}

variable "subjects" {
  type        = map(string)
  description = "Agents allowed to act as the service account: label => subject (fc_...) shown in Control Panel."

  validation {
    condition     = length(var.subjects) > 0 && alltrue([for s in values(var.subjects) : can(regex("^fc_[0-9a-z]{26}$", s))])
    error_message = "subjects must be a non-empty map of fc_... subjects from Control Panel."
  }
}

variable "resource_prefix" {
  type        = string
  default     = "cmdl"
  description = "Prefix for the pool, provider and service account IDs."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,10}$", var.resource_prefix))
    error_message = "resource_prefix must be 2-11 chars: lowercase letters, digits, hyphens; starting with a letter."
  }
}

variable "organization_id" {
  type        = string
  default     = null
  description = "Numeric organization ID. Required when organization_roles is set."
}

variable "organization_roles" {
  type        = list(string)
  default     = []
  description = "Roles granted to the service account on the organization."
}

variable "folder_roles" {
  type        = map(list(string))
  default     = {}
  description = "Roles granted to the service account per folder: \"folders/123\" => [roles]."
}

variable "project_roles" {
  type        = map(list(string))
  default     = {}
  description = "Roles granted to the service account per project: project ID => [roles]."
}
