SELECT st.store_state                          AS state,
       round(sum(s.store_sales), 0)::numeric   AS sales
FROM sales_fact_1997 s
JOIN store st ON st.store_id = s.store_id
GROUP BY st.store_state
ORDER BY sales DESC
