# DataWave Industries — SQL Federation Architecture

A local implementation of a SQL Federation Layer for DataWave Industries, unifying access to disparate data sources through a single Trino query engine. This project demonstrates how a logistics company can query across PostgreSQL, MySQL, and S3-compatible object storage using a single SQL endpoint.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Metabase (BI UI)                      │
│                    localhost:3000                        │
└──────────────────────────┬──────────────────────────────┘
                           │ JDBC
┌──────────────────────────▼──────────────────────────────┐
│                  Trino (Federation Engine)               │
│                    localhost:8080                        │
│          ┌───────────┼───────────┐                      │
│      PostgreSQL    MySQL      Hive                      │
│      Connector   Connector  Connector                   │
└──────┬───────────┬───────────┬──────────────────────────┘
       │           │           │
┌──────▼───┐ ┌────▼─────┐ ┌──▼───────────────────┐
│PostgreSQL│ │  MySQL   │ │  Hive Metastore      │
│Logistics │ │Warehouse │ │  (Catalog for S3)    │
│  :5432   │ │  :3306   │ │      :9083           │
└──────────┘ └──────────┘ └──────────┬───────────┘
                                     │
                           ┌─────────▼──────────┐
                           │   MinIO (S3)       │
                           │  API: :9000        │
                           │  Console: :9001    │
                           └────────────────────┘
```

### Components

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| **Trino** | `trinodb/trino:440` | 8080 | SQL federation engine — single query endpoint |
| **PostgreSQL** | `postgres:16` | 5432 | Data source: logistics (shipments, routes) |
| **MySQL** | `mysql:8.0` | 3306 | Data source: warehouse (customers, warehouses) |
| **MinIO** | `minio/minio` | 9000, 9001 | S3-compatible object storage |
| **Hive Metastore** | `bitsondatadev/hive-metastore` | 9083 | Metadata catalog for MinIO/S3 data |
| **Metastore DB** | `mysql:8.0` | — | MySQL backend for Hive Metastore |
| **Metabase** | `metabase/metabase` | 3000 | BI tool / query UI |
| **Keycloak** | `keycloak/keycloak:24.0` | 8180 | Identity Provider (SSO via OpenID Connect) |
| **OAuth2 Proxy** | `oauth2-proxy:v7.6.0` | 4180 | SSO-protected reverse proxy for Trino UI |
| **Trino Init** | `trinodb/trino:440` | — | One-shot: seeds Hive/MinIO data lake on startup |

### How It Maps to the Challenge Diagram

- **SQL Federation Engine** → Trino (single query endpoint at `:8080`)
- **Relational Data Sources** → PostgreSQL (logistics) + MySQL (warehouse)
- **Object Storage** → MinIO (S3-compatible, stores Parquet/data lake files)
- **Catalog/Metadata** → Hive Metastore (manages table metadata for S3 objects)
- **Query UI** → Metabase (BI tool connected to Trino via JDBC)

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (v20.10+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2.0+)
- At least **4 GB of available RAM** for Docker

## Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/adeniyiajobiewe/datawave-sql-federation.git
cd datawave-sql-federation
```

### 2. Start All Services

```bash
docker compose up -d
```

This pulls all required images and starts the entire stack. First run may take a few minutes for image downloads.

### 3. Verify All Services Are Running

```bash
docker compose ps
```

All services should show status `Up` or `healthy`.

### 4. Validate Trino Is Ready

```bash
docker exec -it datawave-trino trino --execute "SHOW CATALOGS"
```

Expected output should include: `hive`, `mysql`, `postgresql`, `system`.

### 5. Validate Data Sources

PostgreSQL and MySQL are seeded automatically on first startup via `init.sql` scripts. The Hive/MinIO data lake is seeded automatically by the `trino-init` container once Trino is healthy.

```bash
# Check PostgreSQL data (expect 20 rows)
docker exec -it datawave-trino trino --execute \
  "SELECT count(*) FROM postgresql.logistics.shipments"

# Check MySQL data (expect 10 rows)
docker exec -it datawave-trino trino --execute \
  "SELECT count(*) FROM mysql.warehouse.customers"

# Check Hive/MinIO data (expect 20 rows)
docker exec -it datawave-trino trino --execute \
  "SELECT count(*) FROM hive.datalake.shipping_events"
```

