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