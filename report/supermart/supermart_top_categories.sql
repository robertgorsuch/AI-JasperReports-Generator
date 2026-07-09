SELECT pc.product_category AS category,
       round(sum(s.store_sales), 0)::numeric AS sales
FROM sales_fact_1997 s
JOIN product p ON p.product_id = s.product_id
JOIN product_class pc ON pc.product_class_id = p.product_class_id
GROUP BY pc.product_category
ORDER BY sales DESC
LIMIT 10
