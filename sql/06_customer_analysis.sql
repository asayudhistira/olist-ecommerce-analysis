-- ============================================================
-- Olist Brazilian E-Commerce Database
-- Script: 06_customer_analysis.sql
-- Description: Customer analysis covering overview, repeat
--              behavior, RFM foundation and cohort preparation.
--              Full RFM segmentation and cohort analysis
--              are handled in Phase 2 (Python).
-- Author: Asa Yudhistira
-- ============================================================

-- ============================================================
-- SECTION 1 — CUSTOMER OVERVIEW
-- Goal: Understand the customer base at a high level before
--       any segmentation or behavioral analysis.
-- ============================================================

-- 1.1 Overall customer metrics
-- Why: Establishes the scale of the customer base.
--      Repeat rate is one of the most important health
--      metrics for any e-commerce business.
SELECT
    COUNT(DISTINCT c.customer_unique_id)                        AS total_unique_customers,
    COUNT(DISTINCT o.order_id)                                  AS total_orders,
    ROUND(COUNT(DISTINCT o.order_id) * 1.0 /
          NULLIF(COUNT(DISTINCT c.customer_unique_id), 0), 2)   AS avg_orders_per_customer,
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
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN (
    SELECT
        c2.customer_unique_id,
        COUNT(DISTINCT o2.order_id) AS customer_order_count
    FROM customers c2
    JOIN orders o2 ON c2.customer_id = o2.customer_id
    WHERE o2.order_status = 'delivered'
    GROUP BY c2.customer_unique_id
) counts ON c.customer_unique_id = counts.customer_unique_id
WHERE o.order_status = 'delivered';

-- WHAT WE LEARN: [fill after running]

-- ------------------------------------------------------------

-- 1.2 Distribution of order frequency per customer
-- Why: Tells us whether repeat buyers order 2 times or 10.
--      Shapes how we define loyalty segments.
SELECT
    customer_order_count                AS orders_placed,
    COUNT(*)                            AS number_of_customers,
    ROUND(COUNT(*) * 100.0 /
          SUM(COUNT(*)) OVER (), 2)     AS pct_of_customers
FROM (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS customer_order_count
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
) freq
GROUP BY customer_order_count
ORDER BY customer_order_count;

-- WHAT WE LEARN: [fill after running]

-- ------------------------------------------------------------

-- 1.3 Average time between orders for repeat customers
-- Why: If repeat customers return within 30 days vs 6 months,
--      the retention strategy needs to be completely different.
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_purchase_timestamp,
        LAG(o.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS prev_order_timestamp
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
)
SELECT
    ROUND(AVG(
        EXTRACT(EPOCH FROM (order_purchase_timestamp - prev_order_timestamp)) / 86400
    ), 0)   AS avg_days_between_orders,
    ROUND(MIN(
        EXTRACT(EPOCH FROM (order_purchase_timestamp - prev_order_timestamp)) / 86400
    ), 0)   AS min_days_between_orders,
    ROUND(MAX(
        EXTRACT(EPOCH FROM (order_purchase_timestamp - prev_order_timestamp)) / 86400
    ), 0)   AS max_days_between_orders,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (order_purchase_timestamp - prev_order_timestamp)) / 86400
    ), 0)   AS median_days_between_orders
FROM customer_orders
WHERE prev_order_timestamp IS NOT NULL;

-- WHAT WE LEARN: [fill after running]

-- ============================================================
-- SECTION 2 — RFM FOUNDATION
-- Goal: Calculate Recency, Frequency and Monetary value
--       per customer. This output feeds directly into
--       Python RFM segmentation in Phase 2.
-- ============================================================

-- 2.1 RFM raw scores per customer
-- Why: RFM is the industry standard framework for customer
--      segmentation. Recency = days since last order,
--      Frequency = number of orders, Monetary = total spend.
--      Calculating in SQL first makes Python analysis faster.
WITH rfm_base AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp)             AS last_order_date,
        COUNT(DISTINCT o.order_id)                  AS frequency,
        ROUND(SUM(oi.price + oi.freight_value), 2)  AS monetary
    FROM customers c
    JOIN orders o       ON c.customer_id  = o.customer_id
    JOIN order_items oi ON o.order_id     = oi.order_id
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
    EXTRACT(DAY FROM (rd.max_date - r.last_order_date))::INT    AS recency_days,
    r.frequency,
    r.monetary,
    r.last_order_date
