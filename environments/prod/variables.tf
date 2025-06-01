variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for the domain"
  type        = string
}

variable "domain" {
  description = "Domain name for the Matrix server (e.g., example.com)"
  type        = string
}

variable "server_name" {
  description = "Full server name for Matrix (e.g., matrix.example.com)"
  type        = string
}

variable "location" {
  description = "Hetzner Cloud location for the server (e.g., nbg1, fsn1, hel1, ash)"
  type        = string
}

variable "server_type" {
  description = "Hetzner Cloud server type (e.g., cpx11)"
  type        = string
}

variable "ssh_keys" {
  description = "List of Hetzner SSH key IDs or names to associate with the server"
  type        = list(string)
}

variable "postgres_password" {
  description = "Password for the PostgreSQL 'synapse' user"
  type        = string
  sensitive   = true
}

variable "synapse_db_user" {
  description = "PostgreSQL user for Synapse"
  type        = string
  default     = "synapse"
}

variable "synapse_db_name" {
  description = "PostgreSQL database name for Synapse"
  type        = string
  default     = "synapse"
}

variable "synapse_registration_secret" {
  description = "Shared secret for Synapse registration"
  type        = string
  sensitive   = true
}

variable "synapse_macaroon_secret" {
  description = "Macaroon secret key for Synapse"
  type        = string
  sensitive   = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "certbot_email" {
  description = "Email address for Certbot (Let's Encrypt) notifications"
  type        = string
}

variable "environment" {
  description = "The deployment environment (e.g., prod, dev)"
  type        = string
  default     = "prod"
}
