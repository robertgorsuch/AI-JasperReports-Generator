SELECT pr.media_type AS media_type,
       round(sum(s.store_sales), 0)::numeric AS sales
FROM sales_fact_1997 s
JOIN promotion pr ON pr.promotion_id = s.promotion_id
WHERE pr.media_type <> 'No Media'
GROUP BY pr.media_type
ORDER BY sales DESC
