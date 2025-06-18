#!/bin/bash

# CONFIGURATION
BACKUP_DIR="/backups/swift"
DATE=$(date +%F)
RETENTION_DAYS=7
export OS_USER_ID=0d04d8097c2e48b0ae2457ad86075b38
export OS_PASSWORD=0b24b045ef604Aad9377BccabDbd8eb9
export OS_USER_DOMAIN_NAME=Default
export OS_TENANT_ID=dfa6a7f8b338460c9a9308db982e750f
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://192.168.19.100:5000/v3
export OS_IDENTITY_API_VERSION=3

mkdir -p "$BACKUP_DIR"

# Logging
LOGFILE="$BACKUP_DIR/backup_$DATE.log"
# exec > >(tee -a "$LOGFILE") 2>&1

MAX_JOBS=4  # Limit of parallel jobs

# Function to limit concurrent background jobs
run_with_limit() {
    while [ "$(jobs -rp | wc -l)" -ge "$MAX_JOBS" ]; do
        sleep 1
    done
    "$@" &
}

# Function to backup a project
backup_project() {
    local project=$1
    local backup_dir=$2
    local backup_date=$3
    export OS_STORAGE_URL="http://192.168.19.100:8080/v1/AUTH_$project"

    mkdir -p "$backup_dir/$backup_date/$project"

    echo "Backing up project: $project"

    rclone sync "abriment-swift:" "$backup_dir/$backup_date/$project" \
        --transfers=4 \
        --checkers=4 \
        --fast-list \
        --copy-links \
        --use-mmap \
        --bwlimit=0 \
        --exclude='*+segments/**' \
        --log-level=INFO
}

START_TIME=$(date +%s)

# Get project IDs from keystone and back them up
mysql -Ns -h 192.168.19.100 -u backup -p'backup@abriment' -D keystone \
    -e "SELECT id FROM project WHERE domain_id='default' ORDER BY id" | while read -r project; do
    run_with_limit backup_project "$project" "$BACKUP_DIR" "$DATE"
done

# Cleanup old backups
find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" -exec rm -rf {} \;

# Wait for all background jobs
wait

END_TIME=$(date +%s)

# Script execution time
DURATION=$((END_TIME - START_TIME))
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$((DURATION % 60))
echo "Script execution time: ${HOURS}h ${MINUTES}m ${SECONDS}s"
