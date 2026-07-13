-- Title: Revenue Analysis in E-commerce Database
-- Author: Asa Yudhistira
-- Description: This SQL script performs a revenue analysis on an e-commerce database. It retrieves customer information and their associated revenue data.


-- SECTION 1 — OVERALL REVENUE
-- 1.0 Does Payment Value match price + freight value per order
-- How many orders have a mismatch, and how large is it overall?
WITH item_totals AS (
    SELECT
        order_id,
        ROUND(SUM(price + freight_value), 2) AS item_total
    FROM order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        ROUND(SUM(payment_value), 2) AS payment_total
    FROM order_payments
    GROUP BY order_id
),
comparison AS (
    SELECT
        it.order_id,
        it.item_total,
        pt.payment_total,
        ROUND(it.item_total - pt.payment_total, 2) AS difference
    FROM item_totals it
    JOIN payment_totals pt ON it.order_id = pt.order_id
)
SELECT
    COUNT(*)                                            AS total_orders_compared,
    COUNT(*) FILTER (WHERE ABS(difference) > 0.01)      AS mismatched_orders,
    ROUND(COUNT(*) FILTER (WHERE ABS(difference) > 0.01)
          * 100.0 / COUNT(*), 2)                        AS mismatch_pct,
    ROUND(AVG(ABS(difference)), 2)                       AS avg_abs_difference,
    ROUND(SUM(difference), 2)                             AS net_total_difference,
    MAX(ABS(difference))                                  AS largest_mismatch
FROM comparison;
-- Only 0.31% of orders have a mismatch


-- 1.1 Headline revenue metrics
SELECT 
	COUNT(DISTINCT o.order_id)					AS total_orders,
	COUNT(DISTINCT c.customer_unique_id)		AS unique_customers,
	ROUND(SUM(oi.price + oi.freight_value), 2)	AS total_revenue,
	ROUND(SUM(oi.price), 2)						AS total_product_revenue,
	ROUND(SUM(oi.freight_value), 2)				AS total_freight_revenue,
	ROUND(SUM(oi.price + oi.freight_value) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS avg_order_value
FROM 
	orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
INNER JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered';

-- The total number of orders delivered is 96478 with a total of 93358 unique customers.
-- The total revenue is $15419773.75 with $13221498.11 coming from the products and the rest from freight.
-- The average order valye is $159.83.

-- 1.2 Order value percentiles
SELECT
    ROUND(PERCENTILE_CONT(0.10) WITHIN GROUP
        (ORDER BY order_revenue)::numeric, 2)    AS p10,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP
        (ORDER BY order_revenue)::numeric, 2)    AS p25,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP
        (ORDER BY order_revenue)::numeric, 2)    AS median,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP
        (ORDER BY order_revenue)::numeric, 2)    AS p75,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP
        (ORDER BY order_revenue)::numeric, 2)    AS p90,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP
        (ORDER BY order_revenue)::numeric, 2)    AS p99,
    ROUND(AVG(order_revenue)::numeric, 2)        AS mean_order_value
FROM (
    SELECT
        o.order_id,
        SUM(oi.price + oi.freight_value) AS order_revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id
) order_totals;



-- 1.3 High value orders — what defines the top 10%?
WITH order_totals AS (
    SELECT
        o.order_id,
        SUM(oi.price + oi.freight_value)    AS order_revenue,
        COUNT(oi.order_item_id)             AS items_in_order
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id
),
threshold AS (
    SELECT PERCENTILE_CONT(0.90) WITHIN GROUP
        (ORDER BY order_revenue)::numeric AS p90_value
    FROM order_totals
)
SELECT
    COUNT(*)                            AS high_value_order_count,
    ROUND(AVG(ot.order_revenue)::numeric, 2)     AS avg_revenue,
    ROUND(AVG(ot.items_in_order)::numeric, 2)    AS avg_items,
    MIN(ot.order_revenue)               AS min_revenue,
    MAX(ot.order_revenue)               AS max_revenue
