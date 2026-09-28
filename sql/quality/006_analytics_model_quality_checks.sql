-- ============================================================
-- Analytics Model Quality Checks
-- ============================================================

\echo ''
\echo '============================================================'
\echo '1. ANALYTICS TABLE ROW COUNTS'
\echo '============================================================'

SELECT 'dim_date' AS table_name, COUNT(*) AS row_count
FROM analytics.dim_date

UNION ALL
SELECT 'dim_customer', COUNT(*)
FROM analytics.dim_customer

UNION ALL
SELECT 'dim_product', COUNT(*)
FROM analytics.dim_product

UNION ALL
SELECT 'dim_seller', COUNT(*)
FROM analytics.dim_seller

UNION ALL
SELECT 'fact_orders', COUNT(*)
FROM analytics.fact_orders

UNION ALL
SELECT 'fact_order_items', COUNT(*)
FROM analytics.fact_order_items

UNION ALL
SELECT 'fact_payments', COUNT(*)
FROM analytics.fact_payments

UNION ALL
SELECT 'fact_reviews', COUNT(*)
FROM analytics.fact_reviews

ORDER BY table_name;


\echo ''
\echo '============================================================'
\echo '2. DUPLICATE BUSINESS KEYS'
\echo '============================================================'

SELECT
    'fact_orders.order_id' AS check_name,
    COUNT(*) AS duplicate_groups
FROM (
    SELECT order_id
    FROM analytics.fact_orders
    GROUP BY order_id
    HAVING COUNT(*) > 1
) x

UNION ALL

SELECT
    'fact_order_items.order_id+order_item_id',
    COUNT(*)
FROM (
    SELECT
        order_id,
        order_item_id
    FROM analytics.fact_order_items
    GROUP BY
        order_id,
        order_item_id
    HAVING COUNT(*) > 1
) x

UNION ALL

SELECT
    'fact_payments.order_id+payment_sequential',
    COUNT(*)
FROM (
    SELECT
        order_id,
        payment_sequential
    FROM analytics.fact_payments
    GROUP BY
        order_id,
        payment_sequential
    HAVING COUNT(*) > 1
) x

UNION ALL

SELECT
    'fact_reviews.review_id+order_id',
    COUNT(*)
FROM (
    SELECT
        review_id,
        order_id
    FROM analytics.fact_reviews
    GROUP BY
        review_id,
        order_id
    HAVING COUNT(*) > 1
) x;


\echo ''
\echo '============================================================'
\echo '3. MISSING DIMENSION KEYS'
\echo '============================================================'

SELECT
    'fact_orders_customer_key' AS check_name,
    COUNT(*) AS issue_count
FROM analytics.fact_orders
WHERE customer_key IS NULL

UNION ALL

SELECT
    'fact_order_items_customer_key',
    COUNT(*)
FROM analytics.fact_order_items
WHERE customer_key IS NULL

UNION ALL

SELECT
    'fact_order_items_product_key',
    COUNT(*)
FROM analytics.fact_order_items
WHERE product_key IS NULL

UNION ALL

SELECT
    'fact_order_items_seller_key',
    COUNT(*)
FROM analytics.fact_order_items
WHERE seller_key IS NULL

UNION ALL

SELECT
    'fact_payments_customer_key',
    COUNT(*)
FROM analytics.fact_payments
WHERE customer_key IS NULL

UNION ALL

SELECT
    'fact_reviews_customer_key',
    COUNT(*)
FROM analytics.fact_reviews
WHERE customer_key IS NULL;


\echo ''
\echo '============================================================'
\echo '4. ORDER QUALITY FLAGS'
\echo '============================================================'

SELECT
    COUNT(*) AS orders,

    COUNT(*) FILTER (
        WHERE NOT has_items
    ) AS orders_without_items,

    COUNT(*) FILTER (
        WHERE NOT has_payment
    ) AS orders_without_payment,

    COUNT(*) FILTER (
        WHERE has_payment_reconciliation_issue
    ) AS payment_reconciliation_issues,

    COUNT(*) FILTER (
        WHERE has_carrier_before_purchase_anomaly
    ) AS carrier_before_purchase,

    COUNT(*) FILTER (
        WHERE has_delivery_before_carrier_anomaly
    ) AS delivery_before_carrier,

    COUNT(*) FILTER (
        WHERE has_missing_delivery_timestamp
    ) AS delivered_missing_timestamp,

    COUNT(*) FILTER (
        WHERE is_late_delivery
    ) AS late_deliveries

FROM analytics.fact_orders;


\echo ''
\echo '============================================================'
\echo '5. SALES TOTAL RECONCILIATION'
\echo '============================================================'

SELECT
    ROUND(
        (
            SELECT SUM(price)
            FROM staging.order_items
        ),
        2
    ) AS staging_merchandise,

    ROUND(
        (
            SELECT SUM(merchandise_value)
            FROM analytics.fact_orders
        ),
        2
    ) AS analytics_merchandise,

    ROUND(
        (
            SELECT SUM(freight_value)
            FROM staging.order_items
        ),
        2
    ) AS staging_freight,

    ROUND(
        (
            SELECT SUM(freight_value)
            FROM analytics.fact_orders
        ),
        2
    ) AS analytics_freight;


\echo ''
\echo '============================================================'
\echo '6. PAYMENT TOTAL RECONCILIATION'
\echo '============================================================'

SELECT
    ROUND(
        (
            SELECT SUM(payment_value)
            FROM staging.order_payments
        ),
        2
    ) AS staging_payment_value,

    ROUND(
        (
            SELECT SUM(payment_value)
            FROM analytics.fact_payments
        ),
        2
    ) AS fact_payment_value,

    ROUND(
        (
            SELECT SUM(payment_value)
            FROM analytics.fact_orders
        ),
        2
    ) AS order_level_payment_value;


\echo ''
\echo '============================================================'
\echo '7. ITEM FACT TOTAL RECONCILIATION'
\echo '============================================================'

SELECT
    ROUND(
        (
            SELECT SUM(price)
            FROM staging.order_items
        ),
        2
    ) AS staging_price,

    ROUND(
        (
            SELECT SUM(price)
            FROM analytics.fact_order_items
        ),
        2
    ) AS fact_price,

    ROUND(
        (
            SELECT SUM(freight_value)
            FROM staging.order_items
        ),
        2
    ) AS staging_freight,

    ROUND(
        (
            SELECT SUM(freight_value)
            FROM analytics.fact_order_items
        ),
        2
    ) AS fact_freight;


\echo ''
\echo '============================================================'
\echo '8. PAYMENT / ITEM POPULATION DECOMPOSITION'
\echo '============================================================'

SELECT
    COUNT(*) FILTER (
        WHERE has_items AND has_payment
    ) AS orders_with_items_and_payment,

    COUNT(*) FILTER (
        WHERE NOT has_items AND has_payment
    ) AS paid_orders_without_items,

    COUNT(*) FILTER (
        WHERE has_items AND NOT has_payment
    ) AS item_orders_without_payment,

    COUNT(*) FILTER (
        WHERE NOT has_items AND NOT has_payment
    ) AS orders_without_items_or_payment,

    ROUND(
        SUM(payment_value) FILTER (
            WHERE NOT has_items AND has_payment
        ),
        2
    ) AS payment_value_without_items

FROM analytics.fact_orders;
