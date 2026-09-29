-- ============================================================
-- Enterprise Business KPI Baseline
--
-- SQL control totals for profitability, stores, planning,
-- inventory, suppliers and marketing.
-- ============================================================


\echo ''
\echo '============================================================'
\echo '1. DELIVERED PROFITABILITY'
\echo '============================================================'

SELECT
    COUNT(DISTINCT f.order_id)
        AS delivered_orders,

    ROUND(
        SUM(f.price),
        2
    ) AS merchandise_value,

    ROUND(
        SUM(f.estimated_cogs),
        2
    ) AS estimated_cogs,

    ROUND(
        SUM(f.estimated_gross_margin),
        2
    ) AS estimated_gross_margin,

    ROUND(
        100.0
        * SUM(f.estimated_gross_margin)
        / NULLIF(SUM(f.price), 0),
        2
    ) AS estimated_gross_margin_pct

FROM analytics.fact_order_items f

INNER JOIN analytics.dim_order_status s
    ON f.order_status_key =
       s.order_status_key

WHERE s.order_status = 'delivered';


\echo ''
\echo '============================================================'
\echo '2. STORE PERFORMANCE'
\echo '============================================================'

WITH order_actuals AS (

    SELECT
        f.store_key,

        COUNT(*) AS delivered_orders,

        SUM(f.gross_order_value)
            AS gross_order_value

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'

    GROUP BY f.store_key
),

margin_actuals AS (

    SELECT
        f.store_key,

        SUM(f.price)
            AS merchandise_value,

        SUM(f.estimated_cogs)
            AS estimated_cogs,

        SUM(f.estimated_gross_margin)
            AS estimated_gross_margin

    FROM analytics.fact_order_items f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'

    GROUP BY f.store_key
)

SELECT
    d.store_id,
    d.store_name,
    d.state,
    d.store_format,

    o.delivered_orders,

    ROUND(
        o.gross_order_value,
        2
    ) AS gross_order_value,

    ROUND(
        m.merchandise_value,
        2
    ) AS merchandise_value,

    ROUND(
        m.estimated_gross_margin,
        2
    ) AS estimated_gross_margin,

    ROUND(
        100.0
        * m.estimated_gross_margin
        / NULLIF(m.merchandise_value, 0),
        2
    ) AS estimated_margin_pct

FROM analytics.dim_store d

INNER JOIN order_actuals o
    ON d.store_key = o.store_key

INNER JOIN margin_actuals m
    ON d.store_key = m.store_key

ORDER BY gross_order_value DESC;


\echo ''
\echo '============================================================'
\echo '3. ACTUAL VS BUDGET / TARGET'
\echo '============================================================'

WITH monthly_actual AS (

    SELECT
        DATE_TRUNC(
            'month',
            f.order_purchase_timestamp
        )::date AS month,

        f.store_key,

        COUNT(*) AS actual_orders,

        SUM(f.gross_order_value)
            AS actual_sales

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'

    GROUP BY
        DATE_TRUNC(
            'month',
            f.order_purchase_timestamp
        )::date,
        f.store_key
),

comparison AS (

    SELECT
        p.plan_date_key,
        p.store_key,

        COALESCE(
            a.actual_sales,
            0
        ) AS actual_sales,

        COALESCE(
            a.actual_orders,
            0
        ) AS actual_orders,

        p.sales_budget,
        p.sales_target,
        p.order_target

    FROM analytics.fact_store_plan p

    LEFT JOIN analytics.dim_date d
        ON p.plan_date_key = d.date_key

    LEFT JOIN monthly_actual a
        ON d.full_date = a.month
       AND p.store_key = a.store_key
)

