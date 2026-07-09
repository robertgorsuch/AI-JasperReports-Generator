-- Hourly Sales Pattern - Peak Hours Analysis (Ingres SQL)
SELECT
    hour_of_day,
    CAST(COUNT(DISTINCT transaction_unique_id) AS INTEGER) AS transaction_count,
    CAST(SUM(quantity) AS INTEGER) AS units_sold,
    CAST(SUM(royalty_sales) AS DECIMAL(18,2)) AS hourly_sales,
    CAST(SUM(royalty_sales) / NULLIF(COUNT(DISTINCT transaction_unique_id), 0) AS DECIMAL(18,2)) AS avg_transaction_value
FROM pos_transactions
WHERE transaction_type = 'Regular Sale'
GROUP BY hour_of_day
ORDER BY hour_of_day
