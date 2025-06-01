variable "location" {
  description = "The Hetzner location for the Matrix server."
  type        = string
  default     = "nbg1"
}

variable "server_type" {
  description = "The Hetzner server type for the Matrix server."
  type        = string
  default     = "cpx11"
}

variable "ssh_keys" {
  description = "A list of SSH key names to allow access to the server."
  type        = list(string)
}

variable "network_id" {
  description = "ID of the Hetzner private network to attach the server to"
  type        = string
}

variable "firewall_id" {
  description = "ID of the Hetzner Firewall to assign to the server"
  type        = string
}

variable "domain_name" {
  description = "The main domain name (e.g., example.com) passed for user_data."
  type        = string
}

variable "server_name" {
  description = "The server name (subdomain) for the Matrix server."
  type        = string
}

variable "volume_size" {
  description = "Size of the volume for Matrix application data in GB"
  type        = number
  default     = 10
}

variable "postgres_password" {
  description = "Password for the PostgreSQL synapse user, for homeserver.yaml"
  type        = string
  sensitive   = true
}

variable "synapse_db_user" {
  description = "PostgreSQL user for Synapse, for homeserver.yaml"
  type        = string
}

variable "synapse_db_name" {
  description = "PostgreSQL database name for Synapse, for homeserver.yaml"
  type        = string
}

variable "synapse_registration_secret" {
  description = "The registration shared secret for Synapse."
  type        = string
  sensitive   = true
}

variable "synapse_macaroon_secret" {
  description = "The macaroon secret key for Synapse."
  type        = string
  sensitive   = true
}

variable "backup_retention_days" {
  description = "The number of days to retain database backups."
  type        = number
  default     = 7
}

variable "certbot_email" {
  description = "Email address for Certbot SSL certificate registration and renewal notices."
  type        = string
}