### 6. Verify Full Federation

Run a three-way federated JOIN across all three data sources:

```bash
docker exec -it datawave-trino trino --execute "
SELECT s.tracking_number, c.name AS customer, e.event_type, e.location
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
JOIN hive.datalake.shipping_events e ON s.tracking_number = e.tracking_number
WHERE e.event_type = 'delivered'
ORDER BY s.tracking_number
"
```

If this returns rows, all three data sources are federated correctly.

## Usage Guide

> **For a comprehensive guide** covering all Trino clients (CLI, Web UI, Metabase, REST API, JDBC, direct database access), complete data model reference, and query cookbook, see the full [User Guide](docs/USER_GUIDE.md).

### Accessing the Query Interfaces

| Interface | URL | Credentials |
|-----------|-----|-------------|
| **Trino Web UI** | http://localhost:8080 | Any username (no password) |
| **Trino Web UI (SSO)** | http://localhost:4180 | Keycloak login (see [SSO section](#sso-single-sign-on)) |
| **Metabase** | http://localhost:3000 | Set up on first visit |
| **MinIO Console** | http://localhost:9001 | `minioadmin` / `minioadmin` |
| **Keycloak Admin** | http://localhost:8180 | `admin` / `admin` |

### Using Trino CLI

```bash
# Open an interactive Trino session
docker exec -it datawave-trino trino
```

### Connecting Metabase to Trino

1. Open http://localhost:3000 and complete the initial setup wizard.
2. When adding a database, choose **Starburst** (Trino-compatible driver).
3. Configure with:
   - **Host**: `trino`
   - **Port**: `8080`
   - **Database**: `postgresql` (or any catalog)
   - **User**: `trino`

### Example SQL Queries

#### Single-Source: List Shipments (PostgreSQL)
```sql
SELECT tracking_number, origin, destination, status, weight_kg
FROM postgresql.logistics.shipments
ORDER BY shipped_date DESC;
```

#### Single-Source: List Customers (MySQL)
```sql
SELECT name, country, tier
FROM mysql.warehouse.customers
ORDER BY name;
```

#### Cross-Source JOIN: Shipments with Customer Details
```sql
SELECT
    s.tracking_number,
    s.origin,
    s.destination,
    s.status,
    c.name AS customer_name,
    c.country AS customer_country,
    c.tier AS customer_tier
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
ORDER BY s.shipped_date DESC;
```

#### Cross-Source JOIN: Full Supply Chain View
```sql
SELECT
    s.tracking_number,
    c.name AS customer,
    c.tier,
    w.name AS warehouse,
    w.city AS warehouse_city,
    s.origin,
    s.destination,
    s.status,
    s.weight_kg
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
JOIN mysql.warehouse.warehouses w ON s.warehouse_id = w.id
ORDER BY s.shipped_date DESC;
```

#### Analytical: Shipment Volume by Customer Tier
```sql
SELECT
    c.tier AS customer_tier,
    COUNT(s.id) AS total_shipments,
    ROUND(SUM(s.weight_kg), 2) AS total_weight_kg
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
GROUP BY c.tier
ORDER BY total_shipments DESC;
```

More examples are available in [`scripts/example-queries.sql`](scripts/example-queries.sql).

### Querying the Hive/MinIO Data Lake

After running the init script (step 6 above), you can query the data lake tables:

```sql
-- List shipping events from MinIO
SELECT event_id, tracking_number, event_type, location
FROM hive.datalake.shipping_events
ORDER BY event_timestamp;

-- List carrier rates from MinIO
SELECT carrier_name, transport_mode, region, rate_per_kg
FROM hive.datalake.carrier_rates;

-- Three-way JOIN: PostgreSQL + MySQL + Hive/MinIO
SELECT
    s.tracking_number,
    c.name AS customer,
    e.event_type,
    e.event_timestamp,
    e.location
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
JOIN hive.datalake.shipping_events e ON s.tracking_number = e.tracking_number
ORDER BY e.event_timestamp;
```

You can also create your own tables in the data lake:

```sql
CREATE TABLE hive.datalake.my_table (
    id INT, name VARCHAR
) WITH (format = 'PARQUET');

INSERT INTO hive.datalake.my_table VALUES (1, 'example');
```

