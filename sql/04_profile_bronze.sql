-- 04_profile_bronze.sql
-- Profiles retail.bronze.transactions before any rules are written.
-- Purpose: measure, don't fix. Every result goes into findings.md with its DQ dimension.
-- All Bronze columns are STRING, so numeric and date checks use try_cast / try_to_timestamp,
-- which return NULL instead of failing when a value can't be converted.
-- SAS anchors: P1 ~ PROC MEANS NMISS, P4-P6 ~ PROC FREQ, P8 ~ PROC MEANS MIN MAX.


-- P0. Row count (baseline: 1,067,371)
select count(*) as total_rows from retail.bronze.transactions;

-- P1. Completeness: NULL or blank per source column
WITH P1 as (select 
    sum(CASE WHEN invoice is null or trim(invoice) = '' then 1 else 0 end)          as invoice,
    sum(case when stock_code is null or trim(stock_code) = '' then 1 else 0 end)      as stock_code,
    sum(case when description is null or trim(description) = '' then 1 else 0 end)  as description,
    sum(case when quantity is null or trim(quantity) = '' then 1 else 0 end)        as quantity,
    sum(case when invoice_date is null or trim(invoice_date) = '' then 1 else 0 end)  as invoice_date,
    sum(case when price is null or trim(price) = '' then 1 else 0 end)      as price,
    sum(case when customer_id is null or trim(customer_id) = '' then 1 else 0 end)    as customer_id,
    sum(case when country is null or trim(country) = '' then 1 else 0 end)          as country,
    count(*) as total_rows
from retail.bronze.transactions 
)
select 
column_name, 
missing_rows,
round(100*(missing_rows/total_rows), 2) as pct_missing
from P1 
unpivot (missing_rows for column_name in (invoice, stock_code, description, quantity, invoice_date, price, customer_id, country))
order by missing_rows desc;


SELECT
  CASE WHEN try_cast(price AS DECIMAL(12,4)) = 0 THEN 'price = 0' ELSE 'price > 0' END AS price_band,
  COUNT(*) AS rows,
  SUM(CASE WHEN customer_id IS NULL OR trim(customer_id) = '' THEN 1 ELSE 0 END) AS also_no_customer
FROM retail.bronze.transactions
WHERE description IS NULL OR trim(description) = ''
GROUP BY 1;


-- P2. Uniqueness: exact duplicate rows across all eight source columns
SELECT
  COUNT(*)                 AS duplicate_groups,
  SUM(copies)              AS rows_in_duplicate_groups,
  SUM(copies) - COUNT(*)   AS extra_copies
FROM (
  SELECT COUNT(*) AS copies
  FROM retail.bronze.transactions
  GROUP BY invoice, stock_code, description, quantity, invoice_date, price, customer_id, country
  HAVING COUNT(*) > 1
);

SELECT
  COUNT(*)                                   AS total_rows,
  COUNT(DISTINCT struct(invoice, stock_code, description, quantity,
                        invoice_date, price, customer_id, country)) AS distinct_rows,
  COUNT(*) - COUNT(DISTINCT struct(invoice, stock_code, description, quantity,
                        invoice_date, price, customer_id, country)) AS extra_copies
FROM retail.bronze.transactions;

SELECT *,
  ROW_NUMBER() OVER (PARTITION BY invoice, stock_code, description, quantity,
                                  invoice_date, price, customer_id, country
                     ORDER BY _loaded_at) AS copy_no
FROM retail.bronze.transactions
QUALIFY copy_no > 1
ORDER BY copy_no DESC
LIMIT 20;


SELECT COUNT(*) AS groups_in_both_files
FROM (
  SELECT COUNT(DISTINCT _source_file) AS files
  FROM retail.bronze.transactions
  GROUP BY invoice, stock_code, description, quantity, invoice_date, price, customer_id, country
)
WHERE files > 1;

SELECT _source_file,
       MIN(to_date(invoice_date)) AS first_day,
       MAX(to_date(invoice_date)) AS last_day
FROM retail.bronze.transactions
GROUP BY _source_file;

