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
