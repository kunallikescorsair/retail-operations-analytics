# Business KPI Dictionary

## Scope

These definitions form the metric contract for SQL analysis, Power BI and
stakeholder reporting.

Unless otherwise stated, commercial performance KPIs use completed
(`delivered`) orders.

---

## Delivered Orders

**Definition**

Number of orders with order status `delivered`.

**Fact**

`analytics.fact_orders`

**Formula**

```text
COUNT(order_id)
WHERE order_status = delivered
```

---

## Delivered Merchandise Value

**Definition**

Total item selling price associated with delivered orders.

Freight is excluded.

**Fact**

`analytics.fact_order_items`

**Formula**

```text
SUM(price)
WHERE order_status = delivered
```

---

## Delivered Freight Value

**Definition**

Total freight associated with delivered orders.

**Fact**

`analytics.fact_order_items`

**Formula**

```text
SUM(freight_value)
WHERE order_status = delivered
```

---

## Delivered Gross Order Value

**Definition**

Merchandise value plus freight value for delivered orders.

**Formula**

```text
Delivered Merchandise Value
+
Delivered Freight Value
```

This is the primary order-value measure.

It is not forced to equal customer payment value.

---

## Average Order Value

**Definition**

Average gross order value per delivered order.

**Formula**

```text
Delivered Gross Order Value
/
Delivered Orders
```

---

## Average Items per Order

**Definition**

Average number of item rows in delivered orders.

**Formula**

```text
SUM(item_count)
/
Delivered Orders
```

---

## Unique Customers

**Definition**

Number of unique real customers who have at least one delivered order.

Use `customer_unique_id`, not `customer_id`.

---

## Repeat Customers

**Definition**

Unique customers with at least two delivered orders.

---

## Repeat Customer Rate

**Definition**

Percentage of delivered-order customers who placed at least two delivered
orders.

**Formula**

```text
Repeat Customers
/
Unique Customers
```

---

## Late Deliveries

**Definition**

Delivered orders with a valid delivery timeline where actual customer delivery
occurred after estimated delivery.

Orders with invalid lifecycle timestamps are excluded.

---

## Late Delivery Rate

**Definition**

Late deliveries divided by delivered orders eligible for delivery-performance
measurement.

Eligible orders must have:

- valid delivery timeline
- customer delivery date
- estimated delivery date

---

## On-Time Delivery Rate

**Definition**

Percentage of eligible delivered orders delivered on or before the estimated
delivery date.

**Formula**

```text
1 - Late Delivery Rate
```

---

## Average Delivery Days

**Definition**

Average elapsed days between purchase and customer delivery.

Only delivered orders with a valid delivery timeline are included.

---

## Average Review Score

**Definition**

Average customer review score.

Review score range:

```text
1 to 5
```

For commercial dashboard reporting, delivered-order reviews should normally be
used unless another scope is explicitly stated.

---

## Positive Review Rate

**Definition**

Percentage of review records with score 4 or 5.

---

## Negative Review Rate

**Definition**

Percentage of review records with score 1 or 2.

---

## Cancellation Rate

**Definition**

Canceled orders divided by all orders.

This is an operational lifecycle KPI rather than a revenue KPI.

---

## Exception Rate

**Definition**

Orders whose order-status group is `Exception` divided by all orders.

The Exception group currently contains:

- canceled
- unavailable

---

## Freight Percentage

**Definition**

Freight as a percentage of gross delivered order value.

**Formula**

```text
Delivered Freight Value
/
Delivered Gross Order Value
```

---

## Payment Mix

**Definition**

Distribution of recorded payment value by payment method.

Authoritative fact:

`analytics.fact_payments`

Payment mix must not be interpreted as product-level sales because payment and
item facts have different grains.

---

## Product Performance

Primary commercial measures:

- delivered merchandise value
- delivered units/items
- delivered order count
- average item price
- freight value

Authoritative fact:

`analytics.fact_order_items`

---

## Seller Performance

Primary commercial measures:

- delivered merchandise value
- delivered item count
- delivered orders
- freight value

Authoritative fact:

`analytics.fact_order_items`

---

## Category Performance

Primary measures:

- delivered merchandise value
- item count
- order count
- average item price
- freight value

Authoritative fact:

`analytics.fact_order_items`

---

# Metric Governance

The dashboard must not:

- sum payment and merchandise values together
- join item and payment facts directly
- calculate customer retention using `customer_id`
- include invalid delivery timelines in duration KPIs
- interpret missing geographic coordinates as zero coordinates
- infer missing product categories

---

# Enterprise Operations KPI Contract

The enterprise operations layer combines original ecommerce transactions with
documented synthetic store, supplier, inventory, cost, budget, target and
marketing data.

Synthetic operational measures must never be represented as historical Olist
operational data.

## Commercial Scope

Unless otherwise stated:

