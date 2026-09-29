-- ============================================================
-- Enterprise Analytics Quality Checks
-- ============================================================


\echo ''
\echo '============================================================'
\echo '1. ENTERPRISE FACT ROW COUNTS'
\echo '============================================================'

SELECT
    'fact_inventory_monthly' AS fact_table,
    COUNT(*) AS row_count
FROM analytics.fact_inventory_monthly

UNION ALL

SELECT
    'fact_store_plan',
    COUNT(*)
FROM analytics.fact_store_plan

UNION ALL

SELECT
    'fact_marketing_spend',
    COUNT(*)
FROM analytics.fact_marketing_spend

ORDER BY fact_table;


\echo ''
\echo '============================================================'
\echo '2. MISSING DIMENSION KEYS'
\echo '============================================================'

SELECT
    'inventory_date_key' AS check_name,
    COUNT(*) AS issue_count
FROM analytics.fact_inventory_monthly
WHERE snapshot_date_key IS NULL

UNION ALL

SELECT
    'inventory_store_key',
    COUNT(*)
FROM analytics.fact_inventory_monthly
WHERE store_key IS NULL

UNION ALL

SELECT
    'inventory_product_key',
    COUNT(*)
FROM analytics.fact_inventory_monthly
WHERE product_key IS NULL

UNION ALL

SELECT
    'inventory_supplier_key',
    COUNT(*)
FROM analytics.fact_inventory_monthly
WHERE supplier_key IS NULL

UNION ALL

SELECT
    'store_plan_date_key',
    COUNT(*)
FROM analytics.fact_store_plan
WHERE plan_date_key IS NULL

UNION ALL

SELECT
    'store_plan_store_key',
    COUNT(*)
FROM analytics.fact_store_plan
WHERE store_key IS NULL

UNION ALL

SELECT
    'marketing_date_key',
    COUNT(*)
FROM analytics.fact_marketing_spend
WHERE spend_date_key IS NULL

UNION ALL

SELECT
    'marketing_store_key',
    COUNT(*)
FROM analytics.fact_marketing_spend
WHERE store_key IS NULL

UNION ALL

SELECT
    'marketing_channel_key',
    COUNT(*)
FROM analytics.fact_marketing_spend
WHERE marketing_channel_key IS NULL;


\echo ''
\echo '============================================================'
\echo '3. INVENTORY ACCOUNTING CHECK'
\echo '============================================================'

SELECT
    COUNT(*) AS inventory_rows,

    COUNT(*) FILTER (
        WHERE
            opening_stock_qty
            + received_qty
            - sold_qty
            <> closing_stock_qty
    ) AS balance_errors,

    COUNT(*) FILTER (
        WHERE closing_stock_qty < 0
    ) AS negative_closing_stock,

    COUNT(*) FILTER (
        WHERE had_stockout
    ) AS stockout_rows,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE had_stockout
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS stockout_row_rate_pct

FROM analytics.fact_inventory_monthly;


\echo ''
\echo '============================================================'
\echo '4. INVENTORY SOURCE RECONCILIATION'
\echo '============================================================'

SELECT
    (
        SELECT SUM(opening_stock_qty)
        FROM staging.inventory_snapshot
    ) AS staging_opening_stock,

    (
        SELECT SUM(opening_stock_qty)
        FROM analytics.fact_inventory_monthly
    ) AS fact_opening_stock,

    (
        SELECT SUM(received_qty)
        FROM staging.inventory_snapshot
    ) AS staging_received,

    (
        SELECT SUM(received_qty)
        FROM analytics.fact_inventory_monthly
    ) AS fact_received,

    (
        SELECT SUM(sold_qty)
        FROM staging.inventory_snapshot
    ) AS staging_sold,

    (
        SELECT SUM(sold_qty)
        FROM analytics.fact_inventory_monthly
    ) AS fact_sold,

    (
        SELECT SUM(closing_stock_qty)
        FROM staging.inventory_snapshot
    ) AS staging_closing_stock,

    (
        SELECT SUM(closing_stock_qty)
        FROM analytics.fact_inventory_monthly
    ) AS fact_closing_stock;


\echo ''
\echo '============================================================'
\echo '5. STORE PLAN SOURCE RECONCILIATION'
\echo '============================================================'

SELECT
    ROUND(
        (
            SELECT SUM(sales_budget)
            FROM staging.monthly_store_budget
        ),
        2
    ) AS staging_sales_budget,

    ROUND(
        (
            SELECT SUM(sales_budget)
            FROM analytics.fact_store_plan
        ),
        2
    ) AS fact_sales_budget,

    ROUND(
        (
            SELECT SUM(sales_target)
            FROM staging.sales_targets
        ),
        2
    ) AS staging_sales_target,

    ROUND(
        (
            SELECT SUM(sales_target)
            FROM analytics.fact_store_plan
        ),
        2
    ) AS fact_sales_target;


\echo ''
\echo '============================================================'
\echo '6. MARKETING SOURCE RECONCILIATION'
\echo '============================================================'

SELECT
    ROUND(
        (
            SELECT SUM(spend)
            FROM staging.marketing_spend
        ),
        2
    ) AS staging_marketing_spend,

    ROUND(
        (
            SELECT SUM(spend)
            FROM analytics.fact_marketing_spend
        ),
        2
    ) AS fact_marketing_spend;


\echo ''
\echo '============================================================'
\echo '7. PROFITABILITY COVERAGE'
\echo '============================================================'

SELECT
    COUNT(*) AS item_rows,

    COUNT(*) FILTER (
        WHERE estimated_unit_cost IS NULL
    ) AS missing_cost,

    COUNT(*) FILTER (
        WHERE estimated_cogs IS NULL
    ) AS missing_cogs,

    COUNT(*) FILTER (
        WHERE estimated_gross_margin IS NULL
    ) AS missing_margin,

    COUNT(*) FILTER (
        WHERE estimated_gross_margin_pct IS NULL
    ) AS missing_margin_pct,

    ROUND(
        SUM(estimated_cogs),
        2
    ) AS estimated_cogs,

    ROUND(
        SUM(estimated_gross_margin),
        2
    ) AS estimated_gross_margin

FROM analytics.fact_order_items;
