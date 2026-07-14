-- ============================================================
-- Olist Brazilian E-Commerce Database
-- Script: 08_delivery_performance.sql
-- Description: Delivery performance analysis covering overview,
--              time analysis, late deliveries, review impact
--              and delivery trends over time.
-- Author: Asa Yudhistira
-- ============================================================

-- ============================================================
-- SECTION 1 — DELIVERY OVERVIEW
-- Goal: Establish headline delivery metrics before any
--       breakdown. These are the KPIs for the operations
--       page of your PowerBI dashboard.
-- ============================================================

-- 1.1 Overall delivery performance headline
-- Why: On-time rate is the single most important delivery
--      metric. Establishes the baseline before any drill-down.
SELECT
    COUNT(DISTINCT order_id)                                    AS total_delivered_orders,
    COUNT(DISTINCT CASE
        WHEN order_delivered_customer_date <=
             order_estimated_delivery_date
        THEN order_id END)                                      AS on_time_orders,
    COUNT(DISTINCT CASE
        WHEN order_delivered_customer_date >
             order_estimated_delivery_date
        THEN order_id END)                                      AS late_orders,
    ROUND(COUNT(DISTINCT CASE
        WHEN order_delivered_customer_date <=
             order_estimated_delivery_date
        THEN order_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT order_id), 0), 2)                 AS on_time_rate_pct,
    ROUND(COUNT(DISTINCT CASE
        WHEN order_delivered_customer_date >
             order_estimated_delivery_date
        THEN order_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT order_id), 0), 2)                 AS late_rate_pct
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;

-- WHAT WE LEARN: [fill after running]

-- ------------------------------------------------------------

-- 1.2 Delivery time distribution
-- Why: Average delivery days alone is misleading.
--      Knowing p25 to p99 reveals whether slow deliveries
--      are common or driven by extreme outliers.
SELECT
    ROUND(AVG(
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_purchase_timestamp)) / 86400), 1)                 AS avg_delivery_days,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_purchase_timestamp)) / 86400), 1)                 AS p25_days,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_purchase_timestamp)) / 86400), 1)                 AS median_days,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_purchase_timestamp)) / 86400), 1)                 AS p75_days,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_purchase_timestamp)) / 86400), 1)                 AS p90_days,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_purchase_timestamp)) / 86400), 1)                 AS p99_days,
    ROUND(MAX(
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_purchase_timestamp)) / 86400), 1)                 AS max_delivery_days
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_purchase_timestamp IS NOT NULL;

-- WHAT WE LEARN: [fill after running]

-- ------------------------------------------------------------

-- 1.3 Delivery pipeline breakdown
-- Why: Total delivery time has two components — time to
--      hand off to carrier, and time from carrier to customer.
--      Identifying which stage is slower helps pinpoint
--      where the bottleneck sits (seller vs logistics).
SELECT
    ROUND(AVG(
        EXTRACT(EPOCH FROM (order_delivered_carrier_date -
        order_purchase_timestamp)) / 86400), 1)                 AS avg_days_to_carrier,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_delivered_carrier_date)) / 86400), 1)             AS avg_days_carrier_to_customer,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_purchase_timestamp)) / 86400), 1)                 AS avg_total_days,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (order_delivered_carrier_date -
        order_purchase_timestamp)) / 86400) * 100.0 /
        NULLIF(AVG(
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_purchase_timestamp)) / 86400), 0), 1)             AS seller_stage_pct,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_delivered_carrier_date)) / 86400) * 100.0 /
        NULLIF(AVG(
        EXTRACT(EPOCH FROM (order_delivered_customer_date -
        order_purchase_timestamp)) / 86400), 0), 1)             AS carrier_stage_pct
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_carrier_date IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL
  AND order_purchase_timestamp IS NOT NULL;

-- WHAT WE LEARN: [fill after running]

-- ============================================================
-- SECTION 2 — DELIVERY TIME ANALYSIS
-- Goal: Understand how delivery time varies by geography
--       and identify the fastest and slowest routes.
-- ============================================================

-- 2.1 Average delivery time by customer state
-- Why: Delivery time varies significantly by state in Brazil
--      due to geography and infrastructure. States with
--      consistently slow delivery need targeted logistics focus.
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date -
        o.order_purchase_timestamp)) / 86400), 1)           AS avg_delivery_days,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (o.order_estimated_delivery_date -
        o.order_purchase_timestamp)) / 86400), 1)           AS avg_estimated_days,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date -
        o.order_purchase_timestamp)) / 86400) -
        AVG(
        EXTRACT(EPOCH FROM (o.order_estimated_delivery_date -
        o.order_purchase_timestamp)) / 86400), 1)           AS avg_days_vs_estimate
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_delivery_days DESC;

-- WHAT WE LEARN: [fill after running]

-- ------------------------------------------------------------

