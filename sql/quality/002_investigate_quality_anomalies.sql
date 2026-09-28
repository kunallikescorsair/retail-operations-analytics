-- ============================================================
-- Detailed investigation of staging quality anomalies
-- ============================================================


\echo ''
\echo '============================================================'
\echo '1. CARRIER DATE BEFORE PURCHASE'
\echo '============================================================'

SELECT
    order_id,
    order_status,
    order_purchase_timestamp,
    order_delivered_carrier_date,
    order_purchase_timestamp - order_delivered_carrier_date
        AS carrier_before_purchase_by
FROM staging.orders
WHERE order_delivered_carrier_date < order_purchase_timestamp
ORDER BY carrier_before_purchase_by DESC
LIMIT 20;


\echo ''
\echo '============================================================'
\echo '2. CUSTOMER DELIVERY BEFORE CARRIER'
\echo '============================================================'

SELECT
    order_id,
    order_status,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_delivered_carrier_date - order_delivered_customer_date
        AS delivery_before_carrier_by
FROM staging.orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_delivered_carrier_date IS NOT NULL
  AND order_delivered_customer_date < order_delivered_carrier_date
ORDER BY delivery_before_carrier_by DESC;


\echo ''
\echo '============================================================'
\echo '3. DELIVERED ORDERS MISSING CUSTOMER DELIVERY DATE'
\echo '============================================================'

SELECT
    *
FROM staging.orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL
ORDER BY order_purchase_timestamp;


\echo ''
\echo '============================================================'
\echo '4. NONPOSITIVE PAYMENT INSTALLMENTS'
\echo '============================================================'

SELECT *
FROM staging.order_payments
WHERE payment_installments <= 0;


\echo ''
\echo '============================================================'
\echo '5. NONPOSITIVE PRODUCT MEASUREMENTS'
\echo '============================================================'

SELECT *
FROM staging.products
WHERE product_weight_g <= 0
   OR product_length_cm <= 0
   OR product_height_cm <= 0
   OR product_width_cm <= 0;


\echo ''
\echo '============================================================'
\echo '6. UNUSUAL ORDERS WITHOUT ITEMS'
\echo '============================================================'

SELECT
    o.*
FROM staging.orders o
WHERE NOT EXISTS (
    SELECT 1
    FROM staging.order_items i
    WHERE i.order_id = o.order_id
)
AND o.order_status NOT IN (
    'canceled',
    'unavailable',
    'created'
)
ORDER BY order_status, order_purchase_timestamp;


\echo ''
\echo '============================================================'
\echo '7. ORDERS WITHOUT PAYMENTS'
\echo '============================================================'

SELECT
    o.*
FROM staging.orders o
WHERE NOT EXISTS (
    SELECT 1
    FROM staging.order_payments p
    WHERE p.order_id = o.order_id
);


\echo ''
\echo '============================================================'
\echo '8. PAYMENT RECONCILIATION SUMMARY'
\echo '============================================================'

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS merchandise_total,
        SUM(freight_value) AS freight_total,
        SUM(price + freight_value) AS item_total
    FROM staging.order_items
    GROUP BY order_id
),

payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total
    FROM staging.order_payments
    GROUP BY order_id
),

reconciliation AS (
    SELECT
        i.order_id,
        i.merchandise_total,
        i.freight_total,
        i.item_total,
        p.payment_total,
        p.payment_total - i.item_total AS signed_difference,
        ABS(p.payment_total - i.item_total) AS absolute_difference
    FROM item_totals i
    INNER JOIN payment_totals p
        ON i.order_id = p.order_id
)

SELECT
    COUNT(*) AS reconciled_orders,

    COUNT(*) FILTER (
        WHERE absolute_difference > 0.01
    ) AS difference_gt_001,

    COUNT(*) FILTER (
        WHERE absolute_difference > 1
    ) AS difference_gt_1,

    COUNT(*) FILTER (
        WHERE absolute_difference > 10
    ) AS difference_gt_10,

    COUNT(*) FILTER (
        WHERE absolute_difference > 100
    ) AS difference_gt_100,

    COUNT(*) FILTER (
        WHERE signed_difference > 0.01
    ) AS payment_greater_than_items,

    COUNT(*) FILTER (
        WHERE signed_difference < -0.01
    ) AS payment_less_than_items,

    ROUND(MAX(absolute_difference), 2)
        AS maximum_absolute_difference,

    ROUND(AVG(absolute_difference), 4)
        AS average_absolute_difference

FROM reconciliation;


\echo ''
\echo '============================================================'
\echo '9. LARGEST PAYMENT RECONCILIATION DIFFERENCES'
\echo '============================================================'

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS merchandise_total,
        SUM(freight_value) AS freight_total,
        SUM(price + freight_value) AS item_total
    FROM staging.order_items
    GROUP BY order_id
),

payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total
    FROM staging.order_payments
    GROUP BY order_id
)

SELECT
    o.order_id,
    o.order_status,
    i.merchandise_total,
    i.freight_total,
    i.item_total,
    p.payment_total,

    ROUND(
        p.payment_total - i.item_total,
        2
    ) AS signed_difference

FROM item_totals i

INNER JOIN payment_totals p
    ON i.order_id = p.order_id

INNER JOIN staging.orders o
    ON i.order_id = o.order_id

WHERE ABS(
    p.payment_total - i.item_total
) > 0.01

ORDER BY ABS(
    p.payment_total - i.item_total
) DESC

LIMIT 30;


\echo ''
\echo '============================================================'
\echo '10. ORDER-ITEM COMPLETENESS BY STATUS'
\echo '============================================================'

SELECT
    order_status,
    COUNT(*) AS total_orders,

    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1
            FROM staging.order_items i
            WHERE i.order_id = o.order_id
        )
    ) AS with_items,

    COUNT(*) FILTER (
        WHERE NOT EXISTS (
            SELECT 1
            FROM staging.order_items i
            WHERE i.order_id = o.order_id
        )
    ) AS without_items

FROM staging.orders o

GROUP BY order_status
ORDER BY total_orders DESC;