FROM order_totals ot, threshold t
WHERE ot.order_revenue >= t.p90_value;


-- SECTION 2 — REVENUE OVER TIME
-- 2.1 Monthly revenue trend with growth rate
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp) AS order_month,
        COUNT(DISTINCT o.order_id)                      AS total_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2)      AS monthly_revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp)
	
)
SELECT
    order_month,
    total_orders,
    monthly_revenue,
    ROUND(LAG(monthly_revenue) OVER (ORDER BY order_month), 2)  AS prev_month_revenue,
    ROUND((monthly_revenue - LAG(monthly_revenue) OVER
        (ORDER BY order_month)) * 100.0 /
        NULLIF(LAG(monthly_revenue) OVER (ORDER BY order_month), 0), 2) AS mom_growth_pct,
    ROUND(AVG(monthly_revenue) OVER (
        ORDER BY order_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2)                                                       AS rolling_3m_avg
FROM monthly
ORDER BY order_month;


-- 2.2 Best and worst performing months
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp) AS order_month,
        TO_CHAR(o.order_purchase_timestamp, 'Month YYYY') AS month_label,
        ROUND(SUM(oi.price + oi.freight_value), 2)      AS monthly_revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp),
             TO_CHAR(o.order_purchase_timestamp, 'Month YYYY')
)
(SELECT 'Best month' AS rank_label, month_label, monthly_revenue
 FROM monthly ORDER BY monthly_revenue DESC LIMIT 1)
UNION ALL
(SELECT 'Worst month', month_label, monthly_revenue
 FROM monthly ORDER BY monthly_revenue ASC LIMIT 1)
ORDER BY rank_label, monthly_revenue DESC;
-- The best month is november 2017 with a revenue of $1153364.2.
-- The worst month is december 2016 with a revenue of $19.62.



-- 2.3 Revenue by day of week
SELECT
    TO_CHAR(o.order_purchase_timestamp, 'Day')           AS day_of_week,
    EXTRACT(DOW FROM o.order_purchase_timestamp)         AS dow_number,
    COUNT(DISTINCT o.order_id)                           AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2)           AS total_revenue,
    ROUND(AVG(oi.price + oi.freight_value), 2)           AS avg_order_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY TO_CHAR(o.order_purchase_timestamp, 'Day'),
         EXTRACT(DOW FROM o.order_purchase_timestamp)
ORDER BY dow_number;
-- The number of orders is lowest in weekends.



-- SECTION 3 — REVENUE BY CATEGORY
-- 3.1 Top 10 categories by total revenue
SELECT 
	pct.product_category_name_english 			AS category,
	COUNT(DISTINCT o.order_id)					AS total_orders,
	COUNT(oi.order_item_id)						AS total_items_sold,
	ROUND(SUM(oi.price + oi.freight_value), 2) 	AS total_revenue,
	ROUND(AVG(oi.price + oi.freight_value), 2) 	AS avg_item_value,
	ROUND(SUM(oi.price + oi.freight_value) * 100.0 /
          SUM(SUM(oi.price + oi.freight_value)) OVER (), 2) AS pct_of_total_revenue
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
INNER JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_translation pct ON p.product_category_name = pct.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY category
ORDER BY total_revenue DESC
LIMIT 10
-- The top 10 categories by revenue are:
-- 1. health beauty
-- 2. watches gifts
-- 3. bed bath table
-- 4. sport leisure
-- 5. computer accessories
-- 6. furmiture decor
-- 7. housewares
-- 8. cool stuff
-- 9. auto
-- 10. garden tools


-- 3.2 Revenue concentration — how much do top 5 categories contribute?

