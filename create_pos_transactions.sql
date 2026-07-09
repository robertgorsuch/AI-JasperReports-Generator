-- create_pos_transactions.sql
-- Clean, correctly-labeled and typed rebuild of pos_transactions.
--
-- BACKGROUND: the live table `sales.pos_transactions` (~66M rows) was loaded
-- positionally from poc_sales_detail_extract_*.csv into a GENERIC snake_case
-- template whose names do NOT describe the data, and every column is VARCHAR(1024).
-- The data column ORDER is correct (it matches the CSV header order); only the
-- labels and types are wrong. The true names come from the CSV header:
--
--   Date, Time, StoreNumber, StoreName, StoreProvince, StoreRegion, CustomerNumber,
--   CustomerFSA, CustomerEmailFlag, TransactionUniqueID, TranbsactionType(*typo),
--   TransactionNumber, TransactionSequence, PLU, ProductDescription,
--   PriceBookRegularPrice, PriceBookSalePrice, PriceBookCost, OriginalSellingPrice,
--   SellingPrice, Cost, Quantity, RoyaltySales, ExpectedSubsidy, MarketingSubsidy,
--   Subsidy, TransactionDiscount, ItemDiscount, OverrideDiscount, PromotionType,
--   Event_ID, Extended_Event_ID
--
-- (*) The source header itself misspells "TransactionType" as "TranbsactionType";
--     we correct it to transaction_type here.
--
-- This script MIGRATES FROM THE EXISTING DATA (no GCS re-load): it reads the
-- already-loaded strings out of sales.pos_transactions BY POSITION and casts them
-- into the correctly-named, correctly-typed columns. The SELECT references the
-- CURRENT (wrong) column names; the INSERT lands them under the TRUE names.

-- ── 1. Clean target table ───────────────────────────────────────────────────────
DROP TABLE IF EXISTS pos_transactions_clean;

CREATE TABLE pos_transactions_clean (
    transaction_date        ANSIDATE,
    transaction_time        TIME WITHOUT TIME ZONE,
    store_number            INTEGER,
    store_name              VARCHAR(100),
    store_province          VARCHAR(8),
    store_region            VARCHAR(32),
    customer_number         BIGINT,
    customer_fsa            VARCHAR(8),
    customer_email_flag     BOOLEAN,
    transaction_unique_id   BIGINT,
    transaction_type        VARCHAR(50),     -- source header typo: "TranbsactionType"
    transaction_number      BIGINT,
    transaction_sequence    INTEGER,
    plu                     INTEGER,
    product_description     VARCHAR(200),
    pricebook_regular_price DECIMAL(18,4),
    pricebook_sale_price    DECIMAL(18,4),
    pricebook_cost          DECIMAL(18,4),
    original_selling_price  DECIMAL(18,4),
    selling_price           DECIMAL(18,4),
    cost                    DECIMAL(18,4),
    quantity                DECIMAL(18,4),
    royalty_sales           DECIMAL(18,4),
    expected_subsidy        DECIMAL(18,4),
    marketing_subsidy       DECIMAL(18,4),
    subsidy                 DECIMAL(18,4),
    transaction_discount    DECIMAL(18,4),
    item_discount           DECIMAL(18,4),
    override_discount       DECIMAL(18,4),
    promotion_type          VARCHAR(32),
    event_id                VARCHAR(32),
    extended_event_id       VARCHAR(64)
);

