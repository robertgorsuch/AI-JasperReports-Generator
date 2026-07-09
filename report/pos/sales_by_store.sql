-- Sales by Store - Top and Bottom Performers (Ingres SQL)
SELECT
    store_number,
    store_name,
    store_province,
    CAST(COUNT(DISTINCT transaction_unique_id) AS INTEGER) AS transaction_count,
    CAST(SUM(quantity) AS INTEGER) AS units_sold,
    CAST(SUM(royalty_sales) AS DECIMAL(18,2)) AS total_sales,
    CAST(SUM(royalty_sales) / NULLIF(COUNT(DISTINCT transaction_unique_id), 0) AS DECIMAL(18,2)) AS avg_transaction_value
FROM pos_transactions
WHERE transaction_type = 'Regular Sale'
GROUP BY store_number, store_name, store_province
ORDER BY total_sales DESC
