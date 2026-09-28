BEGIN;

-- ============================================================
-- Core Fact Tables
--
-- fact_orders:
--     one row per order
--
-- fact_order_items:
--     one row per item sequence within an order
--
-- fact_payments:
--     one row per payment sequence within an order
--
-- fact_reviews:
--     one row per review/order combination
--
-- Fact tables are NOT linked directly to other fact tables.
-- They share conformed dimensions instead.
-- ============================================================

DROP TABLE IF EXISTS
    analytics.fact_reviews,
    analytics.fact_payments,
    analytics.fact_order_items,
    analytics.fact_orders
CASCADE;


-- ============================================================
-- FACT ORDERS
-- Grain: one row per order
-- ============================================================

CREATE TABLE analytics.fact_orders AS

WITH item_agg AS (

    SELECT
        order_id,

        COUNT(*)::integer
            AS item_count,

        COUNT(DISTINCT product_id)::integer
            AS distinct_product_count,

        COUNT(DISTINCT seller_id)::integer
            AS distinct_seller_count,

        SUM(price)::numeric(14, 2)
            AS merchandise_value,

        SUM(freight_value)::numeric(14, 2)
            AS freight_value,

        SUM(price + freight_value)::numeric(14, 2)
            AS gross_order_value

    FROM staging.order_items

    GROUP BY order_id
),

payment_agg AS (

    SELECT
        order_id,

        COUNT(*)::integer
            AS payment_record_count,

        COUNT(DISTINCT payment_type)::integer
            AS payment_type_count,

        STRING_AGG(
            DISTINCT payment_type,
            ', ' ORDER BY payment_type
        ) AS payment_types,

        MAX(payment_installments)::integer
            AS max_payment_installments,

        SUM(payment_value)::numeric(14, 2)
            AS payment_value

    FROM staging.order_payments

    GROUP BY order_id
)

SELECT
    ROW_NUMBER() OVER (
        ORDER BY o.order_id
    )::integer AS order_key,

    o.order_id,

    c.customer_key,

    o.order_status,

    TO_CHAR(
        o.order_purchase_timestamp,
        'YYYYMMDD'
    )::integer AS purchase_date_key,

    CASE
        WHEN o.order_approved_at IS NOT NULL
        THEN TO_CHAR(
            o.order_approved_at,
            'YYYYMMDD'
        )::integer
    END AS approved_date_key,

    CASE
        WHEN o.order_delivered_carrier_date IS NOT NULL
        THEN TO_CHAR(
            o.order_delivered_carrier_date,
            'YYYYMMDD'
        )::integer
    END AS carrier_date_key,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
        THEN TO_CHAR(
            o.order_delivered_customer_date,
            'YYYYMMDD'
        )::integer
    END AS delivered_date_key,

    CASE
        WHEN o.order_estimated_delivery_date IS NOT NULL
        THEN TO_CHAR(
            o.order_estimated_delivery_date,
            'YYYYMMDD'
        )::integer
    END AS estimated_delivery_date_key,

    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    COALESCE(
        ia.item_count,
        0
    )::integer AS item_count,

    COALESCE(
        ia.distinct_product_count,
        0
    )::integer AS distinct_product_count,

    COALESCE(
        ia.distinct_seller_count,
        0
    )::integer AS distinct_seller_count,

    ia.merchandise_value,
    ia.freight_value,
    ia.gross_order_value,

    COALESCE(
        pa.payment_record_count,
        0
    )::integer AS payment_record_count,

    COALESCE(
        pa.payment_type_count,
        0
    )::integer AS payment_type_count,

    pa.payment_types,
    pa.max_payment_installments,
    pa.payment_value,

    CASE
        WHEN ia.gross_order_value IS NOT NULL
         AND pa.payment_value IS NOT NULL
        THEN ROUND(
            pa.payment_value - ia.gross_order_value,
            2
        )
    END::numeric(14, 2)
        AS payment_reconciliation_difference,

    CASE
        WHEN ia.gross_order_value IS NOT NULL
         AND pa.payment_value IS NOT NULL
        THEN ABS(
            pa.payment_value - ia.gross_order_value
        ) > 0.01
        ELSE FALSE
    END AS has_payment_reconciliation_issue,

    (ia.order_id IS NOT NULL)
        AS has_items,

    (pa.order_id IS NOT NULL)
        AS has_payment,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
         AND o.order_delivered_customer_date
                >= o.order_purchase_timestamp
         AND (
                o.order_delivered_carrier_date IS NULL
                OR (
                    o.order_delivered_carrier_date
                        >= o.order_purchase_timestamp
                    AND o.order_delivered_customer_date
                        >= o.order_delivered_carrier_date
                )
             )
        THEN ROUND(
            (
                EXTRACT(
                    EPOCH FROM (
                        o.order_delivered_customer_date
                        - o.order_purchase_timestamp
                    )
                ) / 86400.0
            )::numeric,
            2
        )
    END AS delivery_days,

    CASE
        WHEN o.order_approved_at IS NOT NULL
         AND o.order_approved_at
                >= o.order_purchase_timestamp
        THEN ROUND(
            (
                EXTRACT(
                    EPOCH FROM (
                        o.order_approved_at
                        - o.order_purchase_timestamp
                    )
                ) / 3600.0
            )::numeric,
            2
        )
    END AS approval_hours,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
        THEN
            o.order_delivered_customer_date::date
            - o.order_estimated_delivery_date::date
    END::integer AS delivery_variance_days,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
        THEN
            o.order_delivered_customer_date
            > o.order_estimated_delivery_date
        ELSE NULL
    END AS is_late_delivery,

    (
        o.order_delivered_customer_date IS NOT NULL
        AND o.order_delivered_customer_date
            >= o.order_purchase_timestamp
        AND (
            o.order_delivered_carrier_date IS NULL
            OR (
                o.order_delivered_carrier_date
                    >= o.order_purchase_timestamp
                AND o.order_delivered_customer_date
                    >= o.order_delivered_carrier_date
            )
        )
    ) AS has_valid_delivery_timeline,

    (
        o.order_delivered_carrier_date IS NOT NULL
        AND o.order_delivered_carrier_date
            < o.order_purchase_timestamp
    ) AS has_carrier_before_purchase_anomaly,

    (
        o.order_delivered_customer_date IS NOT NULL
        AND o.order_delivered_carrier_date IS NOT NULL
        AND o.order_delivered_customer_date
            < o.order_delivered_carrier_date
    ) AS has_delivery_before_carrier_anomaly,

    (
        o.order_status = 'delivered'
        AND o.order_delivered_customer_date IS NULL
    ) AS has_missing_delivery_timestamp

