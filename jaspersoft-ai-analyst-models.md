# Jaspersoft AI Analyst (agent_3o3fkndte) — Semantic Layer Models

Explore Jaspersoft BI platform usage — report and dashboard inventory, ownership, and activity — alongside Actian Foodmart retail analytics for sales, margin, and store performance.

_Exported: 2026-06-16T21:51:59.282Z_

**Totals:** 34 models, 43 metrics, glossary mode = `ALL`

---

## `jaspersoft_access_events`

- **Dimensions (12):** `user_id`, `resource_uri`, `hidden`, `resource_type`, `event_id`, `event_date`, `updating`, `resource_name`, `resource_type_label`, `resource_folder`, `event_hour`, `event_day_of_week`
- **Measures (5):** `total_events`, `total_users`, `total_content_events`, `total_read_events`, `total_write_events`
- **Filters (2):** `read_events_only`, `write_events_only`

## `jaspersoft_adhoc_views`

- **Dimensions (7):** `view_id`, `name`, `label`, `description`, `creation_date`, `update_date`, `days_since_update`
- **Measures (1):** `total_views`

## `jaspersoft_adhoc_views_enriched`

- **Dimensions (9):** `view_id`, `name`, `label`, `description`, `creation_date`, `update_date`, `datasource_name`, `datasource_label`, `datasource_type`
- **Measures (3):** `total_views`, `total_direct_datasource_views`, `total_domain_backed_views`

## `jaspersoft_dashboard_content`

- **Dimensions (5):** `dashboard_name`, `dashboard_label`, `content_name`, `content_label`, `content_type_label`
- **Measures (4):** `total_content_items`, `total_dashboards`, `total_adhoc_views`, `total_input_controls`

## `jaspersoft_dashboard_resources`

- **Dimensions (3):** `dashboard_id`, `resource_id`, `resource_index`
- **Measures (3):** `total_resource_references`, `total_dashboards`, `total_resources`

## `jaspersoft_dashboards`

- **Dimensions (7):** `update_date`, `dashboard_id`, `name`, `label`, `description`, `creation_date`, `days_since_update`
- **Measures (1):** `total_dashboards`

## `jaspersoft_datasources`

- **Dimensions (10):** `datasource_id`, `name`, `label`, `description`, `connection_type`, `driver_or_jndi`, `connection_url`, `db_username`, `creation_date`, `update_date`
- **Measures (1):** `total_datasources`

## `jaspersoft_domains`

- **Dimensions (10):** `domain_id`, `domain_name`, `domain_label`, `description`, `creation_date`, `update_date`, `datasource_alias`, `backing_datasource_name`, `backing_datasource_label`, `backing_datasource_type`
- **Measures (1):** `total_domains`

## `jaspersoft_folders`

- **Dimensions (9):** `folder_name`, `folder_label`, `description`, `hidden`, `parent_folder_id`, `folder_id`, `uri`, `creation_date`, `update_date`
- **Measures (3):** `total_folders`, `total_visible_folders`, `total_hidden_folders`
- **Filters (1):** `visible_only`

## `jaspersoft_report_controls`

- **Dimensions (11):** `report_unit_id`, `report_label`, `control_name`, `control_description`, `dimension_field`, `mandatory`, `visible`, `control_type_label`, `report_name`, `input_control_id`, `control_label`
- **Measures (4):** `total_controls`, `total_reports_with_controls`, `total_visible_controls`, `total_mandatory_controls`

## `jaspersoft_reports`

- **Dimensions (7):** `description`, `report_id`, `name`, `label`, `creation_date`, `update_date`, `days_since_update`
- **Measures (1):** `total_reports`

## `jaspersoft_resources`

- **Dimensions (9):** `resource_id`, `name`, `label`, `description`, `resource_type`, `creation_date`, `update_date`, `parent_folder_id`, `resource_type_label`
- **Measures (2):** `total_resources`, `total_content_resources`

## `jaspersoft_roles`

