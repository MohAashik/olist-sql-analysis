/**********************************************************************
 03_data_cleaning.sql
 Transform the raw STAGING data into the CLEAN star schema.
 Run AFTER 01_create_tables.sql and 02_load_data.sql.

 The Olist source is reasonably tidy, but real analytical work still
 needs several fixes. This script:
   1. profiles the key data-quality issues (a quick report)
   2. loads each clean table, fixing issues and explaining WHY

 The three most important cleaning decisions:
   * product categories are in PORTUGUESE  -> translate to English via
     the translation table; missing ones become 'unknown'.
   * every order has its OWN customer_id, even for the same shopper.
     The real person is customer_unique_id. We keep both so customer
     counts and repeat-buyer analysis are correct (see 04 Q8 / 05 A4).
   * timestamps are text and some are blank (an order that was never
     delivered has no delivery date) -> convert with TRY_CONVERT so
     bad/blank values become NULL instead of failing the load.
**********************************************************************/
USE OlistDW;
GO

USE OlistDW;
SELECT name AS table_name
FROM sys.tables
ORDER BY name;

SELECT*FROM dbo.stg_products;

/*====================================================================
  PART 1 - DATA QUALITY REPORT (look before you leap)
====================================================================*/
PRINT '--- Data quality profile of staging tables ---';

SELECT 'customer_id rows vs real people (unique_id)' AS check_name,
       CONCAT(COUNT(*), ' rows / ', COUNT(DISTINCT customer_unique_id), ' people') AS finding
FROM dbo.stg_customers
UNION ALL
SELECT 'products with missing category',
       CAST(SUM(CASE WHEN product_category_name IS NULL OR LTRIM(RTRIM(product_category_name))='' THEN 1 ELSE 0 END) AS NVARCHAR(20))
FROM dbo.stg_products
UNION ALL

SELECT 'orders marked delivered but no delivery date',
       CAST(SUM(CASE WHEN order_status='delivered' AND NULLIF(order_delivered_customer_date,'') IS NULL THEN 1 ELSE 0 END) AS NVARCHAR(20))
FROM dbo.stg_orders
UNION ALL

SELECT 'order_items with non-numeric/negative price',
       CAST(SUM(CASE WHEN TRY_CONVERT(DECIMAL(12,2), price) IS NULL OR TRY_CONVERT(DECIMAL(12,2), price) < 0 THEN 1 ELSE 0 END) AS NVARCHAR(20))
FROM dbo.stg_order_items
UNION ALL
SELECT 'duplicate order_item keys (order_id,item_id)',
       CAST(COUNT(*) - COUNT(DISTINCT CONCAT(order_id,'|',order_item_id)) AS NVARCHAR(20))
FROM dbo.stg_order_items;
GO

/*====================================================================
  PART 2 - Clear clean tables (children first, for re-runnability)
====================================================================*/

--to Check the PK & FK Tables
SELECT 
    OBJECT_NAME(parent_object_id)     AS table_with_the_FK,   -- the child (holds the arrow)
    OBJECT_NAME(referenced_object_id) AS table_being_pointed_at -- the parent (gets DELETE)
FROM sys.foreign_keys;


TRUNCATE TABLE dbo.fact_payments;
TRUNCATE TABLE dbo.fact_order_items;
DELETE FROM dbo.fact_orders;
DELETE FROM dbo.dim_products;
DELETE FROM dbo.dim_sellers;
DELETE FROM dbo.dim_customers;
GO

/*====================================================================
  PART 3 - dim_customers
  Keep BOTH ids; standardise city (lower) and state (upper); de-dup.
====================================================================*/
;WITH c AS (
    SELECT
        customer_id,
        customer_unique_id,
        TRY_CONVERT(INT, customer_zip_code_prefix) AS zip_prefix,
        LOWER(LTRIM(RTRIM(customer_city)))         AS city,
        UPPER(LTRIM(RTRIM(customer_state)))        AS state,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY (SELECT 1)) AS rn
    FROM dbo.stg_customers
    WHERE customer_id IS NOT NULL
)
INSERT INTO dbo.dim_customers (customer_id, customer_unique_id, zip_prefix, city, state)
SELECT customer_id, customer_unique_id, zip_prefix, city, state
FROM c WHERE rn = 1;
GO

