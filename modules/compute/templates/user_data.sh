#!/bin/bash
# shellcheck disable=SC2154,SC1091

# Log all output to a file and console for debugging
exec > >(tee -a /var/log/user_data.log|logger -t user_data -s 2>/dev/console) 2>&1

set -e
echo "INFO: Starting user_data.sh script execution for Dockerized Synapse and PostgreSQL..."

# Variables passed from Terraform
SERVER_NAME="${server_name}"
DOMAIN_NAME="${domain_name}"
POSTGRES_PASSWORD="${postgres_password}"
SYNAPSE_DB_USER="${synapse_db_user}"
SYNAPSE_DB_NAME="${synapse_db_name}"
SYNAPSE_REGISTRATION_SECRET="${synapse_registration_secret}"
SYNAPSE_MACAROON_SECRET="${synapse_macaroon_secret}"
BACKUP_RETENTION_DAYS="${backup_retention_days}"
CERTBOT_EMAIL="${certbot_email}"

export DEBIAN_FRONTEND=noninteractive

# Basic setup and updates
apt-get update -y || { echo "ERROR: Initial apt-get update failed"; exit 1; }

# Pre-configure postfix to avoid interactive prompts if it gets pulled as a dependency
echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections
echo "postfix postfix/mailname string $SERVER_NAME" | debconf-set-selections

apt-get upgrade -y || { echo "ERROR: apt-get upgrade failed"; exit 1; }
apt-get dist-upgrade -y || { echo "ERROR: apt-get dist-upgrade failed"; exit 1; }
apt-get install -y apt-transport-https ca-certificates curl software-properties-common unattended-upgrades gnupg lsb-release fail2ban wget jq haveged || { echo "ERROR: apt-get install base packages failed"; exit 1; }

# Configure unattended upgrades
cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

cat <<EOF > /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Allowed-Origins {
    "$${distro_id}:$${distro_codename}";
    "$${distro_id}:$${distro_codename}-security";
    "$${distro_id}ESMApps:$${distro_codename}-apps-security";
    "$${distro_id}ESMInfra:$${distro_codename}-infra-security";
    "$${distro_id}:$${distro_codename}-updates";
//  "$${distro_id}:$${distro_codename}-proposed";
//  "$${distro_id}:$${distro_codename}-backports";
};
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

systemctl enable unattended-upgrades
systemctl start unattended-upgrades

# Harden SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
# sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config # Further harden by disabling PAM if only key-based auth is used - Temporarily commented out for testing
systemctl restart ssh || { echo "ERROR: Failed to restart SSH service"; exit 1; }

# Install Docker and Docker Compose
if ! command -v docker >/dev/null 2>&1; then
  echo "INFO: Docker not found. Installing Docker and Docker Compose..."
  apt-get update -y || { echo "ERROR: apt-get update (before Docker) failed"; exit 1; }
  apt-get install -y ca-certificates curl gnupg lsb-release || { echo "ERROR: apt-get install Docker prerequisites failed"; exit 1; }
  install -m 0755 -d /etc/apt/keyrings || { echo "ERROR: Failed to create /etc/apt/keyrings"; exit 1; }
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || { echo "ERROR: Failed to download Docker GPG key"; exit 1; }
  chmod a+r /etc/apt/keyrings/docker.gpg || { echo "ERROR: Failed to chmod Docker GPG key"; exit 1; }
  OS_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $OS_CODENAME stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null || { echo "ERROR: Failed to add Docker APT repository"; exit 1; }
  apt-get update -y || { echo "ERROR: apt-get update (after adding Docker repo) failed"; exit 1; }
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { echo "ERROR: Failed to install Docker packages"; exit 1; }
  systemctl enable docker || { echo "ERROR: Failed to enable Docker service"; exit 1; }
  systemctl start docker || { echo "ERROR: Failed to start Docker service"; exit 1; }
  echo "INFO: Docker and Docker Compose installed successfully."
else
  echo "INFO: Docker is already installed. Skipping Docker install."
fi

# Setup data volume
# Determine the device path for the data volume
# Get the device for the root filesystem (e.g., /dev/sda1)
ROOT_FS_DEVICE=$(df / | awk 'NR==2{print $1}')
# Get the parent disk name for the root filesystem (e.g., sda)
ROOT_DISK_NAME=$(lsblk -no pkname "$ROOT_FS_DEVICE")
# Construct the full path for the root disk (e.g., /dev/sda)
ROOT_DISK_PATH="/dev/$ROOT_DISK_NAME"