FROM staging.orders o

INNER JOIN analytics.dim_customer c
    ON o.customer_id = c.customer_id

LEFT JOIN item_agg ia
    ON o.order_id = ia.order_id

LEFT JOIN payment_agg pa
    ON o.order_id = pa.order_id;


ALTER TABLE analytics.fact_orders
ADD CONSTRAINT pk_fact_orders
PRIMARY KEY (order_key);


ALTER TABLE analytics.fact_orders
ADD CONSTRAINT uq_fact_orders_order_id
UNIQUE (order_id);


ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fk_fact_orders_customer
FOREIGN KEY (customer_key)
REFERENCES analytics.dim_customer(customer_key);


ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fk_fact_orders_purchase_date
FOREIGN KEY (purchase_date_key)
REFERENCES analytics.dim_date(date_key);


ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fk_fact_orders_approved_date
FOREIGN KEY (approved_date_key)
REFERENCES analytics.dim_date(date_key);


ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fk_fact_orders_carrier_date
FOREIGN KEY (carrier_date_key)
REFERENCES analytics.dim_date(date_key);


ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fk_fact_orders_delivered_date
FOREIGN KEY (delivered_date_key)
REFERENCES analytics.dim_date(date_key);


ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fk_fact_orders_estimated_date
FOREIGN KEY (estimated_delivery_date_key)
REFERENCES analytics.dim_date(date_key);


-- ============================================================
-- FACT ORDER ITEMS
-- Grain: one item sequence within one order
-- ============================================================

CREATE TABLE analytics.fact_order_items AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY oi.order_id, oi.order_item_id
    )::integer AS order_item_key,

    oi.order_id,
    oi.order_item_id,

    c.customer_key,
    p.product_key,
    s.seller_key,

    TO_CHAR(
        o.order_purchase_timestamp,
        'YYYYMMDD'
    )::integer AS purchase_date_key,

    CASE
        WHEN oi.shipping_limit_date IS NOT NULL
        THEN TO_CHAR(
            oi.shipping_limit_date,
            'YYYYMMDD'
        )::integer
    END AS shipping_limit_date_key,

    oi.shipping_limit_date,

    oi.price,

    oi.freight_value,

    (
        oi.price + oi.freight_value
    )::numeric(14, 2)
        AS gross_item_value

FROM staging.order_items oi

INNER JOIN staging.orders o
    ON oi.order_id = o.order_id

INNER JOIN analytics.dim_customer c
    ON o.customer_id = c.customer_id

INNER JOIN analytics.dim_product p
    ON oi.product_id = p.product_id

INNER JOIN analytics.dim_seller s
    ON oi.seller_id = s.seller_id;


ALTER TABLE analytics.fact_order_items
ADD CONSTRAINT pk_fact_order_items
PRIMARY KEY (order_item_key);


ALTER TABLE analytics.fact_order_items
ADD CONSTRAINT uq_fact_order_items_source
UNIQUE (order_id, order_item_id);


ALTER TABLE analytics.fact_order_items
ADD CONSTRAINT fk_fact_order_items_customer
FOREIGN KEY (customer_key)
REFERENCES analytics.dim_customer(customer_key);


