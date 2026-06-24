SELECT pc.product_category AS category,
       SUM(sf.store_sales)::numeric(12,2) AS sales,
       SUM(sf.unit_sales)::int AS units
FROM sales_fact_1998 sf
JOIN product p ON p.product_id = sf.product_id
JOIN product_class pc ON pc.product_class_id = p.product_class_id
GROUP BY pc.product_category
ORDER BY sales DESC
LIMIT 15
