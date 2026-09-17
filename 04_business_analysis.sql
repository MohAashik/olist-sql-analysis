/**********************************************************************
 04_business_analysis.sql
 Core business questions for the Olist marketplace, on the CLEAN schema.
 Run AFTER 03_data_cleaning.sql.

 Conventions
 -----------
 * "Revenue" = SUM(order_items.price)  (product revenue; freight shown
   separately). This is the standard GMV-style measure for Olist.
 * Revenue is counted on DELIVERED orders only -- an order that was
   cancelled/unavailable never earned money. (Cancellation and delivery
   performance are analysed on their own in Q5 and Q9.)
 * A "customer" = customer_unique_id (the real person), NOT customer_id
   (which Olist issues fresh for every order).
 Each query begins with the stakeholder question it answers.
**********************************************************************/




USE OlistDW;
GO

/*--------------------------------------------------------------------
  Reusable reporting VIEW: one row per sold line item, enriched with
  order, customer, product and seller attributes. Built once so every
  query below is short and uses identical definitions.
--------------------------------------------------------------------*/
IF OBJECT_ID('dbo.vw_sales_lines','V') IS NOT NULL DROP VIEW dbo.vw_sales_lines;
GO
CREATE VIEW dbo.vw_sales_lines AS
SELECT
    oi.order_id,
    oi.item_seq,
    o.order_status,
    o.purchase_ts,
    o.delivered_ts,
    o.estimated_ts,
    o.delivery_days,
    c.customer_id,
    c.customer_unique_id,
    c.state           AS customer_state,
    c.city            AS customer_city,
    p.product_id,
    p.category,
    s.seller_id,
    s.seller_state,
    oi.price,
    oi.freight_value,
    oi.item_total
FROM dbo.fact_order_items oi
JOIN dbo.fact_orders   o ON oi.order_id   = o.order_id
JOIN dbo.dim_customers c ON o.customer_id = c.customer_id
JOIN dbo.dim_products  p ON oi.product_id = p.product_id
JOIN dbo.dim_sellers   s ON oi.seller_id  = s.seller_id;
GO

/*====================================================================
  Q1. Overall business health (executive KPIs) -- delivered orders.
====================================================================*/
SELECT
    COUNT(DISTINCT order_id)             AS delivered_orders,
    COUNT(DISTINCT customer_unique_id)   AS unique_customers,
    COUNT(*)                             AS items_sold,
    CAST(SUM(price)         AS DECIMAL(18,2)) AS product_revenue_brl,
    CAST(SUM(freight_value) AS DECIMAL(18,2)) AS freight_brl,
    CAST(SUM(price) / COUNT(DISTINCT order_id) AS DECIMAL(18,2)) AS avg_order_value_brl
FROM dbo.vw_sales_lines
WHERE order_status = 'delivered';
GO

/*====================================================================
  Q2. Monthly revenue trend -- "are we growing?"
====================================================================*/
SELECT
    FORMAT(purchase_ts, 'yyyy-MM')            AS order_month,
    COUNT(DISTINCT order_id)                  AS orders,
    CAST(SUM(price) AS DECIMAL(18,2))         AS revenue_brl
FROM dbo.vw_sales_lines
WHERE order_status = 'delivered'
GROUP BY FORMAT(purchase_ts, 'yyyy-MM')
ORDER BY order_month;
GO

/*====================================================================
  Q3. Which product CATEGORIES drive the business? (+ % share)
====================================================================*/
SELECT
    category,
    COUNT(DISTINCT order_id)                  AS orders,
    COUNT(*)                                  AS items_sold,
    CAST(SUM(price) AS DECIMAL(18,2))         AS revenue_brl,
    CAST(100.0 * SUM(price) / SUM(SUM(price)) OVER () AS DECIMAL(5,2)) AS pct_of_revenue
FROM dbo.vw_sales_lines
WHERE order_status = 'delivered'
GROUP BY category
ORDER BY revenue_brl DESC;
GO

