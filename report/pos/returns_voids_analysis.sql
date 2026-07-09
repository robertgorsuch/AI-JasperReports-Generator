-- Returns and Voids Impact Analysis (Ingres SQL)
SELECT
    transaction_type,
    CASE transaction_type
        WHEN 'Regular Sale' THEN 'Regular Sale'
        WHEN 'Regular Return' THEN 'Return'
        WHEN 'Post Void TX' THEN 'Void'
        ELSE 'Other'
    END AS transaction_category,
    CAST(COUNT(DISTINCT transaction_unique_id) AS INTEGER) AS transaction_count,
    CAST(SUM(quantity) AS NUMERIC) AS units,
    CAST(SUM(royalty_sales) AS DECIMAL(18,2)) AS impact,
    CAST(CAST(SUM(royalty_sales) AS NUMERIC) /
     (SELECT SUM(royalty_sales) FROM pos_transactions WHERE transaction_type = 'Regular Sale') * 100 AS DECIMAL(6,3)) AS pct_of_sales
FROM pos_transactions
WHERE transaction_type IN ('Regular Sale', 'Regular Return', 'Post Void TX')
GROUP BY transaction_type
ORDER BY CASE WHEN transaction_type = 'Regular Sale' THEN 0 ELSE 1 END, impact DESC
