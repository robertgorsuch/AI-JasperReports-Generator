SELECT 
  customer_id,
  payment_method,
  usage_count
FROM dashboard_customer_payment
ORDER BY usage_count DESC
FETCH FIRST 25 ROWS ONLY
