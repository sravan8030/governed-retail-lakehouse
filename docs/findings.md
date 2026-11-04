# Findings register

Every data or metadata issue found during the build, with its DQ dimension and what happens next. Profiling measures; it doesn't fix. Fixes become Silver rules, and each rule should trace back to a finding here.

**Dimensions:** Completeness · Uniqueness · Validity · Consistency · Timeliness · Accuracy

## Metadata and platform findings

| ID | Date | Finding | Evidence | Action |
| --- | --- | --- | --- | --- |
| F001 | 2026-11-01 | UCI listing shows "541.91K Features" for a dataset with 8 columns; 541,910 is the 2010–2011 row count | UCI dataset page; notebook row count | None (external); noted as a public metadata error |
| F002 | 2026-11-01 | Audit records human and service identities separately; machine identities appear as IDs | `system.access.audit` profile by identity | Identity map in Week 2 controls register |
| F003 | 2026-11-01 | Platform masks columns in its own audit data | `updateTables` events on `system.access.audit`, `system.query.history` | None; reference example of masking |
| F004 | 2026-11-01 | Seven platform-created external HTTP connectors in `system.ai` | `createConnection` audit events | Note for Week 2: external access needs an approval record |
| F005 | 2026-11-01 | Reserved admin groups get `system` catalog access automatically | `updatePermissions` audit events | Document built-in privileged access in Week 2 |

## Bronze profiling (retail.bronze.transactions, 1,067,371 rows)

Run `sql/04_profile_bronze.sql` and fill in one row per issue. Leave a row out if the check finds nothing, but record the check as run in the summary below.

| ID | Check | Dimension | Column(s) | Rows affected | % of rows | Example | Business question | Proposed Silver treatment |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| F006 | P1 | Completeness | customer_id | 243,007 | 22.77% | blank | Is a sale without a customer valid (e.g. guest checkout)? | Keep rows (the sale happened); flag `has_customer = false`; exclude from customer-level Gold, include in sales totals |
| F007 | P1 | Completeness, Validity | description | 4,382 | 0.41% | blank description, price 0, no customer | Are these real sales or stock adjustments? | Confirmed 2026-11-04: all 4,382 rows have price = 0 and no customer, so they are non-sale records (likely stock adjustments). Route to quarantine or flag `is_sale = false`; exclude from sales metrics |
| F008 | P2 | Uniqueness | all source columns | 34,335 extra copies (1,067,371 rows; 1,033,036 distinct) | 3.22% | One identical line appears 20 times, all from the same file and same load | Genuine repeat lines or source duplication? Not a load duplicate: copies share one file and one load time. Pending: check for duplicates across the two files (sheets may overlap in early Dec 2010) | Keep first copy (`ROW_NUMBER() = 1`); route extra copies to quarantine with reason `duplicate`, pending business confirmation |
| F009 | P4 | Validity | quantity | | | | Are negatives returns, errors or adjustments? | |
| F010 | P4 | Validity | price | | | | Are zero prices free items or errors? | |
| F011 | P5 | Validity | invoice | | | | What do non-standard invoice prefixes mean? | |
| F012 | P6 | Validity | stock_code | | | | Which codes are products, which are fees or postage? | |
| F013 | P7 | Consistency | invoice, quantity | | | | Do cancellations always have negative quantity? | |
| F014 | P8 | Consistency | stock_code, description | | | | Which description is authoritative? | |
| F015 | P9 | Timeliness | invoice_date | | | | Are gaps expected (weekends, holidays)? | |

## Checks run

| Check | Date run | Result summary |
| --- | --- | --- |
| P0 Row count | 2026-11-03 | 1,067,371 rows, matches Bronze reconciliation |
| P1 Completeness | 2026-11-03 | customer_id 22.77% missing; description 0.41% missing; all other source columns 100% complete. Follow-up 2026-11-04: all missing-description rows have price = 0 and no customer |
| P2 Duplicates | 2026-11-04 | 34,335 extra copies (3.22%). Counted with `COUNT(DISTINCT struct(...))` so rows with blank customer_id are included; examples via `ROW_NUMBER()` + `QUALIFY` |
| P3 Type validity | 2026-11-04 | 0 failures: every quantity is an integer, every price numeric, every invoice_date parses as yyyy-MM-dd HH:mm:ss, every non-blank customer_id is digits only (no `.0` from the Excel conversion). Clean result recorded as evidence |
| P4 Sign and range | | |
| P5 Invoice patterns | | |
| P6 Non-product codes | | |
| P7 Cancellation consistency | | |
| P8 Code-description consistency | | |
| P9 Date coverage | | |
| P10 Country values | | |
| P11 Length distribution | | |
| P12 Whitespace | | |
