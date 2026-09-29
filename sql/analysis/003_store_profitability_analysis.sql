-- ============================================================
-- Store and Profitability Analysis
--
-- Business questions:
--
-- 1. Which stores generate the most delivered sales?
-- 2. Which stores contribute the most estimated gross margin?
-- 3. How efficiently do stores convert merchandise sales
--    into estimated gross margin?
-- 4. Which stores are above or below budget and target?
-- 5. Which store-months contain the largest commercial gaps?
-- 6. How do store formats compare?
-- ============================================================


\echo ''
\echo '============================================================'
\echo '1. STORE COMMERCIAL PERFORMANCE'
\echo '============================================================'

WITH order_metrics AS (

    SELECT
        f.store_key,

        COUNT(*) AS delivered_orders,

        SUM(f.gross_order_value)
            AS gross_order_value,

        AVG(f.gross_order_value)
            AS average_order_value

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'

    GROUP BY f.store_key
),

margin_metrics AS (

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
),

combined AS (

    SELECT
        d.store_id,
        d.store_name,
        d.state,
        d.store_format,

        o.delivered_orders,
        o.gross_order_value,
        o.average_order_value,

        m.merchandise_value,
        m.estimated_cogs,
        m.estimated_gross_margin

    FROM analytics.dim_store d

    INNER JOIN order_metrics o
        ON d.store_key = o.store_key

    INNER JOIN margin_metrics m
        ON d.store_key = m.store_key
)

SELECT
    store_id,
    store_name,
    state,
    store_format,

    delivered_orders,

    ROUND(
        gross_order_value,
        2
    ) AS gross_order_value,

    ROUND(
        average_order_value,
        2
    ) AS average_order_value,

    ROUND(
        merchandise_value,
        2
    ) AS merchandise_value,

    ROUND(
        estimated_cogs,
        2
    ) AS estimated_cogs,

    ROUND(
        estimated_gross_margin,
        2
    ) AS estimated_gross_margin,

    ROUND(
        100.0
        * estimated_gross_margin
        / NULLIF(
            merchandise_value,
            0
        ),
        2
    ) AS estimated_margin_pct,

    ROUND(
        100.0
        * gross_order_value
        / SUM(
            gross_order_value
        ) OVER (),
        2
    ) AS sales_share_pct,

    ROUND(
        100.0
        * estimated_gross_margin
        / SUM(
            estimated_gross_margin
        ) OVER (),
        2
    ) AS margin_share_pct

FROM combined

ORDER BY gross_order_value DESC;


\echo ''
\echo '============================================================'
\echo '2. STORE ACTUAL VS BUDGET AND TARGET'
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
        p.store_key,
        d.full_date AS month,

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

    INNER JOIN analytics.dim_date d
        ON p.plan_date_key =
           d.date_key

    LEFT JOIN monthly_actual a
        ON d.full_date = a.month
       AND p.store_key = a.store_key
)

SELECT
    s.store_id,
    s.store_name,
    s.store_format,

    COUNT(*) AS planned_months,

    ROUND(
        SUM(c.actual_sales),
        2
    ) AS actual_sales,

    ROUND(
        SUM(c.sales_budget),
        2
    ) AS sales_budget,

    ROUND(
        SUM(c.sales_target),
        2
    ) AS sales_target,

    ROUND(
        SUM(c.actual_sales)
        - SUM(c.sales_budget),
        2
    ) AS budget_variance,

    ROUND(
        SUM(c.actual_sales)
        - SUM(c.sales_target),
        2
    ) AS target_variance,

    ROUND(
        100.0
        * SUM(c.actual_sales)
        / NULLIF(
            SUM(c.sales_budget),
            0
        ),
        2
    ) AS budget_attainment_pct,

    ROUND(
        100.0
        * SUM(c.actual_sales)
        / NULLIF(
            SUM(c.sales_target),
            0
        ),
        2
    ) AS target_attainment_pct,

    COUNT(*) FILTER (
        WHERE c.actual_sales
              >= c.sales_budget
    ) AS months_at_or_above_budget,

    COUNT(*) FILTER (
        WHERE c.actual_sales
              >= c.sales_target
    ) AS months_at_or_above_target

FROM comparison c

INNER JOIN analytics.dim_store s
    ON c.store_key = s.store_key

GROUP BY
    s.store_id,
    s.store_name,
    s.store_format

ORDER BY budget_variance ASC;


\echo ''
\echo '============================================================'
\echo '3. LARGEST STORE-MONTH BUDGET SHORTFALLS'
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
)

SELECT
    d.full_date AS month,

    s.store_id,
    s.store_name,
    s.store_format,

    COALESCE(
        a.actual_orders,
        0
    ) AS actual_orders,

    ROUND(
        COALESCE(
            a.actual_sales,
            0
        ),
        2
    ) AS actual_sales,

    p.sales_budget,

    ROUND(
        COALESCE(
            a.actual_sales,
            0
        )
        - p.sales_budget,
        2
    ) AS budget_variance,

    ROUND(
        100.0
        * COALESCE(
            a.actual_sales,
            0
        )
        / NULLIF(
            p.sales_budget,
            0
        ),
        2
    ) AS budget_attainment_pct,

    p.sales_target,

    ROUND(
        COALESCE(
            a.actual_sales,
            0
        )
        - p.sales_target,
        2
    ) AS target_variance