FROM rfm_base r, reference_date rd
ORDER BY monetary DESC;

-- WHAT WE LEARN: [fill after running]
-- Note: Export this result to CSV for use in Python Phase 2.
--       Save as: rfm_raw.csv

-- ------------------------------------------------------------

-- 2.2 RFM summary statistics
-- Why: Before segmenting, understand the distribution of
--      each RFM dimension. Outliers in monetary value
--      can distort segment boundaries.
WITH rfm_base AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp)             AS last_order_date,
        COUNT(DISTINCT o.order_id)                  AS frequency,
        ROUND(SUM(oi.price + oi.freight_value), 2)  AS monetary
    FROM customers c
    JOIN orders o       ON c.customer_id  = o.customer_id
    JOIN order_items oi ON o.order_id     = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
reference_date AS (
    SELECT MAX(order_purchase_timestamp) AS max_date
    FROM orders WHERE order_status = 'delivered'
)
SELECT
    -- Recency
    ROUND(AVG(EXTRACT(DAY FROM (rd.max_date - r.last_order_date))), 0)  AS avg_recency_days,
    ROUND(MIN(EXTRACT(DAY FROM (rd.max_date - r.last_order_date))), 0)  AS min_recency_days,
    ROUND(MAX(EXTRACT(DAY FROM (rd.max_date - r.last_order_date))), 0)  AS max_recency_days,
    -- Frequency
    ROUND(AVG(r.frequency), 2)                                          AS avg_frequency,
    MAX(r.frequency)                                                    AS max_frequency,
    -- Monetary
    ROUND(AVG(r.monetary), 2)                                           AS avg_monetary,
    ROUND(MIN(r.monetary), 2)                                           AS min_monetary,
    ROUND(MAX(r.monetary), 2)                                           AS max_monetary,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP
        (ORDER BY r.monetary), 2)                                       AS p95_monetary
FROM rfm_base r, reference_date rd;

-- WHAT WE LEARN: [fill after running]

-- ============================================================
-- SECTION 3 — CUSTOMER GEOGRAPHY
-- Goal: Understand where customers are located and whether
--       location influences spending behavior.
-- ============================================================

-- 3.1 Top 10 cities by customer count
-- Why: Identifies the most important markets at city level.
--      Useful for localised marketing and logistics planning.
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

-- WHAT WE LEARN: [fill after running]

-- ------------------------------------------------------------

-- 3.2 Average customer spend by state
-- Why: Some states may have fewer customers but higher
--      average spend — valuable for premium targeting.
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

-- WHAT WE LEARN: [fill after running]

-- ============================================================
-- SECTION 4 — COHORT FOUNDATION
-- Goal: Prepare the cohort data that feeds into Python
--       cohort retention analysis in Phase 2.
--       Here we calculate first purchase month per customer.
-- ============================================================

-- 4.1 First purchase month per customer
-- Why: Cohort analysis groups customers by when they first
--      bought. This is the foundation table for retention
--      analysis in Python. Export this for Phase 2.
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

-- WHAT WE LEARN: [fill after running]
-- Note: Export this result to CSV for use in Python Phase 2.
--       Save as: cohort_base.csv

-- ------------------------------------------------------------

-- 4.2 Cohort size by first purchase month
-- Why: Tells us how many new customers were acquired each
--      month. Combined with retention, shows whether growth
--      is sustainable or driven by one-off spikes.
SELECT
    DATE_TRUNC('month', MIN(o.order_purchase_timestamp))    AS cohort_month,
    COUNT(DISTINCT c.customer_unique_id)                    AS cohort_size
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
HAVING COUNT(DISTINCT o.order_id) >= 1
GROUP BY DATE_TRUNC('month', MIN(o.order_purchase_timestamp))
ORDER BY cohort_month;

-- WHAT WE LEARN: [fill after running]

-- ------------------------------------------------------------

-- 4.3 New vs returning customers per month
-- Why: Tracks whether monthly growth comes from new customer
--      acquisition or existing customer retention.
--      A healthy business grows both.
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

-- WHAT WE LEARN: [fill after running]
