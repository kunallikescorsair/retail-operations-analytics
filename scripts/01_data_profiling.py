from pathlib import Path

import numpy as np
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
# 2. Discover CSV files
# ============================================================

csv_files = sorted(
    list(ECOMMERCE_DIR.glob("*.csv"))
    + list(MARKETING_DIR.glob("*.csv"))
)

print("=" * 80)
print("SOURCE FILE DISCOVERY")
print("=" * 80)
print(f"Found {len(csv_files)} CSV files.\n")

if len(csv_files) != 11:
    print(
        f"WARNING: Expected 11 source files, but found {len(csv_files)}."
    )

for file in csv_files:
    print(file.name)


# ============================================================
# 3. Load datasets
# ============================================================

datasets = {}

print("\n" + "=" * 80)
print("LOADING DATASETS")
print("=" * 80)

for file in csv_files:
    dataset_name = file.stem
    df = pd.read_csv(file)

    datasets[dataset_name] = df

    print(
        f"{dataset_name:<45} "
        f"rows={len(df):>10,} "
        f"columns={len(df.columns):>3}"
    )


# ============================================================
# 4. Dataset inventory
# ============================================================

inventory = []

for name, df in datasets.items():
    inventory.append(
        {
            "dataset": name,
            "rows": len(df),
            "columns": len(df.columns),
            "memory_mb": round(
                df.memory_usage(deep=True).sum() / 1024**2,
                2,
            ),
        }
    )

inventory_df = (
    pd.DataFrame(inventory)
    .sort_values("rows", ascending=False)
    .reset_index(drop=True)
)

inventory_df.to_csv(
    OUTPUT_DIR / "dataset_inventory.csv",
    index=False,
)


# ============================================================
# 5. Column-level profiling
# ============================================================

def profile_dataframe(
    name: str,
    df: pd.DataFrame,
) -> pd.DataFrame:

    row_count = len(df)

    profile = pd.DataFrame(
        {
            "column": df.columns,
            "dtype": df.dtypes.astype(str).values,
            "non_null_count": df.notna().sum().values,
            "null_count": df.isna().sum().values,
            "null_pct": (
                df.isna().mean() * 100
            ).round(2).values,
            "unique_count": df.nunique(
                dropna=True
            ).values,
        }
    )

    profile.insert(0, "dataset", name)

    if row_count > 0:
        profile["unique_pct"] = (
            profile["unique_count"]
            / row_count
            * 100
        ).round(2)
    else:
        profile["unique_pct"] = 0

    return profile


column_profiles = pd.concat(
    [
        profile_dataframe(name, df)
        for name, df in datasets.items()
    ],
    ignore_index=True,
)

column_profiles.to_csv(
    OUTPUT_DIR / "column_profiles.csv",
    index=False,
)


# ============================================================
# 6. Missing-value analysis
# ============================================================

missing_summary = (
    column_profiles[
        column_profiles["null_count"] > 0
    ]
    .sort_values(
        ["null_pct", "dataset"],
        ascending=[False, True],
    )
    .reset_index(drop=True)
)

missing_summary.to_csv(
    OUTPUT_DIR / "missing_values.csv",
    index=False,
)


# ============================================================
# 7. Exact duplicate rows
# ============================================================

duplicate_summary = []

for name, df in datasets.items():
    duplicate_count = int(
        df.duplicated().sum()
    )

    duplicate_pct = (
        duplicate_count
        / len(df)
        * 100
        if len(df) > 0
        else 0
    )

    duplicate_summary.append(
        {
            "dataset": name,
            "rows": len(df),
            "exact_duplicate_rows": duplicate_count,
            "duplicate_pct": round(
                duplicate_pct,
                4,
            ),
        }
    )

duplicate_df = pd.DataFrame(
    duplicate_summary
).sort_values(
    "exact_duplicate_rows",
    ascending=False,
)

duplicate_df.to_csv(
    OUTPUT_DIR / "duplicate_summary.csv",
    index=False,
)


