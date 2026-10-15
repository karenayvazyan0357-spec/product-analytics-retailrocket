CREATE TABLE visitor_day AS
SELECT ts::date                                          AS day,
       visitorid,
       (extract(isodow FROM ts::date) IN (6, 7))         AS is_weekend,
       bool_or(event = 'transaction')                    AS bought
FROM events_clean
WHERE ts::date BETWEEN '2015-05-04' AND '2015-09-15'
  AND visitorid NOT IN (SELECT visitorid FROM visitor_flags WHERE is_suspected_bot)
GROUP BY ts::date, visitorid;

CREATE VIEW v_funnel AS
WITH f AS (
    SELECT visitorid,
           MIN(ts) FILTER (WHERE event = 'view')        AS first_view,
           MIN(ts) FILTER (WHERE event = 'addtocart')   AS first_cart,
           MIN(ts) FILTER (WHERE event = 'transaction') AS first_purchase
    FROM events_clean
    WHERE visitorid NOT IN (SELECT visitorid FROM visitor_flags WHERE is_suspected_bot)
    GROUP BY visitorid
),
s AS (
    SELECT count(*) FILTER (WHERE first_view IS NOT NULL) AS s1,
           count(*) FILTER (WHERE first_view IS NOT NULL AND first_cart >= first_view) AS s2,
           count(*) FILTER (WHERE first_view IS NOT NULL AND first_cart >= first_view
                              AND first_purchase >= first_cart) AS s3
    FROM f
)
SELECT 1 AS step_no, '1. Просмотр' AS step, s1 AS visitors FROM s
UNION ALL SELECT 2, '2. Корзина',  s2 FROM s
UNION ALL SELECT 3, '3. Покупка',  s3 FROM s;

CREATE VIEW v_daily AS
SELECT ts::date AS day,
       count(DISTINCT visitorid) AS visitors,
       count(DISTINCT visitorid) FILTER (WHERE event = 'addtocart')   AS carters,
       count(DISTINCT visitorid) FILTER (WHERE event = 'transaction') AS buyers,
       round(100.0 * count(DISTINCT visitorid) FILTER (WHERE event = 'transaction')
             / count(DISTINCT visitorid), 3) AS conv_pct
FROM events_clean
WHERE ts::date BETWEEN '2015-05-04' AND '2015-09-15'
  AND visitorid NOT IN (SELECT visitorid FROM visitor_flags WHERE is_suspected_bot)
GROUP BY ts::date;

CREATE VIEW v_segments AS
SELECT CASE WHEN orders = 1  THEN '1 заказ'
            WHEN orders <= 6 THEN '2-6 заказов'
            ELSE '7+ заказов' END AS segment,
       count(*)    AS buyers,
       sum(orders) AS orders
FROM visitor_flags
WHERE orders > 0
GROUP BY 1;

SELECT * FROM v_funnel ORDER BY step_no;