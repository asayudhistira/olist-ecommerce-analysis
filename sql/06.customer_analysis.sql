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




-- SECTION 2 — RFM FOUNDATION
-- 2.1 RFM raw scores per customer
-- 2.2 RFM summary statistics


-- SECTION 3 — CUSTOMER GEOGRAPHY
-- 3.1 Top 10 cities by customer count
-- 3.2 Average customer spend by state


-- SECTION 4 — COHORT FOUNDATION
-- 4.1 First purchase month per customer
-- 4.2 Cohort size by first purchase month
-- 4.3 New vs returning customers per month