SELECT
  SUM(CASE WHEN files > 1 THEN copies - 1 ELSE 0 END)   AS extra_from_overlap_or_mixed,
  SUM(CASE WHEN files = 1 THEN copies - 1 ELSE 0 END)   AS extra_within_one_file
FROM (
  SELECT COUNT(*) AS copies, COUNT(DISTINCT _source_file) AS files
  FROM retail.bronze.transactions
  GROUP BY invoice, stock_code, description, quantity, invoice_date, price, customer_id, country
  HAVING COUNT(*) > 1
);

-- P3. Validity: values that can't be read as their intended type
SELECT
  SUM(CASE WHEN quantity IS NOT NULL AND try_cast(quantity AS INT) IS NULL THEN 1 ELSE 0 END) AS quantity_not_integer,
  SUM(CASE WHEN price IS NOT NULL AND try_cast(price AS DECIMAL(12,4)) IS NULL THEN 1 ELSE 0 END) AS price_not_numeric,
  SUM(CASE WHEN invoice_date IS NOT NULL AND try_to_timestamp(invoice_date, 'yyyy-MM-dd HH:mm:ss') IS NULL THEN 1 ELSE 0 END) AS date_not_parseable,
  SUM(CASE WHEN customer_id  IS NOT NULL AND customer_id NOT RLIKE '^[0-9]+$' THEN 1 ELSE 0 END) AS customer_id_not_digits
FROM retail.bronze.transactions;


-- P4. Validity: sign and range of quantity and price
SELECT
  SUM(CASE WHEN try_cast(quantity AS INT) < 0                  THEN 1 ELSE 0 END) AS negative_quantity,
  SUM(CASE WHEN try_cast(quantity AS INT) = 0                  THEN 1 ELSE 0 END) AS zero_quantity,
  SUM(CASE WHEN try_cast(price AS DECIMAL(12,4)) < 0           THEN 1 ELSE 0 END) AS negative_price,
  SUM(CASE WHEN try_cast(price AS DECIMAL(12,4)) = 0           THEN 1 ELSE 0 END) AS zero_price,
  MIN(try_cast(quantity AS INT))                                AS min_quantity,
  MAX(try_cast(quantity AS INT))                                AS max_quantity,
  MIN(try_cast(price AS DECIMAL(12,4)))                         AS min_price,
  MAX(try_cast(price AS DECIMAL(12,4)))                         AS max_price
FROM retail.bronze.transactions;


-- A. The extreme quantities: what are they?
SELECT invoice, stock_code, description, quantity, invoice_date, price, customer_id
FROM retail.bronze.transactions
WHERE abs(try_cast(quantity AS INT)) > 10000
ORDER BY abs(try_cast(quantity AS INT)) DESC;

-- B. Negative and very high prices: what kind of lines are they?
SELECT invoice, stock_code, description, quantity, price, customer_id
FROM retail.bronze.transactions
WHERE try_cast(price AS DECIMAL(12,4)) < 0
   OR try_cast(price AS DECIMAL(12,4)) > 1000
ORDER BY try_cast(price AS DECIMAL(12,4)) DESC;

-- C. Zero-price rows that do have a description (the 1,820)
SELECT stock_code, description, COUNT(*) AS rows
FROM retail.bronze.transactions
WHERE try_cast(price AS DECIMAL(12,4)) = 0
  AND description IS NOT NULL AND trim(description) <> ''
GROUP BY stock_code, description
ORDER BY rows DESC
LIMIT 20;

-- P5. Validity: invoice number patterns (expected: 6 digits, or C + 6 digits for cancellations)
SELECT
  CASE
    WHEN invoice RLIKE '^[0-9]{6}$'   THEN '6 digits'
    WHEN invoice RLIKE '^C[0-9]{6}$'  THEN 'C + 6 digits (cancellation)'
    ELSE 'other: ' || regexp_replace(invoice, '[0-9]', '9')
  END                    AS invoice_pattern,
  COUNT(*)               AS rows,
  MIN(invoice)           AS example
FROM retail.bronze.transactions
GROUP BY 1
ORDER BY rows DESC;


