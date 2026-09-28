# Synthetic Enterprise Operations Design

## Purpose

The original Olist datasets provide strong ecommerce transaction data but do not
contain several operational datasets commonly available inside a retail company.

To support broader business-intelligence use cases, this project will generate a
documented synthetic enterprise operations layer.

Synthetic data will be clearly separated from source data and will never be
presented as original Olist information.

---

# Design Principles

Synthetic data must be:

- reproducible
- deterministic through a fixed random seed
- commercially plausible
- explicitly documented as synthetic
- linked to existing source entities where appropriate
- small enough to run locally
- large enough to demonstrate realistic BI workflows

Synthetic values must not overwrite original Olist values.

---

# Planned Synthetic Tables

## 1. Stores

File: data/synthetic/stores.csv

Grain: one row per synthetic store / fulfilment location.

Planned fields:

- store_id
- store_name
- city
- state
- latitude
- longitude
- store_format
- opening_date
- floor_area_sqm

Purpose:

- store performance
- regional analysis
- budget comparison
- inventory analysis

---

## 2. Order Store Assignment

File: data/synthetic/order_store_assignment.csv

Grain: one row per ecommerce order.

Planned fields:

- order_id
- store_id
- assignment_method

Orders will be assigned reproducibly to a synthetic operating location using
customer geography.

This enables store-level analysis without modifying the original order source.

---

## 3. Suppliers

File: data/synthetic/suppliers.csv

Grain: one row per synthetic supplier.

Planned fields:

- supplier_id
- supplier_name
- supplier_state
- supplier_rating
- standard_lead_time_days
- contractual_fill_rate_pct

Purpose:

- supplier performance
- sourcing analysis
- lead-time analysis

---

## 4. Product Supplier Mapping

File: data/synthetic/product_supplier_mapping.csv

Grain: one row per product.

Planned fields:

- product_id
- supplier_id

Each product will have one primary synthetic supplier.

---

## 5. Product Cost

File: data/synthetic/product_cost.csv

Grain: one row per product.

Planned fields:

- product_id
- estimated_unit_cost
- cost_ratio

Estimated cost will be generated using observed selling-price behaviour and
controlled category-level cost ratios.

Purpose:

- gross margin
- margin percentage
- category profitability
- product profitability

Synthetic cost must never be described as actual Olist cost.

---

## 6. Inventory Snapshot

File: data/synthetic/inventory_snapshot.csv

Grain: one row per selected product, store and month.

Planned fields:

- snapshot_month
- store_id
- product_id
- opening_stock_qty
- received_qty
- sold_qty
- closing_stock_qty
- reorder_point
- stockout_days

The inventory model will be generated around historical sales behaviour rather
than purely random values.

To keep the dataset practical, inventory snapshots may be limited to products
with meaningful historical sales activity.

Purpose:

- stockout analysis
- inventory turnover
- days of supply
- slow-moving products
- inventory availability

---

## 7. Monthly Store Budget

File: data/synthetic/monthly_store_budget.csv

Grain: one row per store and month.

Planned fields:

- budget_month
- store_id
- sales_budget
- freight_budget
- operating_cost_budget

Purpose:

- actual vs budget
- budget variance
- monthly performance monitoring

---

## 8. Sales Targets

File: data/synthetic/sales_targets.csv

Grain: one row per store and month.

Planned fields:

- target_month
- store_id
- sales_target
- order_target
- margin_target_pct

Purpose:

- target attainment
- performance scorecards
- store comparison

---

## 9. Marketing Spend

File: data/synthetic/marketing_spend.csv

Grain: one row per store, month and marketing channel.

Planned channels:

- paid_search
- social
- email
- display
- affiliate

Fields:

- month
- store_id
- channel
- spend

Purpose:

- marketing spend analysis
- sales-to-marketing comparison
- channel mix

---

# Time Period

Synthetic monthly operational data will align with the meaningful ecommerce
history available in the Olist transaction data.

The exact date range will be derived programmatically from the source data.

---

# Geographic Assignment

Synthetic stores will be positioned in major locations represented in the Olist
customer population.

Orders will be assigned using customer geographic information.

The assignment will be deterministic.

No synthetic store assignment will replace the customer's original city, state
or coordinates.

---

# Product Scope for Inventory

Inventory snapshots should not blindly create all products x all stores x all
months because this would create many meaningless combinations.

Products will instead be selected based on observed commercial activity.

The generation process should favour products with meaningful historical sales
volume.

---

# Financial Logic

## Gross Merchandise Value

Original source measure:

order item price

## Estimated COGS

Synthetic measure:

estimated unit cost x delivered quantity

## Gross Margin

Merchandise Value - Estimated COGS

## Gross Margin Percentage

Gross Margin / Merchandise Value

---

# Actual vs Budget

Actual commercial performance comes from the real transactional warehouse.

Budget and target values are synthetic planning measures.

The dashboard must clearly distinguish:

- Actual
- Budget
- Target

---

# Reproducibility

The generator will use a fixed random seed.

Running the generation script repeatedly with the same source data and seed
should reproduce the same synthetic datasets.

---

# Repository Separation

Original source files:

data/raw/

Generated synthetic enterprise data:

data/synthetic/

Processed outputs:

data/processed/

Synthetic datasets remain separate from original source datasets throughout the
pipeline.

---

# Disclosure

Portfolio documentation and dashboards must state that operational planning,
inventory, supplier, cost, store, budget, target and marketing datasets were
synthetically generated to extend the public ecommerce source into an
enterprise-style analytics environment.

The synthetic layer exists to demonstrate analytics engineering and BI
capabilities and must not be represented as historical Olist operational data.
