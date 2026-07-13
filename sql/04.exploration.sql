-- Title: Explore Data in E-commerce Database
-- Author: Asa Yudhistira
-- Description: This SQL script explores the data loaded into the e-commerce database tables.


-- SECTION 1 — DATA STRUCTURE
-- 1.1 What is the date range of the dataset?
SELECT 
	MIN(order_purchase_timestamp) AS earliest_order,
	MAX(order_purchase_timestamp) AS latest_order,
	MAX(order_purchase_timestamp) - MIN(order_purchase_timestamp) AS date_span,
	COUNT(DISTINCT DATE_TRUNC('month', order_purchase_timestamp)) AS months_covered
FROM orders
WHERE order_purchase_timestamp IS NOT NULL
-- Our data spans from 2016-09-04 to 2018-10-17, covering a span of 772 days and 25 months.



-- 1.2 How are orders distributed by status?
SELECT 
	order_status, 
	COUNT(*) AS order_count,
	ROUND(COUNT(*) * 100.0 /SUM(COUNT(*)) OVER (), 2) AS percentage
FROM orders
GROUP BY order_status
ORDER BY order_status DESC
-- We learn that over 97% of orders are delivered, while a small fraction are canceled or still processing. This indicates a high fulfillment rate in the dataset.
-- +---------------+-------------+------------+
-- | order_status  | order_count | percentage |
-- +---------------+-------------+------------+
-- | unavailable   |         609 |       0.61 |
-- | shipped       |        1107 |       1.11 |
-- | processing    |         301 |       0.30 |
-- | invoiced      |         314 |       0.32 |
-- | delivered     |       96478 |      97.02 |
-- | created       |           5 |       0.01 |
-- | canceled      |         625 |       0.63 |
-- | approved      |           2 |       0.00 |
-- +---------------+-------------+------------+



-- 1.3 How many unique customers vs unique orders
SELECT
    COUNT(DISTINCT o.order_id)            AS total_orders,
    COUNT(DISTINCT c.customer_id)         AS total_customer_ids,
    COUNT(DISTINCT c.customer_unique_id)  AS unique_customers,
    ROUND(COUNT(DISTINCT order_id) * 1.0 /
          NULLIF(COUNT(DISTINCT customer_unique_id), 0), 2) AS orders_per_unique_customer
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id;
-- There are a total of 99441 orders with 96096 unique customers.
-- The average order per unique customer is 1.03



-- 1.4 What is the average number of items per order?
SELECT 
	ROUND(AVG(items_per_order), 2)  AS avg_items_per_order,
	MIN(items_per_order)            AS min_items,
    MAX(items_per_order)            AS max_items,
	PERCENTILE_CONT(0.5) WITHIN GROUP
        (ORDER BY items_per_order)  AS median_items
FROM (
	SELECT order_id, COUNT(*) AS items_per_order 
	FROM order_items
	GROUP BY order_id
)
-- The average number of items per order is 1.14, with item ranging from 1 to 21.


-- SECTION 2 — JOIN COMPLETENESS
-- 2.1 How many orders have complete records across all key tables?
SELECT
    COUNT(DISTINCT o.order_id)                                  AS total_orders,
    COUNT(DISTINCT oi.order_id)                                 AS orders_with_items,
    COUNT(DISTINCT op.order_id)                                 AS orders_with_payments,
    COUNT(DISTINCT r.order_id)                                  AS orders_with_reviews,
    COUNT(DISTINCT CASE
        WHEN oi.order_id IS NOT NULL
         AND op.order_id IS NOT NULL
         AND r.order_id  IS NOT NULL
        THEN o.order_id END)                                    AS fully_complete_orders
FROM orders o
LEFT JOIN order_items    oi ON o.order_id = oi.order_id
LEFT JOIN order_payments op ON o.order_id = op.order_id
LEFT JOIN order_reviews  r  ON o.order_id = r.order_id;
--There are 97916 orders with complete records

-- 2.2 How many products have no category assigned?
SELECT 
	COUNT(*) AS total_products,
	COUNT(*) FILTER (WHERE product_category_name IS NULL) AS missing_category,
	ROUND(COUNT(*) FILTER (WHERE product_category_name IS NULL) * 100.0 / COUNT(*) ,2)
FROM products
-- Out of the total 32951 products, 610 has missing categories.
-- This equates to 1.85% of total products.

-- 2.3 How many products have no English category translation?
SELECT 
	COUNT(DISTINCT p.product_id) AS total_products,
	COUNT(DISTINCT p.product_id) FILTER (WHERE pct.product_category_name_english IS NULL) AS missing_english_name,
	ROUND( COUNT(DISTINCT p.product_id) FILTER (WHERE product_category_name_english IS NULL) * 100.0 / COUNT(*) ,2)
FROM products p
LEFT JOIN product_category_translation pct
ON p.product_category_name = pct.product_category_name
-- Out of 32951 products, 623 do not have english translation or 1.89% of total data.

-- SECTION 3 — MISSING VALUES & DATA QUALITY
-- 3.1 Missing values in the orders table
SELECT
    'order_approved_at'             AS column_name,
    COUNT(*) FILTER (WHERE order_approved_at IS NULL)           AS null_count,
    ROUND(COUNT(*) FILTER (WHERE order_approved_at IS NULL)
          * 100.0 / COUNT(*), 2)                               AS null_pct