/*====================================================================
  Q4a. Top 10 sellers by revenue (marketplace: sellers matter).
====================================================================*/
SELECT TOP (10)
    seller_id,
    seller_state,
    COUNT(DISTINCT order_id)                  AS orders,
    CAST(SUM(price) AS DECIMAL(18,2))         AS revenue_brl
FROM dbo.vw_sales_lines
WHERE order_status = 'delivered'
GROUP BY seller_id, seller_state
ORDER BY revenue_brl DESC;
GO

/*====================================================================
  Q4b. Top 10 product categories by number of orders (demand volume).
====================================================================*/
SELECT TOP (10)
    category,
    COUNT(DISTINCT order_id)                  AS orders
FROM dbo.vw_sales_lines
WHERE order_status = 'delivered'
GROUP BY category
ORDER BY orders DESC;
GO

/*====================================================================
  Q5. Order fulfilment health: status mix + cancellation rate.
       Uses ALL orders, not just delivered.
====================================================================*/
SELECT
    order_status,
    COUNT(*)                                  AS orders,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_orders
FROM dbo.fact_orders
GROUP BY order_status
ORDER BY orders DESC;
GO

SELECT
    CAST(100.0 * SUM(CASE WHEN order_status = 'canceled' THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2)) AS cancellation_rate_pct
FROM dbo.fact_orders;
GO

/*====================================================================
  Q6. Where are the customers? Revenue by customer state.
====================================================================*/
SELECT
    customer_state,
    COUNT(DISTINCT order_id)                  AS orders,
    COUNT(DISTINCT customer_unique_id)        AS customers,
    CAST(SUM(price) AS DECIMAL(18,2))         AS revenue_brl,
    CAST(SUM(price) / COUNT(DISTINCT order_id) AS DECIMAL(18,2)) AS avg_order_value_brl
FROM dbo.vw_sales_lines
WHERE order_status = 'delivered'
GROUP BY customer_state
ORDER BY revenue_brl DESC;
GO

/*====================================================================
  Q7. How do customers pay? Payment-type mix and installment behaviour.
       (From the payments table -- payment_value is the amount paid.)
====================================================================*/
SELECT
    payment_type,
    COUNT(*)                                  AS payment_rows,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_payments,
    CAST(AVG(CAST(installments AS DECIMAL(6,2))) AS DECIMAL(6,2))  AS avg_installments,
    CAST(SUM(payment_value) AS DECIMAL(18,2)) AS total_paid_brl
FROM dbo.fact_payments
GROUP BY payment_type
ORDER BY payment_rows DESC;
GO

/*====================================================================
  Q8. Are customers loyal? One-time vs repeat buyers (by real person).
       This is why customer_unique_id matters -- using customer_id here
       would make EVERYONE look one-time.
====================================================================*/
WITH cust AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS orders,
        SUM(price)               AS revenue
    FROM dbo.vw_sales_lines
    WHERE order_status = 'delivered'
    GROUP BY customer_unique_id
)
SELECT
    CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat' END AS customer_type,
    COUNT(*)                                   AS customers,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_customers,
    CAST(SUM(revenue) AS DECIMAL(18,2))        AS revenue_brl,
    CAST(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER () AS DECIMAL(5,2)) AS pct_of_revenue
FROM cust
GROUP BY CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat' END
ORDER BY customer_type;
GO

/*====================================================================
  Q9. Delivery performance: how fast, and how often late vs promised?
====================================================================*/
SELECT
    COUNT(*)                                                       AS delivered_orders,
    CAST(AVG(CAST(DATEDIFF(DAY, purchase_ts, delivered_ts) AS DECIMAL(8,2))) AS DECIMAL(6,1)) AS avg_delivery_days,
    CAST(100.0 * SUM(CASE WHEN delivered_ts > estimated_ts THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2))                              AS pct_delivered_late
FROM dbo.fact_orders
WHERE order_status = 'delivered' AND delivered_ts IS NOT NULL;
GO

PRINT 'Core business analysis (Q1-Q9) complete.';
GO
