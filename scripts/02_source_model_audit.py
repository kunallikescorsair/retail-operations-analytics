from pathlib import Path

import pandas as pd


# ============================================================
# 1. Project paths
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[1]

ECOMMERCE_DIR = PROJECT_ROOT / "data" / "raw" / "olist_ecommerce"
MARKETING_DIR = PROJECT_ROOT / "data" / "raw" / "olist_marketing"

OUTPUT_DIR = PROJECT_ROOT / "docs" / "data_dictionary"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


# ============================================================
# 2. Load required datasets
# ============================================================

customers = pd.read_csv(
    ECOMMERCE_DIR / "olist_customers_dataset.csv"
)

orders = pd.read_csv(
    ECOMMERCE_DIR / "olist_orders_dataset.csv"
)

order_items = pd.read_csv(
    ECOMMERCE_DIR / "olist_order_items_dataset.csv"
)

payments = pd.read_csv(
    ECOMMERCE_DIR / "olist_order_payments_dataset.csv"
)

reviews = pd.read_csv(
    ECOMMERCE_DIR / "olist_order_reviews_dataset.csv"
)

products = pd.read_csv(
    ECOMMERCE_DIR / "olist_products_dataset.csv"
)

sellers = pd.read_csv(
    ECOMMERCE_DIR / "olist_sellers_dataset.csv"
)

closed_deals = pd.read_csv(
    MARKETING_DIR / "olist_closed_deals_dataset.csv"
)

mql = pd.read_csv(
    MARKETING_DIR / "olist_marketing_qualified_leads_dataset.csv"
)


# ============================================================
# 3. Helper: referential integrity test
# ============================================================

def foreign_key_check(
    child_df,
    child_column,
    parent_df,
    parent_column,
    relationship_name,
):
    child_values = child_df[child_column].dropna()

    parent_values = set(
        parent_df[parent_column].dropna()
    )

    missing_mask = ~child_values.isin(parent_values)

    missing_count = int(missing_mask.sum())

    return {
        "relationship": relationship_name,
        "child_rows": len(child_values),
        "unmatched_rows": missing_count,
        "unmatched_pct": round(
            missing_count / len(child_values) * 100,
            4,
        )
        if len(child_values) > 0
        else 0,
    }


# ============================================================
# 4. Referential integrity tests
# ============================================================

relationship_checks = []

relationship_checks.append(
    foreign_key_check(
        orders,
        "customer_id",
        customers,
        "customer_id",
        "orders.customer_id -> customers.customer_id",
    )
)

relationship_checks.append(
    foreign_key_check(
        order_items,
        "order_id",
        orders,
        "order_id",
        "order_items.order_id -> orders.order_id",
    )
)

relationship_checks.append(
    foreign_key_check(
        order_items,
        "product_id",
        products,
        "product_id",
        "order_items.product_id -> products.product_id",
    )
)

relationship_checks.append(
    foreign_key_check(
        order_items,
        "seller_id",
        sellers,
        "seller_id",
        "order_items.seller_id -> sellers.seller_id",
    )
)

relationship_checks.append(
    foreign_key_check(
        payments,
        "order_id",
        orders,
        "order_id",
        "payments.order_id -> orders.order_id",
    )
)

relationship_checks.append(
    foreign_key_check(
        reviews,
        "order_id",
        orders,
        "order_id",
        "reviews.order_id -> orders.order_id",
    )
)

relationship_checks.append(
    foreign_key_check(
        closed_deals,
        "mql_id",
        mql,
        "mql_id",
        "closed_deals.mql_id -> marketing_leads.mql_id",
    )
)

relationship_checks.append(
    foreign_key_check(
        closed_deals,
        "seller_id",
        sellers,
        "seller_id",
        "closed_deals.seller_id -> sellers.seller_id",
    )
)

relationship_df = pd.DataFrame(
    relationship_checks
)

relationship_df.to_csv(
    OUTPUT_DIR / "referential_integrity.csv",
    index=False,
)


# ============================================================
# 5. Composite-key checks
# ============================================================

composite_key_checks = []


def composite_key_test(
    df,
    columns,
    dataset_name,
):
    duplicate_count = int(
        df.duplicated(
            subset=columns
        ).sum()
    )

    composite_key_checks.append(
        {
            "dataset": dataset_name,
            "columns": " + ".join(columns),
            "rows": len(df),
            "duplicate_keys": duplicate_count,
            "is_unique": duplicate_count == 0,
        }
    )


composite_key_test(
    order_items,
    ["order_id", "order_item_id"],
    "olist_order_items_dataset",
)

composite_key_test(
    payments,
    ["order_id", "payment_sequential"],
    "olist_order_payments_dataset",
)

composite_key_test(
    reviews,
    ["review_id", "order_id"],
    "olist_order_reviews_dataset",
)

composite_key_df = pd.DataFrame(
    composite_key_checks
)

composite_key_df.to_csv(
    OUTPUT_DIR / "composite_key_checks.csv",
    index=False,
)


# ============================================================
# 6. Customer identity analysis
# ============================================================

customer_identity = customers.groupby(
    "customer_unique_id"
).agg(
    customer_id_count=("customer_id", "nunique")
).reset_index()

repeat_customers = customer_identity[
    customer_identity["customer_id_count"] > 1
]

customer_summary = pd.DataFrame(
    [
        {
            "customer_rows": len(customers),
            "unique_customer_ids": customers[
                "customer_id"
            ].nunique(),
            "unique_real_customers": customers[
                "customer_unique_id"
            ].nunique(),
            "repeat_customer_count": len(
                repeat_customers
            ),
            "max_customer_ids_for_one_person":
                customer_identity[
                    "customer_id_count"
                ].max(),
        }
    ]
)

customer_summary.to_csv(
    OUTPUT_DIR / "customer_identity_summary.csv",
    index=False,
)


# ============================================================
# 7. Order-level multiplicity
# ============================================================

order_multiplicity = pd.DataFrame(
    [
        {
            "metric": "orders",
            "value": orders["order_id"].nunique(),
        },
        {
            "metric": "orders_with_multiple_items",
            "value": (
                order_items.groupby("order_id").size() > 1
            ).sum(),
        },
        {
            "metric": "max_items_in_single_order",
            "value": order_items.groupby(
                "order_id"
            ).size().max(),
        },
        {
            "metric": "orders_with_multiple_payments",
            "value": (
                payments.groupby("order_id").size() > 1
            ).sum(),
        },
        {
            "metric": "max_payment_records_single_order",
            "value": payments.groupby(
                "order_id"
            ).size().max(),
        },
    ]
)

order_multiplicity.to_csv(
    OUTPUT_DIR / "order_multiplicity.csv",
    index=False,
)


# ============================================================
# 8. Console output
# ============================================================

print("\n" + "=" * 80)
print("REFERENTIAL INTEGRITY")
print("=" * 80)
print(
    relationship_df.to_string(
        index=False
    )
)


print("\n" + "=" * 80)
print("COMPOSITE KEY CHECKS")
print("=" * 80)
print(
    composite_key_df.to_string(
        index=False
    )
)


print("\n" + "=" * 80)
print("CUSTOMER IDENTITY")
print("=" * 80)
print(
    customer_summary.to_string(
        index=False
    )
)


print("\n" + "=" * 80)
print("ORDER MULTIPLICITY")
print("=" * 80)
print(
    order_multiplicity.to_string(
        index=False
    )
)


print("\nAudit complete.")