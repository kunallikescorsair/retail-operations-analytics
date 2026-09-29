from pathlib import Path

import numpy as np
import pandas as pd
from sqlalchemy import create_engine


SEED = 20260929
N_STORES = 12
N_SUPPLIERS = 60
MAX_INVENTORY_PRODUCTS = 1200
MIN_INVENTORY_PRODUCT_SALES = 5

OUTPUT_DIR = Path("data/synthetic")

DATABASE_URL = (
    "postgresql+psycopg2:///retail_operations_analytics"
)


def haversine_matrix(
    latitudes,
    longitudes,
    store_latitudes,
    store_longitudes,
):
    earth_radius_km = 6371.0088

    lat1 = np.radians(
        np.asarray(latitudes, dtype=float)
    )[:, None]

    lon1 = np.radians(
        np.asarray(longitudes, dtype=float)
    )[:, None]

    lat2 = np.radians(
        np.asarray(store_latitudes, dtype=float)
    )[None, :]

    lon2 = np.radians(
        np.asarray(store_longitudes, dtype=float)
    )[None, :]

    delta_lat = lat2 - lat1
    delta_lon = lon2 - lon1

    a = (
        np.sin(delta_lat / 2.0) ** 2
        + np.cos(lat1)
        * np.cos(lat2)
        * np.sin(delta_lon / 2.0) ** 2
    )

    return (
        2.0
        * earth_radius_km
        * np.arcsin(np.sqrt(a))
    )


def load_source_data(engine):
    print("Loading warehouse data...")

    orders = pd.read_sql(
        """
        SELECT
            f.order_id,
            f.order_status,
            f.order_purchase_timestamp,
            f.merchandise_value,
            f.freight_value,
            f.gross_order_value,
            c.customer_city,
            c.customer_state,
            c.latitude,
            c.longitude
        FROM analytics.fact_orders f
        INNER JOIN analytics.dim_customer c
            ON f.customer_key = c.customer_key
        """,
        engine,
        parse_dates=["order_purchase_timestamp"],
    )

    items = pd.read_sql(
        """
        SELECT
            f.order_id,
            p.product_id,
            p.product_category_name,
            f.price,
            f.freight_value,
            s.order_status
        FROM analytics.fact_order_items f
        INNER JOIN analytics.dim_product p
            ON f.product_key = p.product_key
        INNER JOIN analytics.dim_order_status s
            ON f.order_status_key =
               s.order_status_key
        """,
        engine,
    )

    products = pd.read_sql(
        """
        SELECT
            product_id,
            product_category_name
        FROM analytics.dim_product
        """,
        engine,
    )

    sellers = pd.read_sql(
        """
        SELECT
            seller_id,
            seller_state
        FROM analytics.dim_seller
        """,
        engine,
    )

    return orders, items, products, sellers


