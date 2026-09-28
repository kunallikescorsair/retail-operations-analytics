BEGIN;

-- ============================================================
-- Rebuild core staging tables
-- ============================================================

DROP TABLE IF EXISTS
    staging.order_payments,
    staging.order_items,
    staging.orders,
    staging.products,
    staging.customers
CASCADE;


-- ============================================================
-- Customers
-- Grain: one row per customer_id
-- ============================================================

CREATE TABLE staging.customers AS
SELECT
    customer_id,
    customer_unique_id,

    -- Brazilian ZIP prefix is five digits.
    LPAD(customer_zip_code_prefix::text, 5, '0')
        AS customer_zip_code_prefix,

    TRIM(customer_city)
        AS customer_city,

    UPPER(TRIM(customer_state))
        AS customer_state

FROM raw.customers;


ALTER TABLE staging.customers
ADD CONSTRAINT pk_staging_customers
PRIMARY KEY (customer_id);


-- ============================================================
-- Products
-- Grain: one row per product_id
-- ============================================================

CREATE TABLE staging.products AS
SELECT
    product_id,

    NULLIF(TRIM(product_category_name), '')
        AS product_category_name,

    product_name_lenght::integer
        AS product_name_length,

    product_description_lenght::integer
        AS product_description_length,

    product_photos_qty::integer
        AS product_photos_qty,

    product_weight_g::integer
        AS product_weight_g,

    product_length_cm::integer
        AS product_length_cm,

    product_height_cm::integer
        AS product_height_cm,

    product_width_cm::integer
        AS product_width_cm

FROM raw.products;


ALTER TABLE staging.products
ADD CONSTRAINT pk_staging_products
PRIMARY KEY (product_id);


-- ============================================================
-- Orders
-- Grain: one row per order
-- ============================================================

CREATE TABLE staging.orders AS
SELECT
    order_id,
    customer_id,

    LOWER(TRIM(order_status))
        AS order_status,

    NULLIF(order_purchase_timestamp, '')::timestamp
        AS order_purchase_timestamp,

    NULLIF(order_approved_at, '')::timestamp
        AS order_approved_at,

    NULLIF(order_delivered_carrier_date, '')::timestamp
        AS order_delivered_carrier_date,

    NULLIF(order_delivered_customer_date, '')::timestamp
        AS order_delivered_customer_date,

    NULLIF(order_estimated_delivery_date, '')::timestamp
        AS order_estimated_delivery_date

FROM raw.orders;


ALTER TABLE staging.orders
ADD CONSTRAINT pk_staging_orders
PRIMARY KEY (order_id);


ALTER TABLE staging.orders
ADD CONSTRAINT fk_staging_orders_customer
FOREIGN KEY (customer_id)
REFERENCES staging.customers(customer_id);


-- ============================================================
-- Order items
-- Grain: one item sequence within one order
-- ============================================================

CREATE TABLE staging.order_items AS
SELECT
    order_id,
    order_item_id::integer
        AS order_item_id,

    product_id,
    seller_id,

    NULLIF(shipping_limit_date, '')::timestamp
        AS shipping_limit_date,

    ROUND(price::numeric, 2)::numeric(12, 2)
        AS price,

    ROUND(freight_value::numeric, 2)::numeric(12, 2)
        AS freight_value

FROM raw.order_items;


ALTER TABLE staging.order_items
ADD CONSTRAINT pk_staging_order_items
PRIMARY KEY (order_id, order_item_id);


ALTER TABLE staging.order_items
ADD CONSTRAINT fk_staging_order_items_order
FOREIGN KEY (order_id)
REFERENCES staging.orders(order_id);


ALTER TABLE staging.order_items
ADD CONSTRAINT fk_staging_order_items_product
FOREIGN KEY (product_id)
REFERENCES staging.products(product_id);


-- ============================================================
-- Order payments
-- Grain: one payment sequence within one order
-- ============================================================

CREATE TABLE staging.order_payments AS
SELECT
    order_id,

    payment_sequential::integer
        AS payment_sequential,

    LOWER(TRIM(payment_type))
        AS payment_type,

    payment_installments::integer
        AS payment_installments,

    ROUND(payment_value::numeric, 2)::numeric(12, 2)
        AS payment_value

FROM raw.order_payments;


ALTER TABLE staging.order_payments
ADD CONSTRAINT pk_staging_order_payments
PRIMARY KEY (
    order_id,
    payment_sequential
);


ALTER TABLE staging.order_payments
ADD CONSTRAINT fk_staging_order_payments_order
FOREIGN KEY (order_id)
REFERENCES staging.orders(order_id);


COMMIT;