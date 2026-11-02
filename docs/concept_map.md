# Concept map: SAS/UNIX and Teradata → Databricks Unity Catalog

The governance controls in this project aren't new. Ownership, access, metadata, audit and lineage were run for years on SAS/UNIX and Teradata, through the file system, DBC views and scripts. This map shows where each one lives on Databricks, and what the modern platform changes.

Mappings are the closest equivalents, not exact matches.

## Containers and naming

| SAS / UNIX | Teradata | Unity Catalog | Note |
| --- | --- | --- | --- |
| No direct equivalent; closest is a group of libraries for one business area | A whole Teradata system, or a top-level parent database in the hierarchy | **Catalog** (`retail`) | The extra top level is a governance boundary for a domain or environment |
| Library (`LIBNAME`) | Database (or user) | **Schema** (`retail.bronze`) | |
| Dataset | Table | **Table** | |
| Directory holding raw files | Landing area outside the database | **Volume** (`retail.bronze.landing`) | Governed storage for files, under the same permissions as tables |
| `libref.dataset` (two levels) | `database.table` (two levels) | `catalog.schema.table` (three levels) | Always use full three-part names |

**Naming trap:** a SAS *catalog* (`.sas7bcat`) stores formats and macros, not data. A Unity Catalog *catalog* is the top-level container for schemas.

## Metadata

| SAS / UNIX | Teradata | Unity Catalog | What changes |
| --- | --- | --- | --- |
| `DICTIONARY` tables, `sashelp.vtable` and `vcolumn` | DBC views (`DBC.TablesV`, `DBC.ColumnsV`) | `information_schema` (`tables`, `columns`, `schemata`) | Standard ANSI views; persistent and shared rather than session-based |
| Dataset `LABEL=` and column labels | `COMMENT` on tables and columns | `COMMENT ON TABLE`, `ALTER COLUMN … COMMENT` | Descriptions sit on the object, visible in the Catalog screens |
| Business definitions in a separate dictionary or spreadsheet | Same | Comments plus tags on the object | Definitions live with the data, so coverage can be checked with a query |
| Not available | Not available | Tags (e.g. `pii`) via `information_schema.column_tags` | Classification is queryable metadata |

## Ownership and access

| SAS / UNIX | Teradata | Unity Catalog | What changes |
| --- | --- | --- | --- |
| `chown` | Database or object owner | `ALTER … OWNER TO` | Ownership recorded in the catalog, not the file system |
| `x` on a directory (pass through) | Access to the parent database | `USE CATALOG`, `USE SCHEMA` | Required to see anything inside |
| `r` on a directory (list names) | Not separate | `BROWSE` | See that tables exist and read their descriptions without reading data |
| `r` on a file | `GRANT SELECT` | `GRANT SELECT` | |
| `chmod` plus UNIX groups | Roles | `GRANT … TO group` | |
| Not available below file level | Views for column or row restriction | Column masks and row filters | Access down to a single column or row |
| `ls -l` | `DBC.AllRightsV` | `SHOW GRANTS`, `information_schema.*_privileges` | Queryable across every object |

`information_schema` only shows what the person querying is allowed to see, so the same query returns different results for different users.

## Evidence, audit and lineage

| SAS / UNIX | Teradata | Unity Catalog | What changes |
| --- | --- | --- | --- |
| SAS logs, cron output, shell history | DBQL (query logging) | `system.access.audit`, Query History | Captured automatically, in tables |
| Lineage traced by reading code | Same | Unity Catalog lineage, `system.access.table_lineage` | Captured automatically as queries run |
| Evidence compiled by hand for audit | Same | Queries on metadata and system tables | Evidence generated, not compiled |

## Code and workflow

| SAS / UNIX | Unity Catalog / Databricks |
| --- | --- |
| `PROC SQL` | Databricks SQL (almost unchanged) |
| `PROC FREQ`, `PROC MEANS` for profiling | `GROUP BY`, `COUNT(*)`, `SUM(CASE WHEN … IS NULL …)` |
| SAS macros | Parameterised queries; Python functions in notebooks |
| Shell scripts plus `cron` | Notebooks plus Jobs |
| `/* … */` and `* … ;` comments | `/* … */` and `--` comments |
| Code in a shared UNIX directory | Code in Git, with pull requests and automated tests |

## In one line

Same controls, finer grain, and evidence that's generated rather than compiled.
