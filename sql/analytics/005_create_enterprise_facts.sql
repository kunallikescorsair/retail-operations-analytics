BEGIN;

-- ============================================================
-- Enterprise Fact Tables
--
-- fact_inventory_monthly
--     Grain: one month / store / product
--
-- fact_store_plan
--     Grain: one month / store
--
-- fact_marketing_spend
--     Grain: one month / store / marketing channel
-- ============================================================

DROP TABLE IF EXISTS
    analytics.fact_marketing_spend,
    analytics.fact_store_plan,
    analytics.fact_inventory_monthly
CASCADE;


-- ============================================================
-- Monthly Inventory Fact
-- ============================================================

CREATE TABLE analytics.fact_inventory_monthly AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY
            i.snapshot_month,
            i.store_id,
            i.product_id
    )::integer AS inventory_key,

    d.date_key AS snapshot_date_key,
    ds.store_key,
    dp.product_key,
    dsp.supplier_key,

    i.opening_stock_qty,
    i.received_qty,
    i.sold_qty,
    i.closing_stock_qty,
    i.reorder_point,
    i.stockout_days,

    ROUND(
        (
            i.opening_stock_qty
            + i.closing_stock_qty
        ) / 2.0,
        2
    )::numeric(14, 2)
        AS average_stock_qty,

    pc.estimated_unit_cost,

    ROUND(
        i.sold_qty
        * pc.estimated_unit_cost,
        2
    )::numeric(14, 2)
        AS estimated_cogs_sold,

    ROUND(
        i.closing_stock_qty
        * pc.estimated_unit_cost,
        2
    )::numeric(14, 2)
        AS estimated_closing_inventory_value,

    ROUND(
        (
            (
                i.opening_stock_qty
                + i.closing_stock_qty
            ) / 2.0
        )
        * pc.estimated_unit_cost,
        2
    )::numeric(14, 2)
        AS estimated_average_inventory_value,

    (
        i.closing_stock_qty
        < i.reorder_point
    ) AS is_below_reorder_point,

    (
        i.stockout_days > 0
    ) AS had_stockout

FROM staging.inventory_snapshot i

INNER JOIN analytics.dim_date d
    ON i.snapshot_month = d.full_date

INNER JOIN analytics.dim_store ds
    ON i.store_id = ds.store_id

INNER JOIN analytics.dim_product dp
    ON i.product_id = dp.product_id

INNER JOIN staging.product_supplier_mapping psm
    ON i.product_id = psm.product_id

INNER JOIN analytics.dim_supplier dsp
    ON psm.supplier_id = dsp.supplier_id

INNER JOIN staging.product_cost pc
    ON i.product_id = pc.product_id;


ALTER TABLE analytics.fact_inventory_monthly
ADD CONSTRAINT pk_fact_inventory_monthly
PRIMARY KEY (inventory_key);


ALTER TABLE analytics.fact_inventory_monthly
ADD CONSTRAINT uq_fact_inventory_monthly_grain
UNIQUE (
    snapshot_date_key,
    store_key,
    product_key
);


ALTER TABLE analytics.fact_inventory_monthly
ADD CONSTRAINT fk_fact_inventory_date
FOREIGN KEY (snapshot_date_key)
REFERENCES analytics.dim_date(date_key);


ALTER TABLE analytics.fact_inventory_monthly
ADD CONSTRAINT fk_fact_inventory_store
FOREIGN KEY (store_key)
REFERENCES analytics.dim_store(store_key);


ALTER TABLE analytics.fact_inventory_monthly
ADD CONSTRAINT fk_fact_inventory_product
FOREIGN KEY (product_key)
REFERENCES analytics.dim_product(product_key);


ALTER TABLE analytics.fact_inventory_monthly
ADD CONSTRAINT fk_fact_inventory_supplier
FOREIGN KEY (supplier_key)
REFERENCES analytics.dim_supplier(supplier_key);


-- ============================================================
-- Store Planning Fact
--
-- Combines budget and target sources because they have the
-- same month/store grain.
-- ============================================================

CREATE TABLE analytics.fact_store_plan AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY
            b.budget_month,
            b.store_id
    )::integer AS store_plan_key,

    d.date_key AS plan_date_key,
    ds.store_key,

    b.sales_budget,
    b.freight_budget,
    b.operating_cost_budget,

    t.sales_target,
    t.order_target,
    t.margin_target_pct,

    ROUND(
        100.0
        * (
            t.sales_target
            - b.sales_budget
        )
        / NULLIF(
            b.sales_budget,
            0
        ),
        2
    )::numeric(8, 2)
        AS target_uplift_vs_budget_pct

FROM staging.monthly_store_budget b

INNER JOIN staging.sales_targets t
    ON b.budget_month = t.target_month
   AND b.store_id = t.store_id

INNER JOIN analytics.dim_date d
    ON b.budget_month = d.full_date

INNER JOIN analytics.dim_store ds
    ON b.store_id = ds.store_id;


ALTER TABLE analytics.fact_store_plan
ADD CONSTRAINT pk_fact_store_plan
PRIMARY KEY (store_plan_key);


ALTER TABLE analytics.fact_store_plan
ADD CONSTRAINT uq_fact_store_plan_grain
UNIQUE (
    plan_date_key,
    store_key
);


ALTER TABLE analytics.fact_store_plan
ADD CONSTRAINT fk_fact_store_plan_date
FOREIGN KEY (plan_date_key)
REFERENCES analytics.dim_date(date_key);


ALTER TABLE analytics.fact_store_plan
ADD CONSTRAINT fk_fact_store_plan_store
FOREIGN KEY (store_key)
REFERENCES analytics.dim_store(store_key);


-- ============================================================
-- Marketing Spend Fact
-- ============================================================

CREATE TABLE analytics.fact_marketing_spend AS

SELECT
    ROW_NUMBER() OVER (
        ORDER BY
            m.month,
            m.store_id,
            m.channel
    )::integer AS marketing_spend_key,

    d.date_key AS spend_date_key,
    ds.store_key,
    dc.marketing_channel_key,

    m.spend

FROM staging.marketing_spend m

INNER JOIN analytics.dim_date d
    ON m.month = d.full_date

INNER JOIN analytics.dim_store ds
    ON m.store_id = ds.store_id

INNER JOIN analytics.dim_marketing_channel dc
    ON m.channel = dc.channel;


ALTER TABLE analytics.fact_marketing_spend
ADD CONSTRAINT pk_fact_marketing_spend
PRIMARY KEY (marketing_spend_key);


ALTER TABLE analytics.fact_marketing_spend
ADD CONSTRAINT uq_fact_marketing_spend_grain
UNIQUE (
    spend_date_key,
    store_key,
    marketing_channel_key
);


ALTER TABLE analytics.fact_marketing_spend
ADD CONSTRAINT fk_fact_marketing_spend_date
FOREIGN KEY (spend_date_key)
REFERENCES analytics.dim_date(date_key);


ALTER TABLE analytics.fact_marketing_spend
ADD CONSTRAINT fk_fact_marketing_spend_store
FOREIGN KEY (store_key)
REFERENCES analytics.dim_store(store_key);


ALTER TABLE analytics.fact_marketing_spend
ADD CONSTRAINT fk_fact_marketing_spend_channel
FOREIGN KEY (marketing_channel_key)
REFERENCES analytics.dim_marketing_channel(
    marketing_channel_key
);


COMMIT;
