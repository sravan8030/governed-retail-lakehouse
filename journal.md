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
