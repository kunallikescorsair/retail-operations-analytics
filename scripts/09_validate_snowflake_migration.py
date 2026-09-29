from datetime import date, datetime
from decimal import Decimal
from getpass import getpass

import snowflake.connector


POSTGRES_DATABASE = "retail_operations_analytics"
POSTGRES_SCHEMA = "analytics"

SNOWFLAKE_ACCOUNT = "DYSVFLK-KN74571"
SNOWFLAKE_USER = "KUNALGRGEXTRA@GMAIL.COM"
SNOWFLAKE_ROLE = "RETAIL_ANALYTICS_ROLE"
SNOWFLAKE_WAREHOUSE = "RETAIL_ANALYTICS_WH"
SNOWFLAKE_DATABASE = "RETAIL_OPERATIONS_ANALYTICS"
SNOWFLAKE_SCHEMA = "ANALYTICS"


EXPECTED_TABLES = [
    "dim_customer",
    "dim_date",
    "dim_marketing_channel",
    "dim_order_status",
    "dim_product",
    "dim_seller",
    "dim_store",
    "dim_supplier",
    "fact_inventory_monthly",
    "fact_marketing_spend",
    "fact_order_items",
    "fact_orders",
    "fact_payments",
    "fact_reviews",
    "fact_store_plan",
]


CONTROL_METRICS = {
    "dim_date": {
        "row_count":
            "COUNT(*)",
        "min_full_date":
            "MIN(full_date)",
        "max_full_date":
            "MAX(full_date)",
    },

    "fact_orders": {
        "row_count":
            "COUNT(*)",

        "gross_order_value":
            "SUM(gross_order_value)",

        "valid_delivery_orders":
            """
            SUM(
                CASE
                    WHEN has_valid_delivery_timeline
                    THEN 1
                    ELSE 0
                END
            )
            """,

        "late_delivery_orders":
            """
            SUM(
                CASE
                    WHEN is_late_delivery
                    THEN 1
                    ELSE 0
                END
            )
            """,

        "min_purchase_timestamp":
            "MIN(order_purchase_timestamp)",

        "max_purchase_timestamp":
            "MAX(order_purchase_timestamp)",
    },

    "fact_order_items": {
        "row_count":
            "COUNT(*)",

        "merchandise_value":
            "SUM(price)",

        "estimated_cogs":
            "SUM(estimated_cogs)",

        "estimated_gross_margin":
            "SUM(estimated_gross_margin)",
    },

    "fact_payments": {
        "row_count":
            "COUNT(*)",

        "payment_value":
            "SUM(payment_value)",
    },

    "fact_reviews": {
        "row_count":
            "COUNT(*)",

        "review_score_total":
            "SUM(review_score)",

        "min_review_score":
            "MIN(review_score)",

        "max_review_score":
            "MAX(review_score)",
    },

    "fact_inventory_monthly": {
        "row_count":
            "COUNT(*)",

        "opening_stock":
            "SUM(opening_stock_qty)",

        "received_stock":
            "SUM(received_qty)",

        "sold_stock":
            "SUM(sold_qty)",

        "closing_stock":
            "SUM(closing_stock_qty)",

        "stockout_days":
            "SUM(stockout_days)",

        "stockout_rows":
            """
            SUM(
                CASE
                    WHEN had_stockout
                    THEN 1
                    ELSE 0
                END
            )
            """,

        "latest_snapshot_date_key":
            "MAX(snapshot_date_key)",
    },

    "fact_store_plan": {
        "row_count":
            "COUNT(*)",

        "sales_budget":
            "SUM(sales_budget)",

        "sales_target":
            "SUM(sales_target)",
    },

    "fact_marketing_spend": {
        "row_count":
            "COUNT(*)",

        "marketing_spend":
            "SUM(spend)",
    },
}


def connect_postgres():
    try:
        import psycopg

        return psycopg.connect(
            dbname=POSTGRES_DATABASE
        )

    except ImportError:
        import psycopg2

        return psycopg2.connect(
            dbname=POSTGRES_DATABASE
        )


def pg_identifier(value):
    return '"' + value.replace(
        '"',
        '""',
    ) + '"'


