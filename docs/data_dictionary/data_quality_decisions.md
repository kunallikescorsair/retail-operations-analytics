# Data Quality Decisions

## Purpose

This document records the treatment of data-quality issues identified during
profiling and staging validation. Raw source data remains unchanged.

---

## 1. Invalid Order Timelines

### Finding

Some orders contain timestamps that violate the expected lifecycle sequence.

Observed examples include:

- carrier delivery timestamp before order purchase
- customer delivery timestamp before carrier handoff

### Treatment

Original timestamps are retained.

Affected orders will receive quality flags and will be excluded from metrics that
depend on valid delivery durations.

No timestamps will be manually corrected because the source data does not provide
sufficient evidence to infer the correct values.

---

## 2. Delivered Orders Missing Delivery Date

### Finding

Eight orders have status `delivered` but no customer delivery timestamp.

### Treatment

Orders are retained.

Delivery-related duration metrics will be NULL for these records.

A missing-delivery-date quality flag will identify affected orders.

---

## 3. Orders Without Items

### Finding

Most orders without item records are associated with legitimate non-completed
lifecycle states such as:

- unavailable
- canceled
- created

A small number of shipped or invoiced orders also lack item records.

### Treatment

All orders are retained.

Orders without item records are flagged.

Sales metrics requiring item-level records will naturally exclude them.

---

## 4. Delivered Order Without Payment

### Finding

One delivered order has no corresponding payment record.

### Treatment

The order is retained.

Sales metrics may still use item-level values.

Payment-related metrics will treat the payment information as unavailable.

---

## 5. Zero Product Weight

### Finding

Four products have a recorded weight of zero grams.

### Treatment

The original value remains unchanged in the raw layer.

In business-ready models, zero product weight will be treated as unknown/NULL
because a zero physical weight is not analytically meaningful for these products.

Affected products will receive an invalid-weight quality flag.

---

## 6. Missing Product Category

### Finding

610 products do not contain product-category metadata.

### Treatment

Products are retained.

Business-ready dimensions will classify missing categories as `Unknown`.

No category will be inferred without supporting source information.

---

## 7. Payment Installments Equal to Zero

### Finding

Two credit-card payment records contain zero payment installments.

### Treatment

Records are retained.

The zero values will be flagged as anomalous.

No replacement value will be inferred.

---

## 8. Order Value vs Payment Reconciliation

### Finding

Item-level order value and recorded payment totals were independently aggregated
to order level.

Among 98,665 orders with both datasets available:

- 303 differ by more than 0.01
- 249 differ by more than 1
- 98 differ by more than 10
- 3 differ by more than 100
- maximum absolute difference is 182.81

Payment-scenario analysis found:

- 286 mismatches are single non-voucher payments
- 10 contain multiple payment records without vouchers
- 7 contain vouchers

Most mismatches therefore cannot be explained by split payments or vouchers using
the available source fields.

### Treatment

No values will be modified to force reconciliation.

For business reporting:

- merchandise sales will use `order_items.price`
- freight will use `order_items.freight_value`
- gross order value will use `price + freight_value`
- payment-method analysis will use `order_payments`
- payment values and item values will remain separate measures

Orders with differences greater than 0.01 will receive a reconciliation-quality
flag.

The discrepancy is documented as a source-data limitation.

---

## General Principle

Raw source data is immutable.

Data-quality problems are handled using one of four approaches:

1. retain as a valid business condition
2. retain and flag as an anomaly
3. convert invalid analytical values to NULL when defensible
4. exclude only from metrics directly affected by the anomaly

Records are not deleted solely because they contain unusual or incomplete values.