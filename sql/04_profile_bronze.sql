-- 04_profile_bronze.sql
-- Profiles retail.bronze.transactions before any rules are written.
-- Purpose: measure, don't fix. Every result goes into findings.md with its DQ dimension.
-- All Bronze columns are STRING, so numeric and date checks use try_cast / try_to_timestamp,
-- which return NULL instead of failing when a value can't be converted.
-- SAS anchors: P1 ~ PROC MEANS NMISS, P4-P6 ~ PROC FREQ, P8 ~ PROC MEANS MIN MAX.


-- P0. Row count (baseline: 1,067,371)
SELECT COUNT(*) AS total_rows FROM retail.bronze.transactions;


-- P1. Completeness: NULL or blank per source column
SELECT
  COUNT(*)                                                         AS total_rows,
  SUM(CASE WHEN invoice      IS NULL OR trim(invoice)      = '' THEN 1 ELSE 0 END) AS missing_invoice,
  SUM(CASE WHEN stock_code   IS NULL OR trim(stock_code)   = '' THEN 1 ELSE 0 END) AS missing_stock_code,
  SUM(CASE WHEN description  IS NULL OR trim(description)  = '' THEN 1 ELSE 0 END) AS missing_description,
  SUM(CASE WHEN quantity     IS NULL OR trim(quantity)     = '' THEN 1 ELSE 0 END) AS missing_quantity,
  SUM(CASE WHEN invoice_date IS NULL OR trim(invoice_date) = '' THEN 1 ELSE 0 END) AS missing_invoice_date,
  SUM(CASE WHEN price        IS NULL OR trim(price)        = '' THEN 1 ELSE 0 END) AS missing_price,
  SUM(CASE WHEN customer_id  IS NULL OR trim(customer_id)  = '' THEN 1 ELSE 0 END) AS missing_customer_id,
  SUM(CASE WHEN country      IS NULL OR trim(country)      = '' THEN 1 ELSE 0 END) AS missing_country
FROM retail.bronze.transactions;


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


-- P3. Validity: values that can't be read as their intended type
SELECT
  SUM(CASE WHEN quantity     IS NOT NULL AND try_cast(quantity AS INT)              IS NULL THEN 1 ELSE 0 END) AS quantity_not_integer,
  SUM(CASE WHEN price        IS NOT NULL AND try_cast(price AS DECIMAL(12,4))       IS NULL THEN 1 ELSE 0 END) AS price_not_numeric,
  SUM(CASE WHEN invoice_date IS NOT NULL AND try_to_timestamp(invoice_date, 'yyyy-MM-dd HH:mm:ss') IS NULL THEN 1 ELSE 0 END) AS date_not_parseable,
  SUM(CASE WHEN customer_id  IS NOT NULL AND customer_id NOT RLIKE '^[0-9]+$'                      THEN 1 ELSE 0 END) AS customer_id_not_digits
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


-- P10. Consistency: country values (look for spellings, codes or 'Unspecified')
SELECT country, COUNT(*) AS rows
FROM retail.bronze.transactions
GROUP BY country
ORDER BY rows DESC;


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