SELECT*FROM dbo.stg_customers;
SELECT*FROM dbo.dim_customers;

/*====================================================================
  PART 4 - dim_sellers  (de-dup; standardise city/state)
====================================================================*/
;WITH s AS (
    SELECT
        seller_id,
        LOWER(LTRIM(RTRIM(seller_city)))  AS seller_city,
        UPPER(LTRIM(RTRIM(seller_state))) AS seller_state,
        ROW_NUMBER() OVER (PARTITION BY seller_id ORDER BY (SELECT 1)) AS rn
    FROM dbo.stg_sellers
    WHERE seller_id IS NOT NULL
)
INSERT INTO dbo.dim_sellers (seller_id, seller_city, seller_state)
SELECT seller_id, seller_city, seller_state FROM s WHERE rn = 1;
GO

/*====================================================================
  PART 5 - dim_products
  Translate the Portuguese category to English via the lookup table.
  Missing / untranslated categories become 'unknown' (never dropped,
  because the products still generated real sales).
====================================================================*/

SELECT*FROM dbo.stg_products;
SELECT*FROM dbo.stg_category;
SELECT*FROM dim_products;

;WITH p AS (
    SELECT
        pr.product_id,
        COALESCE(cat.product_category_name_english,
                 NULLIF(LTRIM(RTRIM(pr.product_category_name)), ''),
                 'unknown')                       AS category,
        TRY_CONVERT(INT, pr.product_weight_g)     AS weight_g,
        ROW_NUMBER() OVER (PARTITION BY pr.product_id ORDER BY (SELECT 1)) AS rn
    FROM dbo.stg_products pr
    LEFT JOIN dbo.stg_category cat
           ON pr.product_category_name = cat.product_category_name
    WHERE pr.product_id IS NOT NULL
)
INSERT INTO dbo.dim_products (product_id, category, weight_g)
SELECT product_id, category, weight_g FROM p WHERE rn = 1;
GO

/*====================================================================
  PART 6 - fact_orders
  Parse text timestamps (blank -> NULL), lower-case status, de-dup.
  Referential integrity: only keep orders whose customer survived.
====================================================================*/

SELECT*FROM dbo.stg_orders;
SELECT*FROM dbo.fact_orders;
SELECT*FROM dbo.dim_customers;

;WITH o AS (
    SELECT
        order_id,
        customer_id,
        LOWER(LTRIM(RTRIM(order_status)))                         AS order_status,
        TRY_CONVERT(DATETIME2, NULLIF(order_purchase_timestamp,''))      AS purchase_ts,
        TRY_CONVERT(DATETIME2, NULLIF(order_approved_at,''))            AS approved_ts,
        TRY_CONVERT(DATETIME2, NULLIF(order_delivered_customer_date,'')) AS delivered_ts,
        TRY_CONVERT(DATETIME2, NULLIF(order_estimated_delivery_date,'')) AS estimated_ts,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY (SELECT 1)) AS rn
    FROM dbo.stg_orders
    WHERE order_id IS NOT NULL
)
INSERT INTO dbo.fact_orders (order_id, customer_id, order_status, purchase_ts, approved_ts, delivered_ts, estimated_ts)
SELECT o.order_id, o.customer_id, o.order_status, o.purchase_ts, o.approved_ts, o.delivered_ts, o.estimated_ts
FROM o
WHERE o.rn = 1
  AND o.customer_id IN (SELECT customer_id FROM dbo.dim_customers);
GO

/*====================================================================
  PART 7 - fact_order_items
  Numeric price/freight, drop non-numeric or negative price, de-dup on
  (order_id, item_id). Keep only lines whose order/product/seller exist.
====================================================================*/

