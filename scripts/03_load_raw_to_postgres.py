from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text


# ============================================================
# 1. Configuration
# ============================================================

PROJECT_ROOT = Path(__file__).resolve().parents[1]

ECOMMERCE_DIR = PROJECT_ROOT / "data" / "raw" / "olist_ecommerce"
MARKETING_DIR = PROJECT_ROOT / "data" / "raw" / "olist_marketing"

DATABASE_NAME = "retail_operations_analytics"
SCHEMA_NAME = "raw"

engine = create_engine(
    f"postgresql+psycopg2:///{DATABASE_NAME}"
)


# ============================================================
# 2. Source file → PostgreSQL table mapping
# ============================================================

SOURCE_TABLES = {
    ECOMMERCE_DIR / "olist_customers_dataset.csv":
        "customers",

    ECOMMERCE_DIR / "olist_geolocation_dataset.csv":
        "geolocation",

    ECOMMERCE_DIR / "olist_order_items_dataset.csv":
        "order_items",

    ECOMMERCE_DIR / "olist_order_payments_dataset.csv":
        "order_payments",

    ECOMMERCE_DIR / "olist_order_reviews_dataset.csv":
        "order_reviews",

    ECOMMERCE_DIR / "olist_orders_dataset.csv":
        "orders",

    ECOMMERCE_DIR / "olist_products_dataset.csv":
        "products",

    ECOMMERCE_DIR / "olist_sellers_dataset.csv":
        "sellers",

    ECOMMERCE_DIR / "product_category_name_translation.csv":
        "product_category_translation",

    MARKETING_DIR / "olist_closed_deals_dataset.csv":
        "closed_deals",

    MARKETING_DIR / "olist_marketing_qualified_leads_dataset.csv":
        "marketing_qualified_leads",
}


# ============================================================
# 3. Validate source files
# ============================================================

print("=" * 80)
print("SOURCE FILE VALIDATION")
print("=" * 80)

for file_path in SOURCE_TABLES:
    if not file_path.exists():
        raise FileNotFoundError(
            f"Required source file not found: {file_path}"
        )

    print(f"OK: {file_path.name}")


# ============================================================
# 4. Load CSV files into PostgreSQL
# ============================================================

load_results = []

print("\n" + "=" * 80)
print("RAW DATA INGESTION")
print("=" * 80)

for file_path, table_name in SOURCE_TABLES.items():

    print(f"\nLoading {file_path.name}")
    print(f"Target: {SCHEMA_NAME}.{table_name}")

    df = pd.read_csv(file_path)

    source_rows = len(df)

    df.to_sql(
        name=table_name,
        con=engine,
        schema=SCHEMA_NAME,
        if_exists="replace",
        index=False,
        chunksize=10_000,
    )

    with engine.connect() as connection:
        database_rows = connection.execute(
            text(
                f'SELECT COUNT(*) '
                f'FROM "{SCHEMA_NAME}"."{table_name}"'
            )
        ).scalar_one()

    row_count_match = (
        source_rows == database_rows
    )

    load_results.append(
        {
            "table": f"{SCHEMA_NAME}.{table_name}",
            "source_rows": source_rows,
            "database_rows": database_rows,
            "row_count_match": row_count_match,
        }
    )

    print(
        f"Source rows:   {source_rows:,}\n"
        f"Database rows: {database_rows:,}\n"
        f"Match:         {row_count_match}"
    )

    if not row_count_match:
        raise ValueError(
            f"Row-count validation failed for "
            f"{table_name}: "
            f"source={source_rows}, "
            f"database={database_rows}"
        )


# ============================================================
# 5. Final validation summary
# ============================================================

results_df = pd.DataFrame(load_results)

print("\n" + "=" * 80)
print("INGESTION SUMMARY")
print("=" * 80)

print(
    results_df.to_string(
        index=False
    )
)

if not results_df["row_count_match"].all():
    raise RuntimeError(
        "One or more tables failed row-count validation."
    )

print("\nAll raw tables loaded successfully.")
print("All PostgreSQL row counts match the source CSV files.")

engine.dispose()