FROM analytics.fact_store_plan p

INNER JOIN analytics.dim_date d
    ON p.plan_date_key =
       d.date_key

INNER JOIN analytics.dim_store s
    ON p.store_key =
       s.store_key

LEFT JOIN monthly_actual a
    ON d.full_date = a.month
   AND p.store_key = a.store_key

ORDER BY budget_variance ASC

LIMIT 20;


\echo ''
\echo '============================================================'
\echo '4. STRONGEST STORE-MONTH BUDGET OUTPERFORMANCE'
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
)

SELECT
    d.full_date AS month,

    s.store_id,
    s.store_name,
    s.store_format,

    a.actual_orders,

    ROUND(
        a.actual_sales,
        2
    ) AS actual_sales,

    p.sales_budget,

    ROUND(
        a.actual_sales
        - p.sales_budget,
        2
    ) AS budget_variance,

    ROUND(
        100.0
        * a.actual_sales
        / NULLIF(
            p.sales_budget,
            0
        ),
        2
    ) AS budget_attainment_pct,

    p.sales_target,

    ROUND(
        a.actual_sales
        - p.sales_target,
        2
    ) AS target_variance

FROM analytics.fact_store_plan p

INNER JOIN analytics.dim_date d
    ON p.plan_date_key =
       d.date_key

INNER JOIN analytics.dim_store s
    ON p.store_key =
       s.store_key

INNER JOIN monthly_actual a
    ON d.full_date = a.month
   AND p.store_key = a.store_key

ORDER BY budget_variance DESC

LIMIT 20;


\echo ''
\echo '============================================================'
\echo '5. STORE FORMAT PERFORMANCE'
\echo '============================================================'

WITH order_metrics AS (

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

margin_metrics AS (

    SELECT
        f.store_key,

        SUM(f.price)
            AS merchandise_value,

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
    d.store_format,

    COUNT(*) AS stores,

    SUM(o.delivered_orders)
        AS delivered_orders,

    ROUND(
        SUM(o.gross_order_value),
        2
    ) AS gross_order_value,

    ROUND(
        SUM(o.gross_order_value)
        / NULLIF(
            COUNT(*),
            0
        ),
        2
    ) AS average_sales_per_store,

    ROUND(
        SUM(m.estimated_gross_margin),
        2
    ) AS estimated_gross_margin,

    ROUND(
        100.0
        * SUM(m.estimated_gross_margin)
        / NULLIF(
            SUM(m.merchandise_value),
            0
        ),
        2
    ) AS estimated_margin_pct

FROM analytics.dim_store d

INNER JOIN order_metrics o
    ON d.store_key = o.store_key

INNER JOIN margin_metrics m
    ON d.store_key = m.store_key

GROUP BY d.store_format

ORDER BY gross_order_value DESC;


\echo ''
\echo '============================================================'
\echo '6. SALES AND MARGIN CONCENTRATION'
\echo '============================================================'

WITH store_metrics AS (

    SELECT
        f.store_key,

        SUM(f.gross_order_value)
            AS gross_order_value

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'

    GROUP BY f.store_key
),

margin_metrics AS (

    SELECT
        f.store_key,

        SUM(f.estimated_gross_margin)
            AS estimated_gross_margin

    FROM analytics.fact_order_items f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'

    GROUP BY f.store_key
),

ranked AS (

    SELECT
        s.store_key,
        s.gross_order_value,
        m.estimated_gross_margin,

        ROW_NUMBER() OVER (
            ORDER BY
                s.gross_order_value DESC
        ) AS sales_rank

    FROM store_metrics s

    INNER JOIN margin_metrics m
        ON s.store_key = m.store_key
)

SELECT
    ROUND(
        100.0
        * SUM(
            CASE
                WHEN sales_rank <= 3
                THEN gross_order_value
                ELSE 0
            END
        )
        / SUM(gross_order_value),
        2
    ) AS top_3_store_sales_share_pct,

    ROUND(
        100.0
        * SUM(
            CASE
                WHEN sales_rank <= 5
                THEN gross_order_value
                ELSE 0
            END
        )
        / SUM(gross_order_value),
        2
    ) AS top_5_store_sales_share_pct,

    ROUND(
        100.0
        * SUM(
            CASE
                WHEN sales_rank <= 3
                THEN estimated_gross_margin
                ELSE 0
            END
        )
        / SUM(estimated_gross_margin),
        2
    ) AS top_3_store_margin_share_pct,

    ROUND(
        100.0
        * SUM(
            CASE
                WHEN sales_rank <= 5
                THEN estimated_gross_margin
                ELSE 0
            END
        )
        / SUM(estimated_gross_margin),
        2
    ) AS top_5_store_margin_share_pct

FROM ranked;
