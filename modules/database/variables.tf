variable "environment" {
  description = "Environment name (e.g., prod, dev)"
  type        = string
}

variable "location" {
  description = "Hetzner Cloud location"
  type        = string
}

variable "server_type" {
  description = "Hetzner Cloud server type"
  type        = string
}

variable "ssh_keys" {
  description = "List of SSH key IDs to add to the server"
  type        = list(string)
}

variable "network_id" {
  description = "ID of the Hetzner Cloud network"
  type        = string
}

variable "firewall_id" {
  description = "ID of the Hetzner Cloud firewall"
  type        = string
}

variable "postgres_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
}

variable "server_name" {
  description = "The name of the server, used for naming related resources."
  type        = string
}