-- P6. Validity: stock codes that don't look like products
-- Typical product code: 5 digits, optionally followed by letters (e.g. 85048, 85123A)
SELECT
  stock_code,
  MIN(description)       AS example_description,
  COUNT(*)               AS rows
FROM retail.bronze.transactions
WHERE stock_code NOT RLIKE '^[0-9]{5}[A-Za-z]*$'
GROUP BY stock_code
ORDER BY rows DESC
LIMIT 50;

-- P7. Consistency: cancellation flag vs quantity sign
SELECT
  CASE WHEN invoice LIKE 'C%' THEN 'cancelled invoice' ELSE 'normal invoice' END AS invoice_type,
  CASE WHEN try_cast(quantity AS INT) < 0 THEN 'negative qty'
       WHEN try_cast(quantity AS INT) = 0 THEN 'zero qty'
       ELSE 'positive qty' END                                                    AS quantity_sign,
  COUNT(*)                                                                         AS rows
FROM retail.bronze.transactions
GROUP BY 1, 2
ORDER BY 1, 2;

-- A. The single positive cancellation
SELECT invoice, stock_code, description, quantity, invoice_date, price, customer_id
FROM retail.bronze.transactions
WHERE invoice LIKE 'C%' AND try_cast(quantity AS INT) > 0;

-- B. What are the 3,457 negative lines on normal invoices?
SELECT
  CASE WHEN description IS NULL OR trim(description) = '' THEN 'no description' ELSE 'has description' END AS descr,
  CASE WHEN try_cast(price AS DECIMAL(12,4)) = 0 THEN 'price 0' ELSE 'price > 0' END                    AS price_band,
  CASE WHEN customer_id IS NULL OR trim(customer_id) = '' THEN 'no customer' ELSE 'customer' END        AS cust,
  COUNT(*) AS rows
FROM retail.bronze.transactions
WHERE invoice NOT LIKE 'C%' AND try_cast(quantity AS INT) < 0
GROUP BY 1, 2, 3
ORDER BY rows DESC;

-- C. What are the 3,457 negative lines on normal invoices?
SELECT description, COUNT(*) AS rows
FROM retail.bronze.transactions
WHERE invoice NOT LIKE 'C%' AND try_cast(quantity AS INT) < 0
  AND description IS NOT NULL AND trim(description) <> ''
GROUP BY description ORDER BY rows DESC LIMIT 20;

-- P8. Consistency: one stock code, several descriptions
SELECT
  stock_code,
  COUNT(DISTINCT description) AS distinct_descriptions,
  MIN(description)            AS example_1,
  MAX(description)            AS example_2
FROM retail.bronze.transactions
GROUP BY stock_code
HAVING COUNT(DISTINCT description) > 1
ORDER BY distinct_descriptions DESC
LIMIT 25;

-- P9. Timeliness and coverage: date range and days with no data
SELECT
  MIN(try_to_timestamp(invoice_date, 'yyyy-MM-dd HH:mm:ss'))           AS first_invoice,
  MAX(try_to_timestamp(invoice_date, 'yyyy-MM-dd HH:mm:ss'))           AS last_invoice,
  COUNT(DISTINCT to_date(try_to_timestamp(invoice_date, 'yyyy-MM-dd HH:mm:ss'))) AS days_with_data,
  datediff(MAX(to_date(try_to_timestamp(invoice_date, 'yyyy-MM-dd HH:mm:ss'))),
           MIN(to_date(try_to_timestamp(invoice_date, 'yyyy-MM-dd HH:mm:ss')))) + 1 AS days_in_range
FROM retail.bronze.transactions;

-- P9A. Non-Saturday days with no data: check against UK bank holidays and Christmas
WITH days AS (
  SELECT explode(sequence(DATE'2009-12-01', DATE'2011-12-09', INTERVAL 1 DAY)) AS d
),
have AS (
  SELECT DISTINCT to_date(invoice_date) AS d FROM retail.bronze.transactions
)
SELECT date_format(d, 'EEEE') AS weekday, COUNT(*) AS days_without_data
FROM days LEFT ANTI JOIN have USING (d)
GROUP BY 1
ORDER BY 2 DESC;

