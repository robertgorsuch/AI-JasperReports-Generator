# POS Semantic Layer - `pos_transactions`

AI Analyst (Wobby) semantic-layer definition for the `pos_transactions` model.

Point-of-sale transaction line items from retail stores, covering sales, returns, and voids. Each row represents one product line item within a transaction.

- **Source:** `SELECT   * FROM "robert.gorsuch"."pos_transactions"`
- **Grain:** one product line item within a transaction
- **Environment version:** 1.0  -  **Exported:** 2026-06-21T18:10:59.212Z
- **Totals:** 28 dimensions / 25 measures / 15 metrics

---

## Dimensions (28)

| Dimension | Type | Key | Time grains | Expression | Description |
|---|---|---|---|---|---|
| `transaction_date` | date |  | day, week, month, quarter, year | `transaction_date` | Date the transaction occurred |
| `transaction_unique_id` | string |  |  | `transaction_unique_id` | Globally unique identifier for a transaction (basket/receipt) |
| `transaction_sequence` | number |  |  | `transaction_sequence` | Line item sequence number within a transaction |
| `store_number` | number |  |  | `store_number` | Unique store identifier number |
| `store_province` | enum |  |  | `store_province` | Canadian province or territory abbreviation where the store is located |
| `customer_number` | string |  |  | `customer_number` | Loyalty customer identifier. Non-loyalty (anonymous) transactions may have 0 or null. |
| `customer_email_flag` | number |  |  | `customer_email_flag` | Flag indicating whether the customer has provided email consent (1 = yes, 0 = no) |
| `product_description` | string |  |  | `product_description` | Full product name and description |
| `event_id` | string |  |  | `event_id` | Promotion event identifier associated with the transaction line item |
| `pricebook_regular_price` | number |  |  | `pricebook_regular_price` | Standard shelf/pricebook regular price for the product |
| `transaction_time` | string |  |  | `transaction_time` | Time of day the transaction occurred (HH:MM:SS) |
| `transaction_number` | number |  |  | `transaction_number` | Transaction number within a store |
| `transaction_type` | enum |  |  | `transaction_type` | Type of transaction |
| `store_name` | string |  |  | `store_name` | Name of the retail store location (335 unique stores) |
| `store_region` | enum |  |  | `store_region` | Broad geographic sales region grouping provinces |
| `customer_fsa` | string |  |  | `customer_fsa` | Customer forward sortation area (first 3 characters of Canadian postal code) |
| `plu` | number |  |  | `plu` | Price look-up code — unique product identifier at the SKU level |
| `promotion_type` | enum |  |  | `promotion_type` | Type of promotion applied to the item (T = TPR/temporary price reduction, M = markdown, O = override; blank = no promotion) |
| `extended_event_id` | string |  |  | `extended_event_id` | Extended promotion event identifier for more granular promotion tracking |
| `pricebook_sale_price` | number |  |  | `pricebook_sale_price` | Pricebook promotional sale price (0 if no sale price is set) |
| `pricebook_cost` | number |  |  | `pricebook_cost` | Standard cost of the product from the pricebook |
| `day_of_week` | number |  |  | `EXTRACT(DOW FROM transaction_date)` | Day of the week the transaction occurred (1=Monday through 7=Sunday) — use for peak day analysis |
| `transaction_month` | number |  |  | `EXTRACT(MONTH FROM transaction_date)` | Month number the transaction occurred (1=January through 12=December) — use for seasonality analysis |
| `hour_of_day` | number |  |  | `EXTRACT(HOUR FROM transaction_time)` | Hour of day the transaction occurred (0-23) — use for peak hour / time-of-day analysis |
| `is_loyalty_customer` | boolean |  |  | `CASE WHEN customer_number IS NOT NULL AND customer_number != '0' THEN true ELSE false END` | True if the transaction is attributed to an identified loyalty program customer, false if anonymous |
| `transaction_year` | number |  |  | `EXTRACT(YEAR FROM transaction_date)` | Year the transaction occurred — use for year-over-year (2019 vs 2020) comparisons |
| `has_promotion` | boolean |  |  | `CASE WHEN promotion_type IS NOT NULL AND promotion_type != '' THEN true ELSE false END` | True if a promotion was applied to this line item, false if sold at regular price |
| `is_return` | boolean |  |  | `CASE WHEN transaction_type = 'Regular Return' THEN true ELSE false END` | True if this transaction is a Regular Return (customer refund), false otherwise |

