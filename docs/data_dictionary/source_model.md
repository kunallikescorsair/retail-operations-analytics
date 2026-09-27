# Olist Source Data Model

## 1. olist_customers_dataset

**Business meaning:** Customer identifier and geographic information associated with an order.

**Grain:** One row per `customer_id`.

**Primary key:** `customer_id`

**Important identity field:** `customer_unique_id`

`customer_id` is effectively order-specific. The same real customer may have multiple customer IDs across different purchases.

**Observed rows:** 99,441

**Observed unique real customers:** 96,096

**Known considerations:**
- Use `customer_unique_id` for repeat-customer and retention analysis.
- Use `customer_id` for joining customers to orders.

---

## 2. olist_orders_dataset

**Business meaning:** Order lifecycle and status information.

**Grain:** One row per order.

**Primary key:** `order_id`

**Foreign key:**
- `customer_id` → `olist_customers_dataset.customer_id`

**Observed rows:** 99,441

**Known considerations:**
- Delivery-related timestamps may legitimately be null depending on order status.
- Date fields arrive as strings and will be converted in staging.

---

## 3. olist_order_items_dataset

**Business meaning:** Individual items sold within an order.

**Grain:** One row per item sequence within an order.

**Composite primary key:**
- `order_id`
- `order_item_id`

**Foreign keys:**
- `order_id` → orders
- `product_id` → products
- `seller_id` → sellers

**Observed rows:** 112,650

**Known considerations:**
- 9,803 orders contain multiple item rows.
- Maximum observed item rows in one order: 21.
- This table must not be joined directly to payment records when aggregating monetary metrics without controlling grain.

---

## 4. olist_order_payments_dataset

**Business meaning:** Payment transactions associated with orders.

**Grain:** One payment sequence per order.

**Composite primary key:**
- `order_id`
- `payment_sequential`

**Foreign key:**
- `order_id` → orders

**Observed rows:** 103,886

**Known considerations:**
- 2,961 orders have multiple payment records.
- Maximum observed payment records for one order: 29.
- Payments should generally be aggregated to order level before joining to order-item metrics.

---

## 5. olist_order_reviews_dataset

**Business meaning:** Customer review scores and optional written feedback.

**Grain:** Review record associated with an order.

**Composite uniqueness confirmed:**
- `review_id`
- `order_id`

**Foreign key:**
- `order_id` → orders

**Observed rows:** 99,224

**Known considerations:**
- Review titles are missing for approximately 88% of rows.
- Review comments are missing for approximately 59% of rows.
- Missing text does not necessarily indicate bad data because written comments are optional.

---

## 6. olist_products_dataset

**Business meaning:** Product attributes and category information.

**Grain:** One row per product.

**Primary key:** `product_id`

**Observed rows:** 32,951

**Known considerations:**
- 610 products lack category/name-description metadata.
- Two products have missing physical dimension/weight values.
- Portuguese product categories may be translated using the category translation dataset.

---

## 7. olist_sellers_dataset

**Business meaning:** Marketplace seller geographic information.

**Grain:** One row per seller.

**Primary key:** `seller_id`

**Observed rows:** 3,095

---

## 8. olist_geolocation_dataset

**Business meaning:** Geographic coordinates associated with Brazilian ZIP-code prefixes.

**Grain:** Multiple geographic observations per ZIP-code prefix.

**Primary key:** None in the raw source.

**Observed rows:** 1,000,163

**Known considerations:**
- 261,831 exact duplicate rows (~26.18%).
- ZIP-code prefix is not unique.
- A representative geographic record will need to be produced during staging or dimensional modelling.
- Raw records will remain unchanged.

---

## 9. product_category_name_translation

**Business meaning:** Translation between Portuguese and English product-category names.

**Grain:** One row per source category.

**Primary key:** `product_category_name`

**Observed rows:** 71

---

## 10. olist_marketing_qualified_leads_dataset

**Business meaning:** Marketing-qualified leads captured by Olist.

**Grain:** One row per marketing-qualified lead.

**Primary key:** `mql_id`

**Observed rows:** 8,000

**Known considerations:**
- Marketing origin is missing for a small number of leads.

---

## 11. olist_closed_deals_dataset

**Business meaning:** Marketing-qualified leads that became sellers.

**Grain:** One row per converted marketing lead.

**Primary key:** `mql_id`

**Observed rows:** 842

**Foreign key:**
- `mql_id` → marketing-qualified leads

**Seller relationship:**
- `seller_id` can link to the ecommerce seller table only for a subset of rows.

**Observed ecommerce seller coverage:**
- 380 matched seller IDs
- 462 unmatched seller IDs
- ~45.13% matched
- ~54.87% unmatched

**Known considerations:**
- Seller performance analysis must use the matched seller subset.
- Unmatched records must not be discarded from marketing-funnel conversion analysis.
- Missing commercial profile fields are common and may reflect optional lead attributes.

---

# Source Relationship Model

```text
customers
    |
    | customer_id
    v
orders
    |
    +--------------------+
    |                    |
    v                    v
order_items          payments
    |                    |
    +--> products         |
    |                     |
    +--> sellers          |
                          |
orders -------------------+
    |
    +--> reviews


marketing_qualified_leads
        |
        | mql_id
        v
closed_deals
        |
        | seller_id
        v
sellers
  [partial relationship only]