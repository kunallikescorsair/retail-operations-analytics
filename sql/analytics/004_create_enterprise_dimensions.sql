BEGIN;

-- ============================================================
-- Enterprise Dimensions and Core Fact Enrichment
--
-- Adds:
--   dim_store
--   dim_supplier
--   dim_marketing_channel
--
-- Enriches existing ecommerce facts with store/supplier/cost
-- information while preserving their original grains.
-- ============================================================


-- ============================================================
-- Remove downstream enterprise facts if this script is rerun.
-- They are recreated by the next enterprise analytics script.
-- ============================================================

DROP TABLE IF EXISTS
    analytics.fact_marketing_spend,
    analytics.fact_store_plan,
    analytics.fact_inventory_monthly
CASCADE;


-- ============================================================
-- Remove previous enterprise relationships from core facts
-- ============================================================

ALTER TABLE analytics.fact_orders
DROP CONSTRAINT IF EXISTS fk_fact_orders_store;

ALTER TABLE analytics.fact_order_items
DROP CONSTRAINT IF EXISTS fk_fact_order_items_store;

ALTER TABLE analytics.fact_order_items
DROP CONSTRAINT IF EXISTS fk_fact_order_items_supplier;

ALTER TABLE analytics.fact_payments
DROP CONSTRAINT IF EXISTS fk_fact_payments_store;

ALTER TABLE analytics.fact_reviews
DROP CONSTRAINT IF EXISTS fk_fact_reviews_store;


ALTER TABLE analytics.fact_orders
DROP COLUMN IF EXISTS store_key;

ALTER TABLE analytics.fact_order_items
DROP COLUMN IF EXISTS store_key;

ALTER TABLE analytics.fact_order_items
DROP COLUMN IF EXISTS supplier_key;

ALTER TABLE analytics.fact_order_items
DROP COLUMN IF EXISTS estimated_unit_cost;

ALTER TABLE analytics.fact_order_items
DROP COLUMN IF EXISTS estimated_cogs;

ALTER TABLE analytics.fact_order_items
DROP COLUMN IF EXISTS estimated_gross_margin;

ALTER TABLE analytics.fact_order_items
DROP COLUMN IF EXISTS estimated_gross_margin_pct;

ALTER TABLE analytics.fact_payments
DROP COLUMN IF EXISTS store_key;

ALTER TABLE analytics.fact_reviews
DROP COLUMN IF EXISTS store_key;


DROP TABLE IF EXISTS
    analytics.dim_marketing_channel,
    analytics.dim_supplier,
    analytics.dim_store
CASCADE;


-- ============================================================
-- Extend dim_date for synthetic monthly planning dates
--
-- Some synthetic facts use the first day of a month, which can
-- predate the first transactional date in that month.
-- ============================================================

WITH enterprise_dates AS (

    SELECT snapshot_month AS full_date
    FROM staging.inventory_snapshot

    UNION

    SELECT budget_month
    FROM staging.monthly_store_budget

    UNION

    SELECT target_month
    FROM staging.sales_targets

    UNION

    SELECT month
    FROM staging.marketing_spend
),

missing_dates AS (

    SELECT DISTINCT e.full_date
    FROM enterprise_dates e

    LEFT JOIN analytics.dim_date d
        ON e.full_date = d.full_date

    WHERE e.full_date IS NOT NULL
      AND d.full_date IS NULL
)

INSERT INTO analytics.dim_date (
    date_key,
    full_date,
    year,
    quarter,
    month_number,
    month_name,
    month_short_name,
    year_month,
    week_of_year,
    day_of_week,
    day_name,
    is_weekend
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

FROM missing_dates

ON CONFLICT DO NOTHING;


-- ============================================================
-- Store Dimension
-- Grain: one row per synthetic operating location
-- ============================================================

CREATE TABLE analytics.dim_store AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY store_id
    )::integer AS store_key,

    store_id,
    store_name,
    city,
    state,
    latitude,
    longitude,
    store_format,
    opening_date,
    floor_area_sqm,

    TRUE AS is_synthetic

FROM staging.stores;


ALTER TABLE analytics.dim_store
ADD CONSTRAINT pk_dim_store
PRIMARY KEY (store_key);


ALTER TABLE analytics.dim_store
ADD CONSTRAINT uq_dim_store_id
UNIQUE (store_id);


-- ============================================================
-- Supplier Dimension
-- Grain: one row per synthetic supplier
-- ============================================================

CREATE TABLE analytics.dim_supplier AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY supplier_id
    )::integer AS supplier_key,

    supplier_id,
    supplier_name,
    supplier_state,
    supplier_rating,
    standard_lead_time_days,
    contractual_fill_rate_pct,

    TRUE AS is_synthetic

FROM staging.suppliers;


ALTER TABLE analytics.dim_supplier
ADD CONSTRAINT pk_dim_supplier
PRIMARY KEY (supplier_key);


ALTER TABLE analytics.dim_supplier
ADD CONSTRAINT uq_dim_supplier_id
UNIQUE (supplier_id);


-- ============================================================
-- Marketing Channel Dimension
-- Grain: one row per channel
-- ============================================================

CREATE TABLE analytics.dim_marketing_channel AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY channel
    )::integer AS marketing_channel_key,

    channel