def build_stores(orders, rng):
    delivered = orders[
        orders["order_status"].eq("delivered")
        & orders["latitude"].notna()
        & orders["longitude"].notna()
        & orders["customer_state"].notna()
        & orders["customer_city"].notna()
    ].copy()

    city_stats = (
        delivered
        .groupby(
            ["customer_state", "customer_city"],
            as_index=False,
        )
        .agg(
            source_order_count=("order_id", "count"),
            latitude=("latitude", "median"),
            longitude=("longitude", "median"),
        )
        .sort_values(
            "source_order_count",
            ascending=False,
        )
    )

    state_stats = (
        delivered
        .groupby("customer_state")
        .size()
        .sort_values(ascending=False)
    )

    selected_rows = []
    selected_locations = set()

    top_state_count = min(
        10,
        len(state_stats),
    )

    for state in state_stats.head(
        top_state_count
    ).index:
        candidate = (
            city_stats[
                city_stats["customer_state"].eq(state)
            ]
            .sort_values(
                "source_order_count",
                ascending=False,
            )
            .iloc[0]
        )

        key = (
            candidate["customer_state"],
            candidate["customer_city"],
        )

        selected_locations.add(key)
        selected_rows.append(candidate)

    for _, candidate in city_stats.iterrows():
        if len(selected_rows) >= N_STORES:
            break

        key = (
            candidate["customer_state"],
            candidate["customer_city"],
        )

        if key in selected_locations:
            continue

        selected_locations.add(key)
        selected_rows.append(candidate)

    stores = pd.DataFrame(selected_rows).copy()

    stores = (
        stores
        .sort_values(
            "source_order_count",
            ascending=False,
        )
        .reset_index(drop=True)
    )

    stores["store_id"] = [
        f"STORE{i:03d}"
        for i in range(1, len(stores) + 1)
    ]

    formats = []

    for index in range(len(stores)):
        if index < 4:
            formats.append("Fulfilment Hub")
        elif index < 8:
            formats.append("Urban Store")
        else:
            formats.append("Regional Store")

    stores["store_format"] = formats

    earliest_date = (
        orders["order_purchase_timestamp"]
        .min()
        .normalize()
    )

    opening_offsets = rng.integers(
        365,
        1800,
        size=len(stores),
    )

    stores["opening_date"] = [
        (
            earliest_date
            - pd.Timedelta(days=int(days))
        ).date()
        for days in opening_offsets
    ]

    floor_area = []

    for store_format in stores["store_format"]:
        if store_format == "Fulfilment Hub":
            area = rng.integers(4500, 8501)
        elif store_format == "Urban Store":
            area = rng.integers(1200, 3501)
        else:
            area = rng.integers(700, 2201)

        floor_area.append(int(area))

    stores["floor_area_sqm"] = floor_area

    stores["store_name"] = (
        stores["customer_city"]
        .str.title()
        + " "
        + stores["customer_state"]
        + " "
        + stores["store_format"]
    )

    output = stores[
        [
            "store_id",
            "store_name",
            "customer_city",
            "customer_state",
            "latitude",
            "longitude",
            "store_format",
            "opening_date",
            "floor_area_sqm",
        ]
    ].rename(
        columns={
            "customer_city": "city",
            "customer_state": "state",
        }
    )

    return output, stores


def assign_orders_to_stores(
    orders,
    stores_internal,
):
    assignments = pd.DataFrame(
        {
            "order_id": orders["order_id"],
            "store_id": pd.Series(
                index=orders.index,
                dtype="object",
            ),
            "assignment_method": pd.Series(
                index=orders.index,
                dtype="object",
            ),
        }
    )

    valid_geo = (
        orders["latitude"].notna()
        & orders["longitude"].notna()
    )

    if valid_geo.any():
        distances = haversine_matrix(
            orders.loc[
                valid_geo,
                "latitude",
            ].to_numpy(),
            orders.loc[
                valid_geo,
                "longitude",
            ].to_numpy(),
            stores_internal[
                "latitude"
            ].to_numpy(),
            stores_internal[
                "longitude"
            ].to_numpy(),
        )

        nearest_store_index = np.argmin(
            distances,
            axis=1,
        )

        nearest_store_ids = (
            stores_internal
            .iloc[nearest_store_index][
                "store_id"
            ]
            .to_numpy()
        )

        assignments.loc[
            valid_geo,
            "store_id",
        ] = nearest_store_ids

        assignments.loc[
            valid_geo,
            "assignment_method",
        ] = "nearest_geolocation"

    store_priority = (
        stores_internal
        .sort_values(
            "source_order_count",
            ascending=False,
        )
        .drop_duplicates(
            subset=["customer_state"]
        )
        .set_index("customer_state")["store_id"]
        .to_dict()
    )

    missing_geo = ~valid_geo

    for index in orders.index[missing_geo]:
        state = orders.at[
            index,
            "customer_state",
        ]

        if state in store_priority:
            assignments.at[
                index,
                "store_id",
            ] = store_priority[state]

            assignments.at[
                index,
                "assignment_method",
            ] = "state_fallback"

        else:
            assignments.at[
                index,
                "store_id",
            ] = stores_internal.iloc[0][
                "store_id"
            ]

            assignments.at[
                index,
                "assignment_method",
            ] = "national_fallback"

    return assignments


