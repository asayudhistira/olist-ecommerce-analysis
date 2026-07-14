-- Title: Seller Performance Analysis in E-commerce Database
-- Author: Asa Yudhistira
-- Description: This SQL script analyzes seller performance metrics in an e-commerce database.


-- SECTION 1 — SELLER OVERVIEW
-- 1.1 Overall seller metrics
SELECT 
    COUNT(DISTINCT s.seller_id) AS total_sellers,
    COUNT(DISTINCT o.order_id) AS total_orders,
	ROUND(SUM(oi.price + oi.freight_value),2) AS total_revenue,
	ROUND(AVG(oi.price + oi.freight_value), 2)              AS avg_revenue_per_item,
    ROUND(SUM(oi.price + oi.freight_value) /
          NULLIF(COUNT(DISTINCT s.seller_id), 0), 2)        AS avg_revenue_per_seller,
    ROUND(COUNT(DISTINCT o.order_id) * 1.0 /
          NULLIF(COUNT(DISTINCT s.seller_id), 0), 2)        AS avg_orders_per_seller
FROM sellers s
JOIN order_items oi  ON s.seller_id   = oi.seller_id
JOIN orders o        ON oi.order_id   = o.order_id
WHERE o.order_status = 'delivered';


-- 1.2 Seller activity distribution
WITH seller_orders AS (
    SELECT
        s.seller_id,
        COUNT(DISTINCT o.order_id)              AS total_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue
    FROM sellers s
    JOIN order_items oi ON s.seller_id  = oi.seller_id
    JOIN orders o       ON oi.order_id  = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY s.seller_id
)
SELECT
    CASE
        WHEN total_orders = 1        THEN '1 order'
        WHEN total_orders BETWEEN 2 AND 5   THEN '2-5 orders'
        WHEN total_orders BETWEEN 6 AND 20  THEN '6-20 orders'
        WHEN total_orders BETWEEN 21 AND 50 THEN '21-50 orders'
        ELSE '50+ orders'
    END                                         AS order_bucket,
    COUNT(*)                                    AS seller_count,
    ROUND(COUNT(*) * 100.0 /
          SUM(COUNT(*)) OVER (), 2)             AS pct_of_sellers,
    ROUND(SUM(total_revenue), 2)                AS bucket_revenue,
    ROUND(SUM(total_revenue) * 100.0 /
          SUM(SUM(total_revenue)) OVER (), 2)   AS pct_of_revenue
FROM seller_orders
GROUP BY CASE
    WHEN total_orders = 1        THEN '1 order'
    WHEN total_orders BETWEEN 2 AND 5   THEN '2-5 orders'
    WHEN total_orders BETWEEN 6 AND 20  THEN '6-20 orders'
    WHEN total_orders BETWEEN 21 AND 50 THEN '21-50 orders'
    ELSE '50+ orders'
END
ORDER BY MIN(total_orders);


-- 1.3 Revenue concentration — Pareto check
WITH seller_revenue AS (
    SELECT
        s.seller_id,
        SUM(oi.price + oi.freight_value) AS revenue
    FROM sellers s
    JOIN order_items oi ON s.seller_id = oi.seller_id
    JOIN orders o       ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY s.seller_id
),
ranked AS (
    SELECT
        seller_id,
        revenue,
        RANK() OVER (ORDER BY revenue DESC)     AS revenue_rank,
        COUNT(*) OVER ()                        AS total_sellers
    FROM seller_revenue
),
total AS (SELECT SUM(revenue) AS total_revenue FROM seller_revenue)
SELECT
    ROUND(SUM(CASE WHEN revenue_rank <= total_sellers * 0.10
              THEN revenue END) * 100.0 / t.total_revenue, 2) AS top_10pct_sellers_revenue_share,
    ROUND(SUM(CASE WHEN revenue_rank <= total_sellers * 0.20
              THEN revenue END) * 100.0 / t.total_revenue, 2) AS top_20pct_sellers_revenue_share,
    ROUND(SUM(CASE WHEN revenue_rank <= total_sellers * 0.50
              THEN revenue END) * 100.0 / t.total_revenue, 2) AS top_50pct_sellers_revenue_share
