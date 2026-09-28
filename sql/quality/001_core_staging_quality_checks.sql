-- ============================================================
-- Core Staging Data Quality Checks
-- ============================================================

WITH
item_totals AS (
    SELECT
        order_id,
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
        i.item_total,
        p.payment_total,
        ABS(i.item_total - p.payment_total) AS difference
    FROM item_totals i
    INNER JOIN payment_totals p
        ON i.order_id = p.order_id
),

checks AS (

    -- ========================================================
    -- Order timeline checks
    -- ========================================================

    SELECT
        'ERROR' AS severity,
        'approval_before_purchase' AS check_name,
        COUNT(*) AS issue_count
    FROM staging.orders
    WHERE order_approved_at < order_purchase_timestamp

    UNION ALL

    SELECT
        'ERROR',
        'carrier_delivery_before_purchase',
        COUNT(*)
    FROM staging.orders
    WHERE order_delivered_carrier_date < order_purchase_timestamp

    UNION ALL

    SELECT
        'ERROR',
        'customer_delivery_before_purchase',
        COUNT(*)
    FROM staging.orders
    WHERE order_delivered_customer_date < order_purchase_timestamp

    UNION ALL

    SELECT
        'ERROR',
        'customer_delivery_before_carrier',
        COUNT(*)
    FROM staging.orders
    WHERE order_delivered_customer_date IS NOT NULL
      AND order_delivered_carrier_date IS NOT NULL
      AND order_delivered_customer_date < order_delivered_carrier_date

    UNION ALL

    SELECT
        'WARNING',
        'delivered_orders_missing_customer_delivery_date',
        COUNT(*)
    FROM staging.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NULL


    -- ========================================================
    -- Monetary checks
    -- ========================================================

    UNION ALL

    SELECT
        'ERROR',
        'negative_item_price',
        COUNT(*)
    FROM staging.order_items
    WHERE price < 0

    UNION ALL

    SELECT
        'ERROR',
        'negative_freight_value',
        COUNT(*)
    FROM staging.order_items
    WHERE freight_value < 0

    UNION ALL

    SELECT
        'ERROR',
        'negative_payment_value',
        COUNT(*)
    FROM staging.order_payments
    WHERE payment_value < 0

    UNION ALL

    SELECT
        'WARNING',
        'nonpositive_payment_installments',
        COUNT(*)
    FROM staging.order_payments
    WHERE payment_installments <= 0


    -- ========================================================
    -- Customer data checks
    -- ========================================================

    UNION ALL

    SELECT
        'ERROR',
        'invalid_customer_state',
        COUNT(*)
    FROM staging.customers
    WHERE customer_state IS NULL
       OR customer_state !~ '^[A-Z]{2}$'

    UNION ALL

    SELECT
        'ERROR',
        'invalid_customer_zip_prefix',
        COUNT(*)
    FROM staging.customers
    WHERE customer_zip_code_prefix IS NULL
       OR customer_zip_code_prefix !~ '^[0-9]{5}$'

    UNION ALL

    SELECT
        'ERROR',
        'missing_customer_unique_id',
        COUNT(*)
    FROM staging.customers
    WHERE customer_unique_id IS NULL
       OR TRIM(customer_unique_id) = ''


    -- ========================================================
    -- Product checks
    -- ========================================================

    UNION ALL

    SELECT
        'WARNING',
        'missing_product_category',
        COUNT(*)
    FROM staging.products
    WHERE product_category_name IS NULL

    UNION ALL

    SELECT
        'WARNING',
        'nonpositive_product_measurements',
        COUNT(*)
    FROM staging.products
    WHERE product_weight_g <= 0
       OR product_length_cm <= 0
       OR product_height_cm <= 0
       OR product_width_cm <= 0


    -- ========================================================
    -- Order completeness checks
    -- ========================================================

    UNION ALL

    SELECT
        'WARNING',
        'orders_without_items',
        COUNT(*)
    FROM staging.orders o
    WHERE NOT EXISTS (
        SELECT 1
        FROM staging.order_items i
        WHERE i.order_id = o.order_id
    )

    UNION ALL

    SELECT
        'WARNING',
        'orders_without_payments',
        COUNT(*)
    FROM staging.orders o
    WHERE NOT EXISTS (
        SELECT 1
        FROM staging.order_payments p
        WHERE p.order_id = o.order_id
    )


    -- ========================================================
    -- Financial reconciliation
    -- ========================================================

    UNION ALL

    SELECT
        'WARNING',
        'order_payment_reconciliation_difference_gt_001',
        COUNT(*)
    FROM reconciliation
    WHERE difference > 0.01
)

SELECT
    severity,
    check_name,
    issue_count
FROM checks
ORDER BY
    CASE severity
        WHEN 'ERROR' THEN 1
        WHEN 'WARNING' THEN 2
        ELSE 3
    END,
    check_name;