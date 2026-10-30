# Design decisions

| ID | Date | Decision | Reason |
| --- | --- | --- | --- |
| D001 | 2026-10-30 | Removed the auto-created `default` schema from `retail` | Every object should live in a schema with a stated purpose; an unused default schema is where untracked, unowned tables accumulate |
| D002 | 2026-10-30 | Use a dedicated `retail` catalog rather than the workspace catalog | Keeps the project isolated and allows access to be granted at catalog level |
