SELECT
  CAST(sale_date AS VARCHAR(10)) AS sale_date,
  transaction_count,
  store_count,
  customer_count
FROM dashboard_daily_sales
ORDER BY sale_date