Trino writes Parquet files into MinIO automatically — you can browse them at http://localhost:9001.

### Adding New Connectors

1. Create a new `.properties` file in `trino/etc/catalog/`:
   ```properties
   connector.name=<connector-type>
   connection-url=<jdbc-url>
   connection-user=<user>
   connection-password=<password>
   ```
2. Add the corresponding service to `docker-compose.yml` if needed.
3. Restart Trino: `docker compose restart trino`

## SSO (Single Sign-On)

This project includes an OpenID Connect (OIDC) SSO integration using **Keycloak** as the Identity Provider and **OAuth2 Proxy** as the authentication gateway.

### How It Works

1. User navigates to http://localhost:4180 (SSO-protected Trino UI).
2. OAuth2 Proxy redirects to the Keycloak login page at http://localhost:8180.
3. User authenticates with their Keycloak credentials.
4. Keycloak issues an OIDC token and redirects back to OAuth2 Proxy.
5. OAuth2 Proxy validates the token, creates a session cookie, and proxies the request to the Trino Web UI.

```
User → OAuth2 Proxy (:4180) → Keycloak (:8180) → authenticate
     → redirect back → OAuth2 Proxy validates token → Trino UI (:8080)
```

### Test Users

| Username | Password | Role |
|----------|----------|------|
| `datawave-admin` | `admin123` | Administrator |
| `datawave-analyst` | `analyst123` | Analyst |

### Accessing the SSO-Protected Trino UI

1. Open http://localhost:4180 in your browser.
2. Click **Sign in with Keycloak OIDC**.
3. Enter credentials (e.g., `datawave-admin` / `admin123`).
4. After successful login, you are proxied to the Trino Web UI.

### Keycloak Admin Console

Access the Keycloak admin console at http://localhost:8180 with `admin` / `admin` to manage:
- Realms, clients, and identity providers
- Users, roles, and groups
- Authentication flows and session policies

> **Note:** Direct access to the Trino UI at http://localhost:8080 remains available for CLI/API usage. The SSO-protected endpoint at `:4180` is recommended for browser-based access.

For detailed SSO configuration, authentication flow diagrams, and Azure AD integration guidance, see the [User Guide — SSO Section](docs/USER_GUIDE.md#8-sso-single-sign-on).

## Stopping the Environment

```bash
# Stop all services
docker compose down

# Stop and remove all data volumes (clean restart)
docker compose down -v
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Trino can't connect to PostgreSQL/MySQL | Ensure databases are healthy: `docker compose ps`. Wait for healthchecks to pass. |
| Hive Metastore fails to start | Check metastore-db is healthy first. View logs: `docker logs datawave-hive-metastore` |
| MinIO buckets not created | Run `docker compose up minio-init` to reinitialize buckets. |
| Port conflicts | Change host ports in `docker-compose.yml` (e.g., `5433:5432` for PostgreSQL). |
| Trino out of memory | Increase Docker memory allocation to at least 4 GB. |
| Metabase can't find Starburst driver | Use the "Other Databases" → "Starburst" option, or connect via the built-in Trino driver. |

## Project Structure

```
.
├── docker-compose.yml              # Orchestrates all services
├── README.md                       # This file
├── docs/
│   └── USER_GUIDE.md              # Comprehensive user guide
├── keycloak/
│   └── datawave-realm.json         # Keycloak realm with SSO clients and users
├── trino/
│   └── etc/
│       ├── config.properties       # Trino coordinator config
│       ├── jvm.config              # JVM settings
│       ├── node.properties         # Node identity
│       ├── log.properties          # Logging level
│       └── catalog/
│           ├── postgresql.properties   # PostgreSQL connector
│           ├── mysql.properties        # MySQL connector
│           └── hive.properties         # Hive/S3 connector
├── postgres/
│   └── init.sql                    # Seed data: shipments, routes
├── mysql/
│   └── init.sql                    # Seed data: customers, warehouses
├── hive-metastore/
│   └── metastore-site.xml          # Hive Metastore configuration
└── scripts/
    ├── init.sh                     # Post-startup init (seeds Hive/MinIO)
    ├── init-hive-data.sql          # SQL to create data lake tables
    └── example-queries.sql         # Federation query examples
```
