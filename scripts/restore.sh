#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <backup.sql.gz>"
  exit 1
fi

BACKUP_FILE="$1"
CONTAINER="${POSTGRES_CONTAINER:-assessment-postgres}"
SOURCE_DB="${POSTGRES_DB:-bookings}"
DB_USER="${POSTGRES_USER:-postgres}"
RESTORE_DB="${RESTORE_DB:-bookings_restore}"

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "ERROR: Backup file not found: $BACKUP_FILE"
  exit 1
fi

if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q '^true$'; then
  echo "ERROR: PostgreSQL container '$CONTAINER' is not running."
  echo "Start it with: docker compose up -d"
  exit 1
fi

echo "Recreating temporary restore database: $RESTORE_DB"

docker exec "$CONTAINER" \
  psql -U "$DB_USER" -d postgres \
  -v ON_ERROR_STOP=1 \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$RESTORE_DB' AND pid <> pg_backend_pid();" \
  -c "DROP DATABASE IF EXISTS \"$RESTORE_DB\";" \
  -c "CREATE DATABASE \"$RESTORE_DB\";"

echo "Restoring: $BACKUP_FILE"

gzip -dc "$BACKUP_FILE" | \
  docker exec -i "$CONTAINER" \
    psql -U "$DB_USER" -d "$RESTORE_DB" -v ON_ERROR_STOP=1

source_count="$(
  docker exec "$CONTAINER" psql -U "$DB_USER" -d "$SOURCE_DB" -tAc \
    "SELECT COUNT(*) FROM hotel_bookings;"
)"

restore_count="$(
  docker exec "$CONTAINER" psql -U "$DB_USER" -d "$RESTORE_DB" -tAc \
    "SELECT COUNT(*) FROM hotel_bookings;"
)"

source_events="$(
  docker exec "$CONTAINER" psql -U "$DB_USER" -d "$SOURCE_DB" -tAc \
    "SELECT COUNT(*) FROM booking_events;"
)"

restore_events="$(
  docker exec "$CONTAINER" psql -U "$DB_USER" -d "$RESTORE_DB" -tAc \
    "SELECT COUNT(*) FROM booking_events;"
)"

if [[ "$source_count" != "$restore_count" ]]; then
  echo "ERROR: hotel_bookings row count mismatch: source=$source_count restore=$restore_count"
  exit 1
fi

if [[ "$source_events" != "$restore_events" ]]; then
  echo "ERROR: booking_events row count mismatch: source=$source_events restore=$restore_events"
  exit 1
fi

docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres \
  -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE \"$RESTORE_DB\";"

echo "Restore completed successfully."
echo "hotel_bookings rows: $restore_count"
echo "booking_events rows: $restore_events"