FROM ranked, total t
GROUP BY t.total_revenue;


-- SECTION 2 — TOP SELLER ANALYSIS
-- 2.1 Top 10 sellers by revenue
SELECT
    s.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    COUNT(oi.order_item_id)                                 AS total_items_sold,
    ROUND(SUM(oi.price + oi.freight_value), 2)              AS total_revenue,
    ROUND(AVG(oi.price), 2)                                 AS avg_product_price,
    ROUND(AVG(r.review_score), 2)                           AS avg_review_score
FROM sellers s
JOIN order_items oi  ON s.seller_id   = oi.seller_id
JOIN orders o        ON oi.order_id   = o.order_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id, s.seller_city, s.seller_state
ORDER BY total_revenue DESC
LIMIT 10;


-- 2.2 Top 10 sellers by order volume
SELECT
    s.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2)              AS total_revenue,
    ROUND(AVG(oi.price), 2)                                 AS avg_product_price,
    RANK() OVER (ORDER BY COUNT(DISTINCT o.order_id) DESC)  AS volume_rank,
    RANK() OVER (ORDER BY SUM(oi.price + oi.freight_value)
                 DESC)                                      AS revenue_rank
FROM sellers s
JOIN order_items oi ON s.seller_id = oi.seller_id
JOIN orders o       ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id, s.seller_city, s.seller_state
ORDER BY total_orders DESC
LIMIT 10;


-- SECTION 3 — SELLER QUALITY
-- 3.1 Average review score per seller
SELECT
    s.seller_id,
    s.seller_state,
    COUNT(DISTINCT o.order_id)              AS total_orders,
    ROUND(AVG(r.review_score), 2)           AS avg_review_score,
    COUNT(*) FILTER (WHERE r.review_score = 1) AS one_star_reviews,
    COUNT(*) FILTER (WHERE r.review_score = 5) AS five_star_reviews,
    ROUND(COUNT(*) FILTER (WHERE r.review_score <= 2) * 100.0 /
          NULLIF(COUNT(r.review_score), 0), 2) AS low_rating_pct
FROM sellers s
JOIN order_items oi  ON s.seller_id = oi.seller_id
JOIN orders o        ON oi.order_id = o.order_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id, s.seller_state
HAVING COUNT(DISTINCT o.order_id) >= 10
ORDER BY avg_review_score ASC
LIMIT 15;


-- 3.2 Sellers with highest late delivery rate
SELECT
    s.seller_id,
    s.seller_state,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
        THEN o.order_id END)                                AS late_deliveries,
    ROUND(COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date >
             o.order_estimated_delivery_date
        THEN o.order_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT o.order_id), 0), 2)           AS late_delivery_pct,
    ROUND(AVG(r.review_score), 2)                           AS avg_review_score
FROM sellers s
JOIN order_items oi  ON s.seller_id = oi.seller_id
JOIN orders o        ON oi.order_id = o.order_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY s.seller_id, s.seller_state
HAVING COUNT(DISTINCT o.order_id) >= 10
ORDER BY late_delivery_pct DESC
LIMIT 15;


-- 3.3 Seller quality scorecard
WITH seller_metrics AS (
    SELECT
        s.seller_id,
        s.seller_state,
        COUNT(DISTINCT o.order_id)                          AS total_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2)          AS total_revenue,
        ROUND(AVG(r.review_score), 2)                       AS avg_review_score,
        ROUND(COUNT(DISTINCT CASE
            WHEN o.order_delivered_customer_date >
                 o.order_estimated_delivery_date
            THEN o.order_id END) * 100.0 /
            NULLIF(COUNT(DISTINCT o.order_id), 0), 2)       AS late_delivery_pct
    FROM sellers s
    JOIN order_items oi  ON s.seller_id = oi.seller_id
    JOIN orders o        ON oi.order_id = o.order_id
    LEFT JOIN order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY s.seller_id, s.seller_state
    HAVING COUNT(DISTINCT o.order_id) >= 10
)
SELECT
    seller_id,
    seller_state,
    total_orders,
    total_revenue,
    avg_review_score,
    late_delivery_pct,
    CASE
        WHEN avg_review_score >= 4.0
         AND late_delivery_pct < 10    THEN 'High Quality'
        WHEN avg_review_score >= 3.0
         AND late_delivery_pct < 20    THEN 'Acceptable'
        WHEN avg_review_score < 3.0
         OR  late_delivery_pct >= 30   THEN 'At Risk'
        ELSE                                'Needs Monitoring'
    END                                                     AS quality_tier