## Measures (25)

| Measure | Unit | Expression | Description |
|---|---|---|---|
| `price_reduction_amount` | CAD | `SUM(pricebook_regular_price) - SUM(selling_price)` | Total dollar reduction from pricebook regular price to actual selling price — captures the full value of promotions and markdowns |
| `total_transactions` | transactions | `COUNT(DISTINCT transaction_unique_id)` | Count of unique transactions (baskets/receipts) |
| `total_quantity` | units | `SUM(quantity)` | Total quantity of items sold |
| `total_original_revenue` | CAD | `SUM(original_selling_price)` | Total revenue at original (pre-discount) selling price |
| `gross_profit` | CAD | `SUM(selling_price) - SUM(cost)` | Gross profit (revenue minus cost of goods sold) |
| `total_subsidy` | CAD | `SUM(subsidy)` | Total subsidy received (marketing and expected subsidy contributions combined) |
| `total_marketing_subsidy` | CAD | `SUM(marketing_subsidy)` | Total marketing subsidy contributions |
| `total_override_discount` | CAD | `SUM(override_discount)` | Total manual override discounts applied by store staff |
| `avg_basket_size` | CAD | `SUM(selling_price) / COUNT(DISTINCT transaction_unique_id)` | Average transaction value (total revenue divided by number of unique transactions) |
| `total_line_items` | line items | `COUNT(*)` | Total number of transaction line items (one per product per transaction) |
| `total_revenue` | CAD | `SUM(selling_price)` | Total revenue based on actual selling price paid by customers (after discounts and promotions) |
| `total_cost` | CAD | `SUM(cost)` | Total cost of goods sold |
| `total_royalty_sales` | CAD | `SUM(royalty_sales)` | Total royalty-eligible sales amount |
| `total_expected_subsidy` | CAD | `SUM(expected_subsidy)` | Total expected subsidy from supplier or program contributions |
| `total_transaction_discount` | CAD | `SUM(transaction_discount)` | Total discounts applied at the transaction level |
| `total_item_discount` | CAD | `SUM(item_discount)` | Total discounts applied at the individual item level |
| `avg_selling_price` | CAD | `AVG(selling_price)` | Average selling price per line item |
| `total_unique_customers` | customers | `COUNT(DISTINCT customer_number)` | Count of unique loyalty customers who made purchases |
| `gross_margin_pct` | % | `(SUM(selling_price) - SUM(cost)) / NULLIF(SUM(selling_price), 0) * 100` | Gross profit as a percentage of total revenue — the proportion of revenue retained after cost of goods sold |
| `total_discount` | CAD | `SUM(transaction_discount) + SUM(item_discount) + SUM(override_discount)` | Combined total of all discounts applied — transaction-level, item-level, and override discounts combined |
| `void_transaction_count` | transactions | `COUNT(DISTINCT CASE WHEN transaction_type = 'Post Void TX' THEN transaction_unique_id END)` | Count of unique Post Void transactions (transactions voided at the register) |
| `loyalty_customer_revenue` | CAD | `SUM(CASE WHEN customer_number IS NOT NULL AND customer_number != '0' THEN selling_price ELSE 0 END)` | Total revenue from identified loyalty program customers (excludes anonymous transactions where customer_number is 0 or null) |
| `return_transaction_count` | transactions | `COUNT(DISTINCT CASE WHEN transaction_type = 'Regular Return' THEN transaction_unique_id END)` | Count of unique Regular Return transactions (customer refunds/returns) |
| `total_pricebook_regular_revenue` | CAD | `SUM(pricebook_regular_price)` | Total revenue at standard pricebook shelf price — compare against total_revenue to quantify the full impact of all promotions and discounts |
| `avg_items_per_transaction` | items | `COUNT(*) / NULLIF(COUNT(DISTINCT transaction_unique_id), 0)` | Average number of line items (products) per transaction — measures basket depth |

## Metrics (15)

Governed, presentation-ready metrics. Each lists its default time dimension, predefined group-by dimensions, and any default filters.

### `pos_avg_basket_size`

Average revenue per transaction (basket value) — measures how much customers spend per shopping trip