SELECT
    ROUND(
        SUM(actual_sales),
        2
    ) AS actual_sales,

    ROUND(
        SUM(sales_budget),
        2
    ) AS sales_budget,

    ROUND(
        SUM(sales_target),
        2
    ) AS sales_target,

    ROUND(
        100.0
        * SUM(actual_sales)
        / NULLIF(
            SUM(sales_budget),
            0
        ),
        2
    ) AS budget_attainment_pct,

    ROUND(
        100.0
        * SUM(actual_sales)
        / NULLIF(
            SUM(sales_target),
            0
        ),
        2
    ) AS target_attainment_pct,

    COUNT(*) FILTER (
        WHERE actual_sales
              >= sales_budget
    ) AS store_months_at_or_above_budget,

    COUNT(*) FILTER (
        WHERE actual_sales
              >= sales_target
    ) AS store_months_at_or_above_target,

    COUNT(*) AS planned_store_months

FROM comparison;


\echo ''
\echo '============================================================'
\echo '4. INVENTORY KPIS'
\echo '============================================================'

WITH latest_inventory_date AS (

    SELECT
        MAX(snapshot_date_key)
            AS snapshot_date_key

    FROM analytics.fact_inventory_monthly
),

period_metrics AS (

    SELECT
        COUNT(*) AS inventory_snapshot_rows,

        COUNT(DISTINCT product_key)
            AS inventory_products,

        COUNT(DISTINCT store_key)
            AS inventory_stores,

        SUM(sold_qty)
            AS units_sold,

        SUM(received_qty)
            AS units_received,

        SUM(stockout_days)
            AS total_stockout_days,

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
        ) AS stockout_row_rate_pct,

        COUNT(*) FILTER (
            WHERE is_below_reorder_point
        ) AS below_reorder_rows,

        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE is_below_reorder_point
            )
            / NULLIF(COUNT(*), 0),
            2
        ) AS below_reorder_rate_pct

    FROM analytics.fact_inventory_monthly
),

current_inventory AS (

    SELECT
        d.full_date
            AS current_inventory_date,

        COUNT(*)
            AS current_store_product_rows,

        SUM(f.closing_stock_qty)
            AS current_units_on_hand,

        ROUND(
            SUM(
                f.estimated_closing_inventory_value
            ),
            2
        ) AS current_inventory_value,

        COUNT(*) FILTER (
            WHERE f.is_below_reorder_point
        ) AS current_below_reorder_rows,

        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE f.is_below_reorder_point
            )
            / NULLIF(COUNT(*), 0),
            2
        ) AS current_below_reorder_rate_pct

    FROM analytics.fact_inventory_monthly f

    INNER JOIN latest_inventory_date l
        ON f.snapshot_date_key =
           l.snapshot_date_key

    INNER JOIN analytics.dim_date d
        ON f.snapshot_date_key =
           d.date_key

    GROUP BY d.full_date
)

SELECT
    p.inventory_snapshot_rows,
    p.inventory_products,
    p.inventory_stores,
    p.units_sold,
    p.units_received,
    p.total_stockout_days,
    p.stockout_rows,
    p.stockout_row_rate_pct,
    p.below_reorder_rows,
    p.below_reorder_rate_pct,

    c.current_inventory_date,
    c.current_store_product_rows,
    c.current_units_on_hand,
    c.current_inventory_value,
    c.current_below_reorder_rows,
    c.current_below_reorder_rate_pct

FROM period_metrics p
CROSS JOIN current_inventory c;


\echo ''
\echo '============================================================'
\echo '5. SUPPLIER COMMERCIAL PERFORMANCE'
\echo '============================================================'

SELECT
    d.supplier_id,
    d.supplier_name,
    d.supplier_state,
    d.supplier_rating,
    d.standard_lead_time_days,
    d.contractual_fill_rate_pct,

    COUNT(*) AS delivered_item_rows,

    COUNT(DISTINCT f.order_id)
        AS delivered_orders,

    ROUND(
        SUM(f.price),
        2
    ) AS merchandise_value,

    ROUND(
        SUM(f.estimated_cogs),
        2
    ) AS estimated_cogs,

    ROUND(
        SUM(f.estimated_gross_margin),
        2
    ) AS estimated_gross_margin,

    ROUND(
        100.0
        * SUM(f.estimated_gross_margin)
        / NULLIF(SUM(f.price), 0),
        2
    ) AS estimated_margin_pct