-- ── 2. Migrate + cast from the existing (mislabeled) data, BY POSITION ───────────
-- LEFT side = current wrong column name in sales.pos_transactions
-- (commented) = true column it actually holds
INSERT INTO pos_transactions_clean (
    transaction_date, transaction_time, store_number, store_name, store_province,
    store_region, customer_number, customer_fsa, customer_email_flag,
    transaction_unique_id, transaction_type, transaction_number, transaction_sequence,
    plu, product_description, pricebook_regular_price, pricebook_sale_price,
    pricebook_cost, original_selling_price, selling_price, cost, quantity,
    royalty_sales, expected_subsidy, marketing_subsidy, subsidy, transaction_discount,
    item_discount, override_discount, promotion_type, event_id, extended_event_id
)
SELECT
    DATE(transaction_date)                              AS transaction_date,    -- col1  Date
    TIME(transaction_time)                              AS transaction_time,    -- col2  Time
    INT4(NULLIF(TRIM(store_id),''))                     AS store_number,        -- col3  StoreNumber
    TRIM(store_location)                                AS store_name,          -- col4  StoreName
    TRIM(province_state)                                AS store_province,      -- col5  StoreProvince
    TRIM(postal_code)                                   AS store_region,        -- col6  StoreRegion
    INT8(NULLIF(TRIM(device_id),''))                    AS customer_number,     -- col7  CustomerNumber
    TRIM(cashier_id)                                    AS customer_fsa,        -- col8  CustomerFSA
    CASE WHEN TRIM(transaction_id)='1' THEN TRUE
         WHEN TRIM(transaction_id)='0' THEN FALSE ELSE NULL END
                                                        AS customer_email_flag, -- col9  CustomerEmailFlag
    INT8(NULLIF(TRIM(transaction_type),''))             AS transaction_unique_id,-- col10 TransactionUniqueID
    TRIM(line_item_num)                                 AS transaction_type,    -- col11 TranbsactionType -> transaction_type
    INT8(NULLIF(TRIM(sku),''))                          AS transaction_number,  -- col12 TransactionNumber
    INT4(NULLIF(TRIM(item_description),''))             AS transaction_sequence,-- col13 TransactionSequence
    INT4(NULLIF(TRIM(qty),''))                          AS plu,                 -- col14 PLU
    TRIM(unit_price)                                    AS product_description, -- col15 ProductDescription
    DECIMAL(NULLIF(TRIM(discount_amount),''),18,4)      AS pricebook_regular_price, -- col16
    DECIMAL(NULLIF(TRIM(tax_amount),''),18,4)           AS pricebook_sale_price,-- col17 PriceBookSalePrice
    DECIMAL(NULLIF(TRIM(line_total),''),18,4)           AS pricebook_cost,      -- col18 PriceBookCost
    DECIMAL(NULLIF(TRIM(payment_method),''),18,4)       AS original_selling_price,-- col19
    DECIMAL(NULLIF(TRIM(payment_amount),''),18,4)       AS selling_price,       -- col20 SellingPrice
    DECIMAL(NULLIF(TRIM(customer_id),''),18,4)          AS cost,                -- col21 Cost
    DECIMAL(NULLIF(TRIM(customer_name),''),18,4)        AS quantity,            -- col22 Quantity
    DECIMAL(NULLIF(TRIM(customer_phone),''),18,4)       AS royalty_sales,       -- col23 RoyaltySales
    DECIMAL(NULLIF(TRIM(customer_email),''),18,4)       AS expected_subsidy,    -- col24 ExpectedSubsidy
    DECIMAL(NULLIF(TRIM(loyalty_member),''),18,4)       AS marketing_subsidy,   -- col25 MarketingSubsidy
    DECIMAL(NULLIF(TRIM(loyalty_points),''),18,4)       AS subsidy,             -- col26 Subsidy
    DECIMAL(NULLIF(TRIM(receipt_number),''),18,4)       AS transaction_discount,-- col27 TransactionDiscount
    DECIMAL(NULLIF(TRIM(batch_id),''),18,4)             AS item_discount,       -- col28 ItemDiscount
    DECIMAL(NULLIF(TRIM(terminal_id),''),18,4)          AS override_discount,   -- col29 OverrideDiscount
    TRIM(shift_id)                                      AS promotion_type,      -- col30 PromotionType
    TRIM(void_flag)                                     AS event_id,            -- col31 Event_ID
    TRIM(notes)                                         AS extended_event_id    -- col32 Extended_Event_ID
FROM sales.pos_transactions;

-- ── 3. Verify, then swap (run after row count + spot-check look right) ───────────
-- SELECT COUNT(*) FROM pos_transactions_clean;          -- expect ~65,982,073
-- SELECT FIRST 10 * FROM pos_transactions_clean;
--   To replace the original (requires rights on the sales schema):
--   DROP TABLE sales.pos_transactions;
--   -- recreate sales.pos_transactions with the clean DDL above, then
--   INSERT INTO sales.pos_transactions SELECT * FROM pos_transactions_clean;
--
-- NOTE (date/time parsing): values look like '11-Jan-2019 00:00:00' / '13:36:10'.
-- DATE()/TIME() should parse these, but VALIDATE on a small sample first:
--   SELECT FIRST 5 DATE(transaction_date), TIME(transaction_time) FROM sales.pos_transactions;
-- If any row fails to cast, load that column as VARCHAR and refine the cast.
