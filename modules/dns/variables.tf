variable "domain" {
  description = "Domain name for the Matrix server"
  type        = string
}

variable "server_name" {
  description = "Matrix server name (e.g., matrix.example.com)"
  type        = string
}

variable "server_ip" {
  description = "IP address of the Matrix server"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare Zone ID for the domain"
  type        = string
}