FROM analytics.fact_order_items f

INNER JOIN analytics.dim_supplier d
    ON f.supplier_key = d.supplier_key

INNER JOIN analytics.dim_order_status s
    ON f.order_status_key =
       s.order_status_key

WHERE s.order_status = 'delivered'

GROUP BY
    d.supplier_id,
    d.supplier_name,
    d.supplier_state,
    d.supplier_rating,
    d.standard_lead_time_days,
    d.contractual_fill_rate_pct

ORDER BY merchandise_value DESC

LIMIT 15;


\echo ''
\echo '============================================================'
\echo '6. MARKETING SPEND'
\echo '============================================================'

SELECT
    c.channel,

    ROUND(
        SUM(f.spend),
        2
    ) AS marketing_spend,

    ROUND(
        100.0
        * SUM(f.spend)
        / SUM(SUM(f.spend)) OVER (),
        2
    ) AS marketing_spend_share_pct

FROM analytics.fact_marketing_spend f

INNER JOIN analytics.dim_marketing_channel c
    ON f.marketing_channel_key =
       c.marketing_channel_key

GROUP BY c.channel

ORDER BY marketing_spend DESC;


\echo ''
\echo '============================================================'
\echo '7. MARKETING SPEND VS DELIVERED SALES'
\echo '============================================================'

WITH monthly_sales AS (

    SELECT
        DATE_TRUNC(
            'month',
            f.order_purchase_timestamp
        )::date AS month,

        f.store_key,

        SUM(f.gross_order_value)
            AS delivered_sales

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'

    GROUP BY
        DATE_TRUNC(
            'month',
            f.order_purchase_timestamp
        )::date,
        f.store_key
),

monthly_marketing AS (

    SELECT
        d.full_date AS month,
        f.store_key,

        SUM(f.spend)
            AS marketing_spend

    FROM analytics.fact_marketing_spend f

    INNER JOIN analytics.dim_date d
        ON f.spend_date_key =
           d.date_key

    GROUP BY
        d.full_date,
        f.store_key
),

coverage AS (

    SELECT
        COALESCE(
            s.month,
            m.month
        ) AS month,

        COALESCE(
            s.store_key,
            m.store_key
        ) AS store_key,

        COALESCE(
            s.delivered_sales,
            0
        ) AS delivered_sales,

        COALESCE(
            m.marketing_spend,
            0
        ) AS marketing_spend

    FROM monthly_sales s

    FULL OUTER JOIN monthly_marketing m
        ON s.month = m.month
       AND s.store_key = m.store_key
)

SELECT
    ROUND(
        SUM(delivered_sales),
        2
    ) AS total_delivered_sales,

    ROUND(
        SUM(marketing_spend),
        2
    ) AS total_marketing_spend,

    ROUND(
        SUM(
            CASE
                WHEN delivered_sales > 0
                THEN marketing_spend
                ELSE 0
            END
        ),
        2
    ) AS marketing_spend_active_sales_months,

    ROUND(
        SUM(
            CASE
                WHEN delivered_sales = 0
                THEN marketing_spend
                ELSE 0
            END
        ),
        2
    ) AS marketing_spend_zero_sales_months,

    COUNT(*) FILTER (
        WHERE delivered_sales > 0
    ) AS active_sales_store_months,

    COUNT(*) FILTER (
        WHERE delivered_sales = 0
          AND marketing_spend > 0
    ) AS marketing_store_months_without_sales,

    ROUND(
        100.0
        * SUM(marketing_spend)
        / NULLIF(
            SUM(delivered_sales),
            0
        ),
        2
    ) AS total_marketing_spend_pct_sales,

    ROUND(
        100.0
        * SUM(
            CASE
                WHEN delivered_sales > 0
                THEN marketing_spend
                ELSE 0
            END
        )
        / NULLIF(
            SUM(delivered_sales),
            0
        ),
        2
    ) AS active_month_marketing_spend_pct_sales

FROM coverage;