def sf_identifier(value):
    return '"' + value.replace(
        '"',
        '""',
    ) + '"'


def normalize(value):
    if value is None:
        return None

    if isinstance(value, Decimal):
        return value

    if isinstance(value, float):
        return Decimal(str(value))

    if isinstance(value, int):
        return Decimal(value)

    if isinstance(value, datetime):
        if value.tzinfo is not None:
            return value.isoformat()

        return value.isoformat(
            sep=" "
        )

    if isinstance(value, date):
        return value.isoformat()

    return str(value)


def values_equal(left, right):
    left = normalize(left)
    right = normalize(right)

    if (
        isinstance(left, Decimal)
        and isinstance(
            right,
            Decimal,
        )
    ):
        return (
            abs(left - right)
            <= Decimal("0.01")
        )

    return left == right


def expected_snowflake_family(
    pg_data_type,
):
    data_type = (
        pg_data_type
        or ""
    ).lower()

    if data_type in {
        "smallint",
        "integer",
        "bigint",
        "numeric",
        "decimal",
    }:
        return "NUMBER"

    if data_type in {
        "real",
        "double precision",
    }:
        return "FLOAT"

    if data_type == "boolean":
        return "BOOLEAN"

    if data_type == "date":
        return "DATE"

    if (
        data_type
        == "timestamp without time zone"
    ):
        return "TIMESTAMP_NTZ"

    if (
        data_type
        == "timestamp with time zone"
    ):
        return "TIMESTAMP_TZ"

    if data_type.startswith("time "):
        return "TIME"

    if data_type in {
        "text",
        "character varying",
        "character",
        "varchar",
        "char",
    }:
        return "TEXT"

    if data_type in {
        "json",
        "jsonb",
    }:
        return "VARIANT"

    raise RuntimeError(
        "Unsupported PostgreSQL type "
        f"for validation: {data_type}"
    )


def normalize_snowflake_family(
    snowflake_type,
):
    data_type = (
        snowflake_type
        or ""
    ).upper()

    if data_type in {
        "NUMBER",
        "DECIMAL",
        "NUMERIC",
        "FIXED",
    }:
        return "NUMBER"

    if data_type in {
        "FLOAT",
        "DOUBLE",
        "DOUBLE PRECISION",
        "REAL",
    }:
        return "FLOAT"

    if data_type in {
        "VARCHAR",
        "TEXT",
        "STRING",
        "CHAR",
        "CHARACTER",
    }:
        return "TEXT"

    if data_type.startswith(
        "TIMESTAMP_NTZ"
    ):
        return "TIMESTAMP_NTZ"

    if data_type.startswith(
        "TIMESTAMP_TZ"
    ):
        return "TIMESTAMP_TZ"

    if data_type.startswith(
        "TIMESTAMP_LTZ"
    ):
        return "TIMESTAMP_LTZ"

    return data_type


def postgres_columns(
    connection,
    table,
):
    query = """
        SELECT
            column_name,
            data_type
        FROM information_schema.columns
        WHERE table_schema = %s
          AND table_name = %s
        ORDER BY ordinal_position
    """

    with connection.cursor() as cursor:
        cursor.execute(
            query,
            (
                POSTGRES_SCHEMA,
                table,
            ),
        )

        return cursor.fetchall()


def snowflake_columns(
    connection,
    table,
):
    cursor = connection.cursor()

    try:
        cursor.execute(
            """
            SELECT
                COLUMN_NAME,
                DATA_TYPE
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = %s
              AND TABLE_NAME = %s
            ORDER BY ORDINAL_POSITION
            """,
            (
                SNOWFLAKE_SCHEMA,
                table.upper(),
            ),
        )

        return cursor.fetchall()

    finally:
        cursor.close()


