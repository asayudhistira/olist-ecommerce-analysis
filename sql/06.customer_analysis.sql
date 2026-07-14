-- Title: Customer Analysis in E-commerce Database
-- Author: Asa Yudhistira
-- Description: This SQL script performs a customer analysis on an e-commerce database.


-- SECTION 1 — CUSTOMER OVERVIEW
-- 1.1 Overall customer metrics
SELECT 
	COUNT(DISTINCT c.customer_unique_id) 					AS total_unique_customers,
	COUNT(DISTINCT o.order_id)								AS total_orders,
	ROUND(COUNT(DISTINCT o.order_id) * 1.0 / 
	  NULLIF(COUNT(DISTINCT c.customer_unique_id) , 0), 2)	AS avg_orders_per_customers,
	COUNT(DISTINCT CASE
        WHEN customer_order_count > 1
        THEN c.customer_unique_id END)                          AS repeat_customers,
    COUNT(DISTINCT CASE
        WHEN customer_order_count = 1
        THEN c.customer_unique_id END)                          AS one_time_customers,
    ROUND(COUNT(DISTINCT CASE
        WHEN customer_order_count > 1
        THEN c.customer_unique_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT c.customer_unique_id), 0), 2)     AS repeat_customer_rate_pct
FROM 
	customers c
INNER JOIN orders o ON c.customer_id = o.customer_id
INNER JOIN (
    SELECT
        c2.customer_unique_id,
        COUNT(DISTINCT o2.order_id) AS customer_order_count
    FROM customers c2
    JOIN orders o2 ON c2.customer_id = o2.customer_id
    WHERE o2.order_status = 'delivered'
    GROUP BY c2.customer_unique_id
) counts ON c.customer_unique_id = counts.customer_unique_id
WHERE o.order_status = 'delivered';

-- Total Unique Customers = 93358
-- Total Orders = 96478
-- Average Orders per Customers = 1.03
-- No of Repeat Customers = 2801
-- No of One-Time Customers = 90557
-- Repeat Customer Rate = 3.00%

-- 1.2 Distribution of order frequency per customer
SELECT
	customer_order_count 					AS orders_placed,
	COUNT(*)								AS number_of_customers, 
	ROUND(COUNT(*) * 100.0 /
          SUM(COUNT(*)) OVER (), 2)     AS pct_of_customers	
FROM (
	SELECT 
		customer_unique_id,
		COUNT(DISTINCT o.order_id) AS customer_order_count
	FROM customers c
	INNER JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
GROUP BY orders_placed
ORDER BY orders_placed

-- +-------+-------+------------+
-- | value | count | percentage |
-- +-------+-------+------------+
-- |     1 | 90557 |      97.00 |
-- |     2 |  2573 |       2.76 |
-- |     3 |   181 |       0.19 |
-- |     4 |    28 |       0.03 |
-- |     5 |     9 |       0.01 |
-- |     6 |     5 |       0.01 |
-- |     7 |     3 |       0.00 |
-- |     9 |     1 |       0.00 |
-- |    15 |     1 |       0.00 |
-- +-------+-------+------------+


-- 1.3 Average time between orders for repeat customers
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_purchase_timestamp,
        LAG(o.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS prev_order_timestamp
    FROM customers c
    INNER JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
gaps AS (
    SELECT
        customer_unique_id,
        EXTRACT(EPOCH FROM (order_purchase_timestamp - prev_order_timestamp))::numeric
            / 86400 AS days_between
    FROM customer_orders
    WHERE prev_order_timestamp IS NOT NULL
)
SELECT
    COUNT(*)                                   AS gap_count,
    COUNT(DISTINCT customer_unique_id)         AS repeat_customers,
    ROUND(AVG(days_between), 1)                AS avg_days,
    ROUND(MIN(days_between), 1)                AS min_days,
    ROUND(MAX(days_between), 1)                AS max_days,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_between)::numeric, 1) AS median_days,
    ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY days_between)::numeric, 1) AS p90_days
FROM gaps;


-- SECTION 2 — RFM FOUNDATION
-- 2.1 RFM raw scores per customer

WITH rfm AS (
	SELECT 
		c.customer_unique_id,
        MAX(o.order_purchase_timestamp)             AS recency,
        COUNT(DISTINCT o.order_id)                  AS frequency,
        ROUND(SUM(oi.price + oi.freight_value), 2)  AS monetary
	FROM customers c
	INNER JOIN orders o ON c.customer_id = o.customer_id
	INNER JOIN order_items oi ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY c.customer_unique_id
),
reference_date AS (
    SELECT MAX(order_purchase_timestamp) AS max_date
    FROM orders
    WHERE order_status = 'delivered'
)
SELECT
    r.customer_unique_id,
    EXTRACT(DAY FROM (rd.max_date - r.recency))::INT    AS recency_days,
    r.frequency,
    r.monetary,
    r.recency