-- P9b. Non-Saturday days with no data: check against UK bank holidays and Christmas
WITH days AS (SELECT explode(sequence(DATE'2009-12-01', DATE'2011-12-09', INTERVAL 1 DAY)) AS d),
have AS (SELECT DISTINCT to_date(invoice_date) AS d FROM retail.bronze.transactions)
SELECT d, date_format(d, 'EEEE') AS weekday
FROM days LEFT ANTI JOIN have USING (d)
WHERE date_format(d, 'EEEE') <> 'Saturday'
ORDER BY d;

-- P9c. The one Saturday that has data
SELECT to_date(invoice_date) AS d, COUNT(*) AS rows, COUNT(DISTINCT invoice) AS invoices
FROM retail.bronze.transactions
WHERE date_format(to_date(invoice_date), 'EEEE') = 'Saturday'
GROUP BY 1;

-- P10. Consistency: country values (look for spellings, codes or 'Unspecified')
SELECT country, COUNT(*) AS rows
FROM retail.bronze.transactions
GROUP BY country
ORDER BY rows DESC;

-- P10b. Customers recorded against more than one country
SELECT customer_id,
       COUNT(DISTINCT country)          AS countries,
       concat_ws(' | ', collect_set(country)) AS country_list,
       COUNT(*)                         AS rows
FROM retail.bronze.transactions
WHERE customer_id IS NOT NULL
GROUP BY customer_id
HAVING COUNT(DISTINCT country) > 1
ORDER BY countries DESC, rows DESC;

-- P10c. For the conflicting customers: when was each country used?
WITH multi AS (
  SELECT customer_id
  FROM retail.bronze.transactions
  WHERE customer_id IS NOT NULL
  GROUP BY customer_id
  HAVING COUNT(DISTINCT country) > 1
)
SELECT t.customer_id, t.country,
       MIN(to_date(t.invoice_date)) AS first_date,
       MAX(to_date(t.invoice_date)) AS last_date,
       COUNT(DISTINCT t.invoice)    AS invoices
FROM retail.bronze.transactions t
JOIN multi m USING (customer_id)
GROUP BY t.customer_id, t.country
ORDER BY t.customer_id, first_date;

-- P11. Length distribution per key column (spot hidden spaces or odd formats)
SELECT 'invoice' AS column_name, LENGTH(invoice) AS len, COUNT(*) AS rows, MIN(invoice) AS example
FROM retail.bronze.transactions GROUP BY LENGTH(invoice)
UNION ALL
SELECT 'stock_code', LENGTH(stock_code), COUNT(*), MIN(stock_code)
FROM retail.bronze.transactions GROUP BY LENGTH(stock_code)
UNION ALL
SELECT 'customer_id', LENGTH(customer_id), COUNT(*), MIN(customer_id)
FROM retail.bronze.transactions GROUP BY LENGTH(customer_id)
ORDER BY column_name, len;

-- P12. Whitespace: values with leading or trailing spaces
SELECT
  SUM(CASE WHEN description <> trim(description) THEN 1 ELSE 0 END) AS description_untrimmed,
  SUM(CASE WHEN stock_code  <> trim(stock_code)  THEN 1 ELSE 0 END) AS stock_code_untrimmed,
  SUM(CASE WHEN country     <> trim(country)     THEN 1 ELSE 0 END) AS country_untrimmed
FROM retail.bronze.transactions;

-- P12b. Whitespace detail and effect on distinct descriptions
SELECT
  SUM(CASE WHEN description <> rtrim(description) THEN 1 ELSE 0 END) AS trailing_spaces,
  SUM(CASE WHEN description <> ltrim(description) THEN 1 ELSE 0 END) AS leading_spaces,
  SUM(CASE WHEN description LIKE '%  %'           THEN 1 ELSE 0 END) AS internal_double_spaces,
  COUNT(DISTINCT description)                                          AS distinct_raw,
  COUNT(DISTINCT trim(description))                                    AS distinct_trimmed,
  COUNT(DISTINCT upper(regexp_replace(trim(description), '\\s+', ' '))) AS distinct_normalised
FROM retail.bronze.transactions;
