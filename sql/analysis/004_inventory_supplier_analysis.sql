-- ============================================================
-- Inventory and Supplier Analysis
--
-- Business questions:
--
-- 1. Where is current inventory capital concentrated?
-- 2. Which stores have the greatest reorder exposure?
-- 3. Which products show stockout or slow-moving risk?
-- 4. Which suppliers represent the greatest commercial
--    and inventory exposure?
-- 5. How concentrated is supplier dependency?
-- ============================================================


\echo ''
\echo '============================================================'
\echo '1. CURRENT INVENTORY BY STORE'
\echo '============================================================'

WITH latest_date AS (

    SELECT
        MAX(snapshot_date_key)
            AS snapshot_date_key

    FROM analytics.fact_inventory_monthly
)

SELECT
    s.store_id,
    s.store_name,
    s.store_format,

    COUNT(*) AS product_rows,

    SUM(f.closing_stock_qty)
        AS units_on_hand,

    ROUND(
        SUM(
            f.estimated_closing_inventory_value
        ),
        2
    ) AS current_inventory_value,

    COUNT(*) FILTER (
        WHERE f.is_below_reorder_point
    ) AS below_reorder_rows,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE f.is_below_reorder_point
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS below_reorder_rate_pct,

    ROUND(
        100.0
        * SUM(
            f.estimated_closing_inventory_value
        )
        / SUM(
            SUM(
                f.estimated_closing_inventory_value
            )
        ) OVER (),
        2
    ) AS inventory_value_share_pct

FROM analytics.fact_inventory_monthly f

INNER JOIN latest_date l
    ON f.snapshot_date_key =
       l.snapshot_date_key

INNER JOIN analytics.dim_store s
    ON f.store_key = s.store_key

GROUP BY
    s.store_id,
    s.store_name,
    s.store_format

ORDER BY current_inventory_value DESC;


\echo ''
\echo '============================================================'
\echo '2. HISTORICAL STOCKOUT RISK BY STORE'
\echo '============================================================'

SELECT
    s.store_id,
    s.store_name,
    s.store_format,

    COUNT(*) AS inventory_snapshot_rows,

    SUM(f.stockout_days)
        AS stockout_days,

    COUNT(*) FILTER (
        WHERE f.had_stockout
    ) AS stockout_rows,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE f.had_stockout
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS stockout_row_rate_pct,

    COUNT(*) FILTER (
        WHERE f.is_below_reorder_point
    ) AS below_reorder_rows,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE f.is_below_reorder_point
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS below_reorder_rate_pct

FROM analytics.fact_inventory_monthly f

INNER JOIN analytics.dim_store s
    ON f.store_key = s.store_key

GROUP BY
    s.store_id,
    s.store_name,
    s.store_format

ORDER BY stockout_row_rate_pct DESC,
         stockout_days DESC;


\echo ''
\echo '============================================================'
\echo '3. CURRENT HIGH-VALUE INVENTORY PRODUCTS'
\echo '============================================================'

WITH latest_date AS (

    SELECT
        MAX(snapshot_date_key)
            AS snapshot_date_key

    FROM analytics.fact_inventory_monthly
)

SELECT
    p.product_id,
    p.product_category_name,

    SUM(f.closing_stock_qty)
        AS units_on_hand,

    ROUND(
        SUM(
            f.estimated_closing_inventory_value
        ),
        2
    ) AS inventory_value,

    COUNT(DISTINCT f.store_key)
        AS stores_holding_product,

    COUNT(*) FILTER (
        WHERE f.is_below_reorder_point
    ) AS stores_below_reorder

FROM analytics.fact_inventory_monthly f

INNER JOIN latest_date l
    ON f.snapshot_date_key =
       l.snapshot_date_key

INNER JOIN analytics.dim_product p
    ON f.product_key = p.product_key

GROUP BY
    p.product_id,
    p.product_category_name

ORDER BY inventory_value DESC

LIMIT 20;


\echo ''
\echo '============================================================'
\echo '4. PRODUCTS WITH HIGHEST STOCKOUT EXPOSURE'
\echo '============================================================'