ALTER TABLE analytics.fact_order_items
ADD CONSTRAINT fk_fact_order_items_product
FOREIGN KEY (product_key)
REFERENCES analytics.dim_product(product_key);


ALTER TABLE analytics.fact_order_items
ADD CONSTRAINT fk_fact_order_items_seller
FOREIGN KEY (seller_key)
REFERENCES analytics.dim_seller(seller_key);


ALTER TABLE analytics.fact_order_items
ADD CONSTRAINT fk_fact_order_items_purchase_date
FOREIGN KEY (purchase_date_key)
REFERENCES analytics.dim_date(date_key);


ALTER TABLE analytics.fact_order_items
ADD CONSTRAINT fk_fact_order_items_shipping_date
FOREIGN KEY (shipping_limit_date_key)
REFERENCES analytics.dim_date(date_key);


-- ============================================================
-- FACT PAYMENTS
-- Grain: one payment sequence within one order
-- ============================================================

CREATE TABLE analytics.fact_payments AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY p.order_id, p.payment_sequential
    )::integer AS payment_key,

    p.order_id,
    p.payment_sequential,

    c.customer_key,

    TO_CHAR(
        o.order_purchase_timestamp,
        'YYYYMMDD'
    )::integer AS purchase_date_key,

    p.payment_type,

    p.payment_installments,

    p.payment_value,

    (
        p.payment_installments <= 0
    ) AS has_invalid_installment_count

FROM staging.order_payments p

INNER JOIN staging.orders o
    ON p.order_id = o.order_id

INNER JOIN analytics.dim_customer c
    ON o.customer_id = c.customer_id;


ALTER TABLE analytics.fact_payments
ADD CONSTRAINT pk_fact_payments
PRIMARY KEY (payment_key);


ALTER TABLE analytics.fact_payments
ADD CONSTRAINT uq_fact_payments_source
UNIQUE (order_id, payment_sequential);


ALTER TABLE analytics.fact_payments
ADD CONSTRAINT fk_fact_payments_customer
FOREIGN KEY (customer_key)
REFERENCES analytics.dim_customer(customer_key);


ALTER TABLE analytics.fact_payments
ADD CONSTRAINT fk_fact_payments_purchase_date
FOREIGN KEY (purchase_date_key)
REFERENCES analytics.dim_date(date_key);


-- ============================================================
-- FACT REVIEWS
-- Grain: one review/order combination
-- ============================================================

CREATE TABLE analytics.fact_reviews AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY r.review_id, r.order_id
    )::integer AS review_key,

    r.review_id,
    r.order_id,

    c.customer_key,

    CASE
        WHEN r.review_creation_date IS NOT NULL
        THEN TO_CHAR(
            r.review_creation_date,
            'YYYYMMDD'
        )::integer
    END AS review_creation_date_key,

    CASE
        WHEN r.review_answer_timestamp IS NOT NULL
        THEN TO_CHAR(
            r.review_answer_timestamp,
            'YYYYMMDD'
        )::integer
    END AS review_answer_date_key,

    r.review_score,

    (
        r.review_comment_title IS NOT NULL
    ) AS has_comment_title,

    (
        r.review_comment_message IS NOT NULL
    ) AS has_comment_message,

    r.review_comment_title,

    r.review_comment_message,

    r.review_creation_date,
    r.review_answer_timestamp,

    CASE
        WHEN r.review_answer_timestamp IS NOT NULL
         AND r.review_creation_date IS NOT NULL
         AND r.review_answer_timestamp
                >= r.review_creation_date
        THEN ROUND(
            (
                EXTRACT(
                    EPOCH FROM (
                        r.review_answer_timestamp
                        - r.review_creation_date
                    )
                ) / 3600.0
            )::numeric,
            2
        )
    END AS review_response_hours

FROM staging.order_reviews r

INNER JOIN staging.orders o
    ON r.order_id = o.order_id

INNER JOIN analytics.dim_customer c
    ON o.customer_id = c.customer_id;


ALTER TABLE analytics.fact_reviews
ADD CONSTRAINT pk_fact_reviews
PRIMARY KEY (review_key);


ALTER TABLE analytics.fact_reviews
ADD CONSTRAINT uq_fact_reviews_source
UNIQUE (review_id, order_id);


ALTER TABLE analytics.fact_reviews
ADD CONSTRAINT fk_fact_reviews_customer
FOREIGN KEY (customer_key)
REFERENCES analytics.dim_customer(customer_key);


ALTER TABLE analytics.fact_reviews
ADD CONSTRAINT fk_fact_reviews_creation_date
FOREIGN KEY (review_creation_date_key)
REFERENCES analytics.dim_date(date_key);


ALTER TABLE analytics.fact_reviews
ADD CONSTRAINT fk_fact_reviews_answer_date
FOREIGN KEY (review_answer_date_key)
REFERENCES analytics.dim_date(date_key);


COMMIT;
