BEGIN;

-- ============================================================
-- Rebuild extended staging tables
-- ============================================================

DROP TABLE IF EXISTS
    staging.closed_deals,
    staging.marketing_qualified_leads,
    staging.order_reviews,
    staging.sellers,
    staging.product_category_translation,
    staging.geolocation
CASCADE;


-- ============================================================
-- Sellers
-- Grain: one row per seller
-- ============================================================

CREATE TABLE staging.sellers AS
SELECT
    seller_id,

    LPAD(seller_zip_code_prefix::text, 5, '0')
        AS seller_zip_code_prefix,

    NULLIF(TRIM(seller_city), '')
        AS seller_city,

    UPPER(NULLIF(TRIM(seller_state), ''))
        AS seller_state

FROM raw.sellers;


ALTER TABLE staging.sellers
ADD CONSTRAINT pk_staging_sellers
PRIMARY KEY (seller_id);


-- ============================================================
-- Product category translation
-- Grain: one row per Portuguese category
-- ============================================================

CREATE TABLE staging.product_category_translation AS
SELECT
    NULLIF(TRIM(product_category_name), '')
        AS product_category_name,

    NULLIF(TRIM(product_category_name_english), '')
        AS product_category_name_english

FROM raw.product_category_translation;


ALTER TABLE staging.product_category_translation
ADD CONSTRAINT pk_staging_product_category_translation
PRIMARY KEY (product_category_name);


-- ============================================================
-- Order reviews
-- Grain: one review record associated with an order
-- ============================================================

CREATE TABLE staging.order_reviews AS
SELECT
    review_id,
    order_id,

    review_score::integer
        AS review_score,

    NULLIF(TRIM(review_comment_title), '')
        AS review_comment_title,

    NULLIF(TRIM(review_comment_message), '')
        AS review_comment_message,

    NULLIF(review_creation_date, '')::timestamp
        AS review_creation_date,

    NULLIF(review_answer_timestamp, '')::timestamp
        AS review_answer_timestamp

FROM raw.order_reviews;


ALTER TABLE staging.order_reviews
ADD CONSTRAINT pk_staging_order_reviews
PRIMARY KEY (review_id, order_id);


ALTER TABLE staging.order_reviews
ADD CONSTRAINT fk_staging_order_reviews_order
FOREIGN KEY (order_id)
REFERENCES staging.orders(order_id);


-- ============================================================
-- Geolocation
--
-- Raw grain:
-- multiple observations per ZIP-code prefix
--
-- Staging grain:
-- one representative row per ZIP-code prefix
-- ============================================================

CREATE TABLE staging.geolocation AS
SELECT
    LPAD(
        geolocation_zip_code_prefix::text,
        5,
        '0'
    ) AS zip_code_prefix,

    PERCENTILE_CONT(0.5)
        WITHIN GROUP (
            ORDER BY geolocation_lat
        ) AS latitude,

    PERCENTILE_CONT(0.5)
        WITHIN GROUP (
            ORDER BY geolocation_lng
        ) AS longitude,

    MODE()
        WITHIN GROUP (
            ORDER BY NULLIF(
                TRIM(geolocation_city),
                ''
            )
        ) AS city,

    MODE()
        WITHIN GROUP (
            ORDER BY UPPER(
                NULLIF(
                    TRIM(geolocation_state),
                    ''
                )
            )
        ) AS state,

    COUNT(*)::integer
        AS source_row_count,

    COUNT(
        DISTINCT NULLIF(
            TRIM(geolocation_city),
            ''
        )
    )::integer
        AS distinct_city_count,

    COUNT(
        DISTINCT UPPER(
            NULLIF(
                TRIM(geolocation_state),
                ''
            )
        )
    )::integer
        AS distinct_state_count

FROM raw.geolocation

GROUP BY
    geolocation_zip_code_prefix;


ALTER TABLE staging.geolocation
ADD CONSTRAINT pk_staging_geolocation
PRIMARY KEY (zip_code_prefix);


-- ============================================================
-- Marketing qualified leads
-- Grain: one row per marketing-qualified lead
-- ============================================================

CREATE TABLE staging.marketing_qualified_leads AS
SELECT
    mql_id,

    NULLIF(first_contact_date, '')::date
        AS first_contact_date,

    landing_page_id,

    LOWER(
        NULLIF(
            TRIM(origin),
            ''
        )
    ) AS origin

FROM raw.marketing_qualified_leads;


ALTER TABLE staging.marketing_qualified_leads
ADD CONSTRAINT pk_staging_marketing_qualified_leads
PRIMARY KEY (mql_id);


-- ============================================================
-- Closed deals
-- Grain: one row per converted marketing-qualified lead
-- ============================================================

CREATE TABLE staging.closed_deals AS
SELECT
    mql_id,
    seller_id,
    sdr_id,
    sr_id,

    NULLIF(won_date, '')::timestamp
        AS won_date,

    LOWER(
        NULLIF(
            TRIM(business_segment),
            ''
        )
    ) AS business_segment,

    LOWER(
        NULLIF(
            TRIM(lead_type),
            ''
        )
    ) AS lead_type,

    LOWER(
        NULLIF(
            TRIM(lead_behaviour_profile),
            ''
        )
    ) AS lead_behaviour_profile,

    has_company,
    has_gtin,

    LOWER(
        NULLIF(
            TRIM(average_stock),
            ''
        )
    ) AS average_stock,

    LOWER(
        NULLIF(
            TRIM(business_type),
            ''
        )
    ) AS business_type,

    declared_product_catalog_size::integer
        AS declared_product_catalog_size,

    ROUND(
        declared_monthly_revenue::numeric,
        2
    )::numeric(14, 2)
        AS declared_monthly_revenue,

    -- Do not enforce seller FK because only part of the
    -- marketing seller population appears in ecommerce.
    EXISTS (
        SELECT 1
        FROM staging.sellers s
        WHERE s.seller_id = cd.seller_id
    ) AS ecommerce_seller_match

FROM raw.closed_deals cd;


ALTER TABLE staging.closed_deals
ADD CONSTRAINT pk_staging_closed_deals
PRIMARY KEY (mql_id);


ALTER TABLE staging.closed_deals
ADD CONSTRAINT fk_staging_closed_deals_mql
FOREIGN KEY (mql_id)
REFERENCES staging.marketing_qualified_leads(mql_id);


COMMIT;