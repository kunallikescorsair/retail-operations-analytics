BEGIN;

-- ============================================================
-- Conformed Order Status Dimension
--
-- Allows order status to filter multiple fact tables consistently
-- without creating fact-to-fact relationships in Power BI.
-- ============================================================

-- Remove old foreign-key relationships if this script is rerun.
ALTER TABLE analytics.fact_orders
DROP CONSTRAINT IF EXISTS fk_fact_orders_order_status;

ALTER TABLE analytics.fact_order_items
DROP CONSTRAINT IF EXISTS fk_fact_order_items_order_status;

ALTER TABLE analytics.fact_payments
DROP CONSTRAINT IF EXISTS fk_fact_payments_order_status;

ALTER TABLE analytics.fact_reviews
DROP CONSTRAINT IF EXISTS fk_fact_reviews_order_status;


ALTER TABLE analytics.fact_orders
DROP COLUMN IF EXISTS order_status_key;

ALTER TABLE analytics.fact_order_items
DROP COLUMN IF EXISTS order_status_key;

ALTER TABLE analytics.fact_payments
DROP COLUMN IF EXISTS order_status_key;

ALTER TABLE analytics.fact_reviews
DROP COLUMN IF EXISTS order_status_key;


DROP TABLE IF EXISTS analytics.dim_order_status;


-- ============================================================
-- Dimension
-- Grain: one row per distinct order status
-- ============================================================

CREATE TABLE analytics.dim_order_status AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY order_status
    )::integer AS order_status_key,

    order_status,

    CASE
        WHEN order_status = 'delivered'
            THEN 'Completed'

        WHEN order_status IN (
            'canceled',
            'unavailable'
        )
            THEN 'Exception'

        WHEN order_status IN (
            'created',
            'approved',
            'invoiced',
            'processing',
            'shipped'
        )
            THEN 'In Progress'

        ELSE 'Other'
    END AS order_status_group

FROM (
    SELECT DISTINCT order_status
    FROM staging.orders
    WHERE order_status IS NOT NULL
) s;


ALTER TABLE analytics.dim_order_status
ADD CONSTRAINT pk_dim_order_status
PRIMARY KEY (order_status_key);


ALTER TABLE analytics.dim_order_status
ADD CONSTRAINT uq_dim_order_status
UNIQUE (order_status);


-- ============================================================
-- Add status key to fact_orders
-- ============================================================

ALTER TABLE analytics.fact_orders
ADD COLUMN order_status_key integer;


UPDATE analytics.fact_orders f

SET order_status_key = d.order_status_key

FROM analytics.dim_order_status d

WHERE f.order_status = d.order_status;


ALTER TABLE analytics.fact_orders
ALTER COLUMN order_status_key SET NOT NULL;


ALTER TABLE analytics.fact_orders
ADD CONSTRAINT fk_fact_orders_order_status
FOREIGN KEY (order_status_key)
REFERENCES analytics.dim_order_status(order_status_key);


-- ============================================================
-- Add status key to fact_order_items
-- ============================================================

ALTER TABLE analytics.fact_order_items
ADD COLUMN order_status_key integer;


UPDATE analytics.fact_order_items f

SET order_status_key = d.order_status_key

FROM staging.orders o

INNER JOIN analytics.dim_order_status d
    ON o.order_status = d.order_status

WHERE f.order_id = o.order_id;


ALTER TABLE analytics.fact_order_items
ALTER COLUMN order_status_key SET NOT NULL;


ALTER TABLE analytics.fact_order_items
ADD CONSTRAINT fk_fact_order_items_order_status
FOREIGN KEY (order_status_key)
REFERENCES analytics.dim_order_status(order_status_key);


-- ============================================================
-- Add status key to fact_payments
-- ============================================================

ALTER TABLE analytics.fact_payments
ADD COLUMN order_status_key integer;


UPDATE analytics.fact_payments f

SET order_status_key = d.order_status_key

FROM staging.orders o

INNER JOIN analytics.dim_order_status d
    ON o.order_status = d.order_status

WHERE f.order_id = o.order_id;


ALTER TABLE analytics.fact_payments
ALTER COLUMN order_status_key SET NOT NULL;


ALTER TABLE analytics.fact_payments
ADD CONSTRAINT fk_fact_payments_order_status
FOREIGN KEY (order_status_key)
REFERENCES analytics.dim_order_status(order_status_key);


-- ============================================================
-- Add status key to fact_reviews
-- ============================================================

ALTER TABLE analytics.fact_reviews
ADD COLUMN order_status_key integer;


UPDATE analytics.fact_reviews f

SET order_status_key = d.order_status_key

FROM staging.orders o

INNER JOIN analytics.dim_order_status d
    ON o.order_status = d.order_status

WHERE f.order_id = o.order_id;


ALTER TABLE analytics.fact_reviews
ALTER COLUMN order_status_key SET NOT NULL;


ALTER TABLE analytics.fact_reviews
ADD CONSTRAINT fk_fact_reviews_order_status
FOREIGN KEY (order_status_key)
REFERENCES analytics.dim_order_status(order_status_key);


COMMIT;
