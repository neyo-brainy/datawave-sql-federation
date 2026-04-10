-- =============================================
-- DataWave Industries - Logistics Database
-- PostgreSQL Data Source for SQL Federation
-- =============================================

CREATE SCHEMA IF NOT EXISTS logistics;

-- Shipments table: tracks individual package/freight shipments
CREATE TABLE logistics.shipments (
    id SERIAL PRIMARY KEY,
    tracking_number VARCHAR(20) NOT NULL UNIQUE,
    origin VARCHAR(100) NOT NULL,
    destination VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL,
    weight_kg DECIMAL(10, 2),
    shipped_date DATE,
    delivered_date DATE,
    customer_id INT NOT NULL,
    warehouse_id INT NOT NULL
);

-- Routes table: defines available shipping routes
CREATE TABLE logistics.routes (
    id SERIAL PRIMARY KEY,
    origin VARCHAR(100) NOT NULL,
    destination VARCHAR(100) NOT NULL,
    distance_km INT NOT NULL,
    transport_mode VARCHAR(20) NOT NULL,
    estimated_days INT NOT NULL,
    cost_per_kg DECIMAL(6, 2) NOT NULL
);

-- Seed shipments
INSERT INTO logistics.shipments (tracking_number, origin, destination, status, weight_kg, shipped_date, delivered_date, customer_id, warehouse_id) VALUES
('DW-2024-00001', 'Shanghai',    'Los Angeles',  'delivered',   1250.50, '2024-01-15', '2024-02-02', 1,  1),
('DW-2024-00002', 'Rotterdam',   'New York',     'delivered',   3400.00, '2024-01-20', '2024-02-10', 2,  2),
('DW-2024-00003', 'Singapore',   'Sydney',       'delivered',    870.25, '2024-02-01', '2024-02-15', 3,  3),
('DW-2024-00004', 'Hamburg',     'São Paulo',    'in_transit',  2100.00, '2024-03-05', NULL,         1,  2),
('DW-2024-00005', 'Shanghai',    'Rotterdam',    'in_transit',  5600.75, '2024-03-10', NULL,         4,  1),
('DW-2024-00006', 'Los Angeles', 'Tokyo',        'delivered',    430.00, '2024-02-20', '2024-03-08', 5,  4),
('DW-2024-00007', 'Dubai',       'Mumbai',       'delivered',   1800.30, '2024-01-25', '2024-02-05', 6,  5),
('DW-2024-00008', 'New York',    'London',       'in_transit',   950.00, '2024-03-15', NULL,         2,  6),
('DW-2024-00009', 'Singapore',   'Hamburg',      'pending',     4200.00, NULL,         NULL,         7,  3),
('DW-2024-00010', 'Tokyo',       'Los Angeles',  'delivered',    320.50, '2024-02-10', '2024-02-25', 8,  4),
('DW-2024-00011', 'Rotterdam',   'Dubai',        'delivered',   2750.00, '2024-01-30', '2024-02-18', 9,  2),
('DW-2024-00012', 'Shanghai',    'Sydney',       'in_transit',  1100.25, '2024-03-12', NULL,         3,  1),
('DW-2024-00013', 'Mumbai',      'Singapore',    'delivered',    680.00, '2024-02-05', '2024-02-12', 10, 5),
('DW-2024-00014', 'São Paulo',   'New York',     'pending',     3300.50, NULL,         NULL,         4,  7),
('DW-2024-00015', 'London',      'Shanghai',     'in_transit',  1450.75, '2024-03-18', NULL,         5,  6),
('DW-2024-00016', 'Los Angeles', 'Hamburg',      'delivered',   2200.00, '2024-02-15', '2024-03-05', 1,  4),
('DW-2024-00017', 'Tokyo',       'Rotterdam',    'delivered',    890.30, '2024-02-22', '2024-03-12', 6,  4),
('DW-2024-00018', 'Dubai',       'New York',     'in_transit',  1650.00, '2024-03-20', NULL,         7,  5),
('DW-2024-00019', 'Sydney',      'Singapore',    'delivered',    540.25, '2024-01-10', '2024-01-18', 8,  3),
('DW-2024-00020', 'Hamburg',     'Shanghai',     'pending',     4800.00, NULL,         NULL,         9,  2);

-- Seed routes
INSERT INTO logistics.routes (origin, destination, distance_km, transport_mode, estimated_days, cost_per_kg) VALUES
('Shanghai',    'Los Angeles',  10500, 'sea',   18, 2.50),
('Rotterdam',   'New York',      5800, 'sea',   14, 2.80),
('Singapore',   'Sydney',        6300, 'sea',   12, 2.20),
('Hamburg',     'São Paulo',     9800, 'sea',   20, 3.10),
('Shanghai',    'Rotterdam',    19500, 'sea',   30, 2.00),
('Los Angeles', 'Tokyo',         8800, 'sea',   16, 2.60),
('Dubai',       'Mumbai',        1900, 'sea',    5, 1.50),
('New York',    'London',        5500, 'air',    1, 8.50),
('Singapore',   'Hamburg',      15000, 'sea',   25, 2.30),
('Tokyo',       'Los Angeles',   8800, 'air',    1, 9.00),
('Rotterdam',   'Dubai',        5800, 'sea',   12, 2.40),
('Mumbai',      'Singapore',    3800, 'sea',    7, 1.80),
('São Paulo',   'New York',     7700, 'air',    1, 7.50),
('London',      'Shanghai',    14500, 'air',    2, 10.00),
('Los Angeles', 'Hamburg',      9200, 'sea',   22, 2.70);
