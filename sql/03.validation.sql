-- Title: Validate Data in E-commerce Database
-- Author: Asa Yudhistira
-- Description: This SQL script validates the data loaded into the e-commerce database tables.



SELECT 'customers'                      AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'geolocation',                   COUNT(*) FROM geolocation
UNION ALL
SELECT 'sellers',                       COUNT(*) FROM sellers
UNION ALL
SELECT 'product_category_translation',  COUNT(*) FROM product_category_translation
UNION ALL
SELECT 'products',                      COUNT(*) FROM products
UNION ALL
SELECT 'orders',                        COUNT(*) FROM orders
UNION ALL
SELECT 'order_items',                   COUNT(*) FROM order_items
UNION ALL
SELECT 'order_payments',               COUNT(*) FROM order_payments
UNION ALL
SELECT 'order_reviews',                COUNT(*) FROM order_reviews
ORDER BY table_name;