-- 2.2 Fastest and slowest seller-to-customer state routes
-- Why: Cross-state routes vary enormously in delivery time.
--      Knowing the worst routes helps prioritize logistics
--      investment and set realistic delivery estimates.
SELECT
    s.seller_state,
    c.customer_state,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date -
        o.order_purchase_timestamp)) / 86400), 1)           AS avg_delivery_days
FROM orders o
JOIN order_items oi  ON o.order_id    = oi.order_id
JOIN sellers s       ON oi.seller_id  = s.seller_id
JOIN customers c     ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY s.seller_state, c.customer_state
HAVING COUNT(DISTINCT o.order_id) >= 50
ORDER BY avg_delivery_days DESC
LIMIT 15;

-- WHAT WE LEARN: [fill after running]

-- ============================================================
-- SECTION 3 — LATE DELIVERY ANALYSIS
-- Goal: Understand where and when late deliveries occur
--       and how severe the delays are.
-- ============================================================

-- 3.1 Late delivery rate by customer state
-- Why: Some states may have structurally higher late rates
--      due to geography. Others may reflect specific
--      logistics failures that can be addressed.
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
        THEN o.order_id END)                                AS late_orders,
    ROUND(COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
        THEN o.order_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT o.order_id), 0), 2)           AS late_rate_pct,
    ROUND(AVG(CASE
        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
        THEN EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date -
            o.order_estimated_delivery_date)) / 86400
        END), 1)                                            AS avg_days_late
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY late_rate_pct DESC;

-- WHAT WE LEARN: [fill after running]

-- ------------------------------------------------------------

-- 3.2 Late delivery rate by product category
-- Why: Certain categories (heavy, fragile, bulky items)
--      may have structurally higher late rates. This helps
--      set category-specific delivery expectations.
SELECT
    COALESCE(pct.product_category_name_english, 'Unknown')  AS category,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
        THEN o.order_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT o.order_id), 0), 2)           AS late_rate_pct,
    ROUND(AVG(r.review_score), 2)                           AS avg_review_score
FROM orders o
JOIN order_items oi  ON o.order_id       = oi.order_id
JOIN products p      ON oi.product_id    = p.product_id
LEFT JOIN product_category_translation pct
                     ON p.product_category_name = pct.product_category_name
LEFT JOIN order_reviews r ON o.order_id  = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY pct.product_category_name_english
HAVING COUNT(DISTINCT o.order_id) >= 100
ORDER BY late_rate_pct DESC
LIMIT 15;

-- WHAT WE LEARN: [fill after running]

-- ------------------------------------------------------------

-- 3.3 Severity of late deliveries
-- Why: Being 1 day late is very different from being
--      2 weeks late. Understanding delay severity helps
--      prioritize which late orders need compensation.
SELECT
    CASE
        WHEN delay_days <= 1              THEN '1 day late'
        WHEN delay_days BETWEEN 2 AND 3   THEN '2-3 days late'
        WHEN delay_days BETWEEN 4 AND 7   THEN '4-7 days late'
        WHEN delay_days BETWEEN 8 AND 14  THEN '8-14 days late'
        ELSE '15+ days late'
    END                                                     AS delay_bucket,
    COUNT(*)                                                AS order_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)     AS pct_of_late_orders,
    ROUND(AVG(review_score), 2)                             AS avg_review_score
FROM (
    SELECT
        o.order_id,
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date -
            o.order_estimated_delivery_date)) / 86400       AS delay_days,
        r.review_score
    FROM orders o
    LEFT JOIN order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_estimated_delivery_date
) late_orders
GROUP BY CASE
    WHEN delay_days <= 1              THEN '1 day late'
    WHEN delay_days BETWEEN 2 AND 3   THEN '2-3 days late'
    WHEN delay_days BETWEEN 4 AND 7   THEN '4-7 days late'
    WHEN delay_days BETWEEN 8 AND 14  THEN '8-14 days late'
    ELSE '15+ days late'
END
ORDER BY MIN(delay_days);

-- WHAT WE LEARN: [fill after running]

-- ============================================================
-- SECTION 4 — DELIVERY & REVIEW SCORE
-- Goal: Quantify the relationship between delivery
--       performance and customer satisfaction.
-- ============================================================

-- 4.1 Average review score by delivery status
-- Why: Directly quantifies how much delivery performance
--      impacts customer satisfaction. The gap between
--      on-time and late review scores is the business case
--      for investing in logistics improvement.
SELECT
    CASE
        WHEN o.order_delivered_customer_date <=
             o.order_estimated_delivery_date THEN 'On time'
        ELSE 'Late'
    END                                                     AS delivery_status,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(AVG(r.review_score), 2)                           AS avg_review_score,
    COUNT(*) FILTER (WHERE r.review_score = 5)              AS five_star_count,
    COUNT(*) FILTER (WHERE r.review_score = 1)              AS one_star_count,
    ROUND(COUNT(*) FILTER (WHERE r.review_score >= 4) * 100.0 /
          NULLIF(COUNT(r.review_score), 0), 2)              AS positive_review_pct
