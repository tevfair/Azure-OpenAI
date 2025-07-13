variable "ARM_CLIENT_ID" {
  description = "Azure Client ID for authentication"
  type        = string
}

variable "ARM_CLIENT_SECRET" {
  description = "Azure Client Secret for authentication"
  type        = string
  sensitive   = true
}

variable "ARM_SUBSCRIPTION_ID" {
  description = "Azure Subscription ID for authentication"
  type        = string
}

variable "ARM_TENANT_ID" {
  description = "Azure Tenant ID for authentication"
  type        = string
}