- sales KPIs use delivered orders
- merchandise value uses original order-item price
- gross order value uses merchandise plus freight
- cost and margin measures use synthetic estimated product cost
- store assignments are synthetic operating-location assignments
- supplier attributes and mappings are synthetic
- inventory, budgets, targets and marketing spend are synthetic

---

## Estimated COGS

Grain:

order item

Definition:

estimated unit cost multiplied by item quantity represented by the order-item
row.

Because each Olist order-item row represents one purchased item, the warehouse
stores estimated unit cost directly as estimated COGS for that row.

This is a synthetic analytical estimate and is not actual Olist cost data.

---

## Estimated Gross Margin

Definition:

merchandise value minus estimated COGS

Formula:

Estimated Gross Margin =
Merchandise Value - Estimated COGS

---

## Estimated Gross Margin Percentage

Formula:

Estimated Gross Margin Percentage =
Estimated Gross Margin / Merchandise Value

The metric must be calculated from aggregated margin and merchandise value.

Do not average row-level margin percentages.

---

## Store Sales

Definition:

gross order value for delivered orders assigned to a synthetic operating
location.

Store assignments are generated deterministically using customer geography.

---

## Sales Budget

Synthetic monthly planning measure at store-month grain.

This must be labelled as Budget rather than Actual.

---

## Sales Target

Synthetic monthly commercial target at store-month grain.

This must be labelled as Target rather than Actual.

---

## Budget Attainment Percentage

Formula:

Actual Delivered Sales / Sales Budget

A value above 100 percent indicates actual sales exceeded budget.

---

## Target Attainment Percentage

Formula:

Actual Delivered Sales / Sales Target

A value above 100 percent indicates actual sales exceeded target.

---

## Inventory Snapshot Grain

Inventory is stored at:

month x store x product

Inventory balances are semi-additive.

Opening stock, closing stock and inventory value may be aggregated across stores
and products for the same snapshot date.

They must not be summed across multiple snapshot dates and interpreted as an
inventory balance.

---

## Current Units on Hand

Definition:

sum of closing stock quantity at the latest available inventory snapshot date.

The snapshot date must always be displayed with this KPI.

---

## Current Inventory Value

Definition:

sum of estimated closing inventory value at the latest available inventory
snapshot date.

Formula:

Closing Stock Quantity x Estimated Unit Cost

This is an estimated synthetic inventory valuation.

It must not be summed across months.

---

## Stockout Row Rate

Definition:

percentage of inventory snapshot rows where stockout days is greater than zero.

Formula:

Inventory Rows With Stockout /
Total Inventory Snapshot Rows

This measures stockout incidence across monthly store-product observations.

---

## Total Stockout Days

Definition:

sum of synthetic stockout days across inventory snapshot rows.

This is a period flow metric and may be aggregated across time.

---

## Below Reorder Rate

Definition:

percentage of inventory snapshot rows where closing stock is below the
configured reorder point.

For historical period analysis:

Below-Reorder Snapshot Rows /
Total Inventory Snapshot Rows

For current inventory analysis, the same calculation must be restricted to the
latest snapshot date.

---

## Supplier Commercial Performance

Supplier commercial measures use delivered order items assigned to each
synthetic primary supplier.

Typical measures include:

- delivered item rows
- delivered orders
- merchandise value
- estimated COGS
- estimated gross margin
- estimated gross margin percentage

Supplier rating, lead time and contractual fill rate are synthetic supplier
attributes.

---

## Marketing Spend

Synthetic marketing expenditure at:

month x store x channel

Channels:

- paid_search
- social
- email
- display
- affiliate

---

## Total Marketing Spend

Definition:

all marketing spend in the selected reporting period.

This includes store-months with and without delivered sales.

---

## Marketing Spend in Active Sales Months

Definition:

marketing spend where the same store-month has positive delivered sales.

This metric is useful when comparing marketing expenditure directly with
realized commercial activity.

---

## Marketing Spend in Zero-Sales Months

Definition:

marketing spend for store-months where delivered sales equal zero.

This must remain visible rather than being silently removed from total
marketing expenditure.

---

## Total Marketing Spend Percentage of Sales

Formula:

Total Marketing Spend /
Total Delivered Sales

Total marketing spend includes zero-sales store-months.

---

## Active-Month Marketing Spend Percentage of Sales

Formula:

Marketing Spend in Active Sales Months /
Total Delivered Sales

This measure excludes marketing expenditure from zero-sales store-months from
the numerator.

It is analytically distinct from Total Marketing Spend Percentage of Sales.

---

## Synthetic Data Disclosure

Operational planning, inventory, supplier, cost, store, budget, target and
marketing datasets were synthetically generated to extend the public ecommerce
source into an enterprise-style analytics environment.

The synthetic layer exists to demonstrate analytics engineering and business
intelligence capabilities and must not be represented as historical Olist
operational data.

