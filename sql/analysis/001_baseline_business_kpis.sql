-- ============================================================
-- Baseline Business KPIs
--
-- These results form the SQL control totals that future
-- Power BI measures must reconcile against.
-- ============================================================


\echo ''
\echo '============================================================'
\echo '1. EXECUTIVE COMMERCIAL KPIs'
\echo '============================================================'

WITH delivered_orders AS (

    SELECT f.*
    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key = s.order_status_key

    WHERE s.order_status = 'delivered'
)

SELECT
    COUNT(*) AS delivered_orders,

    ROUND(
        SUM(merchandise_value),
        2
    ) AS merchandise_value,

    ROUND(
        SUM(freight_value),
        2
    ) AS freight_value,

    ROUND(
        SUM(gross_order_value),
        2
    ) AS gross_order_value,

    ROUND(
        AVG(gross_order_value),
        2
    ) AS average_order_value,

    ROUND(
        AVG(item_count),
        2
    ) AS average_items_per_order,

    ROUND(
        100.0 * SUM(freight_value)
        / NULLIF(SUM(gross_order_value), 0),
        2
    ) AS freight_pct

FROM delivered_orders;


\echo ''
\echo '============================================================'
\echo '2. CUSTOMER KPIs'
\echo '============================================================'

WITH customer_orders AS (

    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT f.order_id) AS delivered_orders

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_customer c
        ON f.customer_key = c.customer_key

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key = s.order_status_key

    WHERE s.order_status = 'delivered'

    GROUP BY c.customer_unique_id
)

SELECT
    COUNT(*) AS unique_customers,

    COUNT(*) FILTER (
        WHERE delivered_orders >= 2
    ) AS repeat_customers,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE delivered_orders >= 2
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS repeat_customer_rate_pct,

    MAX(delivered_orders)
        AS max_delivered_orders_one_customer

FROM customer_orders;


\echo ''
\echo '============================================================'
\echo '3. DELIVERY KPIs'
\echo '============================================================'

WITH eligible AS (

    SELECT f.*

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key = s.order_status_key

    WHERE s.order_status = 'delivered'
      AND f.has_valid_delivery_timeline
      AND f.order_delivered_customer_date IS NOT NULL
      AND f.order_estimated_delivery_date IS NOT NULL
)

SELECT
    COUNT(*) AS delivery_eligible_orders,

    COUNT(*) FILTER (
        WHERE is_late_delivery
    ) AS late_deliveries,

    COUNT(*) FILTER (
        WHERE NOT is_late_delivery
    ) AS on_time_deliveries,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE is_late_delivery
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS late_delivery_rate_pct,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE NOT is_late_delivery
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS on_time_delivery_rate_pct,

    ROUND(
        AVG(delivery_days),
        2
    ) AS average_delivery_days

FROM eligible;


\echo ''
\echo '============================================================'
\echo '4. REVIEW KPIs'
\echo '============================================================'

SELECT
    COUNT(*) AS delivered_review_records,

    ROUND(
        AVG(r.review_score),
        2
    ) AS average_review_score,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE r.review_score >= 4
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS positive_review_rate_pct,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE r.review_score <= 2
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS negative_review_rate_pct

FROM analytics.fact_reviews r

INNER JOIN analytics.dim_order_status s
    ON r.order_status_key = s.order_status_key

WHERE s.order_status = 'delivered';


\echo ''
\echo '============================================================'
\echo '5. ORDER STATUS KPIs'
\echo '============================================================'

SELECT
    s.order_status,
    s.order_status_group,

    COUNT(*) AS orders,

    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS order_share_pct

FROM analytics.fact_orders f

INNER JOIN analytics.dim_order_status s
    ON f.order_status_key = s.order_status_key

GROUP BY
    s.order_status,
    s.order_status_group

ORDER BY orders DESC;


\echo ''
\echo '============================================================'
\echo '6. PAYMENT MIX - DELIVERED ORDERS'
\echo '============================================================'

SELECT
    p.payment_type,

    COUNT(*) AS payment_records,

    ROUND(
        SUM(p.payment_value),
        2
    ) AS payment_value,

    ROUND(
        100.0 * SUM(p.payment_value)
        / SUM(SUM(p.payment_value)) OVER (),
        2
    ) AS payment_value_share_pct

FROM analytics.fact_payments p

INNER JOIN analytics.dim_order_status s
    ON p.order_status_key = s.order_status_key

WHERE s.order_status = 'delivered'

GROUP BY p.payment_type

ORDER BY payment_value DESC;


\echo ''
\echo '============================================================'
\echo '7. TOP PRODUCT CATEGORIES'
\echo '============================================================'

SELECT
    p.product_category_name,

    COUNT(*) AS item_rows,

    COUNT(DISTINCT f.order_id)
        AS orders,

    ROUND(
        SUM(f.price),
        2
    ) AS merchandise_value,

    ROUND(
        SUM(f.freight_value),
        2
    ) AS freight_value

FROM analytics.fact_order_items f

INNER JOIN analytics.dim_product p
    ON f.product_key = p.product_key

INNER JOIN analytics.dim_order_status s
    ON f.order_status_key = s.order_status_key

WHERE s.order_status = 'delivered'

GROUP BY p.product_category_name

ORDER BY merchandise_value DESC

LIMIT 15;