- **Expression:** `pos_transactions.avg_basket_size`
- **Unit:** CAD
- **Time dimension:** `transaction_date` (grains: day, week, month, quarter, year)
- **Group by:** `store_region`, `store_province`, `store_name`, `transaction_year`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_gross_margin_pct`

Gross profit as a percentage of revenue — measures how much of each dollar of sales is retained after product costs

- **Expression:** `pos_transactions.gross_margin_pct`
- **Unit:** %
- **Time dimension:** `transaction_date` (grains: week, month, quarter, year)
- **Group by:** `store_region`, `store_province`, `store_name`, `transaction_year`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_gross_profit`

Gross profit (selling price minus cost of goods sold) from regular sales — measures profitability after product costs

- **Expression:** `pos_transactions.gross_profit`
- **Unit:** CAD
- **Time dimension:** `transaction_date` (grains: day, week, month, quarter, year)
- **Group by:** `store_region`, `store_province`, `store_name`, `transaction_year`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_loyalty_customer_revenue`

Total revenue from identified loyalty program customers — excludes anonymous transactions for loyalty-specific analysis

- **Expression:** `pos_transactions.loyalty_customer_revenue`
- **Unit:** CAD
- **Time dimension:** `transaction_date` (grains: month, quarter, year)
- **Group by:** `customer_number`, `customer_fsa`, `store_region`, `transaction_year`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_
- **Filter** `loyalty_customers_only`: `customer_number IS NOT NULL AND customer_number != '0'` _(applied by default)_

### `pos_loyalty_vs_anonymous`

Total revenue split between identified loyalty program customers and anonymous (non-loyalty) transactions — measures loyalty program penetration and value

- **Expression:** `pos_transactions.total_revenue`
- **Unit:** CAD
- **Time dimension:** `transaction_date` (grains: month, quarter, year)
- **Group by:** `is_loyalty_customer`, `store_region`, `transaction_year`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_promotion_revenue`

Total revenue grouped by promotion type — enables comparison of promoted vs non-promoted sales and analysis of promotion effectiveness by type

- **Expression:** `pos_transactions.total_revenue`
- **Unit:** CAD
- **Time dimension:** `transaction_date` (grains: month, quarter, year)
- **Group by:** `promotion_type`, `has_promotion`, `event_id`, `store_region`, `transaction_year`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_return_rate`

Percentage of transactions that are customer returns — return transactions divided by regular sales transactions

- **Expression:** `COUNT(DISTINCT CASE WHEN pos_transactions.transaction_type = 'Regular Return' THEN pos_transactions.transaction_unique_id END) * 100.0 / NULLIF(COUNT(DISTINCT CASE WHEN pos_transactions.transaction_type = 'Regular Sale' THEN pos_transactions.transaction_unique_id END), 0)`
- **Unit:** %
- **Time dimension:** `transaction_date` (grains: month, quarter, year)
- **Group by:** `store_region`, `store_province`, `store_name`, `transaction_year`

### `pos_revenue_by_product`

Total revenue grouped by product (PLU/description) — identifies top-selling products by revenue

- **Expression:** `pos_transactions.total_revenue`
- **Unit:** CAD
- **Time dimension:** `transaction_date` (grains: month, quarter, year)
- **Group by:** `plu`, `product_description`, `store_region`, `transaction_year`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_revenue_by_store`

Total revenue grouped by store location — enables geographic performance comparison across stores, provinces, and regions

- **Expression:** `pos_transactions.total_revenue`
- **Unit:** CAD
- **Time dimension:** `transaction_date` (grains: month, quarter, year)
- **Group by:** `store_name`, `store_number`, `store_province`, `store_region`, `transaction_year`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_total_discount`

Total dollar value of all discounts applied (transaction, item, and override) — measures the financial impact of discounting activity

- **Expression:** `pos_transactions.total_discount`
- **Unit:** CAD
- **Time dimension:** `transaction_date` (grains: month, quarter, year)
- **Group by:** `store_region`, `store_province`, `promotion_type`, `transaction_year`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_total_revenue`

Total revenue at actual selling price from regular sales transactions — the primary POS revenue KPI

- **Expression:** `pos_transactions.total_revenue`
- **Unit:** CAD
- **Time dimension:** `transaction_date` (grains: day, week, month, quarter, year)
- **Group by:** `store_region`, `store_province`, `store_name`, `transaction_year`, `transaction_month`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_total_transactions`

Total number of unique sales transactions (baskets/receipts) over time — measures store traffic and visit volume

- **Expression:** `pos_transactions.total_transactions`
- **Unit:** transactions
- **Time dimension:** `transaction_date` (grains: day, week, month, quarter, year)
- **Group by:** `store_region`, `store_province`, `store_name`, `transaction_year`, `transaction_month`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_transactions_by_store`

