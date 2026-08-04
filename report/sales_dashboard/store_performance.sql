SELECT
  store_name,
  province,
  transaction_count,
  revenue
FROM dashboard_store_performance
ORDER BY transaction_count DESC
FETCH FIRST 20 ROWS ONLY
