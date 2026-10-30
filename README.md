# Governed Retail Lakehouse

A hands-on build of a governed lakehouse on Databricks Free Edition, using the *Online Retail II* transactions dataset. The focus is governance: where each control sits, which policy objective it serves, and what evidence it leaves behind.

## What this project shows

- Medallion layers (Bronze → Silver → Gold) in Unity Catalog, each with a stated purpose
- Ownership, classification (PII tags), masking, lineage and audit evidence
- Data quality rules as code, quarantine of failing rows, and a gate that stops bad data reaching Gold
- Statistical monitoring, a severity model and incident post-mortems
- Rules under version control with automated tests on every change
- A data contract (ODCS) and a DQ scorecard

## Repository layout

| Folder | Contents |
| --- | --- |
| `sql/` | Setup and governance SQL, numbered in run order |
| `rules/` | DQ rules as YAML |
| `notebooks/` | Databricks notebooks exported as source |
| `contracts/` | Data contracts (ODCS) |
| `tests/` | Small sample files used to test rules |
| `docs/` | Design decisions, registers and incident write-ups |

## Progress

| Week | Focus | Status |
| --- | --- | --- |
| 1 | Setup, Bronze load, profiling, definitions and CDEs | In progress |
| 2 | Unity Catalog governance | Not started |
| 3 | DQ rules as code, gate, monitoring, incidents | Not started |
| 4 | CI, data contract, scorecard, write-up | Not started |

## Dataset

*Online Retail II*, UCI Machine Learning Repository. The raw data is not stored in this repository; download it from the UCI site and check the licence there.