Total number of transactions grouped by store — measures foot traffic and visit volume per location

- **Expression:** `pos_transactions.total_transactions`
- **Unit:** transactions
- **Time dimension:** `transaction_date` (grains: week, month, quarter, year)
- **Group by:** `store_name`, `store_number`, `store_province`, `store_region`, `transaction_year`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_units_by_product`

Total quantity of units sold grouped by product — identifies best-selling products by volume

- **Expression:** `pos_transactions.total_quantity`
- **Unit:** units
- **Time dimension:** `transaction_date` (grains: month, quarter, year)
- **Group by:** `plu`, `product_description`, `store_region`, `transaction_year`
- **Filter** `regular_sales_only`: `transaction_type = 'Regular Sale'` _(applied by default)_

### `pos_void_rate`

Percentage of transactions that are post-void (cancelled at the register) — a high void rate may indicate cashier errors or training issues

- **Expression:** `COUNT(DISTINCT CASE WHEN pos_transactions.transaction_type = 'Post Void TX' THEN pos_transactions.transaction_unique_id END) * 100.0 / NULLIF(COUNT(DISTINCT CASE WHEN pos_transactions.transaction_type = 'Regular Sale' THEN pos_transactions.transaction_unique_id END), 0)`
- **Unit:** %
- **Time dimension:** `transaction_date` (grains: month, quarter, year)
- **Group by:** `store_region`, `store_province`, `store_name`, `transaction_year`

## Filters

The model defines **no standalone reusable filters**; filtering is expressed through:

1. **Named metric-level filters** - most sales metrics apply `regular_sales_only` (`transaction_type = 'Regular Sale'`) by default so KPIs exclude returns and voids. `pos_return_rate` and `pos_void_rate` deliberately omit it to measure all transaction types.
2. **Boolean dimension flags** for ad-hoc slicing: `is_loyalty_customer`, `has_promotion`, `is_return`.

## Glossary (15 terms tagged `pos`)

| Term | Definition | Tags |
|---|---|---|
| **Basket Size** | The average dollar value a customer spends per shopping trip, calculated as total revenue divided by the number of unique transactions. Basket size is a key retail performance indicator — a rising basket size means customers are spending more per visit, while a falling basket size may indicate smaller purchases or increased price sensitivity. During COVID-19 in 2020, basket sizes typically increased as customers made fewer but larger shopping trips. | core_concept, financial, pos |
| **COVID Demand History** | The 2020 portion of the POS dataset reflects significantly altered consumer behaviour caused by the COVID-19 pandemic in Canada. Key patterns when comparing 2019 vs 2020 — store traffic (total_transactions) declined as customers shopped less frequently; basket sizes (avg_basket_size) increased as customers made larger consolidated shopping trips; Ontario and Quebec experienced stricter lockdowns than Western provinces, creating regional asymmetry. Always flag these dynamics when presenting year-over-year comparisons. | pos, context, covid |
| **Forward Sortation Area** | The first three characters of a Canadian postal code, used to identify the general geographic area of a customer's home address. FSAs represent a geographic zone roughly equivalent to a neighbourhood or district and are used in retail analytics to understand where loyalty customers live relative to store locations. For example, 'V2A' represents part of Penticton, BC. Only available for identified loyalty customers — anonymous transactions have no FSA. | geography, customer, pos |
| **Loyalty Customer** | An identified shopper who is a member of the retail loyalty program and whose purchases can be tracked across visits using their customer_number. Loyalty customers provide richer analytics because their behaviour can be studied over time. Anonymous customers (non-loyalty) have a customer_number of 0 or null and cannot be tracked individually. Use the is_loyalty_customer dimension to segment analysis between loyalty and anonymous shoppers, or the loyalty_customers_only filter to restrict to loyalty members only. | customer, pos |
| **PLU** | Price Look-Up code — the unique numeric identifier for a product (SKU) at the point of sale. PLUs are used by cashiers and POS systems to identify products and retrieve their price. Each PLU corresponds to a specific product and is paired with a product_description for human-readable analysis. Use PLU for precise SKU-level product analysis; use product_description for readable product names. | core_concept, product, pos |
| **POS Transaction** | A point-of-sale transaction representing a single customer visit to a store resulting in a basket of purchased items. Each transaction has a unique identifier (transaction_unique_id) and may contain multiple line items — one per product purchased. Three transaction types exist: Regular Sale (normal purchase), Regular Return (customer refund), and Post Void TX (cancelled at the register). When counting transactions, always use COUNT(DISTINCT transaction_unique_id) — not COUNT(*), which counts line items. | core_concept, pos |
| **Post Void Transaction** | A transaction that was cancelled by the cashier at the register after being initially processed, recorded as transaction_type = 'Post Void TX'. Post voids are distinct from customer returns — they are cancelled before the customer leaves the store, typically due to cashier errors, pricing disputes, or system corrections. A high post-void rate at a specific store may indicate cashier training issues or potential internal fraud. Exclude post-voids using the regular_sales_only or exclude_returns_and_voids filters for clean revenue analysis. | operations, pos |
| **Pricebook** | The master pricing reference used by the POS system, containing three price points per product. pricebook_regular_price is the standard shelf price customers see displayed. pricebook_sale_price is a pre-set promotional price from the pricebook (0 if no sale price exists). pricebook_cost is the standard cost of the product. Compare pricebook_regular_price against selling_price to measure the total impact of all promotions and discounts applied at the register. | financial, product, pos |
| **Regular Return** | A transaction where a customer returns previously purchased products and receives a refund, recorded as transaction_type = 'Regular Return'. Returns reduce net revenue and should be excluded from standard sales analysis using the regular_sales_only filter. A rising return rate may indicate product quality issues, customer dissatisfaction, or promotional mis-selling. The pos_return_rate metric expresses returns as a percentage of regular sales transactions. | operations, pos |
| **Royalty Sales** | The portion of revenue that is eligible for royalty calculations, typically associated with branded or licensed products where a portion of sales revenue is owed to a franchisor, brand owner, or licensor. Tracked in the royalty_sales field. Royalty sales may differ from total selling_price where not all products are royalty-eligible. Use total_royalty_sales to aggregate this across transactions. | financial, pos |
| **Selling Price** | The actual price paid by the customer for a product after all promotions, discounts, and markdowns have been applied. Selling price is the primary basis for revenue calculations in the POS dataset. It differs from the original_selling_price (pre-discount price), pricebook_regular_price (standard shelf price), and pricebook_sale_price (pricebook promotional price). Use selling_price for all revenue and margin analysis. | financial, pos |
| **Store Region** | The four broad geographic sales regions used in the POS dataset to group Canadian stores — Ontario (ON), Western (BC, AB, SK, MB, NT, YT), Quebec (QC), and Atlantic (NB, NS, NL, PE). Ontario is the largest region by revenue and transaction volume. Use store_region for high-level geographic analysis, store_province for provincial detail, and store_name or store_number for individual store analysis. | geography, pos |
| **Subsidy** | Funding received from suppliers or marketing programs to offset the cost of promotional price reductions. Three subsidy fields exist: expected_subsidy (the anticipated supplier contribution per item), marketing_subsidy (the marketing-funded portion), and subsidy (the total combined subsidy received). Subsidies reduce the net cost of running promotions for the retailer. High subsidy values on a product indicate strong supplier co-investment in promotional activity. | promotions, financial, pos |
| **Temporary Price Reduction** | A short-term promotional price reduction applied to a product for a defined period, represented by promotion_type = 'T' in the POS data. TPRs are the most common promotion type and are funded either by the retailer, the supplier (via marketing_subsidy), or shared between both. Items sold under a TPR are sold below pricebook_regular_price. Compare TPR revenue against non-promoted revenue to measure promotion lift and effectiveness. | promotions, pos |
| **Transaction Line Item** | A single product (SKU) scanned within a transaction. The pos_transactions model is at line item grain — each row is one product within one transaction. A single customer visit (transaction) typically produces multiple line items, one per product purchased. Use total_line_items to count line items and total_transactions to count unique visits. | core_concept, pos |

> Selected by the analyst glossary's `pos` tag. The shared glossary also holds related retail KPIs (Gross Profit, Average Transaction Value, Units Sold, etc.) tagged `retail`/`core_kpi` but not `pos` - omitted here to keep this export scoped to the POS model.
