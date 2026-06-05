SELECT lpad(t.month_of_year::text, 2, '0') || ' ' || left(t.the_month, 3) AS month,
       y.yr AS year,
       round(sum(y.store_sales), 0)::numeric AS sales
FROM (SELECT time_id, store_sales, '1997' AS yr FROM sales_fact_1997
      UNION ALL
      SELECT time_id, store_sales, '1998' AS yr FROM sales_fact_1998
      UNION ALL
      SELECT time_id, store_sales, '1998' AS yr FROM sales_fact_dec_1998) y
JOIN time_by_day t ON t.time_id = y.time_id
GROUP BY t.month_of_year, t.the_month, y.yr
ORDER BY t.month_of_year, y.yr