SELECT
    p.product_id,
    p.product_category_name,

    COUNT(*) AS snapshot_rows,

    COUNT(*) FILTER (
        WHERE f.had_stockout
    ) AS stockout_rows,

    SUM(f.stockout_days)
        AS stockout_days,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE f.had_stockout
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS stockout_row_rate_pct,

    SUM(f.sold_qty)
        AS units_sold

FROM analytics.fact_inventory_monthly f

INNER JOIN analytics.dim_product p
    ON f.product_key = p.product_key

GROUP BY
    p.product_id,
    p.product_category_name

HAVING COUNT(*) FILTER (
    WHERE f.had_stockout
) > 0

ORDER BY stockout_days DESC,
         stockout_row_rate_pct DESC

LIMIT 20;


\echo ''
\echo '============================================================'
\echo '5. SLOW-MOVING CURRENT INVENTORY'
\echo '============================================================'

WITH latest_date AS (

    SELECT
        MAX(d.full_date)
            AS latest_month

    FROM analytics.fact_inventory_monthly f

    INNER JOIN analytics.dim_date d
        ON f.snapshot_date_key =
           d.date_key
),

recent_sales AS (

    SELECT
        f.store_key,
        f.product_key,

        SUM(f.sold_qty)
            AS last_3_month_units_sold

    FROM analytics.fact_inventory_monthly f

    INNER JOIN analytics.dim_date d
        ON f.snapshot_date_key =
           d.date_key

    CROSS JOIN latest_date l

    WHERE d.full_date
          >= (
              l.latest_month
              - INTERVAL '2 months'
          )::date

    GROUP BY
        f.store_key,
        f.product_key
),

current_inventory AS (

    SELECT
        f.store_key,
        f.product_key,
        f.closing_stock_qty,
        f.estimated_closing_inventory_value

    FROM analytics.fact_inventory_monthly f

    INNER JOIN analytics.dim_date d
        ON f.snapshot_date_key =
           d.date_key

    CROSS JOIN latest_date l

    WHERE d.full_date =
          l.latest_month
)

SELECT
    s.store_id,
    s.store_name,

    p.product_id,
    p.product_category_name,

    c.closing_stock_qty,

    ROUND(
        c.estimated_closing_inventory_value,
        2
    ) AS current_inventory_value,

    COALESCE(
        r.last_3_month_units_sold,
        0
    ) AS last_3_month_units_sold

FROM current_inventory c

INNER JOIN analytics.dim_store s
    ON c.store_key = s.store_key

INNER JOIN analytics.dim_product p
    ON c.product_key = p.product_key

LEFT JOIN recent_sales r
    ON c.store_key = r.store_key
   AND c.product_key = r.product_key

WHERE c.closing_stock_qty > 0
  AND COALESCE(
      r.last_3_month_units_sold,
      0
  ) = 0

ORDER BY current_inventory_value DESC

LIMIT 30;


\echo ''
\echo '============================================================'
\echo '6. SUPPLIER COMMERCIAL AND CURRENT INVENTORY EXPOSURE'
\echo '============================================================'

WITH commercial AS (

    SELECT
        f.supplier_key,

        COUNT(DISTINCT f.order_id)
            AS delivered_orders,

        SUM(f.price)
            AS merchandise_value,

        SUM(f.estimated_cogs)
            AS estimated_cogs,

        SUM(f.estimated_gross_margin)
            AS estimated_gross_margin

    FROM analytics.fact_order_items f

    INNER JOIN analytics.dim_order_status os
        ON f.order_status_key =
           os.order_status_key

    WHERE os.order_status = 'delivered'

    GROUP BY f.supplier_key
),

latest_date AS (

    SELECT
        MAX(snapshot_date_key)
            AS snapshot_date_key

    FROM analytics.fact_inventory_monthly
),

