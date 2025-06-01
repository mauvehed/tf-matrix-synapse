terraform {
  required_version = ">= 1.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45.0"
    }
  }
}

locals {
  network_zones = {
    "hil" = "eu-north"
    "nbg" = "eu-central"
    "fsn" = "eu-central"
    "ash" = "us-east"
  }
}

resource "hcloud_firewall" "matrix" {
  name = "matrix-synapse-${var.environment}"

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["136.62.151.53/32"]
    description = "SSH access"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0"]
    description = "HTTP access"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0"]
    description = "HTTPS access"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "8448"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Matrix federation"
  }

}

resource "hcloud_network" "matrix" {
  name     = "matrix-network-${var.environment}"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "matrix" {
  network_id   = hcloud_network.matrix.id
  type         = "cloud"
  network_zone = local.network_zones[var.location]
  ip_range     = "10.0.0.0/24"
}
