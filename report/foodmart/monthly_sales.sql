SELECT lpad(t.month_of_year::text, 2, '0') || ' ' || left(t.the_month, 3) AS month,
       round(sum(s.store_sales), 0)::numeric AS sales
FROM sales_fact_1997 s
JOIN time_by_day t ON t.time_id = s.time_id
GROUP BY t.month_of_year, t.the_month
ORDER BY t.month_of_year