echo "INFO: Root filesystem is on $ROOT_FS_DEVICE (parent disk $ROOT_DISK_PATH)."

# Find all disk-type devices, excluding the root disk and CD-ROMs (srX)
# Then take the first one found that is not the root disk.
DEVICE_PATH=$(lsblk -dpno NAME,TYPE | grep 'disk' | awk '{print $1}' | grep -vF "$ROOT_DISK_PATH" | grep -v '/dev/sr[0-9]' | head -n 1)

TARGET_MOUNT_POINT="/opt"

if [ -z "$DEVICE_PATH" ]; then
    echo "WARNING: No unmounted device found to format and mount for $TARGET_MOUNT_POINT. Docker data will be on root disk."
else
    # Ensure $DEVICE_PATH is mounted at $TARGET_MOUNT_POINT
    # Check if TARGET_MOUNT_POINT is already a mount point
    if findmnt -rno TARGET "$TARGET_MOUNT_POINT" >/dev/null; then
        # TARGET_MOUNT_POINT is mounted. Check if it's by our DEVICE_PATH.
        CURRENTLY_MOUNTED_DEVICE_AT_TARGET=$(findmnt -no SOURCE "$TARGET_MOUNT_POINT")
        if [ "$CURRENTLY_MOUNTED_DEVICE_AT_TARGET" == "$DEVICE_PATH" ]; then
            echo "INFO: $DEVICE_PATH is already mounted at $TARGET_MOUNT_POINT."
        else
            # /opt is mounted, but not by our intended DEVICE_PATH. This is a potential conflict.
            # For this script's purpose, we assume DEVICE_PATH should be authoritative for /opt.
            echo "WARNING: $TARGET_MOUNT_POINT is mounted by $CURRENTLY_MOUNTED_DEVICE_AT_TARGET, but script intends to use $DEVICE_PATH. Attempting to unmount $CURRENTLY_MOUNTED_DEVICE_AT_TARGET and mount $DEVICE_PATH."
            umount "$TARGET_MOUNT_POINT" || { echo "ERROR: Failed to unmount $CURRENTLY_MOUNTED_DEVICE_AT_TARGET from $TARGET_MOUNT_POINT. Cannot proceed with mounting $DEVICE_PATH."; exit 1; }
            # Proceed to mount $DEVICE_PATH
            echo "INFO: Proceeding with formatting (if needed) and mounting $DEVICE_PATH to $TARGET_MOUNT_POINT."
            if ! blkid -p -s TYPE -o value "$DEVICE_PATH" | grep -q ext4; then
                mkfs.ext4 -F "$DEVICE_PATH" || { echo "ERROR: mkfs.ext4 failed on $DEVICE_PATH"; exit 1; }
                echo "INFO: Successfully formatted $DEVICE_PATH with ext4."
            else
                echo "INFO: $DEVICE_PATH already has an ext4 filesystem. Skipping format."
            fi
            mkdir -p "$TARGET_MOUNT_POINT" || { echo "ERROR: Failed to create mount point $TARGET_MOUNT_POINT"; exit 1; }
            mount "$DEVICE_PATH" "$TARGET_MOUNT_POINT" || { echo "ERROR: Failed to mount $DEVICE_PATH to $TARGET_MOUNT_POINT. Device fstype: $(lsblk -no FSTYPE "$DEVICE_PATH")"; df -h; lsblk -f; exit 1; }
            echo "INFO: Successfully mounted $DEVICE_PATH to $TARGET_MOUNT_POINT."
        fi
    else
        # TARGET_MOUNT_POINT is NOT YET a mount point. Mount $DEVICE_PATH.
        echo "INFO: $TARGET_MOUNT_POINT not mounted. Proceeding with formatting and mounting $DEVICE_PATH."
        if ! blkid -p -s TYPE -o value "$DEVICE_PATH" | grep -q ext4; then
            mkfs.ext4 -F "$DEVICE_PATH" || { echo "ERROR: mkfs.ext4 failed on $DEVICE_PATH"; exit 1; }
            echo "INFO: Successfully formatted $DEVICE_PATH with ext4."
        else
            echo "INFO: $DEVICE_PATH already has an ext4 filesystem. Skipping format."
        fi
        mkdir -p "$TARGET_MOUNT_POINT" || { echo "ERROR: Failed to create mount point $TARGET_MOUNT_POINT"; exit 1; }
        mount "$DEVICE_PATH" "$TARGET_MOUNT_POINT" || { echo "ERROR: Failed to mount $DEVICE_PATH to $TARGET_MOUNT_POINT. Device fstype: $(lsblk -no FSTYPE "$DEVICE_PATH")"; df -h; lsblk -f; exit 1; }
        echo "INFO: Successfully mounted $DEVICE_PATH to $TARGET_MOUNT_POINT."
    fi

    # Add to fstab for persistence, using $DEVICE_PATH
    UUID=$(blkid -s UUID -o value "$DEVICE_PATH")
    if [ -z "$UUID" ]; then
        echo "ERROR: Failed to get UUID for $DEVICE_PATH. Cannot add to fstab."
    else
        # Define the desired fstab line, including x-systemd.automount
        DESIRED_FSTAB_LINE="UUID=$UUID $TARGET_MOUNT_POINT ext4 defaults,nofail,x-systemd.automount 0 2"

        # Check if the exact desired line already exists in /etc/fstab
        if grep -Fxq "$DESIRED_FSTAB_LINE" /etc/fstab; then
            echo "INFO: Correct fstab entry already exists: $DESIRED_FSTAB_LINE"
        else
            echo "INFO: Desired fstab entry not found or is incorrect. Updating /etc/fstab."
            # Remove any existing fstab entries for this UUID and TARGET_MOUNT_POINT to avoid duplicates or conflicts.
            # Using '#' as a delimiter for sed, as TARGET_MOUNT_POINT will contain '/'.
            # This command deletes any line starting with the specific UUID, followed by whitespace, then the specific TARGET_MOUNT_POINT, followed by whitespace.
            sed -i "\#^UUID=$${UUID}[[:space:]]\+$${TARGET_MOUNT_POINT}[[:space:]]#d" /etc/fstab || \
                { echo "WARNING: sed command to remove old fstab entry might have failed. Proceeding to add new entry anyway."; }

            # Add the desired line
            echo "$DESIRED_FSTAB_LINE" >> /etc/fstab || { echo "ERROR: Failed to add desired line to /etc/fstab"; exit 1; }
            echo "INFO: Added/Updated fstab entry to: $DESIRED_FSTAB_LINE"
        fi
    fi
