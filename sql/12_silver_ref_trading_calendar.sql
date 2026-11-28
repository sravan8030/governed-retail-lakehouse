-- 12_silver_ref_trading_calendar.sql
-- Reference table 1 of 4: expected trading days (F015).
-- Built from published facts and business rules, NOT derived from the sales data:
-- a calendar derived from the data would label a real outage as a closed day.
-- Run as a member of retail_all_regions: the row filter on Bronze applies to the reconciliation in step 4.

--Step 1: the table, with constraints that refuse inconsistent rows
CREATE TABLE IF NOT EXISTS retail.silver.ref_trading_calendar (
  business_date      DATE    NOT NULL COMMENT 'Calendar date, UK local time (timestamps in the source carry no time zone)',
  day_name           STRING           COMMENT 'Mon to Sun',
  is_trading_day     BOOLEAN NOT NULL COMMENT 'True if the business is expected to trade and send data that day',
  non_trading_reason STRING           COMMENT 'saturday | bank_holiday | holiday_sunday | christmas_shutdown. NULL on trading days',
  holiday_name       STRING           COMMENT 'Published name, for bank holidays only',
  note               STRING           COMMENT 'Exceptions and assumptions behind the entry',
  source             STRING           COMMENT 'Where the entry comes from: published list, business rule, or observed and pending confirmation',
  CONSTRAINT pk_ref_trading_calendar PRIMARY KEY (business_date)
) COMMENT 'Expected trading days for the UK online retailer, 1 Dec 2009 to 31 Dec 2011. Used by freshness and volume monitors so closed days are not raised as missing data (F015). Owned by retail_data_stewards';

-- PRIMARY KEY is informational only (not enforced). CHECK constraints ARE enforced: a write that breaks one fails.
ALTER TABLE retail.silver.ref_trading_calendar ADD CONSTRAINT valid_reason
  CHECK (non_trading_reason IS NULL OR non_trading_reason IN ('saturday', 'bank_holiday', 'holiday_sunday', 'christmas_shutdown'));
ALTER TABLE retail.silver.ref_trading_calendar ADD CONSTRAINT reason_matches_flag
  CHECK ((is_trading_day AND non_trading_reason IS NULL) OR (NOT is_trading_day AND non_trading_reason IS NOT NULL));

--Step 2: load. Holidays come from a list, not a rule: 29 Apr 2011 (Royal Wedding) can't be calculated.
INSERT OVERWRITE retail.silver.ref_trading_calendar
  (business_date, day_name, is_trading_day, non_trading_reason, holiday_name, note, source)
WITH dates AS (
  SELECT explode(sequence(DATE'2009-12-01', DATE'2011-12-31', INTERVAL 1 DAY)) AS business_date
),
listed AS (
  SELECT * FROM VALUES
    -- England and Wales bank holidays in range (17)
    (DATE'2009-12-25', 'bank_holiday', 'Christmas Day'),
    (DATE'2009-12-28', 'bank_holiday', 'Boxing Day (substitute day)'),
    (DATE'2010-01-01', 'bank_holiday', 'New Year''s Day'),
    (DATE'2010-04-02', 'bank_holiday', 'Good Friday'),
    (DATE'2010-04-05', 'bank_holiday', 'Easter Monday'),
    (DATE'2010-05-03', 'bank_holiday', 'Early May bank holiday'),
    (DATE'2010-05-31', 'bank_holiday', 'Spring bank holiday'),
    (DATE'2010-08-30', 'bank_holiday', 'Summer bank holiday'),
    (DATE'2010-12-27', 'bank_holiday', 'Christmas Day (substitute day)'),
    (DATE'2010-12-28', 'bank_holiday', 'Boxing Day (substitute day)'),
    (DATE'2011-01-03', 'bank_holiday', 'New Year''s Day (substitute day)'),
    (DATE'2011-04-22', 'bank_holiday', 'Good Friday'),
    (DATE'2011-04-25', 'bank_holiday', 'Easter Monday'),
    (DATE'2011-04-29', 'bank_holiday', 'Wedding of Prince William and Catherine Middleton'),
    (DATE'2011-05-02', 'bank_holiday', 'Early May bank holiday'),
    (DATE'2011-05-30', 'bank_holiday', 'Spring bank holiday'),
    (DATE'2011-08-29', 'bank_holiday', 'Summer bank holiday'),
    -- Sundays inside holiday periods (6). Candidates; step 4 confirms them against the data
    (DATE'2009-12-27', 'holiday_sunday', NULL),
    (DATE'2010-01-03', 'holiday_sunday', NULL),
    (DATE'2010-04-04', 'holiday_sunday', 'Easter Sunday'),
    (DATE'2010-12-26', 'holiday_sunday', NULL),
    (DATE'2011-01-02', 'holiday_sunday', NULL),
    (DATE'2011-04-24', 'holiday_sunday', 'Easter Sunday'),
    -- Christmas shutdown weekdays (8)
    (DATE'2009-12-24', 'christmas_shutdown', NULL),
    (DATE'2009-12-29', 'christmas_shutdown', NULL),
    (DATE'2009-12-30', 'christmas_shutdown', NULL),
    (DATE'2009-12-31', 'christmas_shutdown', NULL),
    (DATE'2010-12-24', 'christmas_shutdown', NULL),
    (DATE'2010-12-29', 'christmas_shutdown', NULL),
    (DATE'2010-12-30', 'christmas_shutdown', NULL),
    (DATE'2010-12-31', 'christmas_shutdown', NULL)
  AS t(business_date, reason, holiday_name)
),
classified AS (
  SELECT d.business_date,
         l.holiday_name,
         coalesce(l.reason,
                  CASE WHEN dayofweek(d.business_date) = 7 AND d.business_date <> DATE'2009-12-05'
                       THEN 'saturday' END) AS non_trading_reason
  FROM dates d
  LEFT JOIN listed l ON l.business_date = d.business_date
)
SELECT business_date,
       date_format(business_date, 'E')  AS day_name,
       non_trading_reason IS NULL       AS is_trading_day,
       non_trading_reason,
       holiday_name,
       CASE WHEN business_date = DATE'2009-12-05'
            THEN 'Saturday with 402 rows in 32 invoices (F015). Treated as a one-off opening; business confirmation pending'
            WHEN non_trading_reason = 'christmas_shutdown'
            THEN 'Shutdown 24 and 29-31 Dec; business confirmation pending (definitions.md open question 4)'
       END AS note,
       CASE WHEN non_trading_reason = 'bank_holiday'                         THEN 'Published list: gov.uk bank holidays, England and Wales'
            WHEN non_trading_reason IN ('holiday_sunday', 'christmas_shutdown') THEN 'Observed in data (F015); business confirmation pending'
            WHEN non_trading_reason = 'saturday'                             THEN 'Business rule: no Saturday trading (F015)'
            WHEN business_date = DATE'2009-12-05'                            THEN 'Exception to the Saturday rule (F015)'
            ELSE 'Business rule: default trading day'
       END AS source