def build_suppliers(sellers, rng):
    state_counts = (
        sellers["seller_state"]
        .dropna()
        .value_counts()
    )

    states = state_counts.index.to_numpy()

    probabilities = (
        state_counts
        / state_counts.sum()
    ).to_numpy()

    supplier_states = rng.choice(
        states,
        size=N_SUPPLIERS,
        replace=True,
        p=probabilities,
    )

    ratings = np.round(
        3.3
        + rng.beta(
            5,
            2,
            size=N_SUPPLIERS,
        )
        * 1.7,
        2,
    )

    lead_times = rng.integers(
        2,
        16,
        size=N_SUPPLIERS,
    )

    fill_rates = np.round(
        88
        + rng.beta(
            7,
            2,
            size=N_SUPPLIERS,
        )
        * 11.5,
        2,
    )

    suppliers = pd.DataFrame(
        {
            "supplier_id": [
                f"SUP{i:03d}"
                for i in range(
                    1,
                    N_SUPPLIERS + 1,
                )
            ],
            "supplier_name": [
                f"Enterprise Supplier {i:03d}"
                for i in range(
                    1,
                    N_SUPPLIERS + 1,
                )
            ],
            "supplier_state": supplier_states,
            "supplier_rating": ratings,
            "standard_lead_time_days": (
                lead_times.astype(int)
            ),
            "contractual_fill_rate_pct": (
                fill_rates
            ),
        }
    )

    return suppliers


def build_product_supplier_mapping(
    products,
    suppliers,
    rng,
):
    supplier_ids = suppliers[
        "supplier_id"
    ].to_numpy()

    product_data = products.copy()

    product_data[
        "product_category_name"
    ] = (
        product_data[
            "product_category_name"
        ]
        .fillna("Unknown")
    )

    mapping_rows = []

    categories = sorted(
        product_data[
            "product_category_name"
        ].unique()
    )

    for category in categories:
        category_products = (
            product_data[
                product_data[
                    "product_category_name"
                ].eq(category)
            ]
            .sort_values("product_id")
        )

        pool_size = min(
            int(rng.integers(3, 7)),
            len(supplier_ids),
        )

        supplier_pool = rng.choice(
            supplier_ids,
            size=pool_size,
            replace=False,
        )

        assignments = rng.choice(
            supplier_pool,
            size=len(category_products),
            replace=True,
        )

        for product_id, supplier_id in zip(
            category_products["product_id"],
            assignments,
        ):
            mapping_rows.append(
                {
                    "product_id": product_id,
                    "supplier_id": supplier_id,
                }
            )

    return pd.DataFrame(mapping_rows)


def build_product_cost(
    products,
    items,
    rng,
):
    all_price = (
        items
        .groupby("product_id")["price"]
        .mean()
        .rename("all_avg_price")
    )

    delivered_price = (
        items[
            items["order_status"].eq(
                "delivered"
            )
        ]
        .groupby("product_id")["price"]
        .mean()
        .rename("delivered_avg_price")
    )

    cost = (
        products
        .merge(
            all_price,
            how="left",
            on="product_id",
        )
        .merge(
            delivered_price,
            how="left",
            on="product_id",
        )
    )

    cost["reference_price"] = (
        cost["delivered_avg_price"]
        .fillna(cost["all_avg_price"])
    )

    category_median = (
        cost
        .groupby(
            "product_category_name",
            dropna=False,
        )["reference_price"]
        .transform("median")
    )

    global_median = cost[
        "reference_price"
    ].median()

    cost["reference_price"] = (
        cost["reference_price"]
        .fillna(category_median)
        .fillna(global_median)
    )

    category_labels = (
        cost["product_category_name"]
        .fillna("Unknown")
    )

    category_ratios = {}

    for category in sorted(
        category_labels.unique()
    ):
        category_ratios[category] = (
            rng.uniform(0.48, 0.72)
        )

    base_ratio = category_labels.map(
        category_ratios
    ).astype(float)

    product_variation = rng.normal(
        0,
        0.035,
        size=len(cost),
    )

    cost_ratio = np.clip(
        base_ratio + product_variation,
        0.38,
        0.80,
    )

    cost["cost_ratio"] = np.round(
        cost_ratio,
        4,
    )

    cost["estimated_unit_cost"] = np.round(
        cost["reference_price"]
        * cost["cost_ratio"],
        2,
    )

    return cost[
        [
            "product_id",
            "estimated_unit_cost",
            "cost_ratio",
        ]
    ]


