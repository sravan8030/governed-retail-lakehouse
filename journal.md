# Build journal

## 2026-10-30

**Done**
- Set up Databricks Free Edition and explored the interface.
- Created the `retail` catalog and schemas `bronze`, `silver`, `gold` and `dq`, each with a description stating its purpose.
- Removed the auto-created `default` schema (see D001 in `docs/decisions.md`).
- Confirmed 100% description coverage on schemas with a query on `retail.information_schema.schemata`.

**Learned**
- Unity Catalog metadata can be queried, so completeness checks on metadata can be automated.
- The SQL editor's comment panel is for discussing a query; object descriptions live on the object itself.

**Next**
- Convert *Online Retail II* sheets to CSV, create the landing volume and upload the files.

## 2026-11-01

**Done**
- Explored `information_schema` (29 views): inventory, privileges, tags, masks and filters, constraints, routines.
- Confirmed `system.access.audit` is available in Free Edition.
- Profiled audit activity by identity: 1 human identity, 10 service identities, plus `System-User`. Machine identities generate most Unity Catalog events (one service identity alone: 10,419 events vs 2,466 human).
- Ran a privileged machine-activity review: 180 create/update/delete/permission events by 3 service identities. All traced to Databricks maintaining platform-owned objects (`system`, `samples`, `system.ai`); none changed project data or permissions. Schema updates on `retail.*` matched the times the catalog and schemas were created (background registration, no content change).
- Created three scoped audit views in `retail.dq` (`audit_users`, `audit_retail`, `audit_privileged_changes`), each with a description. See `sql/03_setup_audit_views.sql`.
- Wrote `docs/concept_map.md`: SAS/UNIX and Teradata mapped to Unity Catalog.

**Findings**
- F001: UCI's dataset listing for Online Retail II shows "541.91K Features"; the dataset has 8 columns, and 541,910 is the row count of the 2010–2011 sheet. Metadata error in a public catalogue.
- F002: Audit records human and service identities separately; `run_by` and `run_as` show delegation. Machine identities appear as IDs and need mapping to be meaningful.
- F003: The platform masks columns in its own audit data (`system.access.audit`, `system.query.history`).
- F004: Seven external HTTP connectors (Gmail, Slack, GitHub and others) exist in `system.ai`, created by the platform, not listable. In production these would need an approval record.
- F005: Reserved admin groups receive access to the `system` catalog automatically. Built-in privileged access should be documented, not discovered.

**Learned**
- `information_schema` ≈ SAS `DICTIONARY` tables / Teradata DBC views, plus owners, tags and privileges; it is permission-aware.
- Raw audit is account-wide and noisy; governance value comes from scoped views (human, project, privileged).
- Views store the query, not the data, so they are always current with the source.
- `BROWSE` separates discovering data from accessing it; ABAC turns classification (tags) into enforcement, so tag quality becomes a control.

## 2026-11-02

**Done**
- Created the landing volume `retail.bronze.landing` with a description.
- Uploaded the original `online_retail_II.xlsx` and converted both sheets to CSV in a Databricks notebook (pandas, `dtype=str`) rather than Excel "Save As", so dates and IDs are not reformatted and the step is repeatable. See `pgms/Excel_to_CSV.py`.
  - Year 2009-2010: 525,461 rows
  - Year 2010-2011: 541,910 rows
- Created `retail.bronze.transactions`: all columns `STRING`, every column described, plus load metadata (`_source_file`, `_loaded_at`) and `_rescued_data`. See `sql/02_bronze_load.sql`.
- Loaded Bronze and reconciled to source:

| Check | Expected | Actual | Result |
| --- | --- | --- | --- |
| 2009–2010 file | 525,461 | 525,461 | Pass |
| 2010–2011 file | 541,910 | 541,910 | Pass |
| Total | 1,067,371 | 1,067,371 | Pass |
| Rows with `_rescued_data` | 0 | 0 | Pass |

**Issue found and closed (same day)**
- The first Bronze `INSERT` read the CSVs without `inferColumnTypes => false`, so values were type-inferred (dates as timestamps, prices as numbers) and then cast back to text. Row counts were correct, but values were not guaranteed to be byte-for-byte as received.
- Fix: dropped, recreated and reloaded `retail.bronze.transactions` with `inferColumnTypes => false`.
- Evidence: reconciliation re-run and passed (525,461 + 541,910 = 1,067,371 rows; 0 rescued). Spot-check shows source text unchanged: `invoice_date` = `2010-12-01 08:26:00`, `price` = `2.55`, `customer_id` = `17850` (no `.0` added by the Excel conversion). All columns typed `STRING`.
- Lesson: the drop-and-recreate reset the table's Delta history, so the first (inferred) load is no longer visible in `DESCRIBE HISTORY`.
- Bronze load changed in Databricks to a rerunnable pattern: `CREATE TABLE IF NOT EXISTS` then `INSERT OVERWRITE` (no `DROP`), which keeps the table's history, comments, owner, grants and tags on every rerun.