inventory AS (

    SELECT
        f.supplier_key,

        SUM(f.closing_stock_qty)
            AS current_units_on_hand,

        SUM(
            f.estimated_closing_inventory_value
        ) AS current_inventory_value,

        COUNT(*) FILTER (
            WHERE f.is_below_reorder_point
        ) AS below_reorder_rows

    FROM analytics.fact_inventory_monthly f

    INNER JOIN latest_date l
        ON f.snapshot_date_key =
           l.snapshot_date_key

    GROUP BY f.supplier_key
)

SELECT
    s.supplier_id,
    s.supplier_name,
    s.supplier_state,
    s.supplier_rating,
    s.standard_lead_time_days,
    s.contractual_fill_rate_pct,

    c.delivered_orders,

    ROUND(
        c.merchandise_value,
        2
    ) AS merchandise_value,

    ROUND(
        c.estimated_gross_margin,
        2
    ) AS estimated_gross_margin,

    ROUND(
        100.0
        * c.estimated_gross_margin
        / NULLIF(
            c.merchandise_value,
            0
        ),
        2
    ) AS estimated_margin_pct,

    i.current_units_on_hand,

    ROUND(
        i.current_inventory_value,
        2
    ) AS current_inventory_value,

    i.below_reorder_rows,

    ROUND(
        100.0
        * c.merchandise_value
        / SUM(
            c.merchandise_value
        ) OVER (),
        2
    ) AS merchandise_share_pct

FROM commercial c

INNER JOIN analytics.dim_supplier s
    ON c.supplier_key =
       s.supplier_key

LEFT JOIN inventory i
    ON c.supplier_key =
       i.supplier_key

ORDER BY merchandise_value DESC

LIMIT 20;


\echo ''
\echo '============================================================'
\echo '7. SUPPLIER CONCENTRATION'
\echo '============================================================'

WITH supplier_sales AS (

    SELECT
        f.supplier_key,

        SUM(f.price)
            AS merchandise_value

    FROM analytics.fact_order_items f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'

    GROUP BY f.supplier_key
),

ranked AS (

    SELECT
        supplier_key,
        merchandise_value,

        ROW_NUMBER() OVER (
            ORDER BY merchandise_value DESC
        ) AS supplier_rank

    FROM supplier_sales
)

SELECT
    ROUND(
        100.0
        * SUM(
            CASE
                WHEN supplier_rank <= 5
                THEN merchandise_value
                ELSE 0
            END
        )
        / SUM(merchandise_value),
        2
    ) AS top_5_supplier_sales_share_pct,

    ROUND(
        100.0
        * SUM(
            CASE
                WHEN supplier_rank <= 10
                THEN merchandise_value
                ELSE 0
            END
        )
        / SUM(merchandise_value),
        2
    ) AS top_10_supplier_sales_share_pct,

    ROUND(
        100.0
        * SUM(
            CASE
                WHEN supplier_rank <= 20
                THEN merchandise_value
                ELSE 0
            END
        )
        / SUM(merchandise_value),
        2
    ) AS top_20_supplier_sales_share_pct

FROM ranked;


\echo ''
\echo '============================================================'
\echo '8. SUPPLIER STOCKOUT EXPOSURE'
\echo '============================================================'

SELECT
    s.supplier_id,
    s.supplier_name,
    s.supplier_rating,
    s.standard_lead_time_days,
    s.contractual_fill_rate_pct,

    COUNT(*) AS inventory_snapshot_rows,

    COUNT(*) FILTER (
        WHERE f.had_stockout
    ) AS stockout_rows,

    SUM(f.stockout_days)
        AS stockout_days,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE f.had_stockout
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS stockout_row_rate_pct

FROM analytics.fact_inventory_monthly f

INNER JOIN analytics.dim_supplier s
    ON f.supplier_key =
       s.supplier_key

GROUP BY
    s.supplier_id,
    s.supplier_name,
    s.supplier_rating,
    s.standard_lead_time_days,
    s.contractual_fill_rate_pct

HAVING COUNT(*) FILTER (
    WHERE f.had_stockout
) > 0

ORDER BY stockout_days DESC,
         stockout_row_rate_pct DESC

LIMIT 20;
