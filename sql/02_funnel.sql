WITH visitor_steps AS (
    SELECT visitorid,
           MAX(CASE WHEN event = 'view'        THEN 1 ELSE 0 END) AS has_view,
           MAX(CASE WHEN event = 'addtocart'   THEN 1 ELSE 0 END) AS has_cart,
           MAX(CASE WHEN event = 'transaction' THEN 1 ELSE 0 END) AS has_purchase
    FROM events_clean
    GROUP BY visitorid
)
SELECT sum(has_view)     AS viewers,
       sum(has_cart)     AS carters,
       sum(has_purchase) AS buyers,
       round(100.0 * sum(has_cart)     / sum(has_view), 2) AS view_to_cart_pct,
       round(100.0 * sum(has_purchase) / sum(has_cart), 2) AS cart_to_purchase_pct,
       round(100.0 * sum(has_purchase) / sum(has_view), 2) AS view_to_purchase_pct
FROM visitor_steps;

WITH first_events AS (
    SELECT visitorid,
           MIN(ts) FILTER (WHERE event = 'view')        AS first_view,
           MIN(ts) FILTER (WHERE event = 'addtocart')   AS first_cart,
           MIN(ts) FILTER (WHERE event = 'transaction') AS first_purchase
    FROM events_clean
    GROUP BY visitorid
)
SELECT count(*) FILTER (WHERE first_purchase IS NOT NULL)                               AS buyers,
       count(*) FILTER (WHERE first_purchase IS NOT NULL AND first_cart IS NULL)        AS buyers_without_cart,
       count(*) FILTER (WHERE first_purchase IS NOT NULL AND first_view IS NULL)        AS buyers_without_view
FROM first_events;

WITH first_events AS (
    SELECT visitorid,
           MIN(ts) FILTER (WHERE event = 'view')        AS first_view,
           MIN(ts) FILTER (WHERE event = 'addtocart')   AS first_cart,
           MIN(ts) FILTER (WHERE event = 'transaction') AS first_purchase
    FROM events_clean
    GROUP BY visitorid
),
funnel AS (
    SELECT count(*) FILTER (WHERE first_view IS NOT NULL) AS step1_view,
           count(*) FILTER (WHERE first_view IS NOT NULL
                              AND first_cart >= first_view) AS step2_cart,
           count(*) FILTER (WHERE first_view IS NOT NULL
                              AND first_cart >= first_view
                              AND first_purchase >= first_cart) AS step3_purchase
    FROM first_events
)
SELECT step1_view,
       step2_cart,
       step3_purchase,
       round(100.0 * step2_cart     / step1_view, 2) AS view_to_cart_pct,
       round(100.0 * step3_purchase / step2_cart, 2) AS cart_to_purchase_pct,
       round(100.0 * step3_purchase / step1_view, 2) AS view_to_purchase_pct
FROM funnel;