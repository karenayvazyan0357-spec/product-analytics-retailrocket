SELECT min(ts)::date AS first_day,
       max(ts)::date AS last_day,
       count(DISTINCT ts::date) AS active_days
FROM events_clean;

SELECT date_trunc('day', ts)::date AS day,
       count(DISTINCT visitorid)                                        AS visitors,
       count(DISTINCT visitorid) FILTER (WHERE event = 'addtocart')    AS carters,
       count(DISTINCT visitorid) FILTER (WHERE event = 'transaction')  AS buyers,
       round(100.0 * count(DISTINCT visitorid) FILTER (WHERE event = 'transaction')
             / count(DISTINCT visitorid), 3)                           AS conv_pct
FROM events_clean
GROUP BY 1
ORDER BY 1;

WITH first_visit AS (
    SELECT visitorid,
           date_trunc('week', min(ts))::date AS cohort_week
    FROM events_clean
    GROUP BY visitorid
)
SELECT cohort_week,
       count(*) AS cohort_size
FROM first_visit
GROUP BY cohort_week
ORDER BY cohort_week;

WITH first_visit AS (
    SELECT visitorid,
           date_trunc('week', min(ts))::date AS cohort_week
    FROM events_clean
    GROUP BY visitorid
),
activity AS (
    SELECT DISTINCT visitorid,
           date_trunc('week', ts)::date AS active_week
    FROM events_clean
),
cohort_activity AS (
    SELECT f.cohort_week,
           (a.active_week - f.cohort_week) / 7 AS week_n,
           count(DISTINCT a.visitorid)         AS active_users
    FROM first_visit f
    JOIN activity a USING (visitorid)
    GROUP BY f.cohort_week, week_n
)
SELECT ca.cohort_week,
       ca.week_n,
       ca.active_users,
       round(100.0 * ca.active_users /
             max(ca.active_users) FILTER (WHERE ca.week_n = 0)
                 OVER (PARTITION BY ca.cohort_week), 2) AS retention_pct
FROM cohort_activity ca
ORDER BY ca.cohort_week, ca.week_n;

WITH daily AS (
    SELECT ts::date AS day,
           count(DISTINCT visitorid) AS visitors,
           count(DISTINCT visitorid) FILTER (WHERE event = 'transaction') AS buyers
    FROM events_clean
    WHERE ts::date BETWEEN '2015-05-04' AND '2015-09-15'
    GROUP BY 1
)
SELECT extract(isodow FROM day)::int AS dow,
       count(*)                      AS days_cnt,
       round(avg(visitors))          AS avg_visitors,
       round(100.0 * sum(buyers) / sum(visitors), 3) AS conv_pct
FROM daily
GROUP BY 1
ORDER BY 1;

WITH per_visitor AS (
    SELECT ts::date AS day,
           visitorid,
           count(*)            AS events_cnt,
           bool_or(event <> 'view') AS has_action
    FROM events_clean
    WHERE ts::date IN ('2015-07-09', '2015-07-10', '2015-07-11', '2015-07-12',
                       '2015-07-23', '2015-07-24', '2015-07-25', '2015-07-26')
    GROUP BY 1, 2
)
SELECT day,
       count(*)                                   AS visitors,
       round(avg(events_cnt), 2)                  AS avg_events,
       max(events_cnt)                            AS max_events,
       round(100.0 * count(*) FILTER (WHERE events_cnt = 1) / count(*), 1) AS single_event_pct,
       round(100.0 * count(*) FILTER (WHERE has_action) / count(*), 2)     AS action_pct
FROM per_visitor
GROUP BY day
ORDER BY day;

SELECT visitorid,
       count(*)               AS events_cnt,
       count(DISTINCT itemid) AS items_cnt,
       count(*) FILTER (WHERE event = 'transaction') AS purchases
FROM events_clean
GROUP BY visitorid
ORDER BY events_cnt DESC
LIMIT 10;

WITH v AS (
    SELECT visitorid,
           count(*) AS events_cnt,
           count(*) FILTER (WHERE event = 'transaction') AS purchase_rows
    FROM events_clean
    GROUP BY visitorid
)
SELECT CASE WHEN events_cnt = 1   THEN '1'
            WHEN events_cnt <= 5  THEN '2-5'
            WHEN events_cnt <= 20 THEN '6-20'
            WHEN events_cnt <= 100 THEN '21-100'
            ELSE '100+' END                                    AS bucket,
       count(*)                                                AS visitors,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2)      AS visitors_pct,
       sum(events_cnt)                                         AS events,
       round(100.0 * sum(events_cnt) / sum(sum(events_cnt)) OVER (), 2) AS events_pct,
       sum(purchase_rows)                                      AS purchase_rows,
       count(*) FILTER (WHERE purchase_rows > 0)               AS buyers
FROM v
GROUP BY 1
ORDER BY min(events_cnt);

SELECT visitorid,
       count(*)                                        AS events_cnt,
       count(DISTINCT ts::date)                        AS active_days,
       round(count(*)::numeric / count(DISTINCT ts::date), 1) AS events_per_day,
       count(*) FILTER (WHERE event = 'view')          AS views,
       count(*) FILTER (WHERE event = 'addtocart')     AS carts,
       count(DISTINCT transactionid)                   AS orders,
       count(*) FILTER (WHERE event = 'transaction')   AS purchase_rows
FROM events_clean
GROUP BY visitorid
HAVING count(*) >= 500
ORDER BY events_cnt DESC;