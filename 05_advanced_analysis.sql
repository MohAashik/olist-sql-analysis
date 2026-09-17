/**********************************************************************
 05_advanced_analysis.sql
 Advanced analytics: window functions, ranking, RFM, Pareto, cohorts.
 Run AFTER 03 (and 04, which builds the reporting view).

 These queries show the analytical thinking behind the numbers -- the
 difference between a "report runner" and an analyst.
**********************************************************************/
USE OlistDW;
GO

-- Safety: (re)create the reporting view in case 04 was not run this session.
IF OBJECT_ID('dbo.vw_sales_lines','V') IS NOT NULL DROP VIEW dbo.vw_sales_lines;
GO
CREATE VIEW dbo.vw_sales_lines AS
SELECT oi.order_id, oi.item_seq, o.order_status, o.purchase_ts, o.delivered_ts,
       o.estimated_ts, o.delivery_days, c.customer_id, c.customer_unique_id,
       c.state AS customer_state, c.city AS customer_city,
       p.product_id, p.category, s.seller_id, s.seller_state,
       oi.price, oi.freight_value, oi.item_total
FROM dbo.fact_order_items oi
JOIN dbo.fact_orders   o ON oi.order_id   = o.order_id
JOIN dbo.dim_customers c ON o.customer_id = c.customer_id
JOIN dbo.dim_products  p ON oi.product_id = p.product_id
JOIN dbo.dim_sellers   s ON oi.seller_id  = s.seller_id;
GO

/*====================================================================
  A1. Month-over-month revenue growth using LAG().
====================================================================*/
WITH monthly AS (
    SELECT DATEFROMPARTS(YEAR(purchase_ts), MONTH(purchase_ts), 1) AS month_start,
           SUM(price) AS revenue
    FROM dbo.vw_sales_lines
    WHERE order_status = 'delivered'
    GROUP BY DATEFROMPARTS(YEAR(purchase_ts), MONTH(purchase_ts), 1)
)
SELECT
    FORMAT(month_start, 'yyyy-MM')                                 AS order_month,
    CAST(revenue AS DECIMAL(18,2))                                 AS revenue_brl,
    CAST(LAG(revenue) OVER (ORDER BY month_start) AS DECIMAL(18,2)) AS prev_month_brl,
    CAST(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month_start))
         / NULLIF(LAG(revenue) OVER (ORDER BY month_start), 0) AS DECIMAL(18,2)) AS mom_growth_pct
FROM monthly
ORDER BY month_start;

/*====================================================================
  A2. Cumulative (running) revenue over time using SUM() OVER().
====================================================================*/
WITH monthly AS (
    SELECT DATEFROMPARTS(YEAR(purchase_ts), MONTH(purchase_ts), 1) AS month_start,
           SUM(price) AS revenue
    FROM dbo.vw_sales_lines
    WHERE order_status = 'delivered'
    GROUP BY DATEFROMPARTS(YEAR(purchase_ts), MONTH(purchase_ts), 1)
)
SELECT
    FORMAT(month_start, 'yyyy-MM')                        AS order_month,
    CAST(revenue AS DECIMAL(18,2))                        AS revenue_brl,
    CAST(SUM(revenue) OVER (ORDER BY month_start
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS DECIMAL(18,2)) AS cumulative_revenue_brl
FROM monthly
ORDER BY month_start;
GO

/*====================================================================
  A3. Top-selling SELLER within each product category, using ROW_NUMBER
       (a "top-N per group" pattern interviewers love).
====================================================================*/
WITH ranked AS (
    SELECT
        category,
        seller_id,
        SUM(price) AS revenue,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY SUM(price) DESC) AS rnk
    FROM dbo.vw_sales_lines
    WHERE order_status = 'delivered'
    GROUP BY category, seller_id
)
SELECT category, seller_id, CAST(revenue AS DECIMAL(18,2)) AS revenue_brl
FROM ranked
WHERE rnk = 1
ORDER BY revenue_brl DESC;
GO

/*====================================================================
  A4. RFM customer segmentation (Recency, Frequency, Monetary).
       Score each real customer 1-4 per dimension with NTILE, then label.
       Recency is measured against the latest purchase date in the data.
====================================================================*/
DECLARE @as_of DATE = (SELECT MAX(purchase_ts) FROM dbo.fact_orders);

