#!/bin/bash

# Check if running as sudo
# if [ "$EUID" -ne 0 ]; then 
#     echo "Error: This script must be run as sudo"
#     exit 1
# fi

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "Error: .env file not found in current directory"
    echo "Please ensure the .env file exists and contains the required configuration"
    exit 1
fi

# Load environment variables first
set -a && source .env && set +a

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            cat << EOF
CURRENT CONFIGURATION:
    UPLOAD_LOCATION: ${UPLOAD_LOCATION:-"Not Set"}
    BACKUP_LOCATION: ${BACKUP_LOCATION:-"Not Set"}
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
    shift
done

# # Create database backup directory
# mkdir -p "$UPLOAD_LOCATION/$DB_DATABASE_NAME-database-backup"

# # Initialize Borg repository if it doesn't exist or isn't valid
BACKUP_DIRECTORY="$BACKUP_LOCATION/$DB_DATABASE_NAME"
# if [ ! -d "$BACKUP_DIRECTORY" ] || ! borg info "$BACKUP_DIRECTORY" >/dev/null 2>&1; then
#     mkdir -p "$BACKUP_DIRECTORY"
#     borg init --encryption=none "$BACKUP_DIRECTORY"

#     echo "Initialized new Borg repository at $BACKUP_DIRECTORY"
# fi

# Backup database
echo "Starting database dump..."
docker exec -t ${DB_DATABASE_NAME}_postgres pg_dumpall --clean --if-exists --username=$DB_USERNAME \
    | gzip > "$UPLOAD_LOCATION/$DB_DATABASE_NAME-database-backup/$DB_DATABASE_NAME.sql.gz"

### Append to local Borg repository
echo "Creating Borg backup..."
echo "Backup started at: $(date)"
START_TIME=$(date +%s)

echo "Calculating backup size..."
BACKUP_SIZE=$(du -sb "$UPLOAD_LOCATION" --exclude="$UPLOAD_LOCATION/thumbs" --exclude="$UPLOAD_LOCATION/encoded-video" 2>/dev/null | cut -f1)
echo "Data to backup: $(numfmt --to=iec-i --suffix=B $BACKUP_SIZE)"

borg create --progress --stats \
    "$BACKUP_DIRECTORY::{now}" "$UPLOAD_LOCATION" \
    --exclude "$UPLOAD_LOCATION"/thumbs/ \
    --exclude "$UPLOAD_LOCATION"/encoded-video/

BACKUP_END_TIME=$(date +%s)
BACKUP_DURATION=$((BACKUP_END_TIME - START_TIME))
echo "Backup completed in: $(date -ud "@$BACKUP_DURATION" +%T) ($(($BACKUP_DURATION / 60)) min $(($BACKUP_DURATION % 60)) sec)"

echo "Pruning old backups..."
PRUNE_START_TIME=$(date +%s)

borg prune --list --stats --keep-weekly=4 --keep-monthly=3 "$BACKUP_DIRECTORY"

PRUNE_END_TIME=$(date +%s)
PRUNE_DURATION=$((PRUNE_END_TIME - PRUNE_START_TIME))
echo "Pruning completed in: $(($PRUNE_DURATION / 60)) min $(($PRUNE_DURATION % 60)) sec"

echo "Compacting repository..."
COMPACT_START_TIME=$(date +%s)

borg compact --progress "$BACKUP_DIRECTORY"

COMPACT_END_TIME=$(date +%s)
COMPACT_DURATION=$((COMPACT_END_TIME - COMPACT_START_TIME))
echo "Compacting completed in: $(($COMPACT_DURATION / 60)) min $(($COMPACT_DURATION % 60)) sec"

TOTAL_END_TIME=$(date +%s)
TOTAL_DURATION=$((TOTAL_END_TIME - START_TIME))
echo "Total backup process completed at: $(date)"
echo "Total time: $(date -ud "@$TOTAL_DURATION" +%T) ($(($TOTAL_DURATION / 60)) min $(($TOTAL_DURATION % 60)) sec)"
