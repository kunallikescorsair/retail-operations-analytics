-- ============================================================
-- Investigate payment reconciliation differences
-- ============================================================

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS merchandise_total,
        SUM(freight_value) AS freight_total,
        SUM(price + freight_value) AS item_total
    FROM staging.order_items
    GROUP BY order_id
),

payment_details AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total,
        COUNT(*) AS payment_records,
        COUNT(DISTINCT payment_type) AS payment_type_count,
        STRING_AGG(
            DISTINCT payment_type,
            ', ' ORDER BY payment_type
        ) AS payment_types
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
        p.payment_records,
        p.payment_type_count,
        p.payment_types,
        p.payment_total - i.item_total AS difference,
        ABS(p.payment_total - i.item_total)
            AS absolute_difference
    FROM item_totals i
    INNER JOIN payment_details p
        ON i.order_id = p.order_id
),

mismatches AS (
    SELECT *
    FROM reconciliation
    WHERE absolute_difference > 0.01
)

-- ============================================================
-- 1. Mismatch classification
-- ============================================================

SELECT
    CASE
        WHEN payment_types LIKE '%voucher%'
            THEN 'contains voucher'
        WHEN payment_records > 1
            THEN 'multiple payment records'
        ELSE 'single non-voucher payment'
    END AS payment_scenario,

    COUNT(*) AS orders,

    ROUND(
        AVG(absolute_difference),
        2
    ) AS avg_abs_difference,

    ROUND(
        MAX(absolute_difference),
        2
    ) AS max_abs_difference

FROM mismatches

GROUP BY 1
ORDER BY orders DESC;


-- ============================================================
-- 2. Breakdown by payment type combination
-- ============================================================

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS item_total
    FROM staging.order_items
    GROUP BY order_id
),

payment_details AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total,
        COUNT(*) AS payment_records,
        STRING_AGG(
            DISTINCT payment_type,
            ', ' ORDER BY payment_type
        ) AS payment_types
    FROM staging.order_payments
    GROUP BY order_id
)

SELECT
    p.payment_types,
    COUNT(*) AS mismatched_orders,

    ROUND(
        AVG(
            ABS(p.payment_total - i.item_total)
        ),
        2
    ) AS avg_abs_difference,

    ROUND(
        MAX(
            ABS(p.payment_total - i.item_total)
        ),
        2
    ) AS max_abs_difference

FROM item_totals i

INNER JOIN payment_details p
    ON i.order_id = p.order_id

WHERE ABS(
    p.payment_total - i.item_total
) > 0.01

GROUP BY p.payment_types
ORDER BY mismatched_orders DESC;


-- ============================================================
-- 3. Detailed mismatched-payment records
-- ============================================================

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS item_total
    FROM staging.order_items
    GROUP BY order_id
),

payment_details AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total,
        COUNT(*) AS payment_records,
        STRING_AGG(
            DISTINCT payment_type,
            ', ' ORDER BY payment_type
        ) AS payment_types
    FROM staging.order_payments
    GROUP BY order_id
)

SELECT
    o.order_id,
    o.order_status,

    p.payment_records,
    p.payment_types,

    i.item_total,
    p.payment_total,

    ROUND(
        p.payment_total - i.item_total,
        2
    ) AS signed_difference

FROM item_totals i

INNER JOIN payment_details p
    ON i.order_id = p.order_id

INNER JOIN staging.orders o
    ON o.order_id = i.order_id

WHERE ABS(
    p.payment_total - i.item_total
) > 0.01

ORDER BY ABS(
    p.payment_total - i.item_total
) DESC

LIMIT 50;