fi

# Create directories for Synapse and PostgreSQL data on the mounted volume
mkdir -p /opt/synapse/data
mkdir -p /opt/postgres/data
chown -R 991:991 /opt/synapse/data # matrix-synapse user/group
# PostgreSQL container runs as postgres user (UID 70 in Alpine, GID 70)
# However, the initdb process might handle permissions if the dir is empty.
# For Alpine-based postgres, it often uses UID/GID 999 if the dir is owned by root.
# Let's ensure it's writable by the group that the postgres container might use, or a common one like 'docker' or leave it for the container to init.
# If issues arise, specific chown for postgres container UID/GID might be needed (e.g. chown 70:70 /opt/postgres/data for alpine postgres)

# Generate homeserver.yaml for Synapse
echo "INFO: Generating homeserver.yaml..."
SYNAPSE_CONFIG_PATH="/opt/synapse/data/homeserver.yaml"

# Ensure data directory exists for Synapse to generate keys/config into
if [ ! -d "/opt/synapse/data" ]; then
    mkdir -p "/opt/synapse/data"
    chown -R 991:991 "/opt/synapse/data"
fi

# Forcefully clean the data directory to ensure a fresh config generation
echo "INFO: Cleaning /opt/synapse/data/ before generating new config..."
find /opt/synapse/data/ -mindepth 1 -delete

# Use Docker to generate initial homeserver.yaml and signing key
# This ensures it uses the correct mechanisms internal to the Synapse image
docker run -i --rm \
    -v /opt/synapse/data:/data \
    -e SYNAPSE_SERVER_NAME="$SERVER_NAME" \
    -e SYNAPSE_REPORT_STATS=no \
    matrixdotorg/synapse:latest generate

# Modify homeserver.yaml (consider using yq or similar for robustness if available)
# Using sed for now for simplicity, ensure it is installed or use awk

# Enable registration and set shared secret
sed -i "s/#enable_registration: false/enable_registration: true/" $SYNAPSE_CONFIG_PATH
sed -i "/^#registration_shared_secret: <SECRET>/c\registration_shared_secret: \"$SYNAPSE_REGISTRATION_SECRET\"" $SYNAPSE_CONFIG_PATH

# Configure database (PostgreSQL)
echo "INFO: Configuring homeserver.yaml for PostgreSQL..."

