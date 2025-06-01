terraform {
  required_version = ">= 1.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

module "network" {
  source = "../../modules/network"

  environment = var.environment
  location    = var.location
}

module "compute" {
  source                      = "../../modules/compute"
  location                    = var.location
  server_type                 = var.server_type
  ssh_keys                    = var.ssh_keys
  network_id                  = module.network.network_id
  firewall_id                 = module.network.firewall_id
  domain_name                 = var.domain
  server_name                 = var.server_name
  postgres_password           = var.postgres_password
  synapse_db_user             = var.synapse_db_user
  synapse_db_name             = var.synapse_db_name
  synapse_registration_secret = var.synapse_registration_secret
  synapse_macaroon_secret     = var.synapse_macaroon_secret
  backup_retention_days       = var.backup_retention_days
  certbot_email               = var.certbot_email
}

module "dns" {
  source = "../../modules/dns"

  zone_id     = var.cloudflare_zone_id
  domain      = var.domain
  server_name = var.server_name
  server_ip   = module.compute.server_ip

  depends_on = [module.compute]
}

output "matrix_server_url" {
  description = "URL for accessing the Matrix server (HTTPS)."
  value       = "https://${var.server_name}"
}

output "matrix_well_known_client_url" {
  description = "URL for .well-known/matrix/client configuration."
  value       = "https://${var.server_name}/.well-known/matrix/client"
}

output "matrix_well_known_server_url" {
  description = "URL for .well-known/matrix/server configuration."
  value       = "https://${var.server_name}/.well-known/matrix/server"
}
