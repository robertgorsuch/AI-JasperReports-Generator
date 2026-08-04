SELECT
  pc.product_family,
  CAST(SUM(sf.unit_sales) AS DECIMAL(18,2)) AS unit_sales,
  CAST(SUM(sf.store_sales) AS DECIMAL(18,2)) AS total_sales
FROM sales_fact_1997 sf
JOIN product p ON sf.product_id = p.product_id
JOIN product_class pc ON p.product_class_id = pc.product_class_id
WHERE pc.product_family IS NOT NULL
GROUP BY pc.product_family
ORDER BY total_sales DESC
