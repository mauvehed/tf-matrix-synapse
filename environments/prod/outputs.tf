output "matrix_server_ip" {
  description = "IP address of the Matrix Synapse server"
  value       = module.compute.server_ip
}

output "matrix_server_name" {
  description = "Hostname of the Matrix Synapse server"
  value       = var.server_name
}

output "matrix_federation_url" {
  description = "Matrix federation URL"
  value       = "https://${var.server_name}:8448"
}

output "matrix_client_url" {
  description = "Matrix client URL"
  value       = "https://${var.server_name}"
}

output "ssh_command" {
  description = "SSH command to connect to the Matrix server"
  value       = "ssh root@${module.compute.server_ip}"
}
