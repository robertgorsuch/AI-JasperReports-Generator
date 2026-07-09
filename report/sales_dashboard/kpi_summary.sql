SELECT 
  COUNT(*) AS total_transactions,
  COUNT(DISTINCT store_id) AS total_stores,
  COUNT(DISTINCT customer_id) AS unique_customers,
  COUNT(DISTINCT transaction_date) AS days_of_data
FROM pos_transactions
