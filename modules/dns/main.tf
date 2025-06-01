terraform {
  required_version = ">= 1.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

resource "cloudflare_record" "matrix" {
  zone_id = var.zone_id
  name    = var.server_name
  content = var.server_ip
  type    = "A"
  proxied = false
}

resource "cloudflare_record" "matrix_federation" {
  zone_id = var.zone_id
  name    = "_matrix._tcp.${var.domain}"
  type    = "SRV"
  data {
    priority = 10
    weight   = 0
    port     = 8448
    target   = var.server_name
  }
  proxied = false
}

resource "cloudflare_record" "matrix_identity" {
  zone_id = var.zone_id
  name    = "_matrix-identity._tcp.${var.domain}"
  type    = "SRV"
  data {
    priority = 10
    weight   = 0
    port     = 443
    target   = var.server_name
  }
  proxied = false
}