def build_monthly_actuals(
    orders,
    assignments,
):
    working = orders.merge(
        assignments,
        on="order_id",
        how="left",
    )

    delivered = working[
        working["order_status"].eq(
            "delivered"
        )
    ].copy()

    delivered["month"] = (
        delivered[
            "order_purchase_timestamp"
        ]
        .dt.to_period("M")
        .dt.to_timestamp()
    )

    monthly = (
        delivered
        .groupby(
            ["month", "store_id"],
            as_index=False,
        )
        .agg(
            actual_sales=(
                "gross_order_value",
                "sum",
            ),
            actual_freight=(
                "freight_value",
                "sum",
            ),
            actual_orders=(
                "order_id",
                "nunique",
            ),
        )
    )

    return delivered, monthly


def build_budget_and_targets(
    stores,
    delivered_orders,
    monthly_actuals,
    rng,
):
    first_month = (
        delivered_orders[
            "order_purchase_timestamp"
        ]
        .min()
        .to_period("M")
        .to_timestamp()
    )

    last_month = (
        delivered_orders[
            "order_purchase_timestamp"
        ]
        .max()
        .to_period("M")
        .to_timestamp()
    )

    months = pd.date_range(
        first_month,
        last_month,
        freq="MS",
    )

    skeleton = pd.MultiIndex.from_product(
        [
            months,
            stores["store_id"],
        ],
        names=[
            "budget_month",
            "store_id",
        ],
    ).to_frame(index=False)

    monthly = monthly_actuals.rename(
        columns={"month": "budget_month"}
    )

    planning = skeleton.merge(
        monthly,
        how="left",
        on=[
            "budget_month",
            "store_id",
        ],
    )

    planning[
        [
            "actual_sales",
            "actual_freight",
            "actual_orders",
        ]
    ] = planning[
        [
            "actual_sales",
            "actual_freight",
            "actual_orders",
        ]
    ].fillna(0)

    store_aov = (
        delivered_orders
        .groupby("store_id")[
            "gross_order_value"
        ]
        .mean()
        .to_dict()
    )

    budgets = []
    targets = []

    for row in planning.itertuples(
        index=False
    ):
        aov = max(
            float(
                store_aov.get(
                    row.store_id,
                    150.0,
                )
            ),
            1.0,
        )

        if row.actual_sales > 0:
            sales_budget = (
                row.actual_sales
                * rng.uniform(0.94, 1.08)
            )

            freight_budget = (
                row.actual_freight
                * rng.uniform(0.92, 1.08)
            )
        else:
            sales_budget = (
                aov
                * rng.uniform(3, 12)
            )

            freight_budget = (
                sales_budget
                * rng.uniform(0.10, 0.17)
            )

        operating_cost_budget = (
            sales_budget
            * rng.uniform(0.09, 0.16)
        )

        sales_target = (
            sales_budget
            * rng.uniform(1.02, 1.08)
        )

        order_target = max(
            1,
            int(
                np.ceil(
                    sales_target / aov
                )
            ),
        )

        margin_target_pct = rng.uniform(
            25,
            38,
        )

        budgets.append(
            {
                "budget_month": (
                    row.budget_month.date()
                ),
                "store_id": row.store_id,
                "sales_budget": round(
                    sales_budget,
                    2,
                ),
                "freight_budget": round(
                    freight_budget,
                    2,
                ),
                "operating_cost_budget": round(
                    operating_cost_budget,
                    2,
                ),
            }
        )

        targets.append(
            {
                "target_month": (
                    row.budget_month.date()
                ),
                "store_id": row.store_id,
                "sales_target": round(
                    sales_target,
                    2,
                ),
                "order_target": order_target,
                "margin_target_pct": round(
                    margin_target_pct,
                    2,
                ),
            }
        )

    return (
        pd.DataFrame(budgets),
        pd.DataFrame(targets),
    )


