-- Promotion Effectiveness Analysis (Ingres SQL)
SELECT
    CASE WHEN has_promotion THEN promotion_type ELSE 'No Promotion' END AS promotion_type,
    CAST(COUNT(DISTINCT transaction_unique_id) AS INTEGER) AS transactions,
    CAST(SUM(quantity) AS INTEGER) AS units_sold,
    CAST(SUM(royalty_sales) AS DECIMAL(18,2)) AS total_sales,
    CAST(SUM(royalty_sales) / COUNT(DISTINCT transaction_unique_id) AS DECIMAL(18,2)) AS avg_transaction_value,
    CAST(CAST(COUNT(DISTINCT transaction_unique_id) AS NUMERIC) /
     (SELECT COUNT(DISTINCT transaction_unique_id) FROM pos_transactions WHERE transaction_type = 'Regular Sale') * 100 AS DECIMAL(5,2)) AS pct_of_transactions
FROM pos_transactions
WHERE transaction_type = 'Regular Sale'
GROUP BY has_promotion, promotion_type
ORDER BY total_sales DESC
