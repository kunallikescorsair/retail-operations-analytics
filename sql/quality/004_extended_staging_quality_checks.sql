-- ============================================================
-- Extended Staging Data Quality Checks
-- ============================================================

WITH checks AS (

    -- ========================================================
    -- Sellers
    -- ========================================================

    SELECT
        'ERROR' AS severity,
        'invalid_seller_state' AS check_name,
        COUNT(*) AS issue_count
    FROM staging.sellers
    WHERE seller_state IS NULL
       OR seller_state !~ '^[A-Z]{2}$'

    UNION ALL

    SELECT
        'ERROR',
        'invalid_seller_zip_prefix',
        COUNT(*)
    FROM staging.sellers
    WHERE seller_zip_code_prefix IS NULL
       OR seller_zip_code_prefix !~ '^[0-9]{5}$'


    -- ========================================================
    -- Reviews
    -- ========================================================

    UNION ALL

    SELECT
        'ERROR',
        'review_score_outside_1_to_5',
        COUNT(*)
    FROM staging.order_reviews
    WHERE review_score NOT BETWEEN 1 AND 5

    UNION ALL

    SELECT
        'ERROR',
        'review_answer_before_creation',
        COUNT(*)
    FROM staging.order_reviews
    WHERE review_answer_timestamp IS NOT NULL
      AND review_creation_date IS NOT NULL
      AND review_answer_timestamp < review_creation_date


    -- ========================================================
    -- Geolocation
    -- ========================================================

    UNION ALL

    SELECT
        'ERROR',
        'invalid_geolocation_latitude',
        COUNT(*)
    FROM staging.geolocation
    WHERE latitude NOT BETWEEN -90 AND 90

    UNION ALL

    SELECT
        'ERROR',
        'invalid_geolocation_longitude',
        COUNT(*)
    FROM staging.geolocation
    WHERE longitude NOT BETWEEN -180 AND 180

    UNION ALL

    SELECT
        'WARNING',
        'zip_prefix_multiple_states',
        COUNT(*)
    FROM staging.geolocation
    WHERE distinct_state_count > 1

    UNION ALL

    SELECT
        'INFO',
        'zip_prefix_multiple_city_labels',
        COUNT(*)
    FROM staging.geolocation
    WHERE distinct_city_count > 1


    -- ========================================================
    -- Geography coverage
    -- ========================================================

    UNION ALL

    SELECT
        'WARNING',
        'customer_zip_not_found_in_geolocation',
        COUNT(*)
    FROM staging.customers c
    WHERE NOT EXISTS (
        SELECT 1
        FROM staging.geolocation g
        WHERE g.zip_code_prefix =
              c.customer_zip_code_prefix
    )

    UNION ALL

    SELECT
        'WARNING',
        'seller_zip_not_found_in_geolocation',
        COUNT(*)
    FROM staging.sellers s
    WHERE NOT EXISTS (
        SELECT 1
        FROM staging.geolocation g
        WHERE g.zip_code_prefix =
              s.seller_zip_code_prefix
    )


    -- ========================================================
    -- Product-category translation
    -- ========================================================

    UNION ALL

    SELECT
        'WARNING',
        'missing_category_translation',
        COUNT(*)
    FROM staging.products p
    WHERE p.product_category_name IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM staging.product_category_translation t
        WHERE t.product_category_name =
              p.product_category_name
    )


    -- ========================================================
    -- Marketing
    -- ========================================================

    UNION ALL

    SELECT
        'ERROR',
        'closed_deal_before_first_contact',
        COUNT(*)
    FROM staging.closed_deals d
    INNER JOIN staging.marketing_qualified_leads m
        ON d.mql_id = m.mql_id
    WHERE d.won_date::date < m.first_contact_date

    UNION ALL

    SELECT
        'WARNING',
        'negative_declared_monthly_revenue',
        COUNT(*)
    FROM staging.closed_deals
    WHERE declared_monthly_revenue < 0

    UNION ALL

    SELECT
        'WARNING',
        'negative_declared_catalog_size',
        COUNT(*)
    FROM staging.closed_deals
    WHERE declared_product_catalog_size < 0

    UNION ALL

    SELECT
        'INFO',
        'closed_deal_seller_not_in_ecommerce',
        COUNT(*)
    FROM staging.closed_deals
    WHERE ecommerce_seller_match = FALSE
)

SELECT
    severity,
    check_name,
    issue_count
FROM checks
ORDER BY
    CASE severity
        WHEN 'ERROR' THEN 1
        WHEN 'WARNING' THEN 2
        WHEN 'INFO' THEN 3
        ELSE 4
    END,
    check_name;