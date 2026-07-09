SELECT round(sum(store_sales), 0)::numeric            AS total_sales,
       round(sum(store_sales - store_cost), 0)::numeric AS gross_profit,
       round(100.0 * sum(store_sales - store_cost) / nullif(sum(store_sales), 0), 1)::numeric AS margin_pct,
       sum(unit_sales)::int                          AS units_sold,
       count(*)::int                                 AS transactions
FROM sales_fact_1997
