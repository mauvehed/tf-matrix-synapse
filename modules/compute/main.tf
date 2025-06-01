terraform {
  required_version = ">= 1.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45.0"
    }
  }
}

resource "hcloud_server" "matrix" {
  name        = "matrix-synapse"
  server_type = var.server_type
  image       = "ubuntu-24.04"
  location    = var.location
  ssh_keys    = var.ssh_keys
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  network {
    network_id = var.network_id
    ip         = "10.0.0.10"
  }
  firewall_ids = [var.firewall_id]

  user_data = templatefile("${path.module}/templates/user_data.sh", {
    server_name                 = var.server_name
    domain_name                 = var.domain_name
    postgres_password           = var.postgres_password
    synapse_db_user             = var.synapse_db_user
    synapse_db_name             = var.synapse_db_name
    synapse_registration_secret = var.synapse_registration_secret
    synapse_macaroon_secret     = var.synapse_macaroon_secret
    backup_retention_days       = var.backup_retention_days
    certbot_email               = var.certbot_email
  })
}

resource "hcloud_volume" "matrix_data" {
  name      = "matrix-data-${var.server_name}"
  size      = var.volume_size
  location  = var.location
  format    = "ext4"
  automount = false # We handle mounting in user_data or fstab
}

resource "hcloud_volume_attachment" "matrix_data_attachment" {
  volume_id = hcloud_volume.matrix_data.id
  server_id = hcloud_server.matrix.id
  automount = false # Explicitly false, we handle in user_data
}

// Output definitions moved to outputs.tf