- **Dimensions (5):** `role_id`, `rolename`, `user_id`, `username`, `fullname`
- **Measures (3):** `total_role_assignments`, `total_roles`, `total_users_with_roles`

## `jaspersoft_users`

- **Dimensions (8):** `user_id`, `username`, `fullname`, `email_address`, `enabled`, `externally_defined`, `previous_password_change_time`, `tenant_id`
- **Measures (2):** `total_users`, `total_disabled_users`
- **Filters (1):** `enabled_accounts`

## `account`

- **Dimensions (6):** `account_id`, `account_rollup`, `custom_members`, `account_parent`, `account_description`, `account_type`
- **Measures (1):** `total_accounts`

## `category`

- **Dimensions (4):** `category_parent`, `category_id`, `category_description`, `category_rollup`
- **Measures (1):** `total_categories`

## `currency`

- **Dimensions (3):** `currency_id`, `currency`, `date`
- **Measures (1):** `avg_conversion_ratio`

## `customer`

- **Dimensions (31):** `customer_id`, `total_children`, `num_cars_owned`, `account_num`, `fname`, `state_province`, `country`, `customer_region_id`, `occupation`, `lname`, `fullname`, `city`, `postal_code`, `gender`, `member_card`, `houseowner`, `num_children_at_home`, `address3`, `address4`, `birthdate`, `mi`, `address1`, `address2`, `phone2`, `date_accnt_opened`, `phone1`, `education`, `marital_status`, `yearly_income`, `rfm_segment`, `age_years`
- **Measures (2):** `total_customers`, `avg_total_children`

## `department`

- **Dimensions (2):** `department_id`, `department_description`
- **Measures (1):** `total_departments`

## `employee`

- **Dimensions (18):** `employee_id`, `first_name`, `position_id`, `store_id`, `supervisor_id`, `marital_status`, `management_role`, `full_name`, `last_name`, `position_title`, `department_id`, `gender`, `education_level`, `birth_date`, `hire_date`, `end_date`, `is_active`, `tenure_years`
- **Measures (4):** `total_employees`, `avg_salary`, `avg_tenure_years`, `active_employee_count`
- **Filters (1):** `active_employees`

## `expense_fact`

- **Dimensions (6):** `store_id`, `account_id`, `category_id`, `exp_date`, `time_id`, `currency_id`
- **Measures (4):** `total_amount`, `expense_count`, `actual_expenses`, `budget_expenses`
- **Filters (2):** `actual_only`, `budget_only`

## `inventory_fact`

- **Dimensions (7):** `product_id`, `time_id`, `store_id`, `warehouse_id`, `supply_time`, `units_ordered`, `units_shipped`
- **Measures (7):** `total_units_ordered`, `total_units_shipped`, `total_warehouse_sales`, `total_warehouse_cost`, `total_store_invoice`, `fulfillment_rate`, `avg_supply_time`

## `position`

- **Dimensions (6):** `position_id`, `pay_type`, `position_title`, `management_role`, `min_scale`, `max_scale`
- **Measures (1):** `total_positions`

## `product`

- **Dimensions (12):** `product_id`, `product_name`, `srp`, `gross_weight`, `recyclable_package`, `units_per_case`, `product_class_id`, `brand_name`, `net_weight`, `low_fat`, `cases_per_pallet`, `sku`
- **Measures (2):** `total_products`, `avg_srp`

## `product_class`

- **Dimensions (5):** `product_class_id`, `product_subcategory`, `product_department`, `product_category`, `product_family`
- **Measures (1):** `total_product_classes`

## `promotion`

- **Dimensions (8):** `promotion_id`, `promotion_district_id`, `promotion_name`, `end_date`, `start_date`, `media_type`, `promotion_cost`, `promotion_duration_days`
- **Measures (2):** `total_promotions`, `total_promotion_cost`

## `region`

- **Dimensions (7):** `sales_region`, `sales_city`, `sales_district`, `region_id`, `sales_state_province`, `sales_district_id`, `sales_country`
- **Measures (1):** `total_regions`

