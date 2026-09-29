-- ============================================================
-- Customer, Delivery, Review and Marketing Analysis
--
-- Business questions:
--
-- 1. Which customer markets contribute the most sales?
-- 2. Where does repeat purchasing occur?
-- 3. What is the censoring-adjusted 90-day repeat rate?
-- 4. How are new and returning customers changing over time?
-- 5. Which stores have the strongest / weakest delivery
--    performance?
-- 6. Is late delivery associated with lower review scores?
-- 7. Which customer states experience the greatest delivery
--    pressure?
-- 8. How large is marketing spend relative to delivered sales
--    at each synthetic store?
--
-- Customer, order, delivery and review measures originate from
-- public ecommerce source data.
--
-- Store assignment and marketing measures belong to the
-- documented synthetic enterprise layer.
-- ============================================================


\echo ''
\echo '============================================================'
\echo '1. CUSTOMER PERFORMANCE BY STATE'
\echo '============================================================'

WITH delivered AS (

    SELECT
        f.order_id,
        f.customer_key,
        f.gross_order_value

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'
),

customer_state_orders AS (

    SELECT
        c.customer_state,
        c.customer_unique_id,

        COUNT(*) AS delivered_orders,

        SUM(d.gross_order_value)
            AS gross_order_value

    FROM delivered d

    INNER JOIN analytics.dim_customer c
        ON d.customer_key =
           c.customer_key

    GROUP BY
        c.customer_state,
        c.customer_unique_id
)

SELECT
    customer_state,

    COUNT(DISTINCT customer_unique_id)
        AS unique_customers,

    SUM(delivered_orders)
        AS delivered_orders,

    COUNT(*) FILTER (
        WHERE delivered_orders >= 2
    ) AS repeat_customers,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE delivered_orders >= 2
        )
        / NULLIF(
            COUNT(*),
            0
        ),
        2
    ) AS repeat_customer_rate_pct,

    ROUND(
        SUM(gross_order_value),
        2
    ) AS gross_order_value,

    ROUND(
        SUM(gross_order_value)
        / NULLIF(
            SUM(delivered_orders),
            0
        ),
        2
    ) AS average_order_value

FROM customer_state_orders

GROUP BY customer_state

ORDER BY gross_order_value DESC

LIMIT 20;


\echo ''
\echo '============================================================'
\echo '2. CENSORING-ADJUSTED 90-DAY REPEAT RATE'
\echo '============================================================'

WITH delivered_orders AS (

    SELECT
        c.customer_unique_id,
        f.order_id,
        f.order_purchase_timestamp,

        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY
                f.order_purchase_timestamp,
                f.order_id
        ) AS order_sequence

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_customer c
        ON f.customer_key =
           c.customer_key

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'
),

observation_window AS (

    SELECT
        MAX(order_purchase_timestamp)
            AS last_observed_order_timestamp

    FROM delivered_orders
),

customer_orders AS (

    SELECT
        customer_unique_id,

        MIN(order_purchase_timestamp)
            FILTER (
                WHERE order_sequence = 1
            )
            AS first_order_timestamp,

        MIN(order_purchase_timestamp)
            FILTER (
                WHERE order_sequence = 2
            )
            AS second_order_timestamp

    FROM delivered_orders

    GROUP BY customer_unique_id
),

eligible AS (

    SELECT
        c.*,

        CASE
            WHEN
                c.second_order_timestamp
                <= c.first_order_timestamp
                   + INTERVAL '90 days'
            THEN 1
            ELSE 0
        END AS repeated_within_90_days

    FROM customer_orders c

    CROSS JOIN observation_window o

    WHERE
        c.first_order_timestamp
        <= o.last_observed_order_timestamp
           - INTERVAL '90 days'
)

SELECT
    COUNT(*) AS eligible_customers,

    SUM(repeated_within_90_days)
        AS customers_repeated_within_90_days,

    ROUND(
        100.0
        * SUM(repeated_within_90_days)
        / NULLIF(COUNT(*), 0),
        2
    ) AS repeat_within_90_days_pct

FROM eligible;


\echo ''
\echo '============================================================'
\echo '3. MONTHLY NEW VS RETURNING CUSTOMERS'
\echo '============================================================'

