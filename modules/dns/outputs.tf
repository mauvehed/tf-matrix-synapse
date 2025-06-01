output "zone_id" {
  description = "Cloudflare Zone ID"
  value       = var.zone_id
}

output "matrix_record" {
  description = "Matrix A record"
  value       = cloudflare_record.matrix
}

output "matrix_federation_record" {
  description = "Matrix federation SRV record"
  value       = cloudflare_record.matrix_federation
}

output "matrix_identity_record" {
  description = "Matrix identity SRV record"
  value       = cloudflare_record.matrix_identity
}