FROM classified;

--Step 3: ownership and business accountability (D013). Stewards maintain reference data; owners are accountable for it
ALTER TABLE retail.silver.ref_trading_calendar OWNER TO `retail_data_stewards`;
ALTER TABLE retail.silver.ref_trading_calendar
  SET TAGS ('data_owner' = 'retail_data_owners', 'data_steward' = 'retail_data_stewards');

--Step 4: evidence
-- 4a. Totals over the data range. Expect: trading 604; saturday 104; bank_holiday 17; holiday_sunday 6; christmas_shutdown 8 (739 days)
/*
SELECT is_trading_day, non_trading_reason, COUNT(*) AS days, sum(count(*)) over (order by is_trading_day desc, count(*) desc, non_trading_reason rows between unbounded preceding and current row ) as running_total, 
round(100*count(*)/sum(count(*)) over(),1) as pct_of_days,
ROUND(100 * SUM(days) OVER (ORDER BY is_trading_day DESC, days DESC, non_trading_reason
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / SUM(days) OVER (), 1)    
FROM retail.silver.ref_trading_calendar
WHERE business_date BETWEEN DATE'2009-12-01' AND DATE'2011-12-09'
GROUP BY ALL
ORDER BY is_trading_day DESC, days DESC;
--********************/;

WITH tst1 AS (
  SELECT is_trading_day, non_trading_reason, COUNT(*) AS days
  FROM retail.silver.ref_trading_calendar
  WHERE business_date BETWEEN DATE'2009-12-01' AND DATE'2011-12-09'
  GROUP BY ALL
)
SELECT *,
       SUM(days) OVER (ORDER BY is_trading_day DESC, days DESC, non_trading_reason
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)           AS running_total,
       ROUND(100 * days / SUM(days) OVER (), 1)                                    AS pct_of_days,
       ROUND(100 * SUM(days) OVER (ORDER BY is_trading_day DESC, days DESC, non_trading_reason
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                 / SUM(days) OVER (), 1)                                           AS running_pct
FROM tst1
ORDER BY is_trading_day DESC, days DESC, non_trading_reason;


--***********;

-- 4b. Reconciliation to observed data (target: 0 rows).
-- A trading day with no data = missing data or a calendar error; a non-trading day with data = calendar error.
-- First check the parse: expect 0 unparsed invoice dates
SELECT COUNT_IF(try_to_timestamp(invoice_date) IS NULL) AS unparsed
FROM retail.bronze.transactions;

WITH observed AS (
  SELECT to_date(try_to_timestamp(invoice_date)) AS business_date, COUNT(*) AS total_rows
  FROM retail.bronze.transactions
  GROUP BY 1
)
SELECT c.business_date, c.day_name, c.is_trading_day, c.non_trading_reason, o.total_rows
FROM retail.silver.ref_trading_calendar c
LEFT JOIN observed o ON o.business_date = c.business_date
WHERE c.business_date BETWEEN DATE'2009-12-01' AND DATE'2011-12-09'
  AND (   (c.is_trading_day     AND o.total_rows IS NULL)
       OR (NOT c.is_trading_day AND o.total_rows IS NOT NULL))
ORDER BY c.business_date;

-- 4c. Ownership and tags
SELECT table_name, table_owner, comment
FROM retail.information_schema.tables
WHERE table_schema = 'silver';

SELECT tag_name, tag_value
FROM retail.information_schema.table_tags
WHERE schema_name = 'silver' AND table_name = 'ref_trading_calendar';

--Step 5: negative test, run once, then comment out.
-- Expect an error: CHECK constraint reason_matches_flag violated (a closed day with no reason)
-- INSERT INTO retail.silver.ref_trading_calendar (business_date, day_name, is_trading_day, non_trading_reason)
-- VALUES (DATE'2012-01-01', 'Sun', false, NULL);

-- Then rerun the governance controls: CTL_TAG_VOCABULARY and CTL_OWNERSHIP_NO_PERSON, expect 0 rows each