FROM rfm r, reference_date rd
ORDER BY monetary DESC;


-- 2.2 RFM summary statistics
WITH rfm_base AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp)             AS last_order_date,
        COUNT(DISTINCT o.order_id)                  AS frequency,
        ROUND(SUM(oi.price + oi.freight_value), 2)  AS monetary
    FROM customers c
    JOIN orders o       ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id    = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
reference_date AS (
    SELECT MAX(order_purchase_timestamp) AS max_date
    FROM orders WHERE order_status = 'delivered'
),
rfm AS (
    SELECT
        r.customer_unique_id,
        (rd.max_date::date - r.last_order_date::date) AS recency_days,
        r.frequency,
        r.monetary
    FROM rfm_base r
    CROSS JOIN reference_date rd
)
SELECT
    COUNT(*)                                    AS customers,
    -- Recency
    ROUND(AVG(recency_days), 0)                 AS avg_recency_days,
    MIN(recency_days)                           AS min_recency_days,
    MAX(recency_days)                           AS max_recency_days,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY recency_days)::numeric, 0)
                                                AS median_recency_days,
    -- Frequency
    ROUND(AVG(frequency), 2)                    AS avg_frequency,
    MAX(frequency)                              AS max_frequency,
    COUNT(*) FILTER (WHERE frequency > 1)       AS repeat_customers,
    -- Monetary
    ROUND(AVG(monetary), 2)                     AS avg_monetary,
    MIN(monetary)                               AS min_monetary,
    MAX(monetary)                               AS max_monetary,
    ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY monetary)::numeric, 2)
                                                AS median_monetary,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY monetary)::numeric, 2)
                                                AS p95_monetary
FROM rfm;


-- SECTION 3 — CUSTOMER GEOGRAPHY
-- 3.1 Top 10 cities by customer count
SELECT
    c.customer_city,
    c.customer_state,
    COUNT(DISTINCT c.customer_unique_id)    AS unique_customers,
    COUNT(DISTINCT o.order_id)              AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue
FROM customers c
JOIN orders o       ON c.customer_id  = o.customer_id
JOIN order_items oi ON o.order_id     = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_city, c.customer_state
ORDER BY unique_customers DESC
LIMIT 10;


-- 3.2 Average customer spend by state
SELECT
    c.customer_state,
    COUNT(DISTINCT c.customer_unique_id)        AS unique_customers,
    ROUND(SUM(oi.price + oi.freight_value) /
          NULLIF(COUNT(DISTINCT c.customer_unique_id), 0), 2) AS avg_spend_per_customer,
    ROUND(AVG(oi.price + oi.freight_value), 2)  AS avg_item_value
FROM customers c
JOIN orders o       ON c.customer_id  = o.customer_id
JOIN order_items oi ON o.order_id     = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY avg_spend_per_customer DESC;

-- SECTION 4 — COHORT FOUNDATION
-- 4.1 First purchase month per customer
SELECT
    c.customer_unique_id,
    DATE_TRUNC('month', MIN(o.order_purchase_timestamp))    AS cohort_month,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    MIN(o.order_purchase_timestamp)                         AS first_order_date,
    MAX(o.order_purchase_timestamp)                         AS last_order_date
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
ORDER BY cohort_month;


-- 4.2 Cohort size by first purchase month
WITH first_order AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp))::date AS cohort_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    cohort_month,
    COUNT(*) AS cohort_size
FROM first_order
GROUP BY cohort_month
ORDER BY cohort_month;

-- 4.3 New vs returning customers per month
WITH customer_first_order AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp)) AS first_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
monthly_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp) AS order_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
)
SELECT
    mo.order_month,
    COUNT(DISTINCT CASE
        WHEN mo.order_month = cfo.first_month
        THEN mo.customer_unique_id END)     AS new_customers,
    COUNT(DISTINCT CASE
        WHEN mo.order_month > cfo.first_month
        THEN mo.customer_unique_id END)     AS returning_customers,
    COUNT(DISTINCT mo.customer_unique_id)   AS total_active_customers
FROM monthly_orders mo
JOIN customer_first_order cfo
  ON mo.customer_unique_id = cfo.customer_unique_id
GROUP BY mo.order_month
ORDER BY mo.order_month;