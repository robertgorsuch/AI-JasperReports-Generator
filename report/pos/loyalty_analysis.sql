-- Loyalty Customer Analysis (Ingres SQL)
SELECT
    is_loyalty_customer,
    CASE WHEN is_loyalty_customer THEN 'Loyalty' ELSE 'Non-Loyalty' END AS customer_type,
    CAST(COUNT(DISTINCT transaction_unique_id) AS INTEGER) AS transactions,
    CAST(SUM(quantity) AS INTEGER) AS units_sold,
    CAST(SUM(royalty_sales) AS DECIMAL(18,2)) AS total_sales,
    CAST(COUNT(DISTINCT customer_number) AS INTEGER) AS unique_customers,
    CAST(SUM(royalty_sales) / COUNT(DISTINCT transaction_unique_id) AS DECIMAL(18,2)) AS avg_transaction_value
FROM pos_transactions
WHERE transaction_type = 'Regular Sale'
GROUP BY is_loyalty_customer
ORDER BY total_sales DESC
