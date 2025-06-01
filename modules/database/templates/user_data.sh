#!/bin/bash
# shellcheck disable=SC2154
set -e

# Update system
apt-get update
apt-get upgrade -y
apt-get -y dist-upgrade
apt-get install -y fail2ban

# Install PostgreSQL
apt-get install -y postgresql postgresql-contrib

# Configure PostgreSQL
cat > /etc/postgresql/16/main/conf.d/matrix.conf << EOF
listen_addresses = '*'
max_connections = 100
shared_buffers = 256MB
effective_cache_size = 768MB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 4MB
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 2
max_parallel_workers_per_gather = 1
max_parallel_workers = 2
max_parallel_maintenance_workers = 1
EOF

# Create Matrix database and user
sudo -u postgres psql << EOF
CREATE USER synapse WITH PASSWORD '${postgres_password}';
CREATE DATABASE synapse OWNER synapse;
GRANT ALL PRIVILEGES ON DATABASE synapse TO synapse;
EOF

# Configure PostgreSQL authentication
cat > /etc/postgresql/16/main/pg_hba.conf << EOF
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
host    synapse         synapse          10.0.0.0/8             md5
EOF

# Restart PostgreSQL
systemctl restart postgresql

# Setup backup script
cat > /usr/local/bin/backup-postgres.sh << EOF
#!/bin/bash
BACKUP_DIR="/var/lib/postgresql/backups"
mkdir -p \$BACKUP_DIR
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
pg_dump -U postgres -d synapse > "\$BACKUP_DIR/synapse_\$TIMESTAMP.sql"
find \$BACKUP_DIR -type f -mtime +${backup_retention_days} -delete
EOF

chmod +x /usr/local/bin/backup-postgres.sh

# Add backup cron job
echo "0 1 * * * postgres /usr/local/bin/backup-postgres.sh" > /etc/cron.d/postgres-backup

# Reboot server
reboot
