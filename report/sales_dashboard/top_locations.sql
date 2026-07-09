SELECT 
  store_location,
  province_state,
  transaction_count
FROM dashboard_top_locations
ORDER BY transaction_count DESC
FETCH FIRST 15 ROWS ONLY
