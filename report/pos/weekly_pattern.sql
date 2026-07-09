-- Weekly Pattern Analysis - Sales by Day of Week (Ingres SQL)
SELECT
    EXTRACT(DOW FROM transaction_date) AS day_of_week,
    CASE EXTRACT(DOW FROM transaction_date)
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
        WHEN 7 THEN 'Sunday'
    END AS day_name,
    CAST(COUNT(DISTINCT transaction_unique_id) AS INTEGER) AS transactions,
    CAST(SUM(quantity) AS INTEGER) AS units_sold,
    CAST(SUM(royalty_sales) AS DECIMAL(18,2)) AS daily_sales,
    CAST(SUM(royalty_sales) / COUNT(DISTINCT transaction_unique_id) AS DECIMAL(18,2)) AS avg_transaction_value
FROM pos_transactions
WHERE transaction_type = 'Regular Sale'
GROUP BY EXTRACT(DOW FROM transaction_date)
ORDER BY EXTRACT(DOW FROM transaction_date)
