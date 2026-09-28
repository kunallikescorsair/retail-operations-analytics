# Analytics Star Schema

## Purpose

The analytics layer provides a business-ready dimensional model for reporting,
SQL analysis and Power BI.

The design intentionally avoids fact-to-fact relationships. Shared business
dimensions filter each fact table independently.

---

## Dimensions

### analytics.dim_date

**Grain:** one row per calendar date.

Primary key:

- `date_key`

Contains:

- full date
- year
- quarter
- month
- year-month
- week
- weekday
- weekend indicator

The date dimension is role-playing.

Examples:

- purchase date
- approval date
- carrier date
- customer delivery date
- estimated delivery date
- shipping limit date
- review creation date
- review answer date

In Power BI, the primary business-date relationship can be active while
secondary date relationships may be inactive and activated through DAX when
required.

---

### analytics.dim_customer

**Grain:** one row per source `customer_id`.

`customer_unique_id` identifies the underlying real customer across multiple
orders.

The dimension remains at `customer_id` grain because customer records contain
order-specific geographic information.

Important fields include:

- customer ID
- customer unique ID
- ZIP-code prefix
- city
- state
- latitude
- longitude
- geolocation-quality flags

Use `customer_unique_id` for:

- unique-customer counts
- repeat-customer analysis
- retention analysis

---

### analytics.dim_product

**Grain:** one row per product.

Contains:

- product ID
- source category
- business-facing category
- product metadata
- physical measurements
- category-quality flags
- measurement-quality flags

English category translation is used where available.

Fallback hierarchy:

1. English category
2. original Portuguese category
3. `Unknown`

---

### analytics.dim_seller

**Grain:** one row per seller.

Contains:

- seller ID
- seller ZIP
- seller city/state
- representative latitude/longitude
- geographic-quality flags

---

### analytics.dim_order_status

**Grain:** one row per order status.

Status groups:

- Completed
- In Progress
- Exception
- Other

This is a conformed dimension shared by all core fact tables.

It allows one Power BI status filter to consistently filter orders, item sales,
payments and reviews without connecting fact tables together.

---

# Fact Tables

## analytics.fact_orders

**Grain:** one row per order.

Primary business key:

- `order_id`

Used for:

- order counts
- order-status analysis
- customer-level order analysis
- order value
- freight
- payment reconciliation
- delivery performance
- operational quality metrics

Important measures include:

- item count
- product count
- seller count
- merchandise value
- freight value
- gross order value
- payment value
- delivery days
- delivery variance
- payment reconciliation difference

Important quality flags include:

- has items
- has payment
- payment reconciliation issue
- carrier before purchase
- delivery before carrier
- missing delivery timestamp
- valid delivery timeline

---

## analytics.fact_order_items

**Grain:** one item sequence within one order.

Business key:

- `order_id`
- `order_item_id`

Used for:

- product performance
- seller performance
- category performance
- merchandise value
- freight analysis
- basket composition

Measures include:

- price
- freight value
- gross item value

This is the authoritative fact for product- and seller-level merchandise
analysis.

---

## analytics.fact_payments

**Grain:** one payment sequence within one order.

Business key:

- `order_id`
- `payment_sequential`

Used for:

- payment-method analysis
- installment analysis
- payment-value analysis

Payment value is intentionally kept separate from merchandise value because
source payment totals do not perfectly reconcile to order-item totals.

---

## analytics.fact_reviews

**Grain:** one review/order combination.

Business key:

- `review_id`
- `order_id`

Used for:

- review score
- customer satisfaction
- review-comment analysis
- review response time

---

# Relationship Rules

Dimensions filter facts using one-to-many relationships.

Core relationships:

```text
dim_customer
    |
    +---- fact_orders
    +---- fact_order_items
    +---- fact_payments
    +---- fact_reviews


dim_order_status
    |
    +---- fact_orders
    +---- fact_order_items
    +---- fact_payments
    +---- fact_reviews


dim_product
    |
    +---- fact_order_items


dim_seller
    |
    +---- fact_order_items


dim_date
    |
    +---- fact_orders
    +---- fact_order_items
    +---- fact_payments
    +---- fact_reviews
```

Fact tables must not be directly related to other fact tables.

---

# Monetary Measure Rules

## Merchandise Value

Authoritative source:

`fact_order_items.price`

or its order-level aggregate:

`fact_orders.merchandise_value`

---

## Freight Value

Authoritative source:

`fact_order_items.freight_value`

or its order-level aggregate:

`fact_orders.freight_value`

---

## Gross Order Value

Defined as:

```text
Merchandise Value + Freight Value
```

This is not forced to equal payment value.

---

## Payment Value

Authoritative source:

`fact_payments.payment_value`

Used for payment and tender analysis.

Payment totals and item totals remain separate because the source contains
documented reconciliation differences.

---

# Data Quality Principle

Raw source values remain unchanged.

The analytics layer:

- preserves valid business records
- flags anomalies
- converts clearly invalid analytical measurements to NULL where defensible
- excludes invalid timelines only from metrics affected by those anomalies
- never fabricates replacement business values