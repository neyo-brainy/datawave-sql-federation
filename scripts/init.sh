#!/bin/bash
# =============================================
# DataWave - Post-startup initialization
# Waits for Trino, then seeds Hive/MinIO data
# =============================================
set -e

TRINO_HOST="${TRINO_HOST:-localhost}"
TRINO_PORT="${TRINO_PORT:-8080}"
MAX_RETRIES=30
RETRY_INTERVAL=5

echo "=== DataWave Post-Startup Init ==="
echo "Waiting for Trino at ${TRINO_HOST}:${TRINO_PORT}..."

# Wait for Trino to be ready
for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf "http://${TRINO_HOST}:${TRINO_PORT}/v1/info" > /dev/null 2>&1; then
        echo "Trino is ready!"
        break
    fi
    if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "ERROR: Trino did not become ready after $((MAX_RETRIES * RETRY_INTERVAL))s"
        exit 1
    fi
    echo "  Attempt $i/$MAX_RETRIES - Trino not ready, retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

# Wait a bit more for catalogs to initialize
echo "Waiting 10s for catalogs to fully initialize..."
sleep 10

# Run the Hive/MinIO data init SQL via Trino CLI
echo "Seeding Hive/MinIO data lake tables..."
docker exec datawave-trino trino --execute "$(cat scripts/init-hive-data.sql)"

echo ""
echo "=== Init Complete ==="
echo ""
echo "Access points:"
echo "  Trino UI:       http://localhost:8080"
echo "  Metabase UI:    http://localhost:3000"
echo "  MinIO Console:  http://localhost:9001  (minioadmin/minioadmin)"
echo ""
echo "Try a federated query:"
echo '  docker exec datawave-trino trino --execute "SELECT s.tracking_number, c.name AS customer FROM postgresql.logistics.shipments s JOIN mysql.warehouse.customers c ON s.customer_id = c.id LIMIT 5"'
