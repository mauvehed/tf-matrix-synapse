output "server_ip" {
  description = "Public IP address of the Matrix server"
  value       = hcloud_server.matrix.ipv4_address
}

output "server_ipv6" {
  description = "The public IPv6 address of the Matrix server."
  value       = hcloud_server.matrix.ipv6_address
}

output "server_id" {
  description = "ID of the Matrix server"
  value       = hcloud_server.matrix.id
}

output "volume_id" {
  description = "ID of the attached data volume"
  value       = hcloud_volume.matrix_data.id
}
