from pathlib import Path

import numpy as np
import pandas as pd
from sqlalchemy import create_engine


DATA_DIR = Path("data/synthetic")
DATABASE_URL = "postgresql+psycopg2:///retail_operations_analytics"


def section(title):
    print("")
    print("=" * 72)
    print(title)
    print("=" * 72)


def main():
    engine = create_engine(DATABASE_URL)

    stores = pd.read_csv(DATA_DIR / "stores.csv")
    assignments = pd.read_csv(DATA_DIR / "order_store_assignment.csv")
    suppliers = pd.read_csv(DATA_DIR / "suppliers.csv")
    product_supplier = pd.read_csv(
        DATA_DIR / "product_supplier_mapping.csv"
    )
    product_cost = pd.read_csv(DATA_DIR / "product_cost.csv")
    inventory = pd.read_csv(DATA_DIR / "inventory_snapshot.csv")
    budgets = pd.read_csv(DATA_DIR / "monthly_store_budget.csv")
    targets = pd.read_csv(DATA_DIR / "sales_targets.csv")
    marketing = pd.read_csv(DATA_DIR / "marketing_spend.csv")

    orders = pd.read_sql(
        """
        SELECT
            order_id,
            order_status,
            order_purchase_timestamp,
            merchandise_value,
            freight_value,
            gross_order_value
        FROM analytics.fact_orders
        """,
        engine,
        parse_dates=["order_purchase_timestamp"],
    )

    delivered_items = pd.read_sql(
        """
        SELECT
            f.order_id,
            p.product_id,
            f.price
        FROM analytics.fact_order_items f
        INNER JOIN analytics.dim_product p
            ON f.product_key = p.product_key
        INNER JOIN analytics.dim_order_status s
            ON f.order_status_key = s.order_status_key
        WHERE s.order_status = 'delivered'
        """,
        engine,
    )

    section("1. SYNTHETIC DATASET INVENTORY")

    datasets = {
        "stores": stores,
        "order_store_assignment": assignments,
        "suppliers": suppliers,
        "product_supplier_mapping": product_supplier,
        "product_cost": product_cost,
        "inventory_snapshot": inventory,
        "monthly_store_budget": budgets,
        "sales_targets": targets,
        "marketing_spend": marketing,
    }

    for name, df in datasets.items():
        print(
            f"{name:<32} "
            f"{len(df):>10,} rows  "
            f"{len(df.columns):>2} columns"
        )

    section("2. ORDER STORE ASSIGNMENT METHODS")

    method_summary = (
        assignments["assignment_method"]
        .value_counts(dropna=False)
        .rename_axis("assignment_method")
        .reset_index(name="orders")
    )

    method_summary["pct"] = (
        100.0
        * method_summary["orders"]
        / len(assignments)
    ).round(2)

    print(method_summary.to_string(index=False))

    section("3. STORE COMMERCIAL DISTRIBUTION")

    order_store = orders.merge(
        assignments,
        on="order_id",
        how="left",
    )

    delivered = order_store[
        order_store["order_status"].eq("delivered")
    ].copy()

    store_performance = (
        delivered
        .groupby("store_id", as_index=False)
        .agg(
            delivered_orders=("order_id", "nunique"),
            gross_order_value=("gross_order_value", "sum"),
        )
        .merge(
            stores[
                [
                    "store_id",
                    "store_name",
                    "state",
                    "store_format",
                ]
            ],
            on="store_id",
            how="left",
        )
    )

    total_sales = store_performance[
        "gross_order_value"
    ].sum()

    store_performance["sales_share_pct"] = (
        100.0
        * store_performance["gross_order_value"]
        / total_sales
    ).round(2)

    store_performance["gross_order_value"] = (
        store_performance["gross_order_value"]
        .round(2)
    )

    store_performance = store_performance.sort_values(
        "gross_order_value",
        ascending=False,
    )

    print(
        store_performance[
            [
                "store_id",
                "state",
                "store_format",
                "delivered_orders",
                "gross_order_value",
                "sales_share_pct",
            ]
        ].to_string(index=False)
    )

    section("4. SUPPLIER DISTRIBUTION")

    print(
        suppliers[
            [
                "supplier_rating",
                "standard_lead_time_days",
                "contractual_fill_rate_pct",
            ]
        ].describe().round(2).to_string()
    )

    supplier_product_counts = (
        product_supplier["supplier_id"]
        .value_counts()
    )

    print("")
    print(
        f"Products per supplier: "
        f"min={supplier_product_counts.min()}, "
        f"median={supplier_product_counts.median():.0f}, "
        f"max={supplier_product_counts.max()}"
    )

    section("5. PRODUCT COST PLAUSIBILITY")

    cost_ratio = product_cost["cost_ratio"]

    print(
        f"Cost ratio min:    {cost_ratio.min():.4f}"
    )
    print(
        f"Cost ratio median: {cost_ratio.median():.4f}"
    )
    print(
        f"Cost ratio mean:   {cost_ratio.mean():.4f}"
    )
    print(
        f"Cost ratio max:    {cost_ratio.max():.4f}"
    )

    price_summary = (
        delivered_items
        .groupby("product_id", as_index=False)
        .agg(
            delivered_avg_price=("price", "mean"),
            delivered_units=("price", "size"),
        )
    )

    margin_check = price_summary.merge(
        product_cost,
        on="product_id",
        how="left",
    )

    margin_check["estimated_margin_pct"] = (
        100.0
        * (
            margin_check["delivered_avg_price"]
            - margin_check["estimated_unit_cost"]
        )
        / margin_check["delivered_avg_price"]
    )

    print("")
    print("Estimated product margin %:")
    print(
        margin_check["estimated_margin_pct"]
        .describe(
            percentiles=[0.05, 0.25, 0.5, 0.75, 0.95]
        )
        .round(2)
        .to_string()
    )

    section("6. INVENTORY PLAUSIBILITY")

    inventory_balance_error = (
        inventory["opening_stock_qty"]
        + inventory["received_qty"]
        - inventory["sold_qty"]
        - inventory["closing_stock_qty"]
    )

    print(
        f"Inventory rows: "
        f"{len(inventory):,}"
    )
    print(
        f"Distinct inventory products: "
        f"{inventory['product_id'].nunique():,}"
    )
    print(
        f"Distinct inventory stores: "
        f"{inventory['store_id'].nunique():,}"
    )
    print(
        f"Balance errors: "
        f"{(inventory_balance_error != 0).sum():,}"
    )
    print(
        f"Negative closing stock rows: "
        f"{(inventory['closing_stock_qty'] < 0).sum():,}"
    )
    print(
        f"Rows with stockout days > 0: "
        f"{(inventory['stockout_days'] > 0).sum():,}"
    )
    print(
        f"Stockout-row rate: "
        f"{100.0 * (inventory['stockout_days'] > 0).mean():.2f}%"
    )

    print("")
    print("Stockout days distribution:")
    print(
        inventory["stockout_days"]
        .describe(
            percentiles=[0.5, 0.75, 0.9, 0.95, 0.99]
        )
        .round(2)
        .to_string()
    )

    section("7. ACTUAL VS BUDGET / TARGET")

    delivered["month"] = (
        delivered["order_purchase_timestamp"]
        .dt.to_period("M")
        .dt.to_timestamp()
    )

    actual_monthly = (
        delivered
        .groupby(
            ["month", "store_id"],
            as_index=False,
        )
        .agg(
            actual_sales=("gross_order_value", "sum"),
            actual_orders=("order_id", "nunique"),
        )
    )

    budgets["budget_month"] = pd.to_datetime(
        budgets["budget_month"]
    )

    targets["target_month"] = pd.to_datetime(
        targets["target_month"]
    )

    plan = (
        budgets
        .merge(
            targets,
            left_on=["budget_month", "store_id"],
            right_on=["target_month", "store_id"],
            how="inner",
        )
        .merge(
            actual_monthly,
            left_on=["budget_month", "store_id"],
            right_on=["month", "store_id"],
            how="left",
        )
    )

    plan["actual_sales"] = (
        plan["actual_sales"].fillna(0)
    )

    plan["actual_orders"] = (
        plan["actual_orders"].fillna(0)
    )

    positive_actual = plan["actual_sales"] > 0

    sales_vs_budget = (
        100.0
        * plan.loc[positive_actual, "actual_sales"]
        / plan.loc[positive_actual, "sales_budget"]
    )

    sales_vs_target = (
        100.0
        * plan.loc[positive_actual, "actual_sales"]
        / plan.loc[positive_actual, "sales_target"]
    )

    print("Actual sales as % of budget:")
    print(
        sales_vs_budget
        .describe(
            percentiles=[0.05, 0.25, 0.5, 0.75, 0.95]
        )
        .round(2)
        .to_string()
    )

    print("")
    print("Actual sales as % of target:")
    print(
        sales_vs_target
        .describe(
            percentiles=[0.05, 0.25, 0.5, 0.75, 0.95]
        )
        .round(2)
        .to_string()
    )

    section("8. MARKETING SPEND PLAUSIBILITY")

    marketing["month"] = pd.to_datetime(
        marketing["month"]
    )

    marketing_monthly = (
        marketing
        .groupby(
            ["month", "store_id"],
            as_index=False,
        )
        .agg(marketing_spend=("spend", "sum"))
    )

    marketing_check = actual_monthly.merge(
        marketing_monthly,
        on=["month", "store_id"],
        how="left",
    )

    marketing_check["marketing_pct_sales"] = (
        100.0
        * marketing_check["marketing_spend"]
        / marketing_check["actual_sales"]
    )

    print("Marketing spend as % of sales:")
    print(
        marketing_check["marketing_pct_sales"]
        .describe(
            percentiles=[0.05, 0.25, 0.5, 0.75, 0.95]
        )
        .round(2)
        .to_string()
    )

    print("")
    print("Marketing channel totals:")

    channel_summary = (
        marketing
        .groupby("channel", as_index=False)
        .agg(spend=("spend", "sum"))
        .sort_values("spend", ascending=False)
    )

    channel_summary["share_pct"] = (
        100.0
        * channel_summary["spend"]
        / channel_summary["spend"].sum()
    ).round(2)

    channel_summary["spend"] = (
        channel_summary["spend"].round(2)
    )

    print(channel_summary.to_string(index=False))

    section("9. VALIDATION RESULT")

    assertions = []

    assertions.append(
        ("12 stores", len(stores) == 12)
    )

    assertions.append(
        (
            "all orders assigned",
            len(assignments) == len(orders)
            and assignments["store_id"].notna().all(),
        )
    )

    assertions.append(
        (
            "all products mapped to supplier",
            product_supplier["product_id"].nunique()
            == 32951,
        )
    )

    assertions.append(
        (
            "all products have cost",
            product_cost["product_id"].nunique()
            == 32951,
        )
    )

    assertions.append(
        (
            "cost ratios between 0 and 1",
            product_cost["cost_ratio"]
            .between(0, 1)
            .all(),
        )
    )

    assertions.append(
        (
            "inventory balances",
            (inventory_balance_error == 0).all(),
        )
    )

    assertions.append(
        (
            "no negative closing inventory",
            (inventory["closing_stock_qty"] >= 0).all(),
        )
    )

    stockout_rate = (
        inventory["stockout_days"] > 0
    ).mean()

    assertions.append(
        (
            "inventory contains meaningful stockouts",
            0.01 <= stockout_rate <= 0.20,
        )
    )

    assertions.append(
        (
            "budget and target grains align",
            len(budgets) == len(targets),
        )
    )

    assertions.append(
        (
            "five marketing channels per plan row",
            len(marketing) == len(budgets) * 5,
        )
    )

    failed = []

    for name, passed in assertions:
        status = "PASS" if passed else "FAIL"
        print(f"{status:<5} {name}")

        if not passed:
            failed.append(name)

    if failed:
        raise RuntimeError(
            "Validation failed: "
            + ", ".join(failed)
        )

    print("")
    print(
        "All structural and plausibility checks passed."
    )


if __name__ == "__main__":
    main()
