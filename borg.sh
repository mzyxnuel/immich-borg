#!/bin/bash

set -a && source .env && set +a

# Create database backup directory
mkdir -p "$UPLOAD_LOCATION/database-backup"

# Initialize Borg repository if it doesn't exist or isn't valid
if [ ! -d "$BACKUP_PATH/immich-borg" ] || ! borg info "$BACKUP_PATH/immich-borg" >/dev/null 2>&1; then
    mkdir -p "$BACKUP_PATH/immich-borg"
    borg init --encryption=none "$BACKUP_PATH/immich-borg"

    echo "Initialized new Borg repository at $BACKUP_PATH/immich-borg"
fi

# Backup Immich database
echo "Starting database dump..."
docker exec -t immich_postgres pg_dumpall --clean --if-exists --username=$DB_USERNAME > "$UPLOAD_LOCATION"/database-backup/immich-database.sql

### Append to local Borg repository
echo "Creating Borg backup..."
echo "Backup started at: $(date)"
START_TIME=$(date +%s)

echo "Calculating backup size..."
BACKUP_SIZE=$(du -sb "$UPLOAD_LOCATION" --exclude="$UPLOAD_LOCATION/thumbs" --exclude="$UPLOAD_LOCATION/encoded-video" 2>/dev/null | cut -f1)
echo "Data to backup: $(numfmt --to=iec-i --suffix=B $BACKUP_SIZE)"

borg create --progress --stats --compression lz4 \
    "$BACKUP_PATH/immich-borg::{now}" "$UPLOAD_LOCATION" \
    --exclude "$UPLOAD_LOCATION"/thumbs/ \
    --exclude "$UPLOAD_LOCATION"/encoded-video/

BACKUP_END_TIME=$(date +%s)
BACKUP_DURATION=$((BACKUP_END_TIME - START_TIME))
echo "Backup completed in: $(date -ud "@$BACKUP_DURATION" +%T) ($(($BACKUP_DURATION / 60)) min $(($BACKUP_DURATION % 60)) sec)"

echo "Pruning old backups..."
PRUNE_START_TIME=$(date +%s)
borg prune --list --stats --keep-weekly=4 --keep-monthly=3 "$BACKUP_PATH"/immich-borg
PRUNE_END_TIME=$(date +%s)
PRUNE_DURATION=$((PRUNE_END_TIME - PRUNE_START_TIME))
echo "Pruning completed in: $(($PRUNE_DURATION / 60)) min $(($PRUNE_DURATION % 60)) sec"

echo "Compacting repository..."
COMPACT_START_TIME=$(date +%s)
borg compact --progress "$BACKUP_PATH"/immich-borg
COMPACT_END_TIME=$(date +%s)
COMPACT_DURATION=$((COMPACT_END_TIME - COMPACT_START_TIME))
echo "Compacting completed in: $(($COMPACT_DURATION / 60)) min $(($COMPACT_DURATION % 60)) sec"

TOTAL_END_TIME=$(date +%s)
TOTAL_DURATION=$((TOTAL_END_TIME - START_TIME))
echo "Total backup process completed at: $(date)"
echo "Total time: $(date -ud "@$TOTAL_DURATION" +%T) ($(($TOTAL_DURATION / 60)) min $(($TOTAL_DURATION % 60)) sec)"