WITH rfm AS (
    SELECT
        customer_unique_id,
        DATEDIFF(DAY, MAX(purchase_ts), @as_of)  AS recency_days,
        COUNT(DISTINCT order_id)                 AS frequency,
        SUM(price)                               AS monetary
    FROM dbo.vw_sales_lines
    WHERE order_status = 'delivered'
    GROUP BY customer_unique_id
),
scored AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY recency_days DESC) AS r_score, -- recent = high
        NTILE(4) OVER (ORDER BY frequency)         AS f_score,
        NTILE(4) OVER (ORDER BY monetary)          AS m_score
    FROM rfm
)
SELECT
    CASE
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
        WHEN m_score >= 3 AND r_score <= 2                  THEN 'At risk (high value, gone quiet)'
        WHEN r_score >= 3 AND f_score <= 2                  THEN 'New / Promising'
        WHEN f_score >= 3                                   THEN 'Loyal'
        ELSE 'Others'
    END                                                  AS segment,
    COUNT(*)                                              AS customers,
    CAST(AVG(monetary) AS DECIMAL(18,2))                 AS avg_spend_brl,
    CAST(SUM(monetary) AS DECIMAL(18,2))                 AS segment_revenue_brl
FROM scored
GROUP BY
    CASE
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Champions'
        WHEN m_score >= 3 AND r_score <= 2                  THEN 'At risk (high value, gone quiet)'
        WHEN r_score >= 3 AND f_score <= 2                  THEN 'New / Promising'
        WHEN f_score >= 3                                   THEN 'Loyal'
        ELSE 'Others'
    END
ORDER BY segment_revenue_brl DESC;
GO

/*====================================================================
  A5. Pareto check: what share of revenue comes from the top sellers?
       Running share of revenue, biggest seller first.
====================================================================*/
WITH seller_rev AS (
    SELECT seller_id, SUM(price) AS revenue
    FROM dbo.vw_sales_lines
    WHERE order_status = 'delivered'
    GROUP BY seller_id
),
ranked AS (
    SELECT seller_id, revenue,
        SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) AS running_rev,
        SUM(revenue) OVER ()                                               AS total_rev,
        ROW_NUMBER()  OVER (ORDER BY revenue DESC)                         AS rn,
        COUNT(*)      OVER ()                                              AS total_sellers
    FROM seller_rev
)
SELECT
    CAST(100.0 * rn / total_sellers AS DECIMAL(5,1))     AS top_pct_of_sellers,
    rn                                                   AS sellers,
    CAST(100.0 * running_rev / total_rev AS DECIMAL(5,1)) AS cumulative_pct_of_revenue
FROM ranked
WHERE rn IN (CEILING(total_sellers*0.01), CEILING(total_sellers*0.05),
             CEILING(total_sellers*0.10), CEILING(total_sellers*0.20), total_sellers)
ORDER BY top_pct_of_sellers;
GO

/*====================================================================
  A6. Monthly acquisition cohorts + simple repeat-rate.
       Cohort = month of a customer's FIRST delivered order.
       We then see how many of each cohort ever ordered again.
====================================================================*/
WITH first_order AS (
    SELECT customer_unique_id,
           MIN(DATEFROMPARTS(YEAR(purchase_ts), MONTH(purchase_ts), 1)) AS cohort_month
    FROM dbo.vw_sales_lines
    WHERE order_status = 'delivered'
    GROUP BY customer_unique_id
),
orders_per_cust AS (
    SELECT customer_unique_id, COUNT(DISTINCT order_id) AS orders
    FROM dbo.vw_sales_lines
    WHERE order_status = 'delivered'
    GROUP BY customer_unique_id
)
SELECT
    FORMAT(f.cohort_month, 'yyyy-MM')                     AS cohort_month,
    COUNT(*)                                              AS new_customers,
    SUM(CASE WHEN o.orders > 1 THEN 1 ELSE 0 END)        AS returned_later,
    CAST(100.0 * SUM(CASE WHEN o.orders > 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS repeat_rate_pct
FROM first_order f
JOIN orders_per_cust o ON f.customer_unique_id = o.customer_unique_id
GROUP BY f.cohort_month
ORDER BY f.cohort_month;
GO

/*====================================================================
  A7. Delivery SLA by customer state: avg days + late rate.
       (Operational insight: where is delivery worst?)
====================================================================*/
SELECT
    c.state                                               AS customer_state,
    COUNT(*)                                              AS delivered_orders,
    CAST(AVG(CAST(o.delivery_days AS DECIMAL(8,2))) AS DECIMAL(6,1)) AS avg_delivery_days,
    CAST(100.0 * SUM(CASE WHEN o.delivered_ts > o.estimated_ts THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2))                      AS pct_late
FROM dbo.fact_orders o
JOIN dbo.dim_customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered' AND o.delivered_ts IS NOT NULL
GROUP BY c.state
HAVING COUNT(*) >= 50            -- ignore tiny states for a fair comparison
ORDER BY avg_delivery_days DESC;
GO

PRINT 'Advanced analysis (A1-A7) complete.';
GO
