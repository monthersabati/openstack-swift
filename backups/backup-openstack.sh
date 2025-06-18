#!/bin/bash

# CONFIGURATION
POOL_LIST=("os_vol_ssd_rep" "os_vol_hdd_rep" "os_images_ssd_rep")
BACKUP_DIR="/backups/ceph-rbd/openstack"
DATE=$(date +%F)
CEPH_CLUSTER="ceph"  # Or your cluster name
CEPH_CONF="/etc/ceph/ceph.conf"
COMPRESS_CMD="zstd -T0"  # Replace with gzip or lz4 if needed
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

# Logging
LOGFILE="$BACKUP_DIR/backup_$DATE.log"
FAILURE_FILE="$BACKUP_DIR/backup_failed"
#exec > >(tee -a "$LOGFILE") 2>&1

# Remove any existing failure tracking file
rm -f "$FAILURE_FILE"

MAX_JOBS=4  # Limit of parallel jobs
ANY_FAILED=false  # Flag to track if any job fails

# Function to limit concurrent background jobs
run_with_limit() {
    while [ "$(jobs -rp | wc -l)" -ge "$MAX_JOBS" ]; do
        sleep 1
    done
    "$@" &
}

# Function to backup a pool
backup_pool() {
    local pool=$1

    # Create backup directory
    mkdir -p "$BACKUP_DIR/$pool/$DATE"

    echo "Backing up pool: $pool"

    # List images in the pool
    IMAGES=$(rbd -c "$CEPH_CONF" -p "$pool" ls)

    for image in $IMAGES; do
        run_with_limit bash -c '
            pool="$1"
            image="$2"
            DATE="$3"
            BACKUP_DIR="$4"
            CEPH_CONF="$5"
            COMPRESS_CMD="$6"
            FAILURE_FILE="$7"

            echo "Backing up image: $pool/$image"
            SNAP="backup_${DATE}"
            EXPORT_FILE="${BACKUP_DIR}/${pool}/${DATE}/${image}.zst"

            echo "Creating snapshot: $image@$SNAP"
            rbd -c "$CEPH_CONF" snap create "$pool/$image@$SNAP" || { echo "Snapshot creation failed for $image"; echo "yes" > "$FAILURE_FILE"; exit 1; }

            echo "Exporting image: $image"
            time rbd -c "$CEPH_CONF" export --export-format 2 "$pool/$image@$SNAP" - | $COMPRESS_CMD > "$EXPORT_FILE" || { echo "Export failed for $image"; echo "yes" > "$FAILURE_FILE"; exit 1; }

            echo "Removing snapshot: $image@$SNAP"
            rbd -c "$CEPH_CONF" snap rm "$pool/$image@$SNAP" || { echo "Snapshot removal failed for $image"; echo "yes" > "$FAILURE_FILE"; exit 1; }

            echo "Finished backing up image: $pool/$image"
            ' bash "$pool" "$image" "$DATE" "$BACKUP_DIR" "$CEPH_CONF" "$COMPRESS_CMD" "$FAILURE_FILE"
    done
}

START_TIME=$(date +%s)

# Iterate through all pools
for pool in "${POOL_LIST[@]}"; do
    backup_pool "$pool"
done

# Cleanup old backups
find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

# Wait for all background jobs to complete and check if any failed
wait

END_TIME=$(date +%s)

# Calculate the duration
DURATION=$((END_TIME - START_TIME))
# Convert the duration to a human-readable format (hours, minutes, seconds)
HOURS=$((DURATION / 3600))
MINUTES=$(( (DURATION % 3600) / 60 ))
SECONDS=$((DURATION % 60))
echo "Script execution time: ${HOURS}h ${MINUTES}m ${SECONDS}s"
