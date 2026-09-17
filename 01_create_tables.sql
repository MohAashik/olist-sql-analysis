/**********************************************************************
 01_create_tables.sql
 Olist Brazilian E-Commerce -- SQL analytics portfolio project


-------------------------------------------------------------------
-- 0. Create the database (skip this batch if your admin made it)
-------------------------------------------------------------------
IF DB_ID('OlistDW') IS NULL
    CREATE DATABASE OlistDW;
GO
USE OlistDW;
GO

-------------------------------------------------------------------
-- 1. Drop existing objects so the script is re-runnable (idempotent).
--    Drop children (tables with FKs) before parents.
-------------------------------------------------------------------
IF OBJECT_ID('dbo.fact_payments','U')    IS NOT NULL DROP TABLE dbo.fact_payments;
IF OBJECT_ID('dbo.fact_order_items','U') IS NOT NULL DROP TABLE dbo.fact_order_items;
IF OBJECT_ID('dbo.fact_orders','U')      IS NOT NULL DROP TABLE dbo.fact_orders;
IF OBJECT_ID('dbo.dim_products','U')     IS NOT NULL DROP TABLE dbo.dim_products;
IF OBJECT_ID('dbo.dim_sellers','U')      IS NOT NULL DROP TABLE dbo.dim_sellers;
IF OBJECT_ID('dbo.dim_customers','U')    IS NOT NULL DROP TABLE dbo.dim_customers;

IF OBJECT_ID('dbo.stg_customers','U')    IS NOT NULL DROP TABLE dbo.stg_customers;
IF OBJECT_ID('dbo.stg_orders','U')       IS NOT NULL DROP TABLE dbo.stg_orders;
IF OBJECT_ID('dbo.stg_order_items','U')  IS NOT NULL DROP TABLE dbo.stg_order_items;
IF OBJECT_ID('dbo.stg_order_payments','U') IS NOT NULL DROP TABLE dbo.stg_order_payments;
IF OBJECT_ID('dbo.stg_products','U')     IS NOT NULL DROP TABLE dbo.stg_products;
IF OBJECT_ID('dbo.stg_sellers','U')      IS NOT NULL DROP TABLE dbo.stg_sellers;
IF OBJECT_ID('dbo.stg_category','U')     IS NOT NULL DROP TABLE dbo.stg_category;
GO

-------------------------------------------------------------------
-- 2. STAGING tables -- one per CSV, every column NVARCHAR on purpose.
--    Column order & names match the CSV headers exactly.
-------------------------------------------------------------------
CREATE TABLE dbo.stg_customers (
    customer_id              NVARCHAR(50),
    customer_unique_id       NVARCHAR(50),
    customer_zip_code_prefix NVARCHAR(20),
    customer_city            NVARCHAR(100),
    customer_state           NVARCHAR(10)
);

CREATE TABLE dbo.stg_orders (
    order_id                       NVARCHAR(50),
    customer_id                    NVARCHAR(50),
    order_status                   NVARCHAR(30),
    order_purchase_timestamp       NVARCHAR(30),
    order_approved_at              NVARCHAR(30),
    order_delivered_carrier_date   NVARCHAR(30),
    order_delivered_customer_date  NVARCHAR(30),
    order_estimated_delivery_date  NVARCHAR(30)
);

CREATE TABLE dbo.stg_order_items (
    order_id            NVARCHAR(50),
    order_item_id       NVARCHAR(10),
    product_id          NVARCHAR(50),
    seller_id           NVARCHAR(50),
    shipping_limit_date NVARCHAR(30),
    price               NVARCHAR(20),
    freight_value       NVARCHAR(20)
);

CREATE TABLE dbo.stg_order_payments (
    order_id             NVARCHAR(50),
    payment_sequential   NVARCHAR(10),
    payment_type         NVARCHAR(30),
    payment_installments NVARCHAR(10),
    payment_value        NVARCHAR(20)
);

CREATE TABLE dbo.stg_products (
    product_id                 NVARCHAR(50),
    product_category_name      NVARCHAR(100),
    product_name_lenght        NVARCHAR(10),
    product_description_lenght NVARCHAR(10),
    product_photos_qty         NVARCHAR(10),
    product_weight_g           NVARCHAR(10),
    product_length_cm          NVARCHAR(10),
    product_height_cm          NVARCHAR(10),
    product_width_cm           NVARCHAR(10)
);

CREATE TABLE dbo.stg_sellers (
    seller_id              NVARCHAR(50),
    seller_zip_code_prefix NVARCHAR(20),
    seller_city            NVARCHAR(100),
    seller_state           NVARCHAR(10)
);

CREATE TABLE dbo.stg_category (
    product_category_name         NVARCHAR(100),
    product_category_name_english NVARCHAR(100)
);
GO



-------------------------------------------------------------------
-- 3. CLEAN star-schema tables -- typed, constrained, analysis-ready.
--    3 dimensions (customer / product / seller) + 2 facts
--    (orders header, order line items) + payments.
-- "washing and chopping" step that moves data from the messy stg_ tables into these clean ones where data types 
-------------------------------------------------------------------
CREATE TABLE dbo.dim_customers (
    customer_id        NVARCHAR(50)  NOT NULL PRIMARY KEY, -- 1 per order (Olist quirk)
    customer_unique_id NVARCHAR(50)  NULL,                 -- the REAL person identifier
    zip_prefix         INT           NULL,
    city               NVARCHAR(100) NULL,
    state              NVARCHAR(5)   NULL
);

CREATE TABLE dbo.dim_products (
    product_id NVARCHAR(50)  NOT NULL PRIMARY KEY,
    category   NVARCHAR(100) NULL,   -- English, translated in 03
    weight_g   INT           NULL
);

CREATE TABLE dbo.dim_sellers (
    seller_id    NVARCHAR(50)  NOT NULL PRIMARY KEY,
    seller_city  NVARCHAR(100) NULL,
    seller_state NVARCHAR(5)   NULL
);

CREATE TABLE dbo.fact_orders (
    order_id       NVARCHAR(50) NOT NULL PRIMARY KEY,
    customer_id    NVARCHAR(50) NOT NULL,
    order_status   NVARCHAR(30) NULL,
    purchase_ts    DATETIME2    NULL,
    approved_ts    DATETIME2    NULL,
    delivered_ts   DATETIME2    NULL,   -- to CUSTOMER; NULL if not delivered
    estimated_ts   DATETIME2    NULL,
    delivery_days  AS (DATEDIFF(DAY, purchase_ts, delivered_ts)),   -- computed
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES dbo.dim_customers(customer_id)
);

CREATE TABLE dbo.fact_order_items (
    order_id      NVARCHAR(50)  NOT NULL,
    item_seq      INT           NOT NULL,     -- 1,2,3... within an order
    product_id    NVARCHAR(50)  NOT NULL,
    seller_id     NVARCHAR(50)  NOT NULL,
    price         DECIMAL(12,2) NOT NULL,
    freight_value DECIMAL(12,2) NULL,
    item_total    AS (CAST(price + ISNULL(freight_value,0) AS DECIMAL(14,2))),
    CONSTRAINT pk_order_items PRIMARY KEY (order_id, item_seq),
    CONSTRAINT fk_items_order   FOREIGN KEY (order_id)   REFERENCES dbo.fact_orders(order_id),
    CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES dbo.dim_products(product_id),
    CONSTRAINT fk_items_seller  FOREIGN KEY (seller_id)  REFERENCES dbo.dim_sellers(seller_id)
);

CREATE TABLE dbo.fact_payments (
    order_id      NVARCHAR(50)  NOT NULL,
    payment_seq   INT           NOT NULL,
    payment_type  NVARCHAR(30)  NULL,
    installments  INT           NULL,
    payment_value DECIMAL(12,2) NULL,
    CONSTRAINT pk_payments PRIMARY KEY (order_id, payment_seq),
    CONSTRAINT fk_pay_order FOREIGN KEY (order_id) REFERENCES dbo.fact_orders(order_id)
);
GO

-- Indexes for the analytical joins/filters in 04 & 05.
CREATE INDEX ix_orders_customer ON dbo.fact_orders(customer_id);
CREATE INDEX ix_orders_status   ON dbo.fact_orders(order_status);
CREATE INDEX ix_orders_purchase ON dbo.fact_orders(purchase_ts);
CREATE INDEX ix_items_product   ON dbo.fact_order_items(product_id);
CREATE INDEX ix_items_seller    ON dbo.fact_order_items(seller_id);
GO

PRINT 'Schema created: 7 staging tables + 6 clean star-schema tables.';
GO



