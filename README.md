# Matrix Synapse Terraform Deployment

This repository contains Terraform configurations for deploying a personal Matrix Synapse server on Hetzner Cloud using Docker.

## Prerequisites

- Terraform >= 1.0.0
- Hetzner Cloud account and API token
- Cloudflare account and API token
- Domain name with DNS managed by Cloudflare
- SSH key added to Hetzner Cloud (use the SSH key _name_)

### SSH Key Setup

1.  **Ensure SSH Key is in Hetzner Cloud**:

    - Log into Hetzner Cloud Console.
    - Go to "Security" > "SSH Keys".
    - If your desired SSH key isn't listed, click "Add SSH Key", give it a name, paste your public SSH key, and click "Add".
    - Note the **name** you gave the SSH key (e.g., "my-server-key").

2.  **Configure in `terraform.tfvars`** (in `environments/prod/`):
    ```hcl
    ssh_keys = ["your_ssh_key_name"] # Replace with your actual SSH key NAME
    ```
    - The `ssh_keys` variable in `environments/prod/variables.tf` expects a list of SSH key names.

### Cloudflare Setup

1.  **API Token Permissions**

    - **Required permissions**: Zone:Read, DNS:Edit, Zone Settings:Read, SSL and Certificates:Read.
    - Create a custom token in your Cloudflare dashboard with these permissions.
    - Scope the token to operate on your specific domain.

2.  **Zone ID**
    - The `cloudflare_zone_id` is a required variable.
    - To find your Zone ID: Log into the Cloudflare dashboard, select your domain. The Zone ID is usually found on the overview page, often in the right sidebar under "API".

## Architecture

The deployment consists of a single Hetzner Cloud server (Ubuntu 24.04) running:

- **Matrix Synapse**: Official Docker image (`matrixdotorg/synapse`).
- **PostgreSQL**: Official Docker image (`postgres:16-alpine`).
- **Nginx**: Reverse proxy running on the host, serving Matrix client/federation APIs and `.well-known` endpoints. Manages SSL termination using Let's Encrypt.
- **Certbot**: Runs on the host to obtain and renew SSL certificates for Nginx.
- **Docker & Docker Compose**: Manage the Synapse and PostgreSQL containers.
- **Cloudflare**: Used for DNS management.
- **Automated Backups**: A script on the host backs up the PostgreSQL database using `docker exec`.

Synapse data (including media and signing key) and PostgreSQL data are stored in Docker volumes mapped to directories on the host (`/opt/synapse/data` and `/opt/postgres/data` respectively), which reside on a Hetzner Cloud Volume attached to the server.

## Directory Structure

```
.
├── environments/
│   └── prod/ # Production environment configuration
│       ├── main.tf
│       ├── terraform.tfvars
│       └── terraform.tfvars.example
├── modules/  # Reusable modules for different components
│   ├── compute/ # For the Matrix Synapse server (hosting Docker, Nginx, Certbot)
│   ├── dns/      # For Cloudflare DNS records
│   └── network/  # For Hetzner network and firewall
├── .pre-commit-config.yaml
├── variables.tf # Root variables (though most are now in environments/prod/variables.tf)
└── README.md
```

## Deployment Steps

1.  Clone this repository:

    ```bash
    git clone <your_repository_url> tf-matrix-synapse
    cd tf-matrix-synapse
    ```

2.  Navigate to the production environment directory:

    ```bash
    cd environments/prod
    ```

3.  Create your `terraform.tfvars` file:

    ```bash
    cp terraform.tfvars.example terraform.tfvars
    ```

4.  Edit `terraform.tfvars` with your configuration:

    - Add your Hetzner Cloud API token (`hcloud_token`).
    - Add your Cloudflare API token (`cloudflare_api_token`).
    - Set your Cloudflare Zone ID (`cloudflare_zone_id`).
    - Confirm your domain name (`domain`).
    - Confirm the server name (subdomain, `server_name`).
    - Set your desired PostgreSQL user, database name, and a secure password (`synapse_db_user`, `synapse_db_name`, `postgres_password`).
    - Set secure secrets for Synapse (`synapse_registration_secret`, `synapse_macaroon_secret`).
    - Add your SSH key name(s) to `ssh_keys` (e.g., `ssh_keys = ["my-key-name"]`).
    - Set your email for Certbot (`certbot_email`).

5.  Initialize Terraform:

    ```bash
    terraform init -upgrade
    ```

6.  Review the planned changes:

    ```bash
    terraform plan -out=matrix.tfplan
    ```

7.  Apply the configuration:
    ```bash
    terraform apply "matrix.tfplan"
    ```

## Configuration

### Server Operating System

- The server runs Ubuntu 24.04.

### Server Type

- The configuration uses a Hetzner Cloud shared CPU instance. The default is provided in `modules/compute/variables.tf` (typically `cpx11`).
- You can override `server_type` in `environments/prod/terraform.tfvars` if needed.
- `cpx11` (2 vCPU, 2GB RAM) is generally sufficient for a personal setup.

### Location

- Specify your desired Hetzner Cloud location (e.g., `nbg1`, `fsn1`, `hel1`, `ash`, `hil`) in `environments/prod/terraform.tfvars` via the `location` variable.

### Storage

- A Hetzner Cloud Volume is attached to the server. Its size can be configured via `volume_size` in `modules/compute/variables.tf` (defaults to 10GB) and overridden if necessary.
- Docker volumes for Synapse (`/opt/synapse/data`) and PostgreSQL (`/opt/postgres/data`) are mapped to this attached volume, ensuring persistent storage.

