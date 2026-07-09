SELECT 
  transaction_date AS date,
  transaction_count,
  store_count,
  customer_count
FROM dashboard_daily_sales
ORDER BY transaction_date
