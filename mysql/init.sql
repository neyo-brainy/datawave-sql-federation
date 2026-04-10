-- =============================================
-- DataWave Industries - Warehouse Database
-- MySQL Data Source for SQL Federation
-- =============================================

CREATE DATABASE IF NOT EXISTS warehouse;
USE warehouse;

-- Customers table: tracks DataWave's logistics customers
CREATE TABLE customers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    email VARCHAR(200) NOT NULL,
    country VARCHAR(100) NOT NULL,
    tier VARCHAR(20) NOT NULL,
    created_at DATE NOT NULL
);

-- Warehouses table: physical warehouse locations
CREATE TABLE warehouses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    city VARCHAR(100) NOT NULL,
    country VARCHAR(100) NOT NULL,
    capacity_tons INT NOT NULL,
    current_utilization DECIMAL(5, 2) NOT NULL,
    manager VARCHAR(200) NOT NULL
);

-- Seed customers (IDs match customer_id references in PostgreSQL shipments)
INSERT INTO customers (name, email, country, tier, created_at) VALUES
('Oceanic Trade Corp',      'ops@oceanictrade.com',        'United States', 'platinum', '2020-03-15'),
('EuroLogistics GmbH',      'shipping@eurologistics.de',   'Germany',       'gold',     '2019-07-22'),
('Pacific Rim Freight',     'info@pacificrim.sg',          'Singapore',     'platinum', '2021-01-10'),
('Atlas Global Shipping',   'dispatch@atlasglobal.ae',     'UAE',           'silver',   '2022-05-18'),
('NovaTrans Japan KK',      'contact@novatrans.jp',        'Japan',         'gold',     '2020-11-03'),
('Bharat Supply Chain',     'ops@bharatsc.in',             'India',         'silver',   '2021-08-25'),
('Meridian Logistics SA',   'info@meridianlog.br',         'Brazil',        'gold',     '2019-12-01'),
('Southern Cross Freight',  'ops@southerncross.au',        'Australia',     'silver',   '2022-02-14'),
('Nordic Express AB',       'shipping@nordicexpress.se',   'Sweden',        'platinum', '2020-06-30'),
('Dragon Gate Trading',     'logistics@dragongate.cn',     'China',         'gold',     '2021-04-12');

-- Seed warehouses (IDs match warehouse_id references in PostgreSQL shipments)
INSERT INTO warehouses (name, city, country, capacity_tons, current_utilization, manager) VALUES
('Shanghai Hub',            'Shanghai',     'China',         50000, 78.50, 'Wei Zhang'),
('Rotterdam Terminal',      'Rotterdam',    'Netherlands',   45000, 82.30, 'Jan de Vries'),
('Singapore Gateway',       'Singapore',    'Singapore',     35000, 65.10, 'Arun Patel'),
('LA Pacific Center',       'Los Angeles',  'United States', 40000, 71.80, 'Maria Garcia'),
('Mumbai Logistics Park',   'Mumbai',       'India',         25000, 58.40, 'Priya Sharma'),
('London Docklands',        'London',       'United Kingdom',30000, 69.20, 'James Wilson'),
('São Paulo Distribution',  'São Paulo',    'Brazil',        28000, 55.90, 'Carlos Silva');
