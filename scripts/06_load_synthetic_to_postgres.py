from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text


DATABASE_URL = (
    "postgresql+psycopg2:///retail_operations_analytics"
)

DATA_DIR = Path("data/synthetic")


DATASETS = {
    "stores": {
        "file": "stores.csv",
        "dates": ["opening_date"],
    },
    "order_store_assignment": {
        "file": "order_store_assignment.csv",
        "dates": [],
    },
    "suppliers": {
        "file": "suppliers.csv",
        "dates": [],
    },
    "product_supplier_mapping": {
        "file": "product_supplier_mapping.csv",
        "dates": [],
    },
    "product_cost": {
        "file": "product_cost.csv",
        "dates": [],
    },
    "inventory_snapshot": {
        "file": "inventory_snapshot.csv",
        "dates": ["snapshot_month"],
    },
    "monthly_store_budget": {
        "file": "monthly_store_budget.csv",
        "dates": ["budget_month"],
    },
    "sales_targets": {
        "file": "sales_targets.csv",
        "dates": ["target_month"],
    },
    "marketing_spend": {
        "file": "marketing_spend.csv",
        "dates": ["month"],
    },
}


def load_dataframe(path, date_columns):
    df = pd.read_csv(path)

    for column in date_columns:
        df[column] = pd.to_datetime(
            df[column]
        ).dt.date

    return df


def main():
    engine = create_engine(DATABASE_URL)

    print(
        "Loading synthetic enterprise data "
        "to PostgreSQL"
    )

    results = []

    for table_name, config in DATASETS.items():
        path = DATA_DIR / config["file"]

        df = load_dataframe(
            path,
            config["dates"],
        )

        source_rows = len(df)

        print(
            f"Loading synthetic.{table_name:<28} "
            f"{source_rows:>10,} rows"
        )

        df.to_sql(
            table_name,
            engine,
            schema="synthetic",
            if_exists="replace",
            index=False,
            chunksize=10000,
            method="multi",
        )

        with engine.connect() as connection:
            database_rows = connection.execute(
                text(
                    f"""
                    SELECT COUNT(*)
                    FROM synthetic.{table_name}
                    """
                )
            ).scalar_one()

        results.append(
            {
                "table": table_name,
                "source_rows": source_rows,
                "database_rows": database_rows,
                "matched": (
                    source_rows
                    == database_rows
                ),
            }
        )

        if source_rows != database_rows:
            raise RuntimeError(
                f"Row-count mismatch for "
                f"{table_name}: "
                f"{source_rows} source vs "
                f"{database_rows} database"
            )

    print("")
    print("=" * 72)
    print("LOAD VERIFICATION")
    print("=" * 72)

    for result in results:
        status = (
            "PASS"
            if result["matched"]
            else "FAIL"
        )

        print(
            f"{status:<5} "
            f"{result['table']:<30} "
            f"{result['source_rows']:>10,} "
            f"{result['database_rows']:>10,}"
        )

    print("")
    print(
        "All synthetic datasets loaded "
        "successfully."
    )


if __name__ == "__main__":
    main()