def build_marketing_spend(
    stores,
    delivered_orders,
    monthly_actuals,
    rng,
):
    channels = [
        "paid_search",
        "social",
        "email",
        "display",
        "affiliate",
    ]

    channel_weights = np.array(
        [4.0, 3.0, 2.0, 1.5, 1.0]
    )

    first_month = (
        delivered_orders[
            "order_purchase_timestamp"
        ]
        .min()
        .to_period("M")
        .to_timestamp()
    )

    last_month = (
        delivered_orders[
            "order_purchase_timestamp"
        ]
        .max()
        .to_period("M")
        .to_timestamp()
    )

    months = pd.date_range(
        first_month,
        last_month,
        freq="MS",
    )

    actual_lookup = (
        monthly_actuals
        .set_index(
            ["month", "store_id"]
        )["actual_sales"]
        .to_dict()
    )

    rows = []

    for month in months:
        for store_id in stores["store_id"]:
            sales = float(
                actual_lookup.get(
                    (month, store_id),
                    0.0,
                )
            )

            if sales > 0:
                total_spend = (
                    sales
                    * rng.uniform(
                        0.025,
                        0.065,
                    )
                )
            else:
                total_spend = rng.uniform(
                    250,
                    900,
                )

            shares = rng.dirichlet(
                channel_weights
            )

            for channel, share in zip(
                channels,
                shares,
            ):
                rows.append(
                    {
                        "month": month.date(),
                        "store_id": store_id,
                        "channel": channel,
                        "spend": round(
                            total_spend
                            * float(share),
                            2,
                        ),
                    }
                )

    return pd.DataFrame(rows)