**Learned**
- `_rescued_data` ≈ SAS "invalid data" notes, except the original value is kept rather than set to missing.
- `read_files` is a built-in table-valued function (≈ `INFILE` + `PROC IMPORT`); it respects volume permissions.
- Databricks SQL: keywords and object names are case-insensitive; text values, `LIKE` and file names are case-sensitive (same as SAS on UNIX).
- Lengths: `STRING` has no declared length; `VARCHAR(n)` is a constraint, so lengths and types belong in Silver, set from profiling.
- Python basics: aliases (`pd`), library functions vs object methods, f-strings, `index=False`, indentation as `DO … END`, filtering returns a new table unless assigned.
- `TRUNCATE TABLE` has no `IF EXISTS`; `INSERT OVERWRITE` replaces contents in one atomic step and keeps the table's definition, controls and history.
- `.ipynb` (Jupyter notebook format) stores outputs as well as code, so it can carry data rows into Git. The repo holds plain source files only.

**Next**
- Copy the updated Bronze load from Databricks into `sql/02_bronze_load.sql` in the repo (the repo copy still has `DROP TABLE` and `INSERT INTO`).
- Profile Bronze (nulls, duplicates, negatives, zero prices, cancellations, non-product codes, length distributions) into `findings.md`. Planned for Wednesday 4 Nov; Bronze is ready, so it can start earlier.

## 2026-11-03 to 2026-11-04

**Done**
- Wrote `sql/04_profile_bronze.sql` (P0–P12) and profiled `retail.bronze.transactions`, then ran follow-up queries where a result raised a question (P9b–c, P10b–c, P12b).
- Logged 19 profiling findings (F006–F024) in `docs/findings.md`, each with its DQ dimension, size, open question and proposed treatment, plus a checks-run table recording when each check ran and what it returned.
- Every count reconciles back to the Bronze total of 1,067,371 rows.

**Main findings**
- Customer ID missing on 22.77% of rows (F006). Kept, flagged `has_customer`.
- 34,335 extra duplicate copies (3.22%), two-thirds from the two source files overlapping on 1–9 Dec 2010 (F008).
- Non-product lines mixed into sales: postage, fees, discounts, manual adjustments, bad debt, vouchers, test records (F012, F016, F019). Needs a `line_type` classification driven by a reference list, not a code pattern.
- No product master: one stock code carries several descriptions (F014). Whitespace explains only 78 of 5,698 distinct descriptions (F024), so a frequency rule is still needed.
- All 135 days with no data are explained: 104 Saturdays (no Saturday trading), 17 UK bank holidays including the one-off Royal Wedding holiday, holiday Sundays and the Christmas shutdown (F015). The one Saturday with data (5 Dec 2009) is genuine trading.
- Country is free text: placeholder "Unspecified", regions that aren't countries, mixed naming (EIRE, USA, RSA) (F022). 13 customers have two countries; 5 use both at the same time, so country can't be a pure customer attribute (F023).
- Free-text fields carry staff names and write-off reasons (F017, F021).

**Silver design taken from profiling**
- Derived columns: `line_type`, `invoice_type`; flags `has_customer`, `is_free_item`, `is_return`, `country_conflict`.
- Quarantine reasons: `source_overlap`, `duplicate_in_file`, `test_record`, `unknown_invoice_type`, `unknown_country`.
- Reference tables, each needing an owner: stock-code classification, country to ISO 3166 code, trading calendar, write-off reason codes.
- Geographic reporting uses the country on the transaction, never the customer's country.

**Learned**
- Profile, don't fix: Bronze stays as received; every anomaly becomes a finding with a treatment, applied in Silver.
- Count a problem at both levels. Whitespace affects 19.9% of rows but only 1.4% of distinct values; reporting only the first overstates it.
- Placeholders such as "Unspecified" are missing values a NULL/blank check can't see.
- Reference data that can't be derived by rule (one-off holidays, substitute days, non-product codes) has to be loaded from a maintained list.
- Code length and pattern can't classify stock codes: products and non-products overlap at lengths 4 to 8.
- SQL: `UNPIVOT` (≈ `PROC TRANSPOSE`); `COUNT(DISTINCT struct(...))` so NULLs count; `sequence()` + `explode` to build a calendar; `LEFT ANTI JOIN` to find what's missing; `try_cast` to test types on `STRING` columns.

**Next**
- Save the follow-up queries (P9b–c, P10b–c, P12b) into `sql/04_profile_bronze.sql`.
- Copy the `INSERT OVERWRITE` Bronze load into `sql/02_bronze_load.sql`; remove the stray "k" at the end of `sql/03_setup_audit_views.sql`; commit and push.
- Record decisions D003–D005 in `docs/decisions.md`.
- CDMP Fundamentals exam on Saturday 7 Nov takes priority.
- After the exam: definitions, critical data elements and `rules/silver_transactions.yaml`, then the Silver build.