### Network

- A private Hetzner network is configured, though primarily for potential future expansion or stricter host firewall rules. Synapse and PostgreSQL communicate via Docker's internal bridge network.
- Firewall rules are configured for necessary ports (SSH, HTTP, HTTPS, Matrix Federation).
- Cloudflare acts as the primary DNS provider and provides DDoS protection. The `A` record for the server is DNS-only.
- Nginx on the host handles SSL termination for client (port 443) and federation (port 8448) traffic using Let's Encrypt certificates obtained via Certbot. Both proxy to Synapse running on `127.0.0.1:8008`.

### Security

- SSL/TLS certificates for client and federation traffic are obtained via Certbot (Let's Encrypt) on the host and managed by Nginx.
- Cloudflare SSL/TLS mode should be set to "Full (strict)" to ensure end-to-end encryption.
- PostgreSQL access is restricted to the Synapse container via Docker networking. Ensure a strong `postgres_password`.
- Regular OS security updates are recommended (manual via `apt`).
- Synapse and PostgreSQL are run from official Docker images.
- Database backups are configured in the `user_data.sh` script, executed on server creation.

## Maintenance

### Backups

- PostgreSQL database backups are configured to run via a cron job on the host. The script uses `docker exec` to run `pg_dumpall` against the `matrix-postgres` container.
- Synapse media and configuration (including signing key) are stored in `/opt/synapse/data` on the host. This directory should be part of your server/volume backup strategy (e.g., Hetzner Cloud Snapshots for the volume).
- Backup retention days for the PostgreSQL dump can be configured via `backup_retention_days`.

### Updates

1.  **Operating System (Host)**: SSH into the server and run:
    ```bash
    sudo apt update && sudo apt dist-upgrade -y
    # Consider a reboot if a new kernel was installed
    # sudo reboot
    ```
2.  **Matrix Synapse & PostgreSQL (Docker Containers)**:
    - Navigate to the Docker Compose directory on the server (e.g., `/opt/synapse/`).
    - Pull the latest images:
      ```bash
      sudo docker-compose pull synapse postgres
      ```
    - Recreate the containers with the new images:
      ```bash
      sudo docker-compose up -d --remove-orphans synapse postgres
      ```
    - Prune old images if desired:
      ```bash
      sudo docker image prune -f
      ```
    - The `matrix-synapse-docker.service` systemd unit will manage the `docker-compose` stack.

### Monitoring

- Basic server monitoring is available via the Hetzner Cloud console.
- Consider setting up more advanced monitoring (e.g., Prometheus/Grafana, or a third-party service) if needed.
- Nginx logs are available via `journalctl -u nginx` on the host.
- Synapse container logs: `sudo docker logs matrix-synapse` (or the actual container name/ID if different, check `sudo docker ps`).
- PostgreSQL container logs: `sudo docker logs matrix-postgres` (or the actual container name/ID).
- Cloudflare provides analytics and DDoS protection insights.

## Troubleshooting

### Common Issues

1.  **SSL/TLS Issues**:
    - Verify Cloudflare SSL/TLS settings are "Full (strict)".
    - Ensure the primary `A` record for `${server_name}.${domain}` in Cloudflare is set to "DNS Only" (not proxied). This allows Certbot to perform HTTP-01 challenges correctly and for direct federation traffic to reach port 8448.
    - Ensure `SRV` records are correctly configured in Cloudflare and are DNS-only.
    - Check Nginx logs on the host: `sudo journalctl -u nginx -n 100 --no-pager`
    - Check Certbot renewal status: `sudo certbot renew --dry-run`
2.  **Database Connection Issues** (Synapse container can't reach PostgreSQL container):
    - Check PostgreSQL container logs: `sudo docker logs matrix-postgres`.
    - Verify the `database.args.host` in Synapse's `homeserver.yaml` (located in `/opt/synapse/data/homeserver.yaml` on the host) is set to `postgres` (the Docker service name).
    - Check Docker network: `sudo docker network ls`, `sudo docker network inspect <network_name>`. Both containers should be on the same Docker network created by Docker Compose.
    - Ensure the PostgreSQL container is running and healthy: `sudo docker ps`, `sudo docker-compose ps`.
3.  **Matrix Synapse Issues**:
    - Check Synapse container logs: `sudo docker logs matrix-synapse -n 200 --tail 0 -f`.
    - Verify `homeserver.yaml` configuration on the host (`/opt/synapse/data/homeserver.yaml`), especially `server_name` and database connection details.
    - Check disk space on the host, particularly the volume mounted at `/opt/synapse` and `/opt/postgres`.
    - Ensure the Docker Compose stack is running: `sudo systemctl status matrix-synapse-docker` or `cd /opt/synapse && sudo docker-compose ps`.

## Security Considerations

- Keep all secrets (API tokens, passwords) in `environments/prod/terraform.tfvars`. This file should **NOT** be committed to public Git repositories. Add it to your `.gitignore` file if it isn't already.
- Regularly update system packages on the host and Docker images for Synapse/PostgreSQL (see Maintenance section).
- Monitor system and container logs for suspicious activity.
- Use strong, unique passwords and secrets.
- Enable 2FA for your Hetzner and Cloudflare accounts.

## License

MIT License

## Contributing

1.  Fork the repository.
2.  Create a feature branch (`git checkout -b feature/AmazingFeature`).
3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4.  Push to the branch (`git push origin feature/AmazingFeature`).
5.  Open a Pull Request.