def validate_columns_and_types(
    pg_connection,
    sf_connection,
    table,
):
    pg_columns = postgres_columns(
        pg_connection,
        table,
    )

    sf_columns = snowflake_columns(
        sf_connection,
        table,
    )

    if (
        len(pg_columns)
        != len(sf_columns)
    ):
        return (
            False,
            pg_columns,
            sf_columns,
            [
                "different column count"
            ],
        )

    issues = []

    for pg_column, sf_column in zip(
        pg_columns,
        sf_columns,
    ):
        pg_name = pg_column[0]
        pg_type = pg_column[1]

        sf_name = sf_column[0]
        sf_type = sf_column[1]

        if (
            pg_name.upper()
            != sf_name.upper()
        ):
            issues.append(
                f"name "
                f"{pg_name} != {sf_name}"
            )

            continue

        expected_family = (
            expected_snowflake_family(
                pg_type
            )
        )

        actual_family = (
            normalize_snowflake_family(
                sf_type
            )
        )

        if (
            expected_family
            != actual_family
        ):
            issues.append(
                f"{pg_name}: "
                f"PG={pg_type} -> "
                f"expected SF "
                f"{expected_family}, "
                f"actual SF={sf_type}"
            )

    return (
        len(issues) == 0,
        pg_columns,
        sf_columns,
        issues,
    )


def postgres_null_counts(
    connection,
    table,
    columns,
):
    expressions = []

    for column in columns:
        identifier = pg_identifier(
            column
        )

        expressions.append(
            f"""
            SUM(
                CASE
                    WHEN {identifier}
                         IS NULL
                    THEN 1
                    ELSE 0
                END
            )
            """
        )

    query = (
        "SELECT "
        + ", ".join(expressions)
        + " FROM "
        + f"{pg_identifier(POSTGRES_SCHEMA)}."
        + f"{pg_identifier(table)}"
    )

    with connection.cursor() as cursor:
        cursor.execute(query)

        values = cursor.fetchone()

    return dict(
        zip(
            columns,
            values,
        )
    )


def snowflake_null_counts(
    connection,
    table,
    columns,
):
    expressions = []

    for column in columns:
        identifier = sf_identifier(
            column.upper()
        )

        expressions.append(
            f"""
            SUM(
                CASE
                    WHEN {identifier}
                         IS NULL
                    THEN 1
                    ELSE 0
                END
            )
            """
        )

    query = (
        "SELECT "
        + ", ".join(expressions)
        + " FROM "
        + f"{sf_identifier(SNOWFLAKE_DATABASE)}."
        + f"{sf_identifier(SNOWFLAKE_SCHEMA)}."
        + f"{sf_identifier(table.upper())}"
    )

    cursor = connection.cursor()

    try:
        cursor.execute(query)
        values = cursor.fetchone()

    finally:
        cursor.close()

    return dict(
        zip(
            columns,
            values,
        )
    )


def run_postgres_metrics(
    connection,
    table,
    metrics,
):
    names = list(
        metrics.keys()
    )

    expressions = list(
        metrics.values()
    )

    query = (
        "SELECT "
        + ", ".join(expressions)
        + " FROM "
        + f"{pg_identifier(POSTGRES_SCHEMA)}."
        + f"{pg_identifier(table)}"
    )

    with connection.cursor() as cursor:
        cursor.execute(query)

        row = cursor.fetchone()

    return dict(
        zip(
            names,
            row,
        )
    )


def run_snowflake_metrics(
    connection,
    table,
    metrics,
):
    names = list(
        metrics.keys()
    )

    expressions = list(
        metrics.values()
    )

    query = (
        "SELECT "
        + ", ".join(expressions)
        + " FROM "
        + f"{sf_identifier(SNOWFLAKE_DATABASE)}."
        + f"{sf_identifier(SNOWFLAKE_SCHEMA)}."
        + f"{sf_identifier(table.upper())}"
    )

    cursor = connection.cursor()

    try:
        cursor.execute(query)

        row = cursor.fetchone()

    finally:
        cursor.close()

    return dict(
        zip(
            names,
            row,
        )
    )