FROM orders o
LEFT JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY CASE
    WHEN o.order_delivered_customer_date <=
         o.order_estimated_delivery_date THEN 'On time'
    ELSE 'Late'
END;

-- WHAT WE LEARN: [fill after running]

-- ------------------------------------------------------------

-- 4.2 Review score by delay severity
-- Why: Identifies at what delay threshold review scores
--      drop significantly. This threshold is the business
--      case for priority handling of at-risk orders.
SELECT
    CASE
        WHEN o.order_delivered_customer_date <=
             o.order_estimated_delivery_date        THEN 'On time'
        WHEN EXTRACT(EPOCH FROM (
             o.order_delivered_customer_date -
             o.order_estimated_delivery_date))
             / 86400 <= 3                           THEN 'Late 1-3 days'
        WHEN EXTRACT(EPOCH FROM (
             o.order_delivered_customer_date -
             o.order_estimated_delivery_date))
             / 86400 <= 7                           THEN 'Late 4-7 days'
        WHEN EXTRACT(EPOCH FROM (
             o.order_delivered_customer_date -
             o.order_estimated_delivery_date))
             / 86400 <= 14                          THEN 'Late 8-14 days'
        ELSE                                             'Late 15+ days'
    END                                                     AS delay_bucket,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(AVG(r.review_score), 2)                           AS avg_review_score
FROM orders o
LEFT JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY CASE
    WHEN o.order_delivered_customer_date <=
         o.order_estimated_delivery_date        THEN 'On time'
    WHEN EXTRACT(EPOCH FROM (
         o.order_delivered_customer_date -
         o.order_estimated_delivery_date))
         / 86400 <= 3                           THEN 'Late 1-3 days'
    WHEN EXTRACT(EPOCH FROM (
         o.order_delivered_customer_date -
         o.order_estimated_delivery_date))
         / 86400 <= 7                           THEN 'Late 4-7 days'
    WHEN EXTRACT(EPOCH FROM (
         o.order_delivered_customer_date -
         o.order_estimated_delivery_date))
         / 86400 <= 14                          THEN 'Late 8-14 days'
    ELSE                                             'Late 15+ days'
END
ORDER BY MIN(CASE
    WHEN o.order_delivered_customer_date <=
         o.order_estimated_delivery_date THEN 0
    ELSE EXTRACT(EPOCH FROM (
         o.order_delivered_customer_date -
         o.order_estimated_delivery_date)) / 86400
END);

-- WHAT WE LEARN: [fill after running]

-- ============================================================
-- SECTION 5 — DELIVERY TRENDS OVER TIME
-- Goal: Understand whether delivery performance has improved
--       or worsened over the dataset period.
-- ============================================================

-- 5.1 Monthly on-time delivery rate trend
-- Why: If on-time rate is declining over time, it signals
--      a growing logistics problem as order volume increases.
--      If improving, it shows operational maturity.
SELECT
    DATE_TRUNC('month', o.order_purchase_timestamp)         AS order_month,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date <=
             o.order_estimated_delivery_date
        THEN o.order_id END)                                AS on_time_orders,
    ROUND(COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date <=
             o.order_estimated_delivery_date
        THEN o.order_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT o.order_id), 0), 2)           AS on_time_rate_pct,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date -
        o.order_purchase_timestamp)) / 86400), 1)           AS avg_delivery_days
FROM orders o
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_purchase_timestamp IS NOT NULL
GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp)
ORDER BY order_month;

-- WHAT WE LEARN: [fill after running]

-- ------------------------------------------------------------

-- 5.2 Delivery performance before and after peak months
-- Why: High-volume months like Black Friday and Christmas
--      often strain logistics. Comparing on-time rates
--      during peak vs normal months reveals resilience.
WITH monthly_metrics AS (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp)     AS order_month,
        COUNT(DISTINCT o.order_id)                          AS total_orders,
        ROUND(COUNT(DISTINCT CASE
            WHEN o.order_delivered_customer_date <=
                 o.order_estimated_delivery_date
            THEN o.order_id END) * 100.0 /
            NULLIF(COUNT(DISTINCT o.order_id), 0), 2)       AS on_time_rate_pct
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp)
)
SELECT
    order_month,
    total_orders,
    on_time_rate_pct,
    ROUND(AVG(on_time_rate_pct) OVER (
        ORDER BY order_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2)                                                   AS rolling_3m_on_time_rate,
    RANK() OVER (ORDER BY total_orders DESC)                AS volume_rank
FROM monthly_metrics
ORDER BY order_month;

-- WHAT WE LEARN: [fill after running]