# Define the new database configuration block as a literal string
# with correct YAML indentation.
# IMPORTANT: Ensure this string starts with 'database:' at no indent,
# and subsequent lines are correctly indented.
NEW_DB_CONFIG="database:
  name: psycopg2
  args:
    user: \"$SYNAPSE_DB_USER\"
    password: \"$POSTGRES_PASSWORD\"
    database: \"$SYNAPSE_DB_NAME\"
    host: \"postgres\"
    cp_min: 5
    cp_max: 10"

# Delete the old database block.
# This sed command finds the line starting with 'database:' and deletes
# it and all subsequent lines that start with whitespace, until it finds
# a line that does not start with whitespace (or end of file).
sed -i '/^database:/,/^[^[:space:]]/ { /^database:/ { :a; N; /\\n[^[:space:]]/! ba; D }; D }' $SYNAPSE_CONFIG_PATH

# Append the new database configuration block, ensuring a newline before it
# if the file doesn't end with one, and a newline after it.
printf '\n%s\n' "$NEW_DB_CONFIG" >> $SYNAPSE_CONFIG_PATH

# Set macaroon secret key
sed -i "s/macaroon_secret_key:.*$/macaroon_secret_key: \"$SYNAPSE_MACAROON_SECRET\"/" $SYNAPSE_CONFIG_PATH

# Optional: configure .well-known (though Nginx will handle this primarily)
# sed -i "s/#serve_server_wellknown: false/serve_server_wellknown: true/" $SYNAPSE_CONFIG_PATH

# Ensure media_store_path is set correctly (Synapse usually defaults this under /data)
# Example: sed -i "s#media_store_path:.*#media_store_path: /data/media_store#" $SYNAPSE_CONFIG_PATH

# Disable search (requires an external search engine and is complex)
if ! grep -q "search:" $SYNAPSE_CONFIG_PATH; then
  echo -e "\nsearch:\n  enable_search: false" >> $SYNAPSE_CONFIG_PATH
fi

# Make sure the signing key path is correct for the Docker volume mount
# The key is generated into /data/your.domain.name.signing.key by the generate command
# This should already be set correctly by the generate command relative to the data dir.
# Example if manual adjustment needed: SIGNING_KEY_PATH="/data/$SERVER_NAME.signing.key"
# sed -i "s|signing_key_path:.*|signing_key_path: $SIGNING_KEY_PATH|" $SYNAPSE_CONFIG_PATH

# Fix permissions after generation for Synapse container (UID 991, GID 991)
chown -R 991:991 /opt/synapse/data

# Create Docker Compose file
echo "INFO: Creating docker-compose.yml..."
cat <<EOF > /opt/synapse/docker-compose.yml
version: '3.8'
services:
  synapse:
    image: matrixdotorg/synapse:latest
    container_name: matrix-synapse
    restart: unless-stopped
    volumes:
      - /opt/synapse/data:/data # Mounts /opt/synapse/data to /data in container
    ports:
      - "127.0.0.1:8008:8008" # Expose Synapse on localhost only
    environment:
      - SYNAPSE_SERVER_NAME=$SERVER_NAME
      - SYNAPSE_REPORT_STATS=no
      # Ensure Synapse uses the homeserver.yaml we configured
      - SYNAPSE_CONFIG_PATH=/data/homeserver.yaml
      # Optional: If Synapse needs to generate a new config on first run if homeserver.yaml is missing
      # - SYNAPSE_CONFIG_DIR=/data
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - matrix_internal

  postgres:
    image: postgres:16-alpine
    container_name: matrix-postgres
    restart: unless-stopped
    volumes:
      - /opt/postgres/data:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=$SYNAPSE_DB_USER
      - POSTGRES_PASSWORD=$POSTGRES_PASSWORD
      - POSTGRES_DB=$SYNAPSE_DB_NAME
      - POSTGRES_INITDB_ARGS=--encoding=UTF-8 --lc-collate=C --lc-ctype=C
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $SYNAPSE_DB_USER -d $SYNAPSE_DB_NAME"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - matrix_internal

networks:
  matrix_internal:
EOF

# Systemd service for Docker Compose
echo "INFO: Setting up systemd service for Docker Compose stack..."
cat <<EOF > /etc/systemd/system/matrix-synapse-docker.service
[Unit]
Description=Matrix Synapse Docker Compose stack
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/synapse
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable matrix-synapse-docker.service
systemctl start matrix-synapse-docker.service

# Nginx setup
echo "INFO: Setting up Nginx..."
apt-get install -y nginx

# Configure Nginx for Matrix Synapse
# Remove default site
rm -f /etc/nginx/sites-enabled/default

