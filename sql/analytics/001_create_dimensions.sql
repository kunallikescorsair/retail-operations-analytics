BEGIN;

-- ============================================================
-- Rebuild dimensions
-- ============================================================

DROP TABLE IF EXISTS
    analytics.dim_seller,
    analytics.dim_product,
    analytics.dim_customer,
    analytics.dim_date
CASCADE;


-- ============================================================
-- Date Dimension
-- Grain: one row per calendar date
-- ============================================================

CREATE TABLE analytics.dim_date AS

WITH date_bounds AS (

    SELECT
        MIN(date_value)::date AS min_date,
        MAX(date_value)::date AS max_date

    FROM (

        SELECT order_purchase_timestamp::date AS date_value
        FROM staging.orders

        UNION ALL

        SELECT order_approved_at::date
        FROM staging.orders

        UNION ALL

        SELECT order_delivered_carrier_date::date
        FROM staging.orders

        UNION ALL

        SELECT order_delivered_customer_date::date
        FROM staging.orders

        UNION ALL

        SELECT order_estimated_delivery_date::date
        FROM staging.orders

        UNION ALL

        SELECT review_creation_date::date
        FROM staging.order_reviews

        UNION ALL

        SELECT review_answer_timestamp::date
        FROM staging.order_reviews

        UNION ALL

        SELECT first_contact_date
        FROM staging.marketing_qualified_leads

        UNION ALL

        SELECT won_date::date
        FROM staging.closed_deals

    ) dates

    WHERE date_value IS NOT NULL
),

calendar AS (

    SELECT
        GENERATE_SERIES(
            min_date,
            max_date,
            INTERVAL '1 day'
        )::date AS full_date

    FROM date_bounds
)

SELECT
    TO_CHAR(full_date, 'YYYYMMDD')::integer
        AS date_key,

    full_date,

    EXTRACT(YEAR FROM full_date)::integer
        AS year,

    EXTRACT(QUARTER FROM full_date)::integer
        AS quarter,

    EXTRACT(MONTH FROM full_date)::integer
        AS month_number,

    TO_CHAR(full_date, 'Month')
        AS month_name,

    TO_CHAR(full_date, 'Mon')
        AS month_short_name,

    TO_CHAR(full_date, 'YYYY-MM')
        AS year_month,

    EXTRACT(WEEK FROM full_date)::integer
        AS week_of_year,

    EXTRACT(ISODOW FROM full_date)::integer
        AS day_of_week,

    TO_CHAR(full_date, 'Day')
        AS day_name,

    CASE
        WHEN EXTRACT(ISODOW FROM full_date)
             IN (6, 7)
        THEN TRUE
        ELSE FALSE
    END AS is_weekend

FROM calendar;


ALTER TABLE analytics.dim_date
ADD CONSTRAINT pk_dim_date
PRIMARY KEY (date_key);


ALTER TABLE analytics.dim_date
ADD CONSTRAINT uq_dim_date_full_date
UNIQUE (full_date);


-- ============================================================
-- Customer Dimension
--
-- Grain:
-- one row per source customer_id
--
-- customer_unique_id identifies the underlying real customer.
-- Keeping customer_id as the dimension grain preserves the
-- geographic information associated with that purchase.
-- ============================================================

CREATE TABLE analytics.dim_customer AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY c.customer_id
    )::integer AS customer_key,

    c.customer_id,

    c.customer_unique_id,

    c.customer_zip_code_prefix,

    c.customer_city,

    c.customer_state,

    g.latitude,

    g.longitude,

    g.city AS geolocation_city,

    g.state AS geolocation_state,

    (g.zip_code_prefix IS NULL)
        AS is_geolocation_missing,

    COALESCE(
        g.distinct_city_count > 1,
        FALSE
    ) AS is_city_label_ambiguous,

    COALESCE(
        g.distinct_state_count > 1,
        FALSE
    ) AS is_state_ambiguous,

    CASE
        WHEN g.state IS NULL THEN NULL
        ELSE c.customer_state <> g.state
    END AS is_state_mismatch

FROM staging.customers c

LEFT JOIN staging.geolocation g
    ON c.customer_zip_code_prefix =
       g.zip_code_prefix;


ALTER TABLE analytics.dim_customer
ADD CONSTRAINT pk_dim_customer
PRIMARY KEY (customer_key);


ALTER TABLE analytics.dim_customer
ADD CONSTRAINT uq_dim_customer_id
UNIQUE (customer_id);


-- ============================================================
-- Product Dimension
-- Grain: one row per product
-- ============================================================

CREATE TABLE analytics.dim_product AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY p.product_id
    )::integer AS product_key,

    p.product_id,

    p.product_category_name
        AS product_category_name_source,

    COALESCE(
        t.product_category_name_english,
        p.product_category_name,
        'Unknown'
    ) AS product_category_name,

    p.product_name_length,
    p.product_description_length,
    p.product_photos_qty,

    CASE
        WHEN p.product_weight_g > 0
        THEN p.product_weight_g
        ELSE NULL
    END AS product_weight_g,

    CASE
        WHEN p.product_length_cm > 0
        THEN p.product_length_cm
        ELSE NULL
    END AS product_length_cm,

    CASE
        WHEN p.product_height_cm > 0
        THEN p.product_height_cm
        ELSE NULL
    END AS product_height_cm,

    CASE
        WHEN p.product_width_cm > 0
        THEN p.product_width_cm
        ELSE NULL
    END AS product_width_cm,

    (p.product_category_name IS NULL)
        AS is_category_missing,

    (
        p.product_category_name IS NOT NULL
        AND t.product_category_name IS NULL
    ) AS is_category_translation_missing,

    (
        COALESCE(p.product_weight_g, 0) <= 0
        OR COALESCE(p.product_length_cm, 0) <= 0
        OR COALESCE(p.product_height_cm, 0) <= 0
        OR COALESCE(p.product_width_cm, 0) <= 0
    ) AS has_missing_or_invalid_measurement

FROM staging.products p

LEFT JOIN staging.product_category_translation t
    ON p.product_category_name =
       t.product_category_name;


ALTER TABLE analytics.dim_product
ADD CONSTRAINT pk_dim_product
PRIMARY KEY (product_key);


ALTER TABLE analytics.dim_product
ADD CONSTRAINT uq_dim_product_id
UNIQUE (product_id);


-- ============================================================
-- Seller Dimension
-- Grain: one row per seller
-- ============================================================

CREATE TABLE analytics.dim_seller AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY s.seller_id
    )::integer AS seller_key,

    s.seller_id,

    s.seller_zip_code_prefix,

    s.seller_city,

    s.seller_state,

    g.latitude,

    g.longitude,

    g.city AS geolocation_city,

    g.state AS geolocation_state,

    (g.zip_code_prefix IS NULL)
        AS is_geolocation_missing,

    COALESCE(
        g.distinct_city_count > 1,
        FALSE
    ) AS is_city_label_ambiguous,

    COALESCE(
        g.distinct_state_count > 1,
        FALSE
    ) AS is_state_ambiguous,

    CASE
        WHEN g.state IS NULL THEN NULL
        ELSE s.seller_state <> g.state
    END AS is_state_mismatch

FROM staging.sellers s

LEFT JOIN staging.geolocation g
    ON s.seller_zip_code_prefix =
       g.zip_code_prefix;


ALTER TABLE analytics.dim_seller
ADD CONSTRAINT pk_dim_seller
PRIMARY KEY (seller_key);


ALTER TABLE analytics.dim_seller
ADD CONSTRAINT uq_dim_seller_id
UNIQUE (seller_id);


COMMIT;