SELECT TOP 3 customer_id FROM dbo.stg_customers;


SELECT*FROM dbo.stg_orders;
SELECT*FROM dbo.fact_orders;
SELECT*FROM dbo.dim_customers;

;WITH i AS (
    SELECT
        order_id,
        TRY_CONVERT(INT, order_item_id)       AS item_seq,
        product_id,
        seller_id,
        TRY_CONVERT(DECIMAL(12,2), price)         AS price,
        TRY_CONVERT(DECIMAL(12,2), freight_value) AS freight_value,
        ROW_NUMBER() OVER (PARTITION BY order_id, order_item_id ORDER BY (SELECT 1)) AS rn
    FROM dbo.stg_order_items
    WHERE TRY_CONVERT(DECIMAL(12,2), price) >= 0
      AND TRY_CONVERT(INT, order_item_id) IS NOT NULL
)
INSERT INTO dbo.fact_order_items (order_id, item_seq, product_id, seller_id, price, freight_value)
SELECT i.order_id, i.item_seq, i.product_id, i.seller_id, i.price, i.freight_value
FROM i
WHERE i.rn = 1
  AND i.order_id   IN (SELECT order_id   FROM dbo.fact_orders)
  AND i.product_id IN (SELECT product_id FROM dbo.dim_products)
  AND i.seller_id  IN (SELECT seller_id  FROM dbo.dim_sellers);
GO

/*====================================================================
  PART 8 - fact_payments
  Numeric installments/value, de-dup on (order_id, payment_sequential).
====================================================================*/
;WITH pay AS (
    SELECT
        order_id,
        TRY_CONVERT(INT, payment_sequential)      AS payment_seq,
        LOWER(LTRIM(RTRIM(payment_type)))         AS payment_type,
        TRY_CONVERT(INT, payment_installments)    AS installments,
        TRY_CONVERT(DECIMAL(12,2), payment_value) AS payment_value,
        ROW_NUMBER() OVER (PARTITION BY order_id, payment_sequential ORDER BY (SELECT 1)) AS rn
    FROM dbo.stg_order_payments
    WHERE TRY_CONVERT(INT, payment_sequential) IS NOT NULL
)
INSERT INTO dbo.fact_payments (order_id, payment_seq, payment_type, installments, payment_value)
SELECT pay.order_id, pay.payment_seq, pay.payment_type, pay.installments, pay.payment_value
FROM pay
WHERE pay.rn = 1
  AND pay.order_id IN (SELECT order_id FROM dbo.fact_orders);
GO

/*====================================================================
  PART 9 - POST-LOAD VERIFICATION (staging vs clean row counts)
====================================================================*/
SELECT 'customers'   AS entity, (SELECT COUNT(*) FROM dbo.stg_customers)      AS raw_rows, (SELECT COUNT(*) FROM dbo.dim_customers)   AS clean_rows
UNION ALL SELECT 'products',    (SELECT COUNT(*) FROM dbo.stg_products),       (SELECT COUNT(*) FROM dbo.dim_products)
UNION ALL SELECT 'sellers',     (SELECT COUNT(*) FROM dbo.stg_sellers),        (SELECT COUNT(*) FROM dbo.dim_sellers)
UNION ALL SELECT 'orders',      (SELECT COUNT(*) FROM dbo.stg_orders),         (SELECT COUNT(*) FROM dbo.fact_orders)
UNION ALL SELECT 'order_items', (SELECT COUNT(*) FROM dbo.stg_order_items),    (SELECT COUNT(*) FROM dbo.fact_order_items)
UNION ALL SELECT 'payments',    (SELECT COUNT(*) FROM dbo.stg_order_payments), (SELECT COUNT(*) FROM dbo.fact_payments);
GO

PRINT 'Cleaning complete. Clean star schema is ready for analysis (04 & 05).';
GO
