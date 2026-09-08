#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER="${POSTGRES_CONTAINER:-assessment-postgres}"
DB_NAME="${POSTGRES_DB:-bookings}"
DB_USER="${POSTGRES_USER:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-backups}"

mkdir -p "$BACKUP_DIR"

if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q '^true$'; then
  echo "ERROR: PostgreSQL container '$CONTAINER' is not running."
  echo "Start it with: docker compose up -d"
  exit 1
fi

timestamp="$(date -u +%Y%m%d_%H%M%S)"
backup_file="${BACKUP_DIR}/${DB_NAME}_${timestamp}.sql.gz"

echo "Creating backup: ${backup_file}"

docker exec "$CONTAINER" \
  pg_dump \
    --username="$DB_USER" \
    --dbname="$DB_NAME" \
    --format=plain \
    --no-owner \
    --no-privileges \
  | gzip -9 > "$backup_file"

if [[ ! -s "$backup_file" ]]; then
  echo "ERROR: Backup file is empty."
  rm -f "$backup_file"
  exit 1
fi

echo "Backup completed successfully."
echo "File: $backup_file"
echo "Size: $(du -h "$backup_file" | cut -f1)"
