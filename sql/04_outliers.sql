CREATE TABLE visitor_flags AS
SELECT visitorid,
       count(*)                                    AS events_cnt,
       count(*) FILTER (WHERE event = 'view')      AS views,
       count(*) FILTER (WHERE event = 'addtocart') AS carts,
       count(DISTINCT transactionid)               AS orders,
       (    count(*) >= 100
        AND count(DISTINCT transactionid) = 0
        AND count(*) FILTER (WHERE event = 'view') >= 0.99 * count(*)
       )                                           AS is_suspected_bot
FROM events_clean
GROUP BY visitorid;

CREATE INDEX idx_visitor_flags_id ON visitor_flags (visitorid);

SELECT is_suspected_bot,
       count(*)        AS visitors,
       sum(events_cnt) AS events,
       round(100.0 * sum(events_cnt) / sum(sum(events_cnt)) OVER (), 2) AS events_pct
FROM visitor_flags
GROUP BY is_suspected_bot;

SELECT count(*)                                              AS buyers,
       round(avg(orders), 2)                                 AS avg_orders,
       percentile_cont(0.5)   WITHIN GROUP (ORDER BY orders) AS median_orders,
       percentile_cont(0.9)   WITHIN GROUP (ORDER BY orders) AS p90,
       percentile_cont(0.99)  WITHIN GROUP (ORDER BY orders) AS p99,
       percentile_cont(0.999) WITHIN GROUP (ORDER BY orders) AS p999,
       max(orders)                                           AS max_orders
FROM visitor_flags
WHERE orders > 0;

SELECT CASE WHEN orders = 1  THEN '1 order'
            WHEN orders <= 6 THEN '2-6 orders'
            ELSE '7+ orders (wholesale)' END                AS segment,
       count(*)                                             AS buyers,
       sum(orders)                                          AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2)   AS buyers_pct,
       round(100.0 * sum(orders) / sum(sum(orders)) OVER (), 2) AS orders_pct
FROM visitor_flags
WHERE orders > 0
GROUP BY 1
ORDER BY min(orders);

ALTER TABLE visitor_flags ADD COLUMN is_wholesale boolean;

UPDATE visitor_flags
SET is_wholesale = (orders >= 7);

SELECT is_wholesale, count(*) AS visitors
FROM visitor_flags
GROUP BY is_wholesale;

WITH first_events AS (
    SELECT e.visitorid,
           MIN(e.ts) FILTER (WHERE e.event = 'view')        AS first_view,
           MIN(e.ts) FILTER (WHERE e.event = 'addtocart')   AS first_cart,
           MIN(e.ts) FILTER (WHERE e.event = 'transaction') AS first_purchase
    FROM events_clean e
    JOIN visitor_flags f USING (visitorid)
    WHERE NOT f.is_suspected_bot
    GROUP BY e.visitorid
)
SELECT count(*) FILTER (WHERE first_view IS NOT NULL) AS step1_view,
       count(*) FILTER (WHERE first_view IS NOT NULL
                          AND first_cart >= first_view) AS step2_cart,
       count(*) FILTER (WHERE first_view IS NOT NULL
                          AND first_cart >= first_view
                          AND first_purchase >= first_cart) AS step3_purchase,
       round(100.0 * count(*) FILTER (WHERE first_view IS NOT NULL
                          AND first_cart >= first_view)
             / count(*) FILTER (WHERE first_view IS NOT NULL), 2) AS view_to_cart_pct,
       round(100.0 * count(*) FILTER (WHERE first_view IS NOT NULL
                          AND first_cart >= first_view
                          AND first_purchase >= first_cart)
             / count(*) FILTER (WHERE first_view IS NOT NULL
                          AND first_cart >= first_view), 2) AS cart_to_purchase_pct
FROM first_events;