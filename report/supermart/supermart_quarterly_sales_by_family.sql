SELECT t.quarter AS quarter,
       pc.product_family AS family,
       round(sum(s.store_sales), 0)::numeric AS sales
FROM sales_fact_1997 s
JOIN time_by_day t ON t.time_id = s.time_id
JOIN product p ON p.product_id = s.product_id
JOIN product_class pc ON pc.product_class_id = p.product_class_id
GROUP BY t.quarter, pc.product_family
ORDER BY t.quarter, pc.product_family
