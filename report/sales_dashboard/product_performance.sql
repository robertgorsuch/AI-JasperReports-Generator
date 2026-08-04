SELECT
  plu,
  product_description,
  units_sold
FROM dashboard_product_performance
ORDER BY units_sold DESC
FETCH FIRST 20 ROWS ONLY
