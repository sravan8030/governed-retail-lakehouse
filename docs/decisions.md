# Design decisions

| ID | Date | Decision | Reason |
| --- | --- | --- | --- |
| D001 | 2026-10-30 | Removed the auto-created `default` schema from `retail` | Every object should live in a schema with a stated purpose; an unused default schema is where untracked, unowned tables accumulate |
| D002 | 2026-10-30 | Use a dedicated `retail` catalog rather than the workspace catalog | Keeps the project isolated and allows access to be granted at catalog level |
| D003 | 2026-11-01 | Review audit through three scoped views in `retail.dq` (`audit_users`, `audit_retail`, `audit_privileged_changes`) rather than the raw `system.access.audit` table | Raw audit is account-wide and dominated by platform service identities; scoped views give a repeatable, reviewable answer to who did what to project data |
| D004 | 2026-11-02 | Bronze stores every source column as `STRING`, reads with `inferColumnTypes => false`, keeps `_rescued_data`, and reloads with `INSERT OVERWRITE` (never `DROP`) | Bronze must hold values exactly as received so every later change is traceable; inference silently reformats values; `DROP` erases table history, comments and grants |
| D005 | 2026-11-02 | Convert the Excel source to CSV in a notebook with pandas `dtype=str`, not with Excel "Save As" | Repeatable and reviewable as code; Excel reformats dates and IDs (e.g. `12346` to `12346.0`) |
| D006 | 2026-11-11 | `description` is not a critical data element | An error in it changes no reported number; critical status is reserved for fields that drive revenue, customer or geographic figures |
| D007 | 2026-11-11 | Lines without a customer ID stay as individual flagged rows (`has_customer = false`), not grouped as one "unknown customer" | Grouping would create one customer holding 22.77% of rows and distort customer counts and rankings (F006) |
| D008 | 2026-11-11 | Treatment of discounts and postage in net product sales is left to the business owner; Gold shows them as separate measures until decided | It's a business definition, not a data decision; reporting them separately avoids building in an assumption |
