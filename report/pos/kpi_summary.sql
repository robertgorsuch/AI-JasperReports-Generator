-- POS KPI Summary - Total Sales, Units, Transactions, Avg Value (Ingres SQL)
SELECT
    CAST(SUM(royalty_sales) AS DECIMAL(18,2)) AS total_sales,
    CAST(SUM(quantity) AS INTEGER) AS total_units,
    CAST(COUNT(DISTINCT transaction_unique_id) AS INTEGER) AS total_transactions,
    CAST(SUM(royalty_sales) / COUNT(DISTINCT transaction_unique_id) AS DECIMAL(18,2)) AS avg_transaction_value,
    CAST(COUNT(DISTINCT store_number) AS INTEGER) AS active_stores,
    CAST(COUNT(DISTINCT CASE WHEN customer_number IS NOT NULL AND customer_number != '0' THEN customer_number END) AS INTEGER) AS loyalty_customers
FROM pos_transactions
WHERE transaction_type = 'Regular Sale'
