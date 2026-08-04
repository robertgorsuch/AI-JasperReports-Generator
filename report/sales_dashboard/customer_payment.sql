SELECT
  customer_number,
  transaction_count,
  total_revenue
FROM dashboard_customer_revenue
ORDER BY total_revenue DESC
FETCH FIRST 25 ROWS ONLY
