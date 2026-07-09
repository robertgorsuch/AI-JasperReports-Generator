-- Daily Sales Trend - Ingres SQL Compliant
SELECT
    transaction_date,
    CAST(COUNT(DISTINCT transaction_unique_id) AS INTEGER) AS transaction_count,
    CAST(SUM(quantity) AS INTEGER) AS units_sold,
    CAST(SUM(royalty_sales) AS DECIMAL(18,2)) AS daily_sales
FROM pos_transactions
WHERE transaction_type = 'Regular Sale'
GROUP BY transaction_date
ORDER BY transaction_date DESC
