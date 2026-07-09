-- Top 15 Products by Sales (Ingres SQL)
SELECT
    plu,
    product_description,
    CAST(COUNT(DISTINCT transaction_unique_id) AS INTEGER) AS transactions,
    CAST(SUM(quantity) AS DECIMAL(18,2)) AS units_sold,
    CAST(SUM(royalty_sales) AS DECIMAL(18,2)) AS total_sales,
    CAST(SUM(royalty_sales) / NULLIF(SUM(quantity), 0) AS DECIMAL(18,4)) AS avg_price_per_unit
FROM pos_transactions
WHERE transaction_type = 'Regular Sale'
GROUP BY plu, product_description
ORDER BY total_sales DESC
LIMIT 15
