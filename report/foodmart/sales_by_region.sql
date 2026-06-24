SELECT r.sales_region AS region,
       SUM(sf.store_sales)::numeric(12,2) AS sales
FROM sales_fact_1998 sf
JOIN store s ON s.store_id = sf.store_id
JOIN region r ON r.region_id = s.region_id
GROUP BY r.sales_region
ORDER BY sales DESC
