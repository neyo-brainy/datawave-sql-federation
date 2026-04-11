# DataWave SQL Federation — User Guide

This guide covers every way to interact with the DataWave SQL Federation platform. It walks through each client available in this environment, from graphical interfaces to command-line tools to programmatic APIs.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Starting the Environment](#starting-the-environment)
- [Client Overview](#client-overview)
- [1. Trino CLI (Command Line)](#1-trino-cli-command-line)
- [2. Trino Web UI](#2-trino-web-ui)
- [3. Metabase (BI Tool)](#3-metabase-bi-tool)
- [4. Trino REST API](#4-trino-rest-api)
- [5. JDBC Connections (Programmatic)](#5-jdbc-connections-programmatic)
- [6. MinIO Console (Object Storage Browser)](#6-minio-console-object-storage-browser)
- [7. Direct Database Clients](#7-direct-database-clients)
- [8. SSO (Single Sign-On)](#8-sso-single-sign-on)
- [Data Model Reference](#data-model-reference)
- [Query Cookbook](#query-cookbook)
- [Managing the Data Lake](#managing-the-data-lake)
- [Adding New Data Source Connectors](#adding-new-data-source-connectors)
- [Stopping and Resetting the Environment](#stopping-and-resetting-the-environment)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (v20.10+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2.0+)
- At least **4 GB of available RAM** allocated to Docker
- `curl` (for REST API usage)
- A JDBC-capable tool (optional — for programmatic access, e.g., DBeaver, DataGrip, or a Python/Java application)

## Starting the Environment

```bash
# Start all services in detached mode
docker compose up -d

# Verify all services are healthy
docker compose ps
```

Wait until all services show `Up` and `(healthy)` status. The `trino-init` container will seed the Hive/MinIO data lake automatically and then exit — this is expected.

---

## Client Overview

This environment provides multiple ways to query and interact with the Trino federation engine and the underlying data sources:

| # | Client | Type | Access | Best For |
|---|--------|------|--------|----------|
| 1 | **Trino CLI** | Command line | `docker exec` into container | Ad-hoc queries, scripting, automation |
| 2 | **Trino Web UI** | Browser | http://localhost:8080 | Monitoring queries, viewing query plans |
| 3 | **Metabase** | Browser (BI tool) | http://localhost:3000 | Dashboards, visualizations, non-technical users |
| 4 | **Trino REST API** | HTTP API | `POST http://localhost:8080/v1/statement` | Application integration, programmatic access |
| 5 | **JDBC Driver** | Programmatic | `jdbc:trino://localhost:8080` | Java/Python/Go apps, database tools (DBeaver, DataGrip) |
| 6 | **MinIO Console** | Browser | http://localhost:9001 | Browsing S3 buckets, inspecting Parquet files |
| 7 | **Direct DB Clients** | Command line | `psql` / `mysql` CLI | Debugging individual data sources directly |

---

## 1. Trino CLI (Command Line)

The Trino CLI is a terminal-based interactive SQL client. It is pre-installed inside the `datawave-trino` container.

### Opening an Interactive Session

```bash
docker exec -it datawave-trino trino
```

This drops you into an interactive SQL prompt:

```
trino>
```

You can now type any SQL query and press Enter to execute it.

### Selecting a Default Catalog and Schema

By default, you must fully qualify table names (e.g., `postgresql.logistics.shipments`). To avoid this, set a default catalog and schema when connecting:

```bash
# Default to the PostgreSQL logistics schema
docker exec -it datawave-trino trino --catalog postgresql --schema logistics
```

Now you can query without full qualification:

```sql
-- Instead of: SELECT * FROM postgresql.logistics.shipments
SELECT * FROM shipments LIMIT 5;
```

### Running a Single Query (Non-Interactive)

Use `--execute` to run a query and return to your shell immediately:

```bash
docker exec -it datawave-trino trino --execute "SELECT count(*) FROM postgresql.logistics.shipments"
```

### Running Queries from a SQL File

Mount or copy a SQL file into the container and execute it:

```bash
# Run the example queries file
docker exec -i datawave-trino trino < scripts/example-queries.sql
```

Or pipe a query via stdin:

```bash
echo "SELECT count(*) FROM mysql.warehouse.customers" | docker exec -i datawave-trino trino
```

### Useful CLI Commands

| Command | Description |
|---------|-------------|
| `SHOW CATALOGS;` | List all configured data source catalogs |
| `SHOW SCHEMAS FROM postgresql;` | List schemas within a catalog |
| `SHOW TABLES FROM postgresql.logistics;` | List tables within a schema |
| `DESCRIBE postgresql.logistics.shipments;` | Show columns and types for a table |
| `SHOW COLUMNS FROM mysql.warehouse.customers;` | Alternative column listing |
| `EXPLAIN SELECT ...;` | Show the query execution plan |
| `EXPLAIN ANALYZE SELECT ...;` | Show plan with actual runtime statistics |

### Output Formatting

The CLI supports output format control:

```bash
# CSV output (useful for piping to files or other tools)
docker exec -it datawave-trino trino --output-format CSV \
  --execute "SELECT tracking_number, status FROM postgresql.logistics.shipments"

# Tab-separated output
docker exec -it datawave-trino trino --output-format TSV \
  --execute "SELECT name, country FROM mysql.warehouse.customers"

# JSON output
docker exec -it datawave-trino trino --output-format JSON \
  --execute "SELECT name, tier FROM mysql.warehouse.customers"
```

### Exiting the CLI

Type `quit` or `exit`, or press `Ctrl+D`.

---

## 2. Trino Web UI

The Trino Web UI is a built-in monitoring dashboard accessible at:

**URL:** http://localhost:8080

**Login:** Enter any username (e.g., `admin`) — no password is required in this development setup.

### What the Web UI Shows

The Web UI is **read-only** — you cannot execute queries from it. It is a monitoring and debugging tool that shows:

- **Active Queries** — Currently running queries with progress indicators
- **Completed Queries** — History of recently executed queries
- **Query Details** — Click any query to see:
  - Full SQL text
  - Execution plan (stages and splits)
  - Resource usage (CPU time, memory, I/O)
  - Timeline and duration breakdown
  - Error details (if the query failed)
- **Cluster Overview** — Node health, active workers, memory utilization
- **Resource Groups** — Query queue and concurrency status

### Typical Workflow

1. Open http://localhost:8080 in your browser.
2. Enter any username (e.g., `trino`) and click **Log In**.
3. Run a query using any other client (e.g., Trino CLI).
4. Watch the query appear in the **Active Queries** list.
5. Click the query ID to inspect the execution plan, stages, and resource usage.

### When to Use the Web UI

- Investigating slow queries — check the execution plan and split distribution.
- Monitoring cluster resource usage during heavy workloads.
- Debugging failed queries — the error tab shows detailed stack traces.
- Understanding how Trino distributes work across federation sources.

---

## 3. Metabase (BI Tool)

Metabase is a graphical BI tool that connects to Trino via JDBC, providing a visual query builder, charting, and dashboarding capabilities.

**URL:** http://localhost:3000

### First-Time Setup

On your first visit, Metabase will walk you through an initial setup wizard:

1. **Open** http://localhost:3000 in your browser.
2. **Choose language** and click **Next**.
3. **Create an admin account** — enter your name, email, and password. These are Metabase credentials only (not Trino credentials).
4. **Add your data** — this is where you connect Metabase to Trino:
   - Click **Add a database**.
   - Select **Starburst** as the database type (Trino-compatible).
   - Fill in the connection details:

| Field | Value |
|-------|-------|
| **Display name** | `Trino Federation` (or any name) |
| **Host** | `trino` |
| **Port** | `8080` |
| **Catalog** | `postgresql` |
| **Schema (optional)** | `logistics` |
| **Username** | `trino` |
| **Password** | *(leave empty)* |

5. Click **Save** to test and save the connection.
6. **Usage data preferences** — Metabase asks whether you'd like to share anonymous usage data. Check or uncheck the **Allow Metabase to anonymously collect usage events** checkbox based on your preference, then click **Finish**.

> **Note:** Metabase connects to Trino using the Docker internal hostname `trino`, not `localhost`, because Metabase runs inside the same Docker network.

> **Important:** The catalog you specify (e.g., `postgresql`) is only the **default** catalog. You can still query **all** catalogs using fully-qualified table names (e.g., `mysql.warehouse.customers` or `hive.datalake.shipping_events`) from this single connection. Cross-catalog federated JOINs work without any additional configuration.

### Adding Additional Catalog Connections (Optional)

For convenience when using the **visual query builder** (which only browses the default catalog's tables), you can add separate Metabase connections for each catalog:

1. Go to **Admin** (gear icon, top-right) → **Databases** → **Add database**.
2. Select **Starburst** and configure each connection:

**MySQL Warehouse connection:**

| Field | Value |
|-------|-------|
| **Display name** | `Trino — MySQL Warehouse` |
| **Host** | `trino` |
| **Port** | `8080` |
| **Catalog** | `mysql` |
| **Schema (optional)** | `warehouse` |
| **Username** | `trino` |
| **Password** | *(leave empty)* |

**Hive Data Lake connection:**

| Field | Value |
|-------|-------|
| **Display name** | `Trino — Hive Data Lake` |
| **Host** | `trino` |
| **Port** | `8080` |
| **Catalog** | `hive` |
| **Schema (optional)** | `datalake` |
| **Username** | `trino` |
| **Password** | *(leave empty)* |

3. Click **Save** for each.

This lets you browse MySQL and Hive tables in the visual query builder. For custom SQL queries, a single connection is sufficient since you can use fully-qualified names.

### Querying with the Visual Query Builder

1. Click **New** → **Question** in the top navigation.
2. Select your Trino database connection.
3. Choose a table (e.g., `shipments`).
4. Use the drag-and-drop interface to:
   - Pick columns.
   - Add filters (e.g., `status = 'delivered'`).
   - Summarize data (count, sum, average).
   - Sort results.
5. Click **Visualize** to run the query and see results.

### Writing Custom SQL in Metabase

1. Click **New** → **SQL Query**.
2. Select any one of your Trino database connections from the dropdown (top-left). The dropdown only allows selecting one connection at a time, but this does **not** limit which catalogs you can query — all connections point to the same Trino federation engine, so fully-qualified table names (e.g., `mysql.warehouse.customers`) work regardless of which connection you selected.
3. Write any SQL query, including cross-source federated queries:

```sql
SELECT
    s.tracking_number,
    c.name AS customer,
    c.tier,
    s.status,
    s.weight_kg
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
WHERE c.tier = 'platinum'
ORDER BY s.weight_kg DESC
```

4. Click the **Run** button (or press `Ctrl+Enter`).
5. Results appear in a table below. Click the **Visualization** dropdown to switch to charts (bar, line, pie, etc.).

### Creating Dashboards

1. Save a question by clicking **Save** and choosing a collection.
2. Click **New** → **Dashboard**.
3. Drag saved questions onto the dashboard canvas.
4. Add filters that apply across multiple cards.
5. Save and share the dashboard.

### When to Use Metabase

- Non-technical stakeholders who need a visual interface.
- Building recurring dashboards and reports.
- Exploring data without writing SQL (visual query builder).
- Sharing query results with a team.

---

## 4. Trino REST API

Trino exposes a REST API at `http://localhost:8080/v1/` that allows you to submit queries and retrieve results programmatically over HTTP.

### API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/v1/info` | GET | Cluster info (version, uptime, status) |
| `/v1/statement` | POST | Submit a SQL query |
| `/v1/query` | GET | List active queries |
| `/v1/query/{queryId}` | GET | Get details of a specific query |
| `/v1/query/{queryId}` | DELETE | Cancel a running query |

### Checking Cluster Info

```bash
curl -s http://localhost:8080/v1/info | python3 -m json.tool
```

Output:

```json
{
    "nodeVersion": { "version": "440" },
    "environment": "docker",
    "coordinator": true,
    "starting": false,
    "uptime": "12.81m"
}
```

### Submitting a Query

```bash
curl -s -X POST http://localhost:8080/v1/statement \
  -H "X-Trino-User: api-user" \
  -H "X-Trino-Source: curl" \
  -d "SELECT name, country, tier FROM mysql.warehouse.customers ORDER BY name"
```

The response contains a `nextUri` field. Trino queries are **asynchronous** — you must poll `nextUri` to retrieve results.

### Polling for Results

The initial response returns a `nextUri`. Follow it to get the next batch of results:

```bash
# Step 1: Submit the query
RESPONSE=$(curl -s -X POST http://localhost:8080/v1/statement \
  -H "X-Trino-User: api-user" \
  -d "SELECT name, tier FROM mysql.warehouse.customers LIMIT 5")

# Step 2: Extract nextUri and poll
NEXT_URI=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('nextUri',''))")

while [ -n "$NEXT_URI" ]; do
    RESPONSE=$(curl -s "$NEXT_URI")
    echo "$RESPONSE" | python3 -m json.tool

    # Extract the next URI (empty when results are complete)
    NEXT_URI=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('nextUri',''))" 2>/dev/null)
done
```

The final response contains a `data` array with the query results and a `columns` array describing the schema.

### Required Headers

| Header | Required | Description |
|--------|----------|-------------|
| `X-Trino-User` | Yes | Username for the query (any string in this dev setup) |
| `X-Trino-Source` | No | Identifies the client application |
| `X-Trino-Catalog` | No | Default catalog for unqualified table names |
| `X-Trino-Schema` | No | Default schema for unqualified table names |
| `X-Trino-Time-Zone` | No | Session time zone (e.g., `America/New_York`) |

### Cancelling a Query

```bash
# List active queries
curl -s http://localhost:8080/v1/query | python3 -m json.tool | head -20

# Cancel a specific query by ID
curl -s -X DELETE http://localhost:8080/v1/query/<query-id>
```

### When to Use the REST API

- Building custom applications that query Trino.
- Integrating Trino into CI/CD pipelines or data workflows.
- Lightweight scripts where JDBC drivers are not available.
- Health checks and monitoring integrations.

---

## 5. JDBC Connections (Programmatic)

Trino provides a JDBC driver that allows any JDBC-compatible application or programming language to connect. This is the standard way to integrate Trino into applications.

### Connection Details

| Property | Value |
|----------|-------|
| **JDBC URL** | `jdbc:trino://localhost:8080` |
| **Driver Class** | `io.trino.jdbc.TrinoDriver` |
| **Username** | Any string (e.g., `trino`) |
| **Password** | *(empty — no auth in dev mode)* |
| **Maven Artifact** | `io.trino:trino-jdbc:440` |
| **PyPI Package** | `trino` |

### Using Database GUI Tools (DBeaver, DataGrip)

#### DBeaver

1. Open DBeaver and click **New Database Connection**.
2. Search for **Trino** in the driver list and select it.
3. Enter the connection details:
   - **Host**: `localhost`
   - **Port**: `8080`
   - **Database/Catalog**: `postgresql` (or leave blank to browse all catalogs)
   - **Username**: `trino`
4. Click **Test Connection** to verify, then **Finish**.
5. In the Database Navigator, expand the connection to browse catalogs → schemas → tables.

#### DataGrip / IntelliJ

1. Open **Database** tool window → **+** → **Data Source** → **Trino**.
2. Set:
   - **Host**: `localhost`
   - **Port**: `8080`
   - **User**: `trino`
   - **URL**: `jdbc:trino://localhost:8080`
3. Download the driver if prompted.
4. Click **Test Connection**, then **OK**.

### Python (using the `trino` library)

Install the driver:

```bash
pip install trino
```

Query example:

```python
from trino.dbapi import connect

conn = connect(
    host="localhost",
    port=8080,
    user="python-app",
    catalog="postgresql",
    schema="logistics",
)

cursor = conn.cursor()
cursor.execute("SELECT tracking_number, origin, destination, status FROM shipments LIMIT 5")

for row in cursor.fetchall():
    print(row)

cursor.close()
conn.close()
```

Cross-source federated query:

```python
cursor = conn.cursor()
cursor.execute("""
    SELECT s.tracking_number, c.name AS customer, c.tier
    FROM postgresql.logistics.shipments s
    JOIN mysql.warehouse.customers c ON s.customer_id = c.id
    WHERE c.tier = 'platinum'
""")

for row in cursor.fetchall():
    print(f"Tracking: {row[0]}, Customer: {row[1]}, Tier: {row[2]}")
```

### Java

Add the Maven dependency:

```xml
<dependency>
    <groupId>io.trino</groupId>
    <artifactId>trino-jdbc</artifactId>
    <version>440</version>
</dependency>
```

Query example:

```java
import java.sql.*;

public class TrinoExample {
    public static void main(String[] args) throws Exception {
        String url = "jdbc:trino://localhost:8080/postgresql/logistics";
        Connection conn = DriverManager.getConnection(url, "java-app", null);

        Statement stmt = conn.createStatement();
        ResultSet rs = stmt.executeQuery(
            "SELECT tracking_number, status FROM shipments LIMIT 5"
        );

        while (rs.next()) {
            System.out.printf("Tracking: %s, Status: %s%n",
                rs.getString("tracking_number"),
                rs.getString("status"));
        }

        rs.close();
        stmt.close();
        conn.close();
    }
}
```

### When to Use JDBC

- Connecting database GUI tools like DBeaver or DataGrip for interactive exploration.
- Building data pipelines or ETL jobs.
- Application backends that need federated query results.
- Any language or tool that supports JDBC (Java, Python, Go, etc.).

---

## 6. MinIO Console (Object Storage Browser)

MinIO provides a web-based console to browse the S3-compatible object storage that backs the Hive data lake.

**URL:** http://localhost:9001

**Credentials:**

| Field | Value |
|-------|-------|
| **Username** | `minioadmin` |
| **Password** | `minioadmin` |

### Navigating the Console

After logging in, you will see the **Object Browser** showing the S3 buckets:

- **`warehouse/`** — Hive Metastore warehouse directory.
- **`datalake/`** — Data lake tables. Trino writes Parquet files here when you insert data into Hive tables.

### Browsing Data Lake Files

1. Click the **`datalake`** bucket.
2. Navigate into table directories (e.g., `shipping_events/`, `carrier_rates/`).
3. You will see `.parquet` files — these are the actual data files created by Trino.
4. You can download individual Parquet files for inspection with external tools.

### Creating and Managing Buckets

1. Click **Create Bucket** in the sidebar.
2. Enter a name and click **Create**.
3. You can then reference the new bucket in Hive table definitions via `s3a://<bucket-name>/`.

### When to Use the MinIO Console

- Verifying that Trino wrote data files to the correct S3 location.
- Inspecting Parquet file sizes and partitioning.
- Debugging storage issues (missing files, incorrect paths).
- Manually uploading files to S3 for ingestion.

---

## 7. Direct Database Clients

You can bypass Trino and connect directly to the underlying PostgreSQL and MySQL databases. This is useful for debugging data issues at the source level.

### PostgreSQL (psql)

```bash
# Using psql from the host machine
psql -h localhost -p 5432 -U postgres -d logistics
# Password: postgres
```

Or from inside Docker:

```bash
docker exec -it datawave-postgres psql -U postgres -d logistics
```

Example queries:

```sql
-- List tables
\dt logistics.*

-- Describe a table
\d logistics.shipments

-- Count rows
SELECT count(*) FROM logistics.shipments;
```

### MySQL (mysql CLI)

```bash
# Using mysql from the host machine
mysql -h 127.0.0.1 -P 3306 -u mysql -pmysql warehouse
```

Or from inside Docker:

```bash
docker exec -it datawave-mysql mysql -u mysql -pmysql warehouse
```

Example queries:

```sql
-- List tables
SHOW TABLES;

-- Describe a table
DESCRIBE customers;

-- Count rows
SELECT count(*) FROM customers;
```

### Connection Details Summary

| Database | Host | Port | User | Password | Database |
|----------|------|------|------|----------|----------|
| PostgreSQL | `localhost` | 5432 | `postgres` | `postgres` | `logistics` |
| MySQL | `localhost` (or `127.0.0.1`) | 3306 | `mysql` | `mysql` | `warehouse` |

### When to Use Direct Database Clients

- Verifying that seed data was loaded correctly.
- Debugging issues where Trino returns unexpected results.
- Performing database-specific operations (indexes, permissions, etc.) not available through Trino.

---

## 8. SSO (Single Sign-On)

The environment includes an **OpenID Connect (OIDC)** SSO integration using **Keycloak** as the Identity Provider (IdP) and **OAuth2 Proxy** as the authentication gateway in front of the Trino Web UI.

### Architecture

```
Browser → OAuth2 Proxy (:4180) → Keycloak (:8180) → user authenticates
       → redirect back with auth code → OAuth2 Proxy exchanges code for token
       → OAuth2 Proxy sets session cookie → proxies request to Trino UI (:8080)
```

| Component | Role | Port |
|-----------|------|------|
| **Keycloak** | OIDC Identity Provider — manages users, clients, and tokens | 8180 |
| **OAuth2 Proxy** | Reverse proxy that enforces authentication before granting access to Trino UI | 4180 |
| **Trino Web UI** | Upstream service protected by OAuth2 Proxy | 8080 (direct, unprotected) |

### Configuration Details

#### Keycloak

- **Image:** `quay.io/keycloak/keycloak:24.0`
- **Admin Console:** http://localhost:8180 (`admin` / `admin`)
- **Realm:** `datawave` — auto-imported from `keycloak/datawave-realm.json`
- **Client:** `trino-sso` (confidential, OIDC)
  - Redirect URI: `http://localhost:4180/oauth2/callback`
  - Grant type: Authorization Code with PKCE (S256)

#### OAuth2 Proxy

- **Image:** `quay.io/oauth2-proxy/oauth2-proxy:v7.6.0`
- **Entry point:** http://localhost:4180
- **Provider:** `keycloak-oidc`
- **Upstream:** `http://trino:8080` (Docker-internal)
- **OIDC Discovery:** `http://keycloak:8080/realms/datawave` (Docker-internal)
- **Browser Login URL:** `http://localhost:8180/realms/datawave/...` (overridden for host access)
- **PKCE:** Enabled (`code_challenge_method=S256`)

> The split between Docker-internal URLs (for backend token exchange) and `localhost` URLs (for browser redirects) is handled by overriding the login URL and skipping strict issuer verification.

### Test Users

| Username | Password | Email | Role |
|----------|----------|-------|------|
| `datawave-admin` | `admin123` | admin@datawave.local | Administrator |
| `datawave-analyst` | `analyst123` | analyst@datawave.local | Analyst |

### Accessing the SSO-Protected Trino UI

1. Open http://localhost:4180 in your browser.
2. Click **Sign in with Keycloak OIDC**.
3. Enter credentials (e.g., `datawave-admin` / `admin123`).
4. After successful authentication, you are redirected to the Trino Web UI.
5. A session cookie maintains your login state across page refreshes.

### Authentication Flow (OIDC Authorization Code + PKCE)

1. **Initiation** — User navigates to `http://localhost:4180`. OAuth2 Proxy detects no valid session.
2. **Redirect to IdP** — OAuth2 Proxy redirects the browser to Keycloak's authorization endpoint with:
   - `client_id=trino-sso`
   - `response_type=code`
   - `redirect_uri=http://localhost:4180/oauth2/callback`
   - `scope=openid profile email`
   - `code_challenge` (SHA-256 of a random verifier, per PKCE)
3. **User Authentication** — Keycloak presents the login form. User enters credentials.
4. **Authorization Code** — After successful login, Keycloak redirects to the callback URL with an authorization code.
5. **Token Exchange** — OAuth2 Proxy sends the authorization code + `code_verifier` to Keycloak's token endpoint (Docker-internal `keycloak:8080`).
6. **Token Validation** — Keycloak validates the code and PKCE verifier, returns an ID token + access token.
7. **Session Creation** — OAuth2 Proxy validates the ID token, creates an encrypted session cookie, and proxies the original request to Trino.

### Managing Users in Keycloak

1. Open http://localhost:8180 and log in as `admin` / `admin`.
2. Select the **datawave** realm from the dropdown.
3. Navigate to **Users** in the left sidebar.
4. Click **Add user** to create new users, or select an existing user to:
   - Reset their password
   - Assign realm or client roles
   - View active sessions

### Azure AD Integration (Production Path)

For production deployment on Azure, Keycloak can be replaced with or federated to **Azure Active Directory (Entra ID)**:

1. **Direct Azure AD** — Register an OAuth2 application in Azure AD, configure OAuth2 Proxy with `--provider=azure` and the Azure tenant/client IDs. No Keycloak needed.
2. **Keycloak + Azure AD Federation** — Keep Keycloak as the IdP broker, add Azure AD as an Identity Provider in the Keycloak admin console under **Identity Providers → OpenID Connect v1.0**. Users authenticate via Azure AD while Keycloak manages roles and group mappings.
3. **Azure Container Apps** — Deploy Keycloak on Azure Container Apps with Azure Database for PostgreSQL as the backing store, replacing the embedded H2 used locally.

---

## Data Model Reference

### PostgreSQL — Logistics Database

#### `logistics.shipments`

| Column | Type | Description |
|--------|------|-------------|
| `id` | SERIAL | Primary key |
| `tracking_number` | VARCHAR(20) | Unique tracking ID (e.g., `DW-2024-00001`) |
| `origin` | VARCHAR(100) | Origin city |
| `destination` | VARCHAR(100) | Destination city |
| `status` | VARCHAR(20) | `delivered`, `in_transit`, or `pending` |
| `weight_kg` | DECIMAL(10,2) | Shipment weight in kilograms |
| `shipped_date` | DATE | Date shipped (NULL if pending) |
| `delivered_date` | DATE | Date delivered (NULL if not yet delivered) |
| `customer_id` | INT | FK → `mysql.warehouse.customers.id` |
| `warehouse_id` | INT | FK → `mysql.warehouse.warehouses.id` |

20 rows seeded. Use via Trino: `postgresql.logistics.shipments`

#### `logistics.routes`

| Column | Type | Description |
|--------|------|-------------|
| `id` | SERIAL | Primary key |
| `origin` | VARCHAR(100) | Route origin city |
| `destination` | VARCHAR(100) | Route destination city |
| `distance_km` | INT | Distance in kilometers |
| `transport_mode` | VARCHAR(20) | `sea` or `air` |
| `estimated_days` | INT | Estimated transit time |
| `cost_per_kg` | DECIMAL(6,2) | Cost per kilogram |

15 rows seeded. Use via Trino: `postgresql.logistics.routes`

### MySQL — Warehouse Database

#### `warehouse.customers`

| Column | Type | Description |
|--------|------|-------------|
| `id` | INT (auto) | Primary key |
| `name` | VARCHAR(200) | Company name |
| `email` | VARCHAR(200) | Contact email |
| `country` | VARCHAR(100) | Country of registration |
| `tier` | VARCHAR(20) | `platinum`, `gold`, or `silver` |
| `created_at` | DATE | Account creation date |

10 rows seeded. Use via Trino: `mysql.warehouse.customers`

#### `warehouse.warehouses`

| Column | Type | Description |
|--------|------|-------------|
| `id` | INT (auto) | Primary key |
| `name` | VARCHAR(200) | Warehouse name |
| `city` | VARCHAR(100) | City location |
| `country` | VARCHAR(100) | Country |
| `capacity_tons` | INT | Maximum capacity in tons |
| `current_utilization` | DECIMAL(5,2) | Percentage of capacity in use |
| `manager` | VARCHAR(200) | Warehouse manager name |

7 rows seeded. Use via Trino: `mysql.warehouse.warehouses`

### Hive/MinIO — Data Lake

#### `hive.datalake.shipping_events`

| Column | Type | Description |
|--------|------|-------------|
| `event_id` | VARCHAR | Unique event ID |
| `tracking_number` | VARCHAR | Links to `shipments.tracking_number` |
| `event_type` | VARCHAR | `pickup`, `customs`, `departed`, `in_transit`, `arrived`, `delivered` |
| `event_timestamp` | TIMESTAMP | When the event occurred |
| `location` | VARCHAR | Event location |
| `details` | VARCHAR | Human-readable event description |

20 rows seeded. Use via Trino: `hive.datalake.shipping_events`

#### `hive.datalake.carrier_rates`

| Column | Type | Description |
|--------|------|-------------|
| `carrier_name` | VARCHAR | Shipping carrier (e.g., Maersk, FedEx) |
| `transport_mode` | VARCHAR | `sea` or `air` |
| `region` | VARCHAR | Geographic region |
| `rate_per_kg` | DECIMAL(6,2) | Rate per kilogram |
| `currency` | VARCHAR | Currency code |
| `valid_from` | DATE | Rate validity start |
| `valid_to` | DATE | Rate validity end |

10 rows seeded. Use via Trino: `hive.datalake.carrier_rates`

---

## Query Cookbook

### Explore the Catalog

```sql
-- List all catalogs
SHOW CATALOGS;

-- List schemas within a catalog
SHOW SCHEMAS FROM postgresql;
SHOW SCHEMAS FROM mysql;
SHOW SCHEMAS FROM hive;

-- List tables
SHOW TABLES FROM postgresql.logistics;
SHOW TABLES FROM mysql.warehouse;
SHOW TABLES FROM hive.datalake;

-- Inspect a table's columns
DESCRIBE postgresql.logistics.shipments;
```

### Single-Source Queries

```sql
-- All delivered shipments (PostgreSQL)
SELECT tracking_number, origin, destination, weight_kg, delivered_date
FROM postgresql.logistics.shipments
WHERE status = 'delivered'
ORDER BY delivered_date DESC;

-- Platinum-tier customers (MySQL)
SELECT name, country, email
FROM mysql.warehouse.customers
WHERE tier = 'platinum';

-- Air routes sorted by cost (PostgreSQL)
SELECT origin, destination, cost_per_kg, estimated_days
FROM postgresql.logistics.routes
WHERE transport_mode = 'air'
ORDER BY cost_per_kg;

-- Recent shipping events (Hive/MinIO)
SELECT tracking_number, event_type, location, event_timestamp
FROM hive.datalake.shipping_events
ORDER BY event_timestamp DESC
LIMIT 10;
```

### Cross-Source Federated Queries

```sql
-- Shipments with customer details (PostgreSQL + MySQL)
SELECT
    s.tracking_number,
    s.origin,
    s.destination,
    s.status,
    c.name AS customer,
    c.country AS customer_country,
    c.tier
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
ORDER BY s.shipped_date DESC;

-- Shipments with warehouse info (PostgreSQL + MySQL)
SELECT
    s.tracking_number,
    s.status,
    w.name AS warehouse,
    w.city,
    w.current_utilization AS utilization_pct
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.warehouses w ON s.warehouse_id = w.id
ORDER BY w.current_utilization DESC;

-- Full supply chain view (PostgreSQL + MySQL + MySQL)
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

### Three-Way Federation (PostgreSQL + MySQL + Hive/MinIO)

```sql
-- Shipment journey: tracking events with customer info
SELECT
    c.name AS customer,
    s.tracking_number,
    s.origin || ' → ' || s.destination AS route,
    e.event_type,
    e.event_timestamp,
    e.location AS event_location
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
JOIN hive.datalake.shipping_events e ON s.tracking_number = e.tracking_number
ORDER BY s.tracking_number, e.event_timestamp;

-- Delivered shipments with customer tier
SELECT
    s.tracking_number,
    c.name AS customer,
    e.event_type,
    e.location
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
JOIN hive.datalake.shipping_events e ON s.tracking_number = e.tracking_number
WHERE e.event_type = 'delivered'
ORDER BY s.tracking_number;
```

### Analytical Queries

```sql
-- Shipment volume by customer tier
SELECT
    c.tier,
    COUNT(*) AS total_shipments,
    ROUND(SUM(s.weight_kg), 2) AS total_weight_kg,
    ROUND(AVG(s.weight_kg), 2) AS avg_weight_kg
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
GROUP BY c.tier
ORDER BY total_weight_kg DESC;

-- Warehouse utilization with shipment counts
SELECT
    w.name AS warehouse,
    w.city,
    w.capacity_tons,
    w.current_utilization AS utilization_pct,
    COUNT(s.id) AS active_shipments
FROM mysql.warehouse.warehouses w
LEFT JOIN postgresql.logistics.shipments s ON s.warehouse_id = w.id
GROUP BY w.name, w.city, w.capacity_tons, w.current_utilization
ORDER BY w.current_utilization DESC;

-- Shipment status breakdown
SELECT
    status,
    COUNT(*) AS count,
    ROUND(SUM(weight_kg), 2) AS total_weight_kg
FROM postgresql.logistics.shipments
GROUP BY status
ORDER BY count DESC;

-- Carrier rates comparison
SELECT
    carrier_name,
    transport_mode,
    region,
    rate_per_kg,
    currency
FROM hive.datalake.carrier_rates
ORDER BY rate_per_kg;
```

---

## Managing the Data Lake

### Creating New Tables

You can create new Hive/MinIO tables directly through Trino. Data is stored as Parquet files in MinIO.

```sql
-- Create a new table in the data lake
CREATE TABLE hive.datalake.my_analysis (
    id INT,
    label VARCHAR,
    value DOUBLE
) WITH (format = 'PARQUET');

-- Insert data
INSERT INTO hive.datalake.my_analysis VALUES
    (1, 'metric_a', 42.5),
    (2, 'metric_b', 99.1);

-- Query it back
SELECT * FROM hive.datalake.my_analysis;
```

After inserting, browse `http://localhost:9001` → bucket `datalake` → folder `my_analysis/` to see the generated Parquet files.

### Supported Storage Formats

| Format | Pros | Cons |
|--------|------|------|
| **PARQUET** (default) | Columnar, compressed, excellent for analytics | Not human-readable |
| **ORC** | Similar to Parquet, good compression | Less widely supported outside Hive |
| **CSV** | Human-readable | No schema enforcement, no compression |

Specify format when creating a table:

```sql
CREATE TABLE hive.datalake.my_orc_table (
    id INT, name VARCHAR
) WITH (format = 'ORC');
```

### Dropping Tables

```sql
DROP TABLE IF EXISTS hive.datalake.my_analysis;
```

This removes the table metadata from Hive Metastore **and** deletes the data files from MinIO.

---

## Adding New Data Source Connectors

To add a new database to the federation:

1. **Create a connector config file** in `trino/etc/catalog/`:

   ```bash
   # Example: adding a SQL Server connector
   cat > trino/etc/catalog/sqlserver.properties << 'EOF'
   connector.name=sqlserver
   connection-url=jdbc:sqlserver://sqlserver:1433;database=mydb
   connection-user=sa
   connection-password=MyPassword123
   EOF
   ```

2. **Add the service** to `docker-compose.yml` if it's a new database (make sure it joins `datawave-net`).

3. **Restart Trino** to pick up the new catalog:

   ```bash
   docker compose restart trino
   ```

4. **Verify** the new catalog appears:

   ```bash
   docker exec -it datawave-trino trino --execute "SHOW CATALOGS"
   ```

### Available Trino Connectors

Trino 440 supports 40+ connectors including: PostgreSQL, MySQL, SQL Server, Oracle, MongoDB, Elasticsearch, Cassandra, Redis, Kafka, Google Sheets, and more. See the [Trino Connectors documentation](https://trino.io/docs/current/connector.html) for the full list.

---

## Stopping and Resetting the Environment

```bash
# Stop all services (data is preserved in Docker volumes)
docker compose down

# Stop and remove all data (clean slate — will re-seed on next startup)
docker compose down -v

# Restart a single service
docker compose restart trino

# View logs for a specific service
docker compose logs -f trino
docker compose logs -f postgres
```

---

## Troubleshooting

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `Connection refused` on port 8080 | Trino hasn't finished starting | Wait 30–60s and retry. Check: `docker compose ps` |
| `Catalog not found: hive` | Hive Metastore not ready yet | Wait for metastore-db and hive-metastore to be healthy |
| `Table not found: hive.datalake.*` | trino-init hasn't run yet | Check: `docker logs datawave-trino-init` |
| Empty results from Hive tables | MinIO data was wiped | Run `docker compose down -v` then `docker compose up -d` for a full reset |
| Metabase can't connect to Trino | Wrong hostname | Use `trino` (not `localhost`) as the host — Metabase runs inside Docker |
| `Port already in use` | Another process is using the port | Stop the conflicting process or change ports in `docker-compose.yml` |
| Trino out of memory errors | Docker needs more RAM | Increase Docker Desktop memory to at least 4 GB |
| Slow queries on Hive tables | First query warms the cache | Subsequent queries will be faster. MinIO performance is limited in local dev |
| `psql: could not connect` | PostgreSQL not healthy yet | Check: `docker compose ps`. Wait for `(healthy)` status |
| MySQL connection with `localhost` fails | MySQL CLI resolves `localhost` to socket | Use `127.0.0.1` instead of `localhost` for the MySQL host |