# Create Nginx configuration for Matrix
cat <<EOF > /etc/nginx/sites-available/matrix
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $SERVER_NAME $DOMAIN_NAME; # Listen on both matrix.example.com and example.com for .well-known

    # For Certbot challenges and .well-known files for non-Matrix services (if any on root domain)
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location /.well-known/matrix/client {
        return 200 '{"m.homeserver": {"base_url": "https://$SERVER_NAME"},"m.identity_server": {"base_url": "https://vector.im"}}';
        add_header Content-Type application/json;
        add_header "Access-Control-Allow-Origin" "*";
    }

    location /.well-known/matrix/server {
        return 200 '{"m.server": "$SERVER_NAME:443"}';
        add_header Content-Type application/json;
        add_header "Access-Control-Allow-Origin" "*";
    }

    # Redirect all other HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name $SERVER_NAME;

    ssl_certificate /etc/letsencrypt/live/$SERVER_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$SERVER_NAME/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    # add_header Content-Security-Policy "default-src 'none'; frame-ancestors 'none';"; # Too restrictive for web clients

    location / {
        proxy_pass http://127.0.0.1:8008;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        client_max_body_size 128M; # For media uploads
    }
}

# Federation listener on 8448
server {
    listen 8448 ssl http2;
    listen [::]:8448 ssl http2;
    server_name $SERVER_NAME;

    ssl_certificate /etc/letsencrypt/live/$SERVER_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$SERVER_NAME/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://127.0.0.1:8008;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        client_max_body_size 128M;
    }
}
EOF

ln -s /etc/nginx/sites-available/matrix /etc/nginx/sites-enabled/matrix

# Certbot setup
echo "INFO: Setting up Certbot and obtaining SSL certificate..."
mkdir -p /var/www/html # For Certbot webroot challenges
apt-get install -y certbot python3-certbot-nginx

# Recommended SSL options from Certbot
if [ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > /etc/letsencrypt/options-ssl-nginx.conf
fi
if [ ! -f /etc/letsencrypt/ssl-dhparams.pem ]; then
    openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
fi

# Obtain SSL certificate from Let's Encrypt using Certbot
echo "INFO: Obtaining SSL certificate for $SERVER_NAME..."
# Staging: --staging
# Production: (remove --staging)
certbot certonly --webroot -w /var/www/html -d "$SERVER_NAME" --email "$CERTBOT_EMAIL" --agree-tos --no-eff-email --keep-until-expiring --staging --quiet || { echo "ERROR: Certbot failed to obtain certificate for $SERVER_NAME"; exit 1; }
echo "INFO: Certbot SSL certificate obtained successfully for $SERVER_NAME."

systemctl reload nginx

# Set up cron job for Certbot renewal
if ! systemctl list-timers | grep -q 'certbot.timer'; then
    echo "0 0,12 * * * root python3 -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew -q" | sudo tee -a /etc/crontab > /dev/null
fi

# Backup script for PostgreSQL
echo "INFO: Setting up PostgreSQL backup script..."
cat <<'EOT' > /usr/local/bin/backup_matrix_postgres.sh
#!/bin/bash
set -e

BACKUP_DIR="/opt/backups/postgres"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/matrix_db_backup_$TIMESTAMP.sql.gz"
LOG_FILE="$BACKUP_DIR/backup_log.txt"
RETENTION_DAYS=$${1:-7} # Default to 7 days if not provided (Escaped for Terraform templatefile)

mkdir -p "$BACKUP_DIR"

echo "Starting PostgreSQL backup at $(date)" >> "$LOG_FILE"

# Ensure the postgres container is running
if ! docker ps --filter "name=matrix-postgres" --filter "status=running" --format "{{.ID}}" | grep -q .; then
    echo "Error: matrix-postgres container is not running. Skipping backup." >> "$LOG_FILE"
    exit 1
fi

docker exec matrix-postgres pg_dumpall -U ${synapse_db_user} | gzip > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "Backup successful: $BACKUP_FILE" >> "$LOG_FILE"
else
    echo "Error: Backup failed." >> "$LOG_FILE"
    exit 1
fi

# Prune old backups
find "$BACKUP_DIR" -name "matrix_db_backup_*.sql.gz" -mtime +$RETENTION_DAYS -exec rm {} ;
echo "Old backups pruned. Kept backups from the last $RETENTION_DAYS days." >> "$LOG_FILE"
echo "Backup finished at $(date)" >> "$LOG_FILE"
EOT

chmod +x /usr/local/bin/backup_matrix_postgres.sh

# Add cron job for backup
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup_matrix_postgres.sh $BACKUP_RETENTION_DAYS") | crontab -

echo "INFO: User data script finished successfully."
exit 0