def build_inventory(
    orders,
    items,
    assignments,
    rng,
):
    delivered_items = items[
        items["order_status"].eq(
            "delivered"
        )
    ][
        [
            "order_id",
            "product_id",
        ]
    ].copy()

    order_dates = orders[
        [
            "order_id",
            "order_purchase_timestamp",
        ]
    ].copy()

    delivered_items = (
        delivered_items
        .merge(
            assignments[
                [
                    "order_id",
                    "store_id",
                ]
            ],
            how="left",
            on="order_id",
        )
        .merge(
            order_dates,
            how="left",
            on="order_id",
        )
    )

    delivered_items["snapshot_month"] = (
        delivered_items[
            "order_purchase_timestamp"
        ]
        .dt.to_period("M")
        .dt.to_timestamp()
    )

    product_sales = (
        delivered_items[
            "product_id"
        ]
        .value_counts()
    )

    eligible_products = (
        product_sales[
            product_sales
            >= MIN_INVENTORY_PRODUCT_SALES
        ]
        .head(MAX_INVENTORY_PRODUCTS)
        .index
    )

    delivered_items = delivered_items[
        delivered_items[
            "product_id"
        ].isin(eligible_products)
    ].copy()

    monthly_sales = (
        delivered_items
        .groupby(
            [
                "snapshot_month",
                "store_id",
                "product_id",
            ]
        )
        .size()
        .rename("sold_qty")
        .reset_index()
    )

    rows = []

    for (
        store_id,
        product_id,
    ), group in monthly_sales.groupby(
        ["store_id", "product_id"]
    ):
        group = group.sort_values(
            "snapshot_month"
        )

        sales_lookup = (
            group
            .set_index(
                "snapshot_month"
            )["sold_qty"]
            .to_dict()
        )

        first_month = group[
            "snapshot_month"
        ].min()

        last_month = group[
            "snapshot_month"
        ].max()

        months = pd.date_range(
            first_month,
            last_month,
            freq="MS",
        )

        avg_monthly_sales = max(
            float(
                group["sold_qty"].mean()
            ),
            1.0,
        )

        reorder_point = max(
            1,
            int(
                np.ceil(
                    avg_monthly_sales
                    * rng.uniform(
                        0.9,
                        1.7,
                    )
                )
            ),
        )

        opening_stock = max(
            reorder_point * 2,
            int(
                np.ceil(
                    avg_monthly_sales
                    * rng.uniform(
                        2.0,
                        3.8,
                    )
                )
            ),
        )

        for month in months:
            sold_qty = int(
                sales_lookup.get(
                    month,
                    0,
                )
            )

            target_closing = max(
                1,
                int(
                    np.ceil(
                        avg_monthly_sales
                        * rng.uniform(
                            0.6,
                            2.2,
                        )
                    )
                ),
            )

            desired_receipt = max(
                0,
                sold_qty
                + target_closing
                - opening_stock,
            )

            if desired_receipt > 0:
                supply_factor = rng.uniform(
                    0.65,
                    1.15,
                )

                planned_receipt = int(
                    round(
                        desired_receipt
                        * supply_factor
                    )
                )
            else:
                planned_receipt = 0

            minimum_receipt_to_avoid_negative = max(
                0,
                sold_qty - opening_stock,
            )

            received_qty = max(
                planned_receipt,
                minimum_receipt_to_avoid_negative,
            )

            closing_stock = (
                opening_stock
                + received_qty
                - sold_qty
            )

            stock_pressure = max(
                0.0,
                (
                    reorder_point
                    - closing_stock
                )
                / max(
                    reorder_point,
                    1,
                ),
            )

            high_demand_pressure = min(
                1.0,
                sold_qty
                / max(
                    avg_monthly_sales * 1.5,
                    1.0,
                ),
            )

            stockout_probability = min(
                0.75,
                (
                    stock_pressure * 0.55
                    + high_demand_pressure * 0.08
                ),
            )

            if (
                sold_qty > 0
                and rng.random()
                < stockout_probability
            ):
                stockout_days = int(
                    rng.integers(
                        1,
                        min(
                            8,
                            max(
                                2,
                                int(
                                    np.ceil(
                                        stock_pressure * 8
                                    )
                                )
                                + 2,
                            ),
                        )
                        + 1,
                    )
                )
            else:
                stockout_days = 0

            rows.append(
                {
                    "snapshot_month": (
                        month.date()
                    ),
                    "store_id": store_id,
                    "product_id": product_id,
                    "opening_stock_qty": int(
                        opening_stock
                    ),
                    "received_qty": int(
                        received_qty
                    ),
                    "sold_qty": sold_qty,
                    "closing_stock_qty": int(
                        closing_stock
                    ),
                    "reorder_point": int(
                        reorder_point
                    ),
                    "stockout_days": int(
                        stockout_days
                    ),
                }
            )

            opening_stock = closing_stock

    return pd.DataFrame(rows)


