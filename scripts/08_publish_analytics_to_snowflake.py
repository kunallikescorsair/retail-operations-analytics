from getpass import getpass

import pandas as pd
import snowflake.connector
from snowflake.connector.pandas_tools import write_pandas


POSTGRES_DATABASE = "retail_operations_analytics"
POSTGRES_SCHEMA = "analytics"

SNOWFLAKE_ACCOUNT = "DYSVFLK-KN74571"
SNOWFLAKE_USER = "KUNALGRGEXTRA@GMAIL.COM"
SNOWFLAKE_ROLE = "RETAIL_ANALYTICS_ROLE"
SNOWFLAKE_WAREHOUSE = "RETAIL_ANALYTICS_WH"
SNOWFLAKE_DATABASE = "RETAIL_OPERATIONS_ANALYTICS"
SNOWFLAKE_SCHEMA = "ANALYTICS"


EXPECTED_TABLES = {
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
    return '"' + value.replace('"', '""') + '"'


def sf_identifier(value):
    return '"' + value.replace('"', '""') + '"'


def discover_postgres_tables(connection):
    query = """
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = %s
          AND table_type = 'BASE TABLE'
        ORDER BY table_name
    """

    with connection.cursor() as cursor:
        cursor.execute(
            query,
            (POSTGRES_SCHEMA,),
        )

        return [
            row[0]
            for row in cursor.fetchall()
        ]


def get_postgres_columns(
    connection,
    table_name,
):
    query = """
        SELECT
            column_name,
            data_type,
            udt_name,
            numeric_precision,
            numeric_scale,
            character_maximum_length,
            is_nullable
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
                table_name,
            ),
        )

        rows = cursor.fetchall()

    columns = []

    for row in rows:
        columns.append(
            {
                "column_name": row[0],
                "data_type": row[1],
                "udt_name": row[2],
                "numeric_precision": row[3],
                "numeric_scale": row[4],
                "character_maximum_length": row[5],
                "is_nullable": row[6],
            }
        )

    return columns


def postgres_to_snowflake_type(column):
    data_type = (
        column["data_type"]
        or ""
    ).lower()

    udt_name = (
        column["udt_name"]
        or ""
    ).lower()

    if data_type in {
        "smallint",
        "integer",
        "bigint",
    }:
        return "NUMBER(38,0)"

    if data_type in {
        "numeric",
        "decimal",
    }:
        precision = (
            column["numeric_precision"]
            or 38
        )

        scale = (
            column["numeric_scale"]
            or 0
        )

        precision = min(
            int(precision),
            38,
        )

        scale = max(
            0,
            int(scale),
        )

        if scale > precision:
            scale = precision

        return (
            f"NUMBER({precision},{scale})"
        )

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
        return "VARCHAR"

    if data_type in {
        "json",
        "jsonb",
    }:
        return "VARIANT"

    if udt_name == "uuid":
        return "VARCHAR"

    raise RuntimeError(
        "Unsupported PostgreSQL data type: "
        f"{data_type!r} "
        f"(udt_name={udt_name!r}) "
        f"for column "
        f"{column['column_name']!r}"
    )


def validate_table_inventory(tables):
    discovered = set(tables)

    missing = sorted(
        EXPECTED_TABLES - discovered
    )

    unexpected = sorted(
        discovered - EXPECTED_TABLES
    )

    print()
    print("=" * 78)
    print(
        "POSTGRESQL ANALYTICS TABLE INVENTORY"
    )
    print("=" * 78)

    for table in tables:
        print(f"FOUND  {table}")

    if missing:
        print()
        print("Missing expected tables:")

        for table in missing:
            print(f"  - {table}")

    if unexpected:
        print()
        print("Unexpected analytics tables:")

        for table in unexpected:
            print(f"  - {table}")

    if missing or unexpected:
        raise RuntimeError(
            "PostgreSQL analytics table "
            "inventory does not match the "
            "expected curated warehouse."
        )

    print()
    print(
        "PASS  Curated warehouse contains "
        f"{len(tables)} expected tables."
    )


def get_postgres_row_count(
    connection,
    table_name,
):
    query = (
        "SELECT COUNT(*) FROM "
        f"{pg_identifier(POSTGRES_SCHEMA)}."
        f"{pg_identifier(table_name)}"
    )

    with connection.cursor() as cursor:
        cursor.execute(query)

        return cursor.fetchone()[0]


def read_postgres_table(
    connection,
    table_name,
):
    query = (
        "SELECT * FROM "
        f"{pg_identifier(POSTGRES_SCHEMA)}."
        f"{pg_identifier(table_name)}"
    )

    with connection.cursor() as cursor:
        cursor.execute(query)

        rows = cursor.fetchall()

        columns = [
            (
                description.name
                if hasattr(
                    description,
                    "name",
                )
                else description[0]
            )
            for description
            in cursor.description
        ]

    return pd.DataFrame(
        rows,
        columns=columns,
    )


def normalize_dataframe(
    dataframe,
    metadata,
):
    dataframe = dataframe.copy()

    dataframe.columns = [
        str(column).upper()
        for column in dataframe.columns
    ]

    for column in metadata:
        source_name = column[
            "column_name"
        ]

        name = source_name.upper()

        data_type = (
            column["data_type"]
            or ""
        ).lower()

        if (
            data_type
            == "timestamp without time zone"
        ):
            dataframe[name] = (
                pd.to_datetime(
                    dataframe[name],
                    errors="coerce",
                )
            )

        elif (
            data_type
            == "timestamp with time zone"
        ):
            dataframe[name] = (
                pd.to_datetime(
                    dataframe[name],
                    errors="coerce",
                    utc=True,
                )
            )

        elif data_type == "date":
            converted = pd.to_datetime(
                dataframe[name],
                errors="coerce",
            )

            dataframe[name] = (
                converted.dt.date
            )

    return dataframe


def create_snowflake_table(
    connection,
    table_name,
    metadata,
):
    column_definitions = []

    for column in metadata:
        name = (
            column["column_name"]
            .upper()
        )

        snowflake_type = (
            postgres_to_snowflake_type(
                column
            )
        )

        column_definitions.append(
            f"{sf_identifier(name)} "
            f"{snowflake_type}"
        )

    ddl = (
        f"CREATE OR REPLACE TABLE "
        f"{sf_identifier(SNOWFLAKE_DATABASE)}."
        f"{sf_identifier(SNOWFLAKE_SCHEMA)}."
        f"{sf_identifier(table_name.upper())} "
        "(\n    "
        + ",\n    ".join(
            column_definitions
        )
        + "\n)"
    )

    cursor = connection.cursor()

    try:
        cursor.execute(ddl)

    finally:
        cursor.close()


def snowflake_row_count(
    connection,
    table_name,
):
    cursor = connection.cursor()

    try:
        cursor.execute(
            f"""
            SELECT COUNT(*)
            FROM
                {sf_identifier(SNOWFLAKE_DATABASE)}.
                {sf_identifier(SNOWFLAKE_SCHEMA)}.
                {sf_identifier(table_name.upper())}
            """
        )

        return cursor.fetchone()[0]

    finally:
        cursor.close()


def validate_snowflake_context(
    connection,
):
    cursor = connection.cursor()

    try:
        cursor.execute(
            """
            SELECT
                CURRENT_ORGANIZATION_NAME(),
                CURRENT_ACCOUNT_NAME(),
                CURRENT_USER(),
                CURRENT_ROLE(),
                CURRENT_REGION(),
                CURRENT_DATABASE(),
                CURRENT_SCHEMA(),
                CURRENT_WAREHOUSE()
            """
        )

        row = cursor.fetchone()

    finally:
        cursor.close()

    expected = [
        "DYSVFLK",
        "KN74571",
        "kunalgrgextra",
        SNOWFLAKE_ROLE,
        "AWS_AP_SOUTHEAST_2",
        SNOWFLAKE_DATABASE,
        SNOWFLAKE_SCHEMA,
        SNOWFLAKE_WAREHOUSE,
    ]

    labels = [
        "organization",
        "account",
        "user",
        "role",
        "region",
        "database",
        "schema",
        "warehouse",
    ]

    print()
    print("=" * 78)
    print("SNOWFLAKE CONTEXT")
    print("=" * 78)

    failures = []

    for label, actual, wanted in zip(
        labels,
        row,
        expected,
    ):
        passed = (
            str(actual).upper()
            == str(wanted).upper()
        )

        print(
            f"{'PASS' if passed else 'FAIL':<5} "
            f"{label:<13} {actual}"
        )

        if not passed:
            failures.append(label)

    if failures:
        raise RuntimeError(
            "Snowflake connection context "
            "validation failed: "
            + ", ".join(failures)
        )


def publish_table(
    pg_connection,
    sf_connection,
    table_name,
):
    source_count = (
        get_postgres_row_count(
            pg_connection,
            table_name,
        )
    )

    metadata = get_postgres_columns(
        pg_connection,
        table_name,
    )

    print()
    print("-" * 78)
    print(
        f"Publishing {table_name} "
        f"({source_count:,} PostgreSQL rows)"
    )
    print("-" * 78)

    if source_count == 0:
        raise RuntimeError(
            f"{table_name} contains "
            "zero rows."
        )

    dataframe = read_postgres_table(
        pg_connection,
        table_name,
    )

    if len(dataframe) != source_count:
        raise RuntimeError(
            f"{table_name}: fetched "
            f"{len(dataframe):,} rows "
            "but PostgreSQL reported "
            f"{source_count:,}."
        )

    dataframe = normalize_dataframe(
        dataframe,
        metadata,
    )

    create_snowflake_table(
        sf_connection,
        table_name,
        metadata,
    )

    success, chunks, rows_loaded, _ = (
        write_pandas(
            conn=sf_connection,
            df=dataframe,
            table_name=(
                table_name.upper()
            ),
            database=(
                SNOWFLAKE_DATABASE
            ),
            schema=(
                SNOWFLAKE_SCHEMA
            ),
            chunk_size=50_000,
            compression="gzip",
            parallel=4,
            quote_identifiers=True,
            use_logical_type=True,
            auto_create_table=False,
            overwrite=False,
        )
    )

    if not success:
        raise RuntimeError(
            "Snowflake COPY failed for "
            f"{table_name}."
        )

    destination_count = (
        snowflake_row_count(
            sf_connection,
            table_name,
        )
    )

    passed = (
        source_count
        == rows_loaded
        == destination_count
    )

    status = (
        "PASS"
        if passed
        else "FAIL"
    )

    print(
        f"{status}  "
        f"source={source_count:,}  "
        f"loaded={rows_loaded:,}  "
        f"snowflake="
        f"{destination_count:,}  "
        f"chunks={chunks}"
    )

    if not passed:
        raise RuntimeError(
            "Row-count reconciliation "
            f"failed for {table_name}."
        )

    return {
        "table": table_name,
        "postgres_rows":
            source_count,
        "snowflake_rows":
            destination_count,
        "status": status,
    }


def main():
    print("=" * 78)
    print(
        "POSTGRESQL -> SNOWFLAKE "
        "TYPED ANALYTICS PUBLISHER"
    )
    print("=" * 78)

    token = getpass(
        "Snowflake programmatic "
        "access token: "
    )

    pg_connection = None
    sf_connection = None

    try:
        print(
            "\nConnecting to PostgreSQL..."
        )

        pg_connection = (
            connect_postgres()
        )

        tables = (
            discover_postgres_tables(
                pg_connection
            )
        )

        validate_table_inventory(
            tables
        )

        print(
            "\nConnecting to Snowflake..."
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
                    "analytics_typed_publish"
                },
            )
        )

        validate_snowflake_context(
            sf_connection
        )

        print()
        print("=" * 78)
        print(
            "PUBLISHING TYPED "
            "CURATED TABLES"
        )
        print("=" * 78)

        results = []

        for index, table_name in enumerate(
            tables,
            start=1,
        ):
            print(
                f"\n[{index}/{len(tables)}]"
            )

            result = publish_table(
                pg_connection,
                sf_connection,
                table_name,
            )

            results.append(result)

        print()
        print("=" * 78)
        print(
            "FINAL ROW-COUNT "
            "RECONCILIATION"
        )
        print("=" * 78)

        print(
            f"{'TABLE':<30}"
            f"{'POSTGRES':>14}"
            f"{'SNOWFLAKE':>14}"
            f"{'STATUS':>10}"
        )

        print("-" * 68)

        for result in results:
            print(
                f"{result['table']:<30}"
                f"{result['postgres_rows']:>14,}"
                f"{result['snowflake_rows']:>14,}"
                f"{result['status']:>10}"
            )

        total_pg = sum(
            item["postgres_rows"]
            for item in results
        )

        total_sf = sum(
            item["snowflake_rows"]
            for item in results
        )

        print("-" * 68)

        print(
            f"{'TOTAL':<30}"
            f"{total_pg:>14,}"
            f"{total_sf:>14,}"
        )

        if total_pg != total_sf:
            raise RuntimeError(
                "Overall row-count "
                "reconciliation failed."
            )

        print()
        print(
            "PASS  All typed analytics "
            "tables published successfully."
        )

        print(
            "PASS  PostgreSQL and Snowflake "
            "row counts reconcile."
        )

    finally:
        if pg_connection is not None:
            pg_connection.close()

        if sf_connection is not None:
            sf_connection.close()


if __name__ == "__main__":
    main()