# ============================================================
# 8. Candidate single-column primary keys
# ============================================================

key_candidates = []

for name, df in datasets.items():

    for column in df.columns:

        is_non_null = (
            df[column]
            .notna()
            .all()
        )

        is_unique = (
            df[column]
            .nunique(dropna=False)
            == len(df)
        )

        if is_non_null and is_unique:
            key_candidates.append(
                {
                    "dataset": name,
                    "candidate_key": column,
                }
            )

key_candidates_df = pd.DataFrame(
    key_candidates
)

key_candidates_df.to_csv(
    OUTPUT_DIR / "candidate_keys.csv",
    index=False,
)


# ============================================================
# 9. ID-column profiling
# ============================================================

id_columns = []

for name, df in datasets.items():

    for column in df.columns:

        if column.endswith("_id"):

            id_columns.append(
                {
                    "dataset": name,
                    "column": column,
                    "rows": len(df),
                    "unique_values": df[
                        column
                    ].nunique(
                        dropna=True
                    ),
                    "null_count": int(
                        df[column]
                        .isna()
                        .sum()
                    ),
                }
            )

id_columns_df = pd.DataFrame(
    id_columns
)

id_columns_df.to_csv(
    OUTPUT_DIR / "id_columns.csv",
    index=False,
)


# ============================================================
# 10. Date-like columns
# ============================================================

date_columns = []

for name, df in datasets.items():

    for column in df.columns:

        column_lower = column.lower()

        if any(
            keyword in column_lower
            for keyword in [
                "date",
                "timestamp",
                "time",
            ]
        ):
            date_columns.append(
                {
                    "dataset": name,
                    "column": column,
                    "source_dtype": str(
                        df[column].dtype
                    ),
                }
            )

date_columns_df = pd.DataFrame(
    date_columns
)

date_columns_df.to_csv(
    OUTPUT_DIR / "date_columns.csv",
    index=False,
)


# ============================================================
# 11. Numeric profiling
# ============================================================

numeric_profiles = []

for name, df in datasets.items():

    numeric_df = df.select_dtypes(
        include=np.number
    )

    for column in numeric_df.columns:

        series = numeric_df[column]

        numeric_profiles.append(
            {
                "dataset": name,
                "column": column,
                "count": int(
                    series.count()
                ),
                "min": series.min(),
                "max": series.max(),
                "mean": series.mean(),
                "median": series.median(),
                "std": series.std(),
                "zero_count": int(
                    (series == 0).sum()
                ),
                "negative_count": int(
                    (series < 0).sum()
                ),
            }
        )

numeric_profiles_df = pd.DataFrame(
    numeric_profiles
)

numeric_profiles_df.to_csv(
    OUTPUT_DIR / "numeric_profiles.csv",
    index=False,
)


# ============================================================
# 12. Console summary
# ============================================================

print("\n" + "=" * 80)
print("DATASET INVENTORY")
print("=" * 80)

print(
    inventory_df.to_string(
        index=False
    )
)


print("\n" + "=" * 80)
print("DUPLICATE SUMMARY")
print("=" * 80)

print(
    duplicate_df.to_string(
        index=False
    )
)


print("\n" + "=" * 80)
print("CANDIDATE KEYS")
print("=" * 80)

if key_candidates_df.empty:
    print(
        "No single-column candidate keys detected."
    )
else:
    print(
        key_candidates_df.to_string(
            index=False
        )
    )


print("\n" + "=" * 80)
print("TOP MISSING-VALUE COLUMNS")
print("=" * 80)

if missing_summary.empty:
    print(
        "No missing values detected."
    )
else:
    print(
        missing_summary
        .head(30)
        .to_string(
            index=False
        )
    )


print("\n" + "=" * 80)
print("PROFILING COMPLETE")
print("=" * 80)

print(
    f"Reports saved to:\n{OUTPUT_DIR}"
)