## `salary`

- **Dimensions (4):** `department_id`, `employee_id`, `currency_id`, `pay_date`
- **Measures (7):** `total_salary_paid`, `total_overtime_paid`, `avg_salary_paid`, `total_vacation_accrued`, `total_vacation_used`, `overtime_ratio`, `vacation_utilization_pct`

## `sales_fact`

- **Dimensions (5):** `product_id`, `customer_id`, `time_id`, `promotion_id`, `store_id`
- **Measures (6):** `total_store_sales`, `total_store_cost`, `total_unit_sales`, `transaction_count`, `gross_profit`, `gross_margin_pct`

## `sales_fact_new`

- **Dimensions (5):** `product_id`, `customer_id`, `time_id`, `promotion_id`, `store_id`
- **Measures (4):** `total_store_sales`, `total_store_cost`, `total_unit_sales`, `transaction_count`

## `store`

- **Dimensions (24):** `store_sqft`, `grocery_sqft`, `meat_sqft`, `video_store`, `store_id`, `region_id`, `store_number`, `store_street_address`, `store_name`, `store_state`, `store_postal_code`, `coffee_bar`, `salad_bar`, `florist`, `store_type`, `store_city`, `store_country`, `store_manager`, `frozen_sqft`, `prepared_food`, `store_fax`, `first_opened_date`, `store_phone`, `last_remodel_date`
- **Measures (3):** `avg_store_sqft`, `total_stores`, `avg_sqft`
- **Filters (1):** `exclude_headquarters`

## `time_by_day`

- **Dimensions (10):** `month_of_year`, `time_id`, `the_day`, `the_year`, `week_of_year`, `quarter`, `the_month`, `day_of_month`, `the_date`, `day_of_week`
- **Measures (1):** `total_days`

## `warehouse`

- **Dimensions (15):** `warehouse_id`, `warehouse_name`, `warehouse_state_province`, `warehouse_country`, `warehouse_class_id`, `warehouse_city`, `warehouse_postal_code`, `warehouse_owner_name`, `wa_address1`, `warehouse_fax`, `wa_address4`, `wa_address2`, `wa_address3`, `warehouse_phone`, `stores_id`
- **Measures (1):** `total_warehouses`

## `warehouse_class`

- **Dimensions (2):** `warehouse_class_id`, `description`
- **Measures (1):** `total_warehouse_classes`

---

## Metrics (43)

- `retail_total_store_sales`
- `retail_avg_supply_time`
- `retail_gross_profit`
- `retail_gross_margin_pct`
- `retail_avg_transaction_value`
- `retail_total_unit_sales`
- `retail_promotional_sales`
- `retail_non_promotional_sales`
- `retail_total_store_expenses`
- `domain_usage`
- `jaspersoft_total_folders`
- `jaspersoft_total_domains`
- `jaspersoft_content_views`
- `jaspersoft_active_users`
- `jaspersoft_content_updates`
- `jaspersoft_total_reports`
- `jaspersoft_total_dashboards`
- `jaspersoft_total_adhoc_views`
- `jaspersoft_total_users`
- `jaspersoft_total_datasources`
- `jaspersoft_total_roles`
- `jaspersoft_total_report_controls`
- `jaspersoft_most_viewed_content`
- `jaspersoft_peak_usage_hours`
- `retail_customer_lifetime_value`
- `revenue_per_sqft`
- `promotion_roi`
- `avg_views_per_report`
- `unique_viewers_per_content`
- `user_last_active`
- `stale_content`
- `content_by_owner`
- `never_accessed`
- `reports_per_folder`
- `retail_actual_vs_budget_expenses`
- `hr_active_headcount`
- `hr_salary_by_department`
- `hr_overtime_ratio`
- `hr_vacation_utilization`
- `hr_avg_tenure`
- `hr_turnover_rate`
- `perfect_order_rate`
- `retail_fulfillment_rate`