def validate_outputs(
    orders,
    products,
    stores,
    assignments,
    suppliers,
    product_supplier,
    product_cost,
    inventory,
    budgets,
    targets,
    marketing,
):
    print("Validating synthetic datasets...")

    assert stores["store_id"].is_unique

    assert len(assignments) == len(orders)
    assert assignments["order_id"].is_unique
    assert assignments["store_id"].notna().all()

    assert set(
        assignments["store_id"]
    ).issubset(
        set(stores["store_id"])
    )

    assert suppliers["supplier_id"].is_unique

    assert len(product_supplier) == len(products)
    assert product_supplier[
        "product_id"
    ].is_unique

    assert set(
        product_supplier["supplier_id"]
    ).issubset(
        set(suppliers["supplier_id"])
    )

    assert len(product_cost) == len(products)
    assert product_cost[
        "product_id"
    ].is_unique

    assert (
        product_cost[
            "estimated_unit_cost"
        ] >= 0
    ).all()

    assert (
        product_cost["cost_ratio"]
        .between(0, 1)
        .all()
    )

    assert (
        inventory[
            "closing_stock_qty"
        ] >= 0
    ).all()

    inventory_balance = (
        inventory[
            "opening_stock_qty"
        ]
        + inventory["received_qty"]
        - inventory["sold_qty"]
        - inventory[
            "closing_stock_qty"
        ]
    )

    assert (
        inventory_balance == 0
    ).all()

    assert len(budgets) == len(targets)

    expected_marketing_rows = (
        len(budgets) * 5
    )

    assert (
        len(marketing)
        == expected_marketing_rows
    )

    print("All synthetic validation checks passed.")


def write_outputs(
    stores,
    assignments,
    suppliers,
    product_supplier,
    product_cost,
    inventory,
    budgets,
    targets,
    marketing,
):
    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    datasets = {
        "stores.csv": stores,
        "order_store_assignment.csv": (
            assignments
        ),
        "suppliers.csv": suppliers,
        "product_supplier_mapping.csv": (
            product_supplier
        ),
        "product_cost.csv": product_cost,
        "inventory_snapshot.csv": inventory,
        "monthly_store_budget.csv": budgets,
        "sales_targets.csv": targets,
        "marketing_spend.csv": marketing,
    }

    for filename, dataframe in datasets.items():
        path = OUTPUT_DIR / filename

        dataframe.to_csv(
            path,
            index=False,
        )

        print(
            f"{filename:<38} "
            f"{len(dataframe):>10,} rows"
        )


def main():
    print(
        "Generating synthetic enterprise "
        "operations data"
    )
    print(f"Random seed: {SEED}")

    rng = np.random.default_rng(SEED)

    engine = create_engine(DATABASE_URL)

    (
        orders,
        items,
        products,
        sellers,
    ) = load_source_data(engine)

    stores, stores_internal = build_stores(
        orders,
        rng,
    )

    assignments = assign_orders_to_stores(
        orders,
        stores_internal,
    )

    suppliers = build_suppliers(
        sellers,
        rng,
    )

    product_supplier = (
        build_product_supplier_mapping(
            products,
            suppliers,
            rng,
        )
    )

    product_cost = build_product_cost(
        products,
        items,
        rng,
    )

    delivered_orders, monthly_actuals = (
        build_monthly_actuals(
            orders,
            assignments,
        )
    )

    budgets, targets = (
        build_budget_and_targets(
            stores,
            delivered_orders,
            monthly_actuals,
            rng,
        )
    )

    marketing = build_marketing_spend(
        stores,
        delivered_orders,
        monthly_actuals,
        rng,
    )

    inventory = build_inventory(
        orders,
        items,
        assignments,
        rng,
    )

    validate_outputs(
        orders,
        products,
        stores,
        assignments,
        suppliers,
        product_supplier,
        product_cost,
        inventory,
        budgets,
        targets,
        marketing,
    )

    print("")
    print("Writing synthetic datasets...")

    write_outputs(
        stores,
        assignments,
        suppliers,
        product_supplier,
        product_cost,
        inventory,
        budgets,
        targets,
        marketing,
    )

    print("")
    print(
        "Synthetic enterprise data generation "
        "completed successfully."
    )


if __name__ == "__main__":
    main()
