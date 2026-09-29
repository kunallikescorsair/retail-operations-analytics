BEGIN;

-- ============================================================
-- Enterprise Synthetic Staging Layer
-- ============================================================

DROP TABLE IF EXISTS
    staging.marketing_spend,
    staging.sales_targets,
    staging.monthly_store_budget,
    staging.inventory_snapshot,
    staging.product_cost,
    staging.product_supplier_mapping,
    staging.order_store_assignment,
    staging.suppliers,
    staging.stores
CASCADE;


-- ============================================================
-- Stores
-- Grain: one row per synthetic store
-- ============================================================

CREATE TABLE staging.stores AS
SELECT
    store_id::text,
    store_name::text,
    LOWER(NULLIF(TRIM(city), '')) AS city,
    UPPER(NULLIF(TRIM(state), '')) AS state,
    latitude::double precision,
    longitude::double precision,
    store_format::text,
    opening_date::date,
    floor_area_sqm::integer
FROM synthetic.stores;

ALTER TABLE staging.stores
ADD CONSTRAINT pk_staging_stores
PRIMARY KEY (store_id);


-- ============================================================
-- Order-store assignment
-- Grain: one row per order
-- ============================================================

CREATE TABLE staging.order_store_assignment AS
SELECT
    order_id::text,
    store_id::text,
    assignment_method::text
FROM synthetic.order_store_assignment;

ALTER TABLE staging.order_store_assignment
ADD CONSTRAINT pk_staging_order_store_assignment
PRIMARY KEY (order_id);

ALTER TABLE staging.order_store_assignment
ADD CONSTRAINT fk_staging_order_store_assignment_order
FOREIGN KEY (order_id)
REFERENCES staging.orders(order_id);

ALTER TABLE staging.order_store_assignment
ADD CONSTRAINT fk_staging_order_store_assignment_store
FOREIGN KEY (store_id)
REFERENCES staging.stores(store_id);


-- ============================================================
-- Suppliers
-- Grain: one row per supplier
-- ============================================================

CREATE TABLE staging.suppliers AS
SELECT
    supplier_id::text,
    supplier_name::text,
    UPPER(NULLIF(TRIM(supplier_state), ''))
        AS supplier_state,
    supplier_rating::numeric(4, 2),
    standard_lead_time_days::integer,
    contractual_fill_rate_pct::numeric(5, 2)
FROM synthetic.suppliers;

ALTER TABLE staging.suppliers
ADD CONSTRAINT pk_staging_suppliers
PRIMARY KEY (supplier_id);


-- ============================================================
-- Product-supplier mapping
-- Grain: one row per product
-- ============================================================

CREATE TABLE staging.product_supplier_mapping AS
SELECT
    product_id::text,
    supplier_id::text
FROM synthetic.product_supplier_mapping;

ALTER TABLE staging.product_supplier_mapping
ADD CONSTRAINT pk_staging_product_supplier_mapping
PRIMARY KEY (product_id);

ALTER TABLE staging.product_supplier_mapping
ADD CONSTRAINT fk_staging_product_supplier_product
FOREIGN KEY (product_id)
REFERENCES staging.products(product_id);

ALTER TABLE staging.product_supplier_mapping
ADD CONSTRAINT fk_staging_product_supplier_supplier
FOREIGN KEY (supplier_id)
REFERENCES staging.suppliers(supplier_id);


-- ============================================================
-- Product cost
-- Grain: one row per product
-- ============================================================

CREATE TABLE staging.product_cost AS
SELECT
    product_id::text,
    estimated_unit_cost::numeric(14, 2),
    cost_ratio::numeric(8, 4)
FROM synthetic.product_cost;

ALTER TABLE staging.product_cost
ADD CONSTRAINT pk_staging_product_cost
PRIMARY KEY (product_id);

ALTER TABLE staging.product_cost
ADD CONSTRAINT fk_staging_product_cost_product
FOREIGN KEY (product_id)
REFERENCES staging.products(product_id);


-- ============================================================
-- Inventory snapshots
-- Grain: one row per month/store/product combination
-- ============================================================

CREATE TABLE staging.inventory_snapshot AS
SELECT
    snapshot_month::date,
    store_id::text,
    product_id::text,
    opening_stock_qty::integer,
    received_qty::integer,
    sold_qty::integer,
    closing_stock_qty::integer,
    reorder_point::integer,
    stockout_days::integer
FROM synthetic.inventory_snapshot;

ALTER TABLE staging.inventory_snapshot
ADD CONSTRAINT pk_staging_inventory_snapshot
PRIMARY KEY (
    snapshot_month,
    store_id,
    product_id
);

ALTER TABLE staging.inventory_snapshot
ADD CONSTRAINT fk_staging_inventory_store
FOREIGN KEY (store_id)
REFERENCES staging.stores(store_id);

ALTER TABLE staging.inventory_snapshot
ADD CONSTRAINT fk_staging_inventory_product
FOREIGN KEY (product_id)
REFERENCES staging.products(product_id);


-- ============================================================
-- Monthly store budgets
-- Grain: one row per month/store
-- ============================================================

CREATE TABLE staging.monthly_store_budget AS
SELECT
    budget_month::date,
    store_id::text,
    sales_budget::numeric(14, 2),
    freight_budget::numeric(14, 2),
    operating_cost_budget::numeric(14, 2)
FROM synthetic.monthly_store_budget;

ALTER TABLE staging.monthly_store_budget
ADD CONSTRAINT pk_staging_monthly_store_budget
PRIMARY KEY (
    budget_month,
    store_id
);

ALTER TABLE staging.monthly_store_budget
ADD CONSTRAINT fk_staging_monthly_store_budget_store
FOREIGN KEY (store_id)
REFERENCES staging.stores(store_id);


-- ============================================================
-- Sales targets
-- Grain: one row per month/store
-- ============================================================

CREATE TABLE staging.sales_targets AS
SELECT
    target_month::date,
    store_id::text,
    sales_target::numeric(14, 2),
    order_target::integer,
    margin_target_pct::numeric(6, 2)
FROM synthetic.sales_targets;

ALTER TABLE staging.sales_targets
ADD CONSTRAINT pk_staging_sales_targets
PRIMARY KEY (
    target_month,
    store_id
);

ALTER TABLE staging.sales_targets
ADD CONSTRAINT fk_staging_sales_targets_store
FOREIGN KEY (store_id)
REFERENCES staging.stores(store_id);


-- ============================================================
-- Marketing spend
-- Grain: one row per month/store/channel
-- ============================================================

CREATE TABLE staging.marketing_spend AS
SELECT
    month::date,
    store_id::text,
    LOWER(NULLIF(TRIM(channel), '')) AS channel,
    spend::numeric(14, 2)
FROM synthetic.marketing_spend;

ALTER TABLE staging.marketing_spend
ADD CONSTRAINT pk_staging_marketing_spend
PRIMARY KEY (
    month,
    store_id,
    channel
);

ALTER TABLE staging.marketing_spend
ADD CONSTRAINT fk_staging_marketing_spend_store
FOREIGN KEY (store_id)
REFERENCES staging.stores(store_id);


COMMIT;