WITH delivered_orders AS (

    SELECT
        c.customer_unique_id,
        f.order_id,

        DATE_TRUNC(
            'month',
            f.order_purchase_timestamp
        )::date AS order_month,

        MIN(
            DATE_TRUNC(
                'month',
                f.order_purchase_timestamp
            )::date
        ) OVER (
            PARTITION BY c.customer_unique_id
        ) AS first_order_month

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_customer c
        ON f.customer_key =
           c.customer_key

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'
),

customer_month AS (

    SELECT DISTINCT
        customer_unique_id,
        order_month,
        first_order_month

    FROM delivered_orders
)

SELECT
    order_month,

    COUNT(*) FILTER (
        WHERE order_month =
              first_order_month
    ) AS new_customers,

    COUNT(*) FILTER (
        WHERE order_month >
              first_order_month
    ) AS returning_customers,

    COUNT(*) AS active_customers,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE order_month >
                  first_order_month
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS returning_customer_share_pct

FROM customer_month

GROUP BY order_month

ORDER BY order_month;


\echo ''
\echo '============================================================'
\echo '4. DELIVERY PERFORMANCE BY STORE'
\echo '============================================================'

SELECT
    s.store_id,
    s.store_name,
    s.store_format,

    COUNT(*) FILTER (
        WHERE f.has_valid_delivery_timeline
    ) AS valid_delivery_orders,

    ROUND(
        AVG(f.delivery_days)
            FILTER (
                WHERE f.has_valid_delivery_timeline
            ),
        2
    ) AS average_delivery_days,

    COUNT(*) FILTER (
        WHERE
            f.has_valid_delivery_timeline
            AND f.is_late_delivery
    ) AS late_orders,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE
                f.has_valid_delivery_timeline
                AND f.is_late_delivery
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE f.has_valid_delivery_timeline
            ),
            0
        ),
        2
    ) AS late_delivery_rate_pct,

    ROUND(
        AVG(f.delivery_variance_days)
            FILTER (
                WHERE f.has_valid_delivery_timeline
            ),
        2
    ) AS average_delivery_variance_days

FROM analytics.fact_orders f

INNER JOIN analytics.dim_store s
    ON f.store_key = s.store_key

INNER JOIN analytics.dim_order_status os
    ON f.order_status_key =
       os.order_status_key

WHERE os.order_status = 'delivered'

GROUP BY
    s.store_id,
    s.store_name,
    s.store_format

ORDER BY late_delivery_rate_pct DESC;


\echo ''
\echo '============================================================'
\echo '5. LATE DELIVERY VS REVIEW SCORE'
\echo '============================================================'

WITH order_reviews AS (

    SELECT
        order_id,

        AVG(review_score::numeric)
            AS average_review_score

    FROM analytics.fact_reviews

    GROUP BY order_id
),

eligible_orders AS (

    SELECT
        f.order_id,
        f.is_late_delivery,
        f.delivery_days,
        r.average_review_score

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    INNER JOIN order_reviews r
        ON f.order_id = r.order_id

    WHERE s.order_status = 'delivered'
      AND f.has_valid_delivery_timeline
)

SELECT
    CASE
        WHEN is_late_delivery
        THEN 'Late'
        ELSE 'On Time'
    END AS delivery_status,

    COUNT(*) AS reviewed_orders,

    ROUND(
        AVG(average_review_score),
        2
    ) AS average_review_score,

    ROUND(
        AVG(delivery_days),
        2
    ) AS average_delivery_days,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE average_review_score >= 4
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS positive_review_rate_pct,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE average_review_score <= 2
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS negative_review_rate_pct

FROM eligible_orders

GROUP BY
    CASE
        WHEN is_late_delivery
        THEN 'Late'
        ELSE 'On Time'
    END

ORDER BY delivery_status;


\echo ''
\echo '============================================================'
\echo '6. DELIVERY PERFORMANCE BY CUSTOMER STATE'
\echo '============================================================'

