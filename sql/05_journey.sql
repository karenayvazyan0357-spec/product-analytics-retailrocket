CREATE TABLE visitor_journey AS
WITH firsts AS (
    SELECT visitorid,
           MIN(ts) FILTER (WHERE event = 'view')        AS first_view,
           MIN(ts) FILTER (WHERE event = 'addtocart')   AS first_cart,
           MIN(ts) FILTER (WHERE event = 'transaction') AS first_purchase
    FROM events_clean
    GROUP BY visitorid
),
pre AS (
    SELECT e.visitorid,
           count(*) FILTER (WHERE e.event = 'view')                    AS views_before_action,
           count(DISTINCT e.itemid) FILTER (WHERE e.event = 'view')    AS items_before_action
    FROM events_clean e
    JOIN firsts f USING (visitorid)
    WHERE e.ts < LEAST(f.first_cart, f.first_purchase, TIMESTAMPTZ 'infinity')
    GROUP BY e.visitorid
)
SELECT f.visitorid,
       f.first_view,
       f.first_cart,
       f.first_purchase,
       COALESCE(p.views_before_action, 0) AS views_before_action,
       COALESCE(p.items_before_action, 0) AS items_before_action,
       (f.first_cart IS NOT NULL OR f.first_purchase IS NOT NULL) AS has_action,
       (f.first_purchase IS NOT NULL)                              AS has_purchase
FROM firsts f
LEFT JOIN pre p USING (visitorid)
JOIN visitor_flags v USING (visitorid)
WHERE NOT v.is_suspected_bot;

SELECT CASE WHEN items_before_action = 0  THEN '0'
            WHEN items_before_action = 1  THEN '1'
            WHEN items_before_action <= 3 THEN '2-3'
            WHEN items_before_action <= 10 THEN '4-10'
            ELSE '10+' END                               AS items_viewed,
       count(*)                                          AS visitors,
       count(*) FILTER (WHERE has_action)                AS with_action,
       round(100.0 * count(*) FILTER (WHERE has_action) / count(*), 2) AS action_pct
FROM visitor_journey
GROUP BY 1
ORDER BY min(items_before_action);

SELECT count(*) AS buyers_with_view,
       percentile_cont(0.25) WITHIN GROUP (ORDER BY secs) AS p25_sec,
       percentile_cont(0.5)  WITHIN GROUP (ORDER BY secs) AS median_sec,
       percentile_cont(0.75) WITHIN GROUP (ORDER BY secs) AS p75_sec,
       percentile_cont(0.9)  WITHIN GROUP (ORDER BY secs) AS p90_sec,
       round(100.0 * count(*) FILTER (WHERE secs <= 86400) / count(*), 1) AS within_1_day_pct
FROM (
    SELECT extract(epoch FROM (first_purchase - first_view)) AS secs
    FROM visitor_journey
    WHERE first_purchase IS NOT NULL
      AND first_view IS NOT NULL
      AND first_purchase >= first_view
) t;

CREATE TABLE visitor_journey_24h AS
SELECT j.visitorid,
       count(DISTINCT e.itemid) FILTER (
           WHERE e.event = 'view'
             AND e.ts <  LEAST(COALESCE(j.first_cart, 'infinity'),
                               COALESCE(j.first_purchase, 'infinity'))
       ) AS items_24h,
       bool_or(e.event IN ('addtocart', 'transaction')
               AND e.ts < j.first_view + interval '24 hours'
               AND e.ts >= j.first_view
       ) AS action_24h
FROM visitor_journey j
JOIN events_clean e USING (visitorid)
WHERE j.first_view IS NOT NULL
  AND e.ts >= j.first_view
  AND e.ts <  j.first_view + interval '24 hours'
GROUP BY j.visitorid;

SELECT count(*) FROM visitor_journey_24h;