SELECT st.store_city || ' (' || st.store_state || ')' AS store,
       round(sum(s.store_sales - s.store_cost), 0)::numeric AS profit
FROM sales_fact_1997 s
JOIN store st ON st.store_id = s.store_id
GROUP BY st.store_city, st.store_state
ORDER BY profit DESC