SELECT
    c.customer_state,

    COUNT(*) FILTER (
        WHERE f.has_valid_delivery_timeline
    ) AS valid_delivery_orders,

    ROUND(
        AVG(f.delivery_days)
            FILTER (
                WHERE f.has_valid_delivery_timeline
            ),
        2
    ) AS average_delivery_days,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE
                f.has_valid_delivery_timeline
                AND f.is_late_delivery
        )
        / NULLIF(
            COUNT(*) FILTER (
                WHERE f.has_valid_delivery_timeline
            ),
            0
        ),
        2
    ) AS late_delivery_rate_pct,

    ROUND(
        AVG(f.delivery_variance_days)
            FILTER (
                WHERE f.has_valid_delivery_timeline
            ),
        2
    ) AS average_delivery_variance_days

FROM analytics.fact_orders f

INNER JOIN analytics.dim_customer c
    ON f.customer_key =
       c.customer_key

INNER JOIN analytics.dim_order_status s
    ON f.order_status_key =
       s.order_status_key

WHERE s.order_status = 'delivered'

GROUP BY c.customer_state

HAVING
    COUNT(*) FILTER (
        WHERE f.has_valid_delivery_timeline
    ) >= 100

ORDER BY late_delivery_rate_pct DESC;


\echo ''
\echo '============================================================'
\echo '7. MARKETING SPEND VS SALES BY STORE'
\echo '============================================================'

WITH monthly_sales AS (

    SELECT
        DATE_TRUNC(
            'month',
            f.order_purchase_timestamp
        )::date AS month,

        f.store_key,

        SUM(f.gross_order_value)
            AS delivered_sales

    FROM analytics.fact_orders f

    INNER JOIN analytics.dim_order_status s
        ON f.order_status_key =
           s.order_status_key

    WHERE s.order_status = 'delivered'

    GROUP BY
        DATE_TRUNC(
            'month',
            f.order_purchase_timestamp
        )::date,
        f.store_key
),

monthly_marketing AS (

    SELECT
        d.full_date AS month,
        f.store_key,

        SUM(f.spend)
            AS marketing_spend

    FROM analytics.fact_marketing_spend f

    INNER JOIN analytics.dim_date d
        ON f.spend_date_key =
           d.date_key

    GROUP BY
        d.full_date,
        f.store_key
),

coverage AS (

    SELECT
        COALESCE(
            s.month,
            m.month
        ) AS month,

        COALESCE(
            s.store_key,
            m.store_key
        ) AS store_key,

        COALESCE(
            s.delivered_sales,
            0
        ) AS delivered_sales,

        COALESCE(
            m.marketing_spend,
            0
        ) AS marketing_spend

    FROM monthly_sales s

    FULL OUTER JOIN monthly_marketing m
        ON s.month = m.month
       AND s.store_key = m.store_key
)

SELECT
    ds.store_id,
    ds.store_name,
    ds.store_format,

    ROUND(
        SUM(c.delivered_sales),
        2
    ) AS delivered_sales,

    ROUND(
        SUM(c.marketing_spend),
        2
    ) AS total_marketing_spend,

    ROUND(
        SUM(
            CASE
                WHEN c.delivered_sales > 0
                THEN c.marketing_spend
                ELSE 0
            END
        ),
        2
    ) AS active_month_marketing_spend,

    COUNT(*) FILTER (
        WHERE c.delivered_sales = 0
          AND c.marketing_spend > 0
    ) AS marketing_months_without_sales,

    ROUND(
        100.0
        * SUM(c.marketing_spend)
        / NULLIF(
            SUM(c.delivered_sales),
            0
        ),
        2
    ) AS marketing_spend_pct_sales

FROM coverage c

INNER JOIN analytics.dim_store ds
    ON c.store_key = ds.store_key

GROUP BY
    ds.store_id,
    ds.store_name,
    ds.store_format

ORDER BY marketing_spend_pct_sales DESC;


\echo ''
\echo '============================================================'
\echo '8. REVIEW SCORE DISTRIBUTION'
\echo '============================================================'

SELECT
    r.review_score,

    COUNT(*) AS review_records,

    ROUND(
        100.0
        * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS review_share_pct

FROM analytics.fact_reviews r

INNER JOIN analytics.fact_orders o
    ON r.order_id = o.order_id

INNER JOIN analytics.dim_order_status s
    ON o.order_status_key =
       s.order_status_key

WHERE s.order_status = 'delivered'

GROUP BY r.review_score

ORDER BY r.review_score;
