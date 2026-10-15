SELECT event,
       count(*) AS cnt,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS share_pct
FROM events
GROUP BY event
ORDER BY cnt DESC;

SELECT count(DISTINCT visitorid)     AS visitors,
       count(DISTINCT itemid)        AS items,
       count(DISTINCT transactionid) AS transactions
FROM events;

SELECT event,
       count(*)                       AS total_rows,
       count(transactionid)           AS with_transaction_id,
       count(*) - count(transactionid) AS null_transaction_id
FROM events
GROUP BY event;

SELECT count(*)          AS duplicate_groups,
       sum(cnt - 1)      AS extra_rows
FROM (
    SELECT ts_ms, visitorid, event, itemid, transactionid, count(*) AS cnt
    FROM events
    GROUP BY ts_ms, visitorid, event, itemid, transactionid
    HAVING count(*) > 1
) AS d;

SELECT event,
       count(*)     AS duplicate_groups,
       sum(cnt - 1) AS extra_rows
FROM (
    SELECT ts_ms, visitorid, event, itemid, transactionid, count(*) AS cnt
    FROM events
    GROUP BY ts_ms, visitorid, event, itemid, transactionid
    HAVING count(*) > 1
) AS d
GROUP BY event;

CREATE TABLE events_clean AS
SELECT DISTINCT
       ts_ms,
       to_timestamp(ts_ms / 1000.0) AS ts,
       visitorid,
       event,
       itemid,
       transactionid
FROM events;

CREATE INDEX idx_events_clean_visitor ON events_clean (visitorid);
CREATE INDEX idx_events_clean_event   ON events_clean (event);
