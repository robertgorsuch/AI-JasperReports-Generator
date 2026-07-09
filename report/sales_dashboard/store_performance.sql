SELECT 
  store_location,
  province_state,
  transaction_count
FROM dashboard_store_performance
ORDER BY transaction_count DESC
FETCH FIRST 20 ROWS ONLY
