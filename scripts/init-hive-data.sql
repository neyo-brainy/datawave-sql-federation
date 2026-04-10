-- =============================================
-- DataWave Industries - Hive/MinIO Data Lake Init
-- Run against Trino after the stack is up
-- Creates schemas and tables in MinIO via Hive
-- =============================================

-- Create a schema for the data lake (files stored in MinIO's datalake bucket)
CREATE SCHEMA IF NOT EXISTS hive.datalake
WITH (location = 's3a://datalake/');

-- Shipping events: real-time tracking events for shipments
CREATE TABLE IF NOT EXISTS hive.datalake.shipping_events (
    event_id VARCHAR,
    tracking_number VARCHAR,
    event_type VARCHAR,
    event_timestamp TIMESTAMP,
    location VARCHAR,
    details VARCHAR
) WITH (format = 'PARQUET');

-- Insert sample shipping events
INSERT INTO hive.datalake.shipping_events VALUES
('EVT-001', 'DW-2024-00001', 'pickup',      TIMESTAMP '2024-01-15 08:30:00', 'Shanghai',    'Package picked up from sender'),
('EVT-002', 'DW-2024-00001', 'customs',      TIMESTAMP '2024-01-16 14:00:00', 'Shanghai',    'Cleared export customs'),
('EVT-003', 'DW-2024-00001', 'departed',     TIMESTAMP '2024-01-17 06:00:00', 'Shanghai',    'Departed Shanghai port'),
('EVT-004', 'DW-2024-00001', 'in_transit',   TIMESTAMP '2024-01-25 12:00:00', 'Pacific',     'In transit - mid-Pacific'),
('EVT-005', 'DW-2024-00001', 'arrived',      TIMESTAMP '2024-01-31 09:00:00', 'Los Angeles', 'Arrived at LA port'),
('EVT-006', 'DW-2024-00001', 'customs',      TIMESTAMP '2024-01-31 16:00:00', 'Los Angeles', 'Cleared import customs'),
('EVT-007', 'DW-2024-00001', 'delivered',    TIMESTAMP '2024-02-02 11:00:00', 'Los Angeles', 'Delivered to recipient'),
('EVT-008', 'DW-2024-00002', 'pickup',       TIMESTAMP '2024-01-20 09:00:00', 'Rotterdam',   'Package picked up from sender'),
('EVT-009', 'DW-2024-00002', 'departed',     TIMESTAMP '2024-01-21 07:00:00', 'Rotterdam',   'Departed Rotterdam port'),
('EVT-010', 'DW-2024-00002', 'arrived',      TIMESTAMP '2024-02-08 10:00:00', 'New York',    'Arrived at NY port'),
('EVT-011', 'DW-2024-00002', 'delivered',    TIMESTAMP '2024-02-10 14:30:00', 'New York',    'Delivered to recipient'),
('EVT-012', 'DW-2024-00003', 'pickup',       TIMESTAMP '2024-02-01 07:00:00', 'Singapore',   'Package picked up from sender'),
('EVT-013', 'DW-2024-00003', 'departed',     TIMESTAMP '2024-02-02 05:00:00', 'Singapore',   'Departed Singapore port'),
('EVT-014', 'DW-2024-00003', 'delivered',    TIMESTAMP '2024-02-15 16:00:00', 'Sydney',      'Delivered to recipient'),
('EVT-015', 'DW-2024-00004', 'pickup',       TIMESTAMP '2024-03-05 10:00:00', 'Hamburg',     'Package picked up from sender'),
('EVT-016', 'DW-2024-00004', 'departed',     TIMESTAMP '2024-03-06 08:00:00', 'Hamburg',     'Departed Hamburg port'),
('EVT-017', 'DW-2024-00004', 'in_transit',   TIMESTAMP '2024-03-15 12:00:00', 'Atlantic',    'In transit - mid-Atlantic'),
('EVT-018', 'DW-2024-00005', 'pickup',       TIMESTAMP '2024-03-10 06:00:00', 'Shanghai',    'Package picked up from sender'),
('EVT-019', 'DW-2024-00005', 'customs',      TIMESTAMP '2024-03-11 13:00:00', 'Shanghai',    'Cleared export customs'),
('EVT-020', 'DW-2024-00005', 'in_transit',   TIMESTAMP '2024-03-20 09:00:00', 'Indian Ocean','In transit - Indian Ocean');

-- Carrier rates: reference data stored in the data lake
CREATE TABLE IF NOT EXISTS hive.datalake.carrier_rates (
    carrier_name VARCHAR,
    transport_mode VARCHAR,
    region VARCHAR,
    rate_per_kg DECIMAL(6, 2),
    currency VARCHAR,
    valid_from DATE,
    valid_to DATE
) WITH (format = 'PARQUET');

INSERT INTO hive.datalake.carrier_rates VALUES
('Maersk',          'sea', 'Asia-Pacific',  2.10, 'USD', DATE '2024-01-01', DATE '2024-12-31'),
('Maersk',          'sea', 'Europe',        2.30, 'USD', DATE '2024-01-01', DATE '2024-12-31'),
('MSC',             'sea', 'Asia-Pacific',  1.95, 'USD', DATE '2024-01-01', DATE '2024-12-31'),
('MSC',             'sea', 'Americas',      2.50, 'USD', DATE '2024-01-01', DATE '2024-12-31'),
('CMA CGM',         'sea', 'Europe',        2.20, 'USD', DATE '2024-01-01', DATE '2024-12-31'),
('CMA CGM',         'sea', 'Middle East',   1.80, 'USD', DATE '2024-01-01', DATE '2024-12-31'),
('FedEx',           'air', 'Global',        8.50, 'USD', DATE '2024-01-01', DATE '2024-12-31'),
('DHL Express',     'air', 'Global',        9.20, 'USD', DATE '2024-01-01', DATE '2024-12-31'),
('Emirates SkyCargo','air', 'Middle East',   7.80, 'USD', DATE '2024-01-01', DATE '2024-12-31'),
('Nippon Express',  'air', 'Asia-Pacific',  8.00, 'USD', DATE '2024-01-01', DATE '2024-12-31');