FROM (
    SELECT DISTINCT channel
    FROM staging.marketing_spend
    WHERE channel IS NOT NULL
) x;


ALTER TABLE analytics.dim_marketing_channel
ADD CONSTRAINT pk_dim_marketing_channel
PRIMARY KEY (marketing_channel_key);


ALTER TABLE analytics.dim_marketing_channel
ADD CONSTRAINT uq_dim_marketing_channel
UNIQUE (channel);


-- ============================================================
-- fact_orders: add store
-- ============================================================

ALTER TABLE analytics.fact_orders
ADD COLUMN store_key integer;


UPDATE analytics.fact_orders f

SET store_key = d.store_key

FROM staging.order_store_assignment a

INNER JOIN analytics.dim_store d
    ON a.store_id = d.store_id

WHERE f.order_id = a.order_id;


ALTER TABLE analytics.fact_orders
ALTER COLUMN store_key SET NOT NULL;


ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fk_fact_orders_store
FOREIGN KEY (store_key)
REFERENCES analytics.dim_store(store_key);


-- ============================================================
-- fact_order_items:
-- add store, supplier and estimated profitability
-- ============================================================

ALTER TABLE analytics.fact_order_items
ADD COLUMN store_key integer;

ALTER TABLE analytics.fact_order_items
ADD COLUMN supplier_key integer;

ALTER TABLE analytics.fact_order_items
ADD COLUMN estimated_unit_cost numeric(14, 2);

ALTER TABLE analytics.fact_order_items
ADD COLUMN estimated_cogs numeric(14, 2);

ALTER TABLE analytics.fact_order_items
ADD COLUMN estimated_gross_margin numeric(14, 2);

ALTER TABLE analytics.fact_order_items
ADD COLUMN estimated_gross_margin_pct numeric(8, 2);


UPDATE analytics.fact_order_items f

SET store_key = d.store_key

FROM staging.order_store_assignment a

INNER JOIN analytics.dim_store d
    ON a.store_id = d.store_id

WHERE f.order_id = a.order_id;


UPDATE analytics.fact_order_items f

SET
    supplier_key = ds.supplier_key,

    estimated_unit_cost =
        pc.estimated_unit_cost,

    estimated_cogs =
        pc.estimated_unit_cost,

    estimated_gross_margin =
        ROUND(
            f.price
            - pc.estimated_unit_cost,
            2
        ),

    estimated_gross_margin_pct =
        ROUND(
            100.0
            * (
                f.price
                - pc.estimated_unit_cost
            )
            / NULLIF(f.price, 0),
            2
        )

FROM analytics.dim_product p

INNER JOIN staging.product_supplier_mapping m
    ON p.product_id = m.product_id

INNER JOIN analytics.dim_supplier ds
    ON m.supplier_id = ds.supplier_id

INNER JOIN staging.product_cost pc
    ON p.product_id = pc.product_id

WHERE f.product_key = p.product_key;


ALTER TABLE analytics.fact_order_items
ALTER COLUMN store_key SET NOT NULL;

ALTER TABLE analytics.fact_order_items
ALTER COLUMN supplier_key SET NOT NULL;

ALTER TABLE analytics.fact_order_items
ALTER COLUMN estimated_unit_cost SET NOT NULL;

ALTER TABLE analytics.fact_order_items
ALTER COLUMN estimated_cogs SET NOT NULL;

ALTER TABLE analytics.fact_order_items
ALTER COLUMN estimated_gross_margin SET NOT NULL;


ALTER TABLE analytics.fact_order_items
ADD CONSTRAINT fk_fact_order_items_store
FOREIGN KEY (store_key)
REFERENCES analytics.dim_store(store_key);


ALTER TABLE analytics.fact_order_items
ADD CONSTRAINT fk_fact_order_items_supplier
FOREIGN KEY (supplier_key)
REFERENCES analytics.dim_supplier(supplier_key);


-- ============================================================
-- fact_payments: add store
-- ============================================================

ALTER TABLE analytics.fact_payments
ADD COLUMN store_key integer;


UPDATE analytics.fact_payments f

SET store_key = d.store_key

FROM staging.order_store_assignment a

INNER JOIN analytics.dim_store d
    ON a.store_id = d.store_id

WHERE f.order_id = a.order_id;


ALTER TABLE analytics.fact_payments
ALTER COLUMN store_key SET NOT NULL;


ALTER TABLE analytics.fact_payments
ADD CONSTRAINT fk_fact_payments_store
FOREIGN KEY (store_key)
REFERENCES analytics.dim_store(store_key);


-- ============================================================
-- fact_reviews: add store
-- ============================================================

ALTER TABLE analytics.fact_reviews
ADD COLUMN store_key integer;


UPDATE analytics.fact_reviews f

SET store_key = d.store_key

FROM staging.order_store_assignment a

INNER JOIN analytics.dim_store d
    ON a.store_id = d.store_id

WHERE f.order_id = a.order_id;


ALTER TABLE analytics.fact_reviews
ALTER COLUMN store_key SET NOT NULL;


ALTER TABLE analytics.fact_reviews
ADD CONSTRAINT fk_fact_reviews_store
FOREIGN KEY (store_key)
REFERENCES analytics.dim_store(store_key);


COMMIT;
