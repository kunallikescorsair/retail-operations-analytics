-- ============================================================
-- Final staging exception investigation
-- ============================================================


\echo ''
\echo '============================================================'
\echo '1. CLOSED DEAL BEFORE FIRST CONTACT'
\echo '============================================================'

SELECT
    m.mql_id,
    m.first_contact_date,
    d.won_date,
    d.seller_id,
    d.business_segment,
    d.lead_type,
    d.business_type,
    d.ecommerce_seller_match
FROM staging.marketing_qualified_leads m
INNER JOIN staging.closed_deals d
    ON m.mql_id = d.mql_id
WHERE d.won_date::date < m.first_contact_date;


\echo ''
\echo '============================================================'
\echo '2. UNTRANSLATED PRODUCT CATEGORIES'
\echo '============================================================'

SELECT
    p.product_category_name,
    COUNT(*) AS products
FROM staging.products p

LEFT JOIN staging.product_category_translation t
    ON p.product_category_name =
       t.product_category_name

WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL

GROUP BY p.product_category_name
ORDER BY products DESC;


\echo ''
\echo '============================================================'
\echo '3. CUSTOMER GEOLOCATION COVERAGE'
\echo '============================================================'

SELECT
    COUNT(*) AS customers,
    
    COUNT(*) FILTER (
        WHERE g.zip_code_prefix IS NOT NULL
    ) AS matched,

    COUNT(*) FILTER (
        WHERE g.zip_code_prefix IS NULL
    ) AS unmatched,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE g.zip_code_prefix IS NULL
        )
        / COUNT(*),
        4
    ) AS unmatched_pct

FROM staging.customers c

LEFT JOIN staging.geolocation g
    ON c.customer_zip_code_prefix =
       g.zip_code_prefix;


\echo ''
\echo '============================================================'
\echo '4. SELLER GEOLOCATION COVERAGE'
\echo '============================================================'

SELECT
    COUNT(*) AS sellers,

    COUNT(*) FILTER (
        WHERE g.zip_code_prefix IS NOT NULL
    ) AS matched,

    COUNT(*) FILTER (
        WHERE g.zip_code_prefix IS NULL
    ) AS unmatched,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE g.zip_code_prefix IS NULL
        )
        / COUNT(*),
        4
    ) AS unmatched_pct

FROM staging.sellers s

LEFT JOIN staging.geolocation g
    ON s.seller_zip_code_prefix =
       g.zip_code_prefix;