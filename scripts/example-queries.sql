-- =============================================
-- DataWave Industries - SQL Federation Examples
-- Run these queries against the Trino endpoint
-- =============================================

-- =============================================
-- 1. Explore Available Catalogs and Schemas
-- =============================================

-- List all configured catalogs
SHOW CATALOGS;

-- List schemas in PostgreSQL catalog
SHOW SCHEMAS FROM postgresql;

-- List schemas in MySQL catalog
SHOW SCHEMAS FROM mysql;

-- List tables in PostgreSQL logistics schema
SHOW TABLES FROM postgresql.logistics;

-- List tables in MySQL warehouse schema
SHOW TABLES FROM mysql.warehouse;

-- =============================================
-- 2. Single-Source Queries
-- =============================================

-- Query shipments from PostgreSQL
SELECT
    tracking_number,
    origin,
    destination,
    status,
    weight_kg,
    shipped_date
FROM postgresql.logistics.shipments
ORDER BY shipped_date DESC
LIMIT 10;

-- Query customers from MySQL
SELECT
    id,
    name,
    country,
    tier
FROM mysql.warehouse.customers
ORDER BY name;

-- Query routes from PostgreSQL
SELECT
    origin,
    destination,
    distance_km,
    transport_mode,
    estimated_days,
    cost_per_kg
FROM postgresql.logistics.routes
ORDER BY distance_km DESC;

-- Query shipping events from Hive/MinIO (data lake)
SELECT
    event_id,
    tracking_number,
    event_type,
    event_timestamp,
    location
FROM hive.datalake.shipping_events
ORDER BY event_timestamp
LIMIT 10;

-- =============================================
-- 3. Cross-Source Federated Queries
-- =============================================

-- JOIN PostgreSQL shipments with MySQL customers
-- (This is the key federation demo: one query, two different databases)
SELECT
    s.tracking_number,
    s.origin,
    s.destination,
    s.status,
    s.weight_kg,
    c.name AS customer_name,
    c.country AS customer_country,
    c.tier AS customer_tier
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
ORDER BY s.shipped_date DESC;

-- JOIN PostgreSQL shipments with MySQL warehouses
SELECT
    s.tracking_number,
    s.origin,
    s.destination,
    s.status,
    w.name AS warehouse_name,
    w.city AS warehouse_city,
    w.current_utilization AS warehouse_utilization_pct
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.warehouses w ON s.warehouse_id = w.id
ORDER BY w.current_utilization DESC;

-- Three-way JOIN across all three data sources:
-- PostgreSQL (shipments) + MySQL (customers) + Hive/MinIO (shipping events)
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
WHERE c.tier = 'platinum'
ORDER BY e.event_timestamp;

-- =============================================
-- 4. Analytical Queries
-- =============================================

-- Shipment volume by customer tier (PostgreSQL + MySQL)
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

-- Query warehouses from MySQL
SELECT
    name,
    city,
    country,
    capacity_tons,
    current_utilization
FROM mysql.warehouse.warehouses
ORDER BY current_utilization DESC;

-- =============================================
-- 3. Cross-Source Federation Queries (JOIN)
-- =============================================

-- Join shipments (PostgreSQL) with customers (MySQL)
-- Shows which customer each shipment belongs to
SELECT
    s.tracking_number,
    s.origin,
    s.destination,
    s.status,
    s.weight_kg,
    c.name AS customer_name,
    c.country AS customer_country,
    c.tier AS customer_tier
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
ORDER BY s.shipped_date DESC;

-- Join shipments (PostgreSQL) with warehouses (MySQL)
-- Shows which warehouse handled each shipment
SELECT
    s.tracking_number,
    s.origin,
    s.destination,
    s.status,
    w.name AS warehouse_name,
    w.city AS warehouse_city,
    w.current_utilization AS warehouse_util_pct
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.warehouses w ON s.warehouse_id = w.id
ORDER BY w.current_utilization DESC;

-- Three-way federation: shipments + customers + warehouses
-- Full supply chain view across all data sources
SELECT
    s.tracking_number,
    c.name AS customer,
    c.tier AS customer_tier,
    w.name AS warehouse,
    w.city AS warehouse_city,
    s.origin,
    s.destination,
    s.status,
    s.weight_kg,
    s.shipped_date
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
JOIN mysql.warehouse.warehouses w ON s.warehouse_id = w.id
ORDER BY s.shipped_date DESC;

-- =============================================
-- 4. Analytical Federation Queries
-- =============================================

-- Shipment volume by customer tier (cross-source aggregation)
SELECT
    c.tier AS customer_tier,
    COUNT(s.id) AS total_shipments,
    ROUND(SUM(s.weight_kg), 2) AS total_weight_kg,
    ROUND(AVG(s.weight_kg), 2) AS avg_weight_kg
FROM postgresql.logistics.shipments s
JOIN mysql.warehouse.customers c ON s.customer_id = c.id
GROUP BY c.tier
ORDER BY total_shipments DESC;

-- Warehouse utilization with shipment counts
SELECT
    w.name AS warehouse,
    w.city,
    w.capacity_tons,
    w.current_utilization AS utilization_pct,
    COUNT(s.id) AS active_shipments,
    ROUND(SUM(s.weight_kg), 2) AS total_weight_in_transit
FROM mysql.warehouse.warehouses w
LEFT JOIN postgresql.logistics.shipments s
    ON s.warehouse_id = w.id AND s.status = 'in_transit'
GROUP BY w.name, w.city, w.capacity_tons, w.current_utilization
ORDER BY w.current_utilization DESC;

-- Estimated shipping cost per shipment (joining shipments with routes)
SELECT
    s.tracking_number,
    s.origin,
    s.destination,
    s.weight_kg,
    r.transport_mode,
    r.distance_km,
    ROUND(s.weight_kg * r.cost_per_kg, 2) AS estimated_cost
FROM postgresql.logistics.shipments s
JOIN postgresql.logistics.routes r
    ON s.origin = r.origin AND s.destination = r.destination
ORDER BY estimated_cost DESC;

-- =============================================
-- 5. Hive/MinIO Queries (Object Storage)
-- =============================================

-- Create a schema in the Hive catalog (stored in MinIO/S3)
-- CREATE SCHEMA IF NOT EXISTS hive.datalake WITH (location = 's3a://datalake/');

-- Create a table in object storage
-- CREATE TABLE hive.datalake.shipment_events (
--     event_id VARCHAR,
--     tracking_number VARCHAR,
--     event_type VARCHAR,
--     event_timestamp TIMESTAMP,
--     location VARCHAR,
--     details VARCHAR
-- ) WITH (
--     format = 'PARQUET',
--     external_location = 's3a://datalake/shipment_events/'
-- );

-- Cross-source query spanning all three catalogs:
-- SELECT
--     s.tracking_number,
--     c.name AS customer,
--     e.event_type,
--     e.event_timestamp,
--     e.location AS event_location
-- FROM postgresql.logistics.shipments s
-- JOIN mysql.warehouse.customers c ON s.customer_id = c.id
-- JOIN hive.datalake.shipment_events e ON s.tracking_number = e.tracking_number
-- ORDER BY e.event_timestamp DESC;