WITH category_revenue AS(
	SELECT 
		pct.product_category_name_english 			AS category,
		SUM(oi.price + oi.freight_value)			AS revenue
	FROM orders o
	INNER JOIN order_items oi ON o.order_id = oi.order_id
	INNER JOIN products p ON oi.product_id = p.product_id
	LEFT JOIN product_category_translation pct ON p.product_category_name = pct.product_category_name
	WHERE o.order_status = 'delivered'
	GROUP BY category
),
total AS (SELECT SUM(revenue) AS total_revenue FROM category_revenue),
ranked AS (
    SELECT category, revenue,
           RANK() OVER (ORDER BY revenue DESC) AS rnk
    FROM category_revenue
)
SELECT
    SUM(CASE WHEN rnk <= 5  THEN revenue END)                       AS top_5_revenue,
    SUM(CASE WHEN rnk <= 10 THEN revenue END)                       AS top_10_revenue,
    t.total_revenue,
    ROUND(SUM(CASE WHEN rnk <= 5  THEN revenue END)
          * 100.0 / t.total_revenue, 2)                             AS top_5_pct,
    ROUND(SUM(CASE WHEN rnk <= 10 THEN revenue END)
          * 100.0 / t.total_revenue, 2)                             AS top_10_pct
FROM ranked, total t
GROUP BY t.total_revenue;
-- Top 5 Revenue: $6052612.59
-- Top 10 Revenue: $9619616.08
-- Top 5 Percentage: 39.25%
-- Top 10 Percentage: 62.38%

-- 3.3 Top 10 categories by average item value
SELECT
    pct.product_category_name_english  						 AS category,
    COUNT(oi.order_item_id)                                  AS total_items_sold,
    ROUND(AVG(oi.price), 2)                                  AS avg_product_price,
    ROUND(AVG(oi.freight_value), 2)                          AS avg_freight,
    ROUND(AVG(oi.price + oi.freight_value), 2)               AS avg_total_per_item
FROM orders o
JOIN order_items oi  ON o.order_id    = oi.order_id
JOIN products p      ON oi.product_id = p.product_id
LEFT JOIN product_category_translation pct
                     ON p.product_category_name = pct.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY category
HAVING COUNT(oi.order_item_id) >= 100
ORDER BY avg_product_price DESC
LIMIT 10;


-- SECTION 4 — REVENUE BY GEOGRAPHY
-- 4.1 Revenue by customer state
SELECT 
	c.customer_state,
	COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2)              AS total_revenue,
    ROUND(AVG(oi.price + oi.freight_value), 2)              AS avg_order_value,
    ROUND(SUM(oi.price + oi.freight_value) * 100.0 /
          SUM(SUM(oi.price + oi.freight_value)) OVER (), 2) AS pct_of_total_revenue
FROM orders o
JOIN order_items oi  ON o.order_id     = oi.order_id
JOIN customers c     ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY total_revenue DESC



-- 4.2 High volume vs high value states
WITH state_metrics AS (
    SELECT
        c.customer_state,
        COUNT(DISTINCT o.order_id)              AS total_orders,
        ROUND(AVG(
            oi.price + oi.freight_value), 2)    AS avg_order_value
    FROM orders o
    JOIN order_items oi  ON o.order_id    = oi.order_id
    JOIN customers c     ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state
),
averages AS (
    SELECT
        AVG(total_orders)       AS avg_orders,
        AVG(avg_order_value)    AS avg_aov
    FROM state_metrics
)
SELECT
    sm.customer_state,
    sm.total_orders,
    sm.avg_order_value,
    CASE
        WHEN sm.total_orders > a.avg_orders
         AND sm.avg_order_value > a.avg_aov   THEN 'High volume, High value'
        WHEN sm.total_orders > a.avg_orders
         AND sm.avg_order_value <= a.avg_aov  THEN 'High volume, Low value'
        WHEN sm.total_orders <= a.avg_orders
         AND sm.avg_order_value > a.avg_aov   THEN 'Low volume, High value'
        ELSE                                       'Low volume, Low value'
    END AS state_segment
FROM state_metrics sm, averages a
ORDER BY sm.total_orders DESC;



	