def main():
    print("=" * 78)
    print(
        "POSTGRESQL <-> SNOWFLAKE "
        "MIGRATION VALIDATION"
    )
    print("=" * 78)

    token = getpass(
        "Snowflake programmatic "
        "access token: "
    )

    pg_connection = None
    sf_connection = None

    failures = []

    try:
        pg_connection = (
            connect_postgres()
        )

        sf_connection = (
            snowflake.connector.connect(
                account=(
                    SNOWFLAKE_ACCOUNT
                ),
                user=(
                    SNOWFLAKE_USER
                ),
                password=token,
                role=(
                    SNOWFLAKE_ROLE
                ),
                warehouse=(
                    SNOWFLAKE_WAREHOUSE
                ),
                database=(
                    SNOWFLAKE_DATABASE
                ),
                schema=(
                    SNOWFLAKE_SCHEMA
                ),
                session_parameters={
                    "QUERY_TAG":
                    "retail_operations_"
                    "analytics_validation"
                },
            )
        )

        print()
        print("=" * 78)
        print(
            "1. COLUMN AND DATA-TYPE "
            "VALIDATION"
        )
        print("=" * 78)

        table_columns = {}

        for table in EXPECTED_TABLES:
            (
                passed,
                pg_columns,
                _,
                issues,
            ) = validate_columns_and_types(
                pg_connection,
                sf_connection,
                table,
            )

            status = (
                "PASS"
                if passed
                else "FAIL"
            )

            print(
                f"{status:<5} "
                f"{table:<30} "
                f"columns={len(pg_columns)}"
            )

            if not passed:
                for issue in issues:
                    print(
                        f"      {issue}"
                    )

                failures.append(
                    f"{table}: "
                    "column/type structure"
                )

            table_columns[table] = [
                column[0]
                for column in pg_columns
            ]

        print()
        print("=" * 78)
        print(
            "2. NULL-PATTERN "
            "RECONCILIATION"
        )
        print("=" * 78)

        for table in EXPECTED_TABLES:
            columns = table_columns[
                table
            ]

            pg_nulls = (
                postgres_null_counts(
                    pg_connection,
                    table,
                    columns,
                )
            )

            sf_nulls = (
                snowflake_null_counts(
                    sf_connection,
                    table,
                    columns,
                )
            )

            mismatches = []

            for column in columns:
                if (
                    pg_nulls[column]
                    != sf_nulls[column]
                ):
                    mismatches.append(
                        column
                    )

            if mismatches:
                print(
                    f"FAIL  {table:<30} "
                    "mismatched columns="
                    + ", ".join(
                        mismatches
                    )
                )

                failures.append(
                    f"{table}: "
                    "NULL patterns"
                )

            else:
                print(
                    f"PASS  {table:<30} "
                    f"{len(columns)} "
                    "columns"
                )

        print()
        print("=" * 78)
        print(
            "3. BUSINESS CONTROL TOTALS"
        )
        print("=" * 78)

        for table, metrics in (
            CONTROL_METRICS.items()
        ):
            pg_values = (
                run_postgres_metrics(
                    pg_connection,
                    table,
                    metrics,
                )
            )

            sf_values = (
                run_snowflake_metrics(
                    sf_connection,
                    table,
                    metrics,
                )
            )

            print()
            print(table)

            for metric in metrics:
                pg_value = pg_values[
                    metric
                ]

                sf_value = sf_values[
                    metric
                ]

                passed = values_equal(
                    pg_value,
                    sf_value,
                )

                status = (
                    "PASS"
                    if passed
                    else "FAIL"
                )

                print(
                    f"  {status:<5} "
                    f"{metric:<30} "
                    f"PG={pg_value} "
                    f"SF={sf_value}"
                )

                if not passed:
                    failures.append(
                        f"{table}: "
                        f"{metric}"
                    )

        print()
        print("=" * 78)
        print("4. FINAL RESULT")
        print("=" * 78)

        if failures:
            print(
                f"FAIL  {len(failures)} "
                "migration validation "
                "issue(s)."
            )

            for failure in failures:
                print(
                    f"  - {failure}"
                )

            raise RuntimeError(
                "Snowflake migration "
                "validation did not pass."
            )

        print(
            "PASS  Column structures "
            "and data types reconcile."
        )

        print(
            "PASS  NULL patterns "
            "reconcile."
        )

        print(
            "PASS  Business control "
            "totals reconcile."
        )

        print()
        print(
            "Snowflake analytics warehouse "
            "validated successfully."
        )

    finally:
        if pg_connection is not None:
            pg_connection.close()

        if sf_connection is not None:
            sf_connection.close()


if __name__ == "__main__":
    main()
