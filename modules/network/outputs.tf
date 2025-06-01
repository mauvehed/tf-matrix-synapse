output "network_id" {
  description = "ID of the private network"
  value       = hcloud_network.matrix.id
}

output "firewall_id" {
  description = "ID of the main firewall"
  value       = hcloud_firewall.matrix.id
}

output "subnet_id" {
  description = "ID of the created subnet"
  value       = hcloud_network_subnet.matrix.id
}