FROM orders
UNION ALL
SELECT
    'order_delivered_carrier_date',
    COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL),
    ROUND(COUNT(*) FILTER (WHERE order_delivered_carrier_date IS NULL)
          * 100.0 / COUNT(*), 2)
FROM orders
UNION ALL
SELECT
    'order_delivered_customer_date',
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL),
    ROUND(COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL)
          * 100.0 / COUNT(*), 2)
FROM orders
UNION ALL
SELECT
    'review_comment_message',
    COUNT(*) FILTER (WHERE review_comment_message IS NULL),
    ROUND(COUNT(*) FILTER (WHERE review_comment_message IS NULL)
          * 100.0 / COUNT(*), 2)
FROM order_reviews;


-- 3.2 Are there any orders with zero or negative price items?
SELECT
    COUNT(*) FILTER (WHERE price <= 0)          AS zero_or_negative_price,
    COUNT(*) FILTER (WHERE freight_value < 0)   AS negative_freight,
    COUNT(*)                                    AS total_items
FROM order_items;
-- Sanity Check passes.

-- 3.3 Are there duplicate orders or reviews?
SELECT
    'duplicate order_ids' AS check_name,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_count
FROM orders
UNION ALL
SELECT
    'duplicate review (review_id + order_id)',
    COUNT(*) - COUNT(DISTINCT review_id || order_id)
FROM order_reviews;

-- No duplicates


-- SECTION 4 — GEOGRAPHIC OVERVIEW
-- 4.1 How many states are represented?
SELECT
    a.states_with_customers,
    b.states_with_sellers
FROM
    (SELECT COUNT(DISTINCT customer_state) AS states_with_customers FROM customers) a,
    (SELECT COUNT(DISTINCT seller_state) AS states_with_sellers FROM sellers) b;
-- We see that customers are available in 27 states whereas sellers are only available in 23.


-- 4.2 What percentage of orders come from the top 10 states?
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)                                  AS total_orders,
    ROUND(COUNT(DISTINCT o.order_id) * 100.0 /
          SUM(COUNT(DISTINCT o.order_id)) OVER (), 2)           AS pct_of_total_orders
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY total_orders DESC
LIMIT 10;

-- 4.3 Are sellers geographically concentrated too?
SELECT 
	seller_state,
	COUNT(DISTINCT seller_id) AS total_sellers,
	ROUND(COUNT(DISTINCT seller_id) * 100.0 / SUM(COUNT(DISTINCT seller_id)) OVER (),2)
FROM sellers
GROUP BY seller_state
ORDER by total_sellers DESC
LIMIT 10;


-- SECTION 5 — PRODUCT OVERVIEW
-- 5.1 How many product categories exist?
SELECT
    COUNT(DISTINCT product_category_name)           AS total_categories_portuguese,
    COUNT(DISTINCT product_category_name_english)   AS total_categories_english
FROM product_category_translation;
-- 71 categories exists.


-- 5.2 What is the distribution of product physical attributes?
SELECT
    ROUND(AVG(product_weight_g), 0)     AS avg_weight_g,
    ROUND(AVG(product_length_cm), 0)    AS avg_length_cm,
    ROUND(AVG(product_height_cm), 0)    AS avg_height_cm,
    ROUND(AVG(product_width_cm), 0)     AS avg_width_cm,
    MAX(product_weight_g)               AS max_weight_g,
    COUNT(*) FILTER (WHERE product_weight_g IS NULL) AS missing_weight
FROM products;

-- SECTION 6 — REVIEW OVERVIEW
-- 6.1 What is the overall review score distribution?
SELECT
    review_score,
    COUNT(*)                                                    AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)         AS percentage
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;



-- 6.2 What proportion of reviews have a written comment?
SELECT
    COUNT(*)                                                        AS total_reviews,
    COUNT(*) FILTER (WHERE review_comment_message IS NOT NULL
                       AND TRIM(review_comment_message) != '')      AS reviews_with_comment,
    ROUND(COUNT(*) FILTER (WHERE review_comment_message IS NOT NULL
                       AND TRIM(review_comment_message) != '')
          * 100.0 / COUNT(*), 2)                                    AS pct_with_comment
FROM order_reviews;

-- SECTION 7 — MASTER TABLE PREVIEW
-- 7.1 Preview of the fully joined master dataset
SELECT
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    c.customer_city,
    c.customer_state,
    oi.price,
    oi.freight_value,
    COALESCE(pct.product_category_name_english, 'Unknown')      AS category_english,
    s.seller_state,
    op.payment_type,
    op.payment_value,
    r.review_score
FROM orders o
LEFT JOIN customers c               ON o.customer_id    = c.customer_id
LEFT JOIN order_items oi            ON o.order_id       = oi.order_id
LEFT JOIN products p                ON oi.product_id    = p.product_id
LEFT JOIN product_category_translation pct
                                    ON p.product_category_name
                                     = pct.product_category_name
LEFT JOIN sellers s                 ON oi.seller_id     = s.seller_id
LEFT JOIN order_payments op         ON o.order_id       = op.order_id
                                   AND op.payment_sequential = 1
LEFT JOIN order_reviews r           ON o.order_id       = r.order_id
LIMIT 10;