FROM seller_metrics
ORDER BY total_revenue DESC;

-- SECTION 4 — SELLER GEOGRAPHY
-- 4.1 Revenue and seller count by state
SELECT
    s.seller_state,
    COUNT(DISTINCT s.seller_id)                             AS total_sellers,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2)              AS total_revenue,
    ROUND(AVG(r.review_score), 2)                           AS avg_review_score,
    ROUND(COUNT(DISTINCT s.seller_id) * 100.0 /
          SUM(COUNT(DISTINCT s.seller_id)) OVER (), 2)      AS pct_of_sellers
FROM sellers s
JOIN order_items oi  ON s.seller_id = oi.seller_id
JOIN orders o        ON oi.order_id = o.order_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_state
ORDER BY total_revenue DESC;

-- 4.2 Same-state vs cross-state orders
SELECT
    CASE
        WHEN s.seller_state = c.customer_state THEN 'Same state'
        ELSE 'Cross state'
    END                                                     AS shipping_type,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(COUNT(DISTINCT o.order_id) * 100.0 /
          SUM(COUNT(DISTINCT o.order_id)) OVER (), 2)       AS pct_of_orders,
    ROUND(AVG(oi.freight_value), 2)                         AS avg_freight_value,
    ROUND(AVG(r.review_score), 2)                           AS avg_review_score,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date -
            o.order_purchase_timestamp)) / 86400), 1)       AS avg_delivery_days
FROM orders o
JOIN order_items oi  ON o.order_id    = oi.order_id
JOIN sellers s       ON oi.seller_id  = s.seller_id
JOIN customers c     ON o.customer_id = c.customer_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY CASE
    WHEN s.seller_state = c.customer_state THEN 'Same state'
    ELSE 'Cross state'
END;


-- SECTION 5 — SELLER CATEGORY RELATIONSHIP
-- 5.1 Top categories per top 10 sellers
WITH top_sellers AS (
    SELECT s.seller_id
    FROM sellers s
    JOIN order_items oi ON s.seller_id = oi.seller_id
    JOIN orders o       ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY s.seller_id
    ORDER BY SUM(oi.price + oi.freight_value) DESC
    LIMIT 10
)
SELECT
    oi.seller_id,
    COALESCE(pct.product_category_name_english, 'Unknown')  AS category,
    COUNT(oi.order_item_id)                                 AS items_sold,
    ROUND(SUM(oi.price + oi.freight_value), 2)              AS category_revenue
FROM order_items oi
JOIN orders o   ON oi.order_id   = o.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_translation pct
                ON p.product_category_name = pct.product_category_name
WHERE o.order_status = 'delivered'
  AND oi.seller_id IN (SELECT seller_id FROM top_sellers)
GROUP BY oi.seller_id, pct.product_category_name_english
ORDER BY oi.seller_id, category_revenue DESC;


-- 5.2 Category seller concentration
 SELECT
    COALESCE(pct.product_category_name_english, 'Unknown')  AS category,
    COUNT(DISTINCT oi.seller_id)                            AS total_sellers,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2)              AS total_revenue,
    ROUND(SUM(oi.price + oi.freight_value) /
          NULLIF(COUNT(DISTINCT oi.seller_id), 0), 2)       AS revenue_per_seller
FROM order_items oi
JOIN orders o   ON oi.order_id   = o.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_translation pct
                ON p.product_category_name = pct.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY pct.product_category_name_english
HAVING COUNT(DISTINCT oi.seller_id) >= 5
ORDER BY revenue_per_seller DESC
LIMIT 15;