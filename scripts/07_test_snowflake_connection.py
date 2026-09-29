from getpass import getpass

import snowflake.connector


ACCOUNT = "DYSVFLK-KN74571"
USER = "KUNALGRGEXTRA@GMAIL.COM"
ROLE = "RETAIL_ANALYTICS_ROLE"
WAREHOUSE = "RETAIL_ANALYTICS_WH"
DATABASE = "RETAIL_OPERATIONS_ANALYTICS"
SCHEMA = "ANALYTICS"


def main():
    print("=" * 72)
    print("SNOWFLAKE CONNECTION TEST")
    print("=" * 72)

    token = getpass("Snowflake programmatic access token: ")

    connection = None

    try:
        connection = snowflake.connector.connect(
            account=ACCOUNT,
            user=USER,
            password=token,
            role=ROLE,
            warehouse=WAREHOUSE,
            database=DATABASE,
            schema=SCHEMA,
            session_parameters={
                "QUERY_TAG": "retail_operations_analytics"
            },
        )

        cursor = connection.cursor()

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

        labels = [
            "Organization",
            "Account",
            "User",
            "Role",
            "Region",
            "Database",
            "Schema",
            "Warehouse",
        ]

        print()
        print("=" * 72)
        print("CONNECTION CONTEXT")
        print("=" * 72)

        for label, value in zip(labels, row):
            print(f"{label:<14}: {value}")

        expected = {
            "Organization": "DYSVFLK",
            "Account": "KN74571",
            "User": "kunalgrgextra",
            "Role": "RETAIL_ANALYTICS_ROLE",
            "Region": "AWS_AP_SOUTHEAST_2",
            "Database": "RETAIL_OPERATIONS_ANALYTICS",
            "Schema": "ANALYTICS",
            "Warehouse": "RETAIL_ANALYTICS_WH",
        }

        actual = dict(zip(labels, row))

        print()
        print("=" * 72)
        print("VALIDATION")
        print("=" * 72)

        failures = []

        for key, expected_value in expected.items():
            actual_value = actual[key]

            passed = (
                str(actual_value).upper()
                == str(expected_value).upper()
            )

            status = "PASS" if passed else "FAIL"

            print(
                f"{status:<5} "
                f"{key:<14} "
                f"expected={expected_value} "
                f"actual={actual_value}"
            )

            if not passed:
                failures.append(key)

        if failures:
            raise RuntimeError(
                "Snowflake connection context validation failed: "
                + ", ".join(failures)
            )

        print()
        print("PASS  Snowflake PAT authentication successful.")
        print("PASS  Connection context validated.")

        cursor.close()

    finally:
        if connection is not None:
            connection.close()


if __name__ == "__main__":
    main()
