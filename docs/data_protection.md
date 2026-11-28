# Data protection note: Bronze

**Scope:** `retail.bronze.transactions`, as built on 15–24 November 2026.
**Owner of this note:** `retail_data_stewards`.
**Related decisions:** D009–D017. **Related findings:** F026–F028.

## 1. What is protected, and why

| Data | Classification | Risk | Protection |
| --- | --- | --- | --- |
| `customer_id` | `pii = pseudonymous_id`, CDE | Identifies a customer through a lookup. With only 5 digits, a hash would be reversible by brute force (D010) | Fully redacted (`*****`) for everyone outside `pii_readers` |
| All rows, by `country` | Not personal data. Access is restricted for business reasons | Regional teams should see only their own markets | Row filter: rows are visible only for countries mapped to the reader's group |

No columns are tagged `direct_id` or `quasi_id` in this dataset (`docs/definitions.md` section 5).

## 2. Controls

There are three kinds of control. **Preventive** controls stop access, **guard** controls stop the protection being set up wrongly, and **detective** controls find gaps afterwards.

| # | Control | Type | Object | What it does |
| --- | --- | --- | --- | --- |
| P1 | Column-mask policy `mask_pii_pseudonymous` | Preventive | ABAC policy on schema `retail.bronze` | Masks every column tagged `pii = pseudonymous_id` in the schema, for `account users` except `pii_readers`, using `retail.governance.mask_pseudonymous_id`. Covers future tables with no extra step (D017) |
| P2 | Row filter `filter_country` | Preventive | Function `retail.governance.filter_country` on `bronze.transactions(country)` | Members of `retail_all_regions` see all rows. Other groups see only the countries mapped to them in `retail.governance.country_access` (D016) |
| G1 | Governed tag `pii` | Guard | Tag policy | Refuses any value outside `direct_id`, `pseudonymous_id`, `quasi_id` at the moment of tagging (`UC_TAG_POLICY_VALUE_NOT_ALLOWED`) |
| G2 | Policy objects owned by stewards | Guard | Schema `governance`, both functions, `country_access` | The engineers who build the pipelines cannot change who sees what (D013) |
| D1 | PII coverage control v2 | Detective | `sql/11_governed_value_tags_ABAC.sql` | Lists any `pii` column not covered by a per-column mask or by a matching mask policy that exempts `pii_readers`. Target: 0 rows |
| D2 | `CTL_TAG_VOCABULARY` | Detective | `sql/08_governance_tag_controls.sql` | Lists any tag key or value not in `retail.governance.tag_vocabulary`, including ungoverned keys such as `PII`. Target: 0 rows |
| D3 | `CTL_OWNERSHIP_NO_PERSON` | Detective | `sql/07_governance_ownership.sql` | Lists any object owned by a person, except approved rows in `retail.dq.control_exceptions`. Target: 0 rows |

**Why both a policy and a check inside the function.** The mask function also tests `is_account_group_member('pii_readers')`. The policy's `EXCEPT pii_readers` already exempts readers, so on its own this test is redundant. It stays so the function is safe if it is ever attached without the policy. NULLs are returned as NULL, not masked. That's deliberate: whether a customer ID is missing is not sensitive, and it's needed for the 22.8% missing-customer finding (F006, D007).

**Access is granted through groups, not people.** Unmasked access is membership of `pii_readers` (D011). All-region access is membership of `retail_all_regions`, which contains `retail_data_engineers`, `retail_data_stewards` and `retail_data_owners` as nested groups. No person or group name is written into the function code, apart from these two access groups.

## 3. Evidence: before and after

Each control was tested in both directions: it must block when it should and allow when it should. Free Edition has one user, so the tests were run by adding and removing that user's own group memberships.

| Test | Setup | Query | Expected | Result |
| --- | --- | --- | --- | --- |
| Mask blocks | Not in `pii_readers` | Top 5 `customer_id` by rows | `*****` | Pass (15 Nov; repeated 24 Nov with the policy as the only protection) |
| Mask allows | In `pii_readers` | Same | Real IDs (17841, 14911, …) | Pass |
| Owners not exempt | Owner of the table, not in `pii_readers` | Same | `*****` | Pass |
| Filter restricts | In `retail_data_analysts` only | Rows by country | United Kingdom only, 981,330 rows | Pass |
| Filter allows | In `retail_all_regions` through a nested role group | Count countries and rows | 43 countries, 1,067,371 rows (matches the Bronze load) | Pass |
| Governed tag refuses | Any | `SET TAGS ('pii' = 'test')` | Error `UC_TAG_POLICY_VALUE_NOT_ALLOWED` | Pass |
| Coverage control finds a gap | Tag `country` as `pii = quasi_id` (allowed value, no policy) | Control D1 | 1 row: `country`, `quasi_id`. Then 0 rows after `UNSET` | Pass |
| Vocabulary control finds a gap | Leftover `pii = test` tag from 15 Nov | Control D2 | 1 row | Caught on its first run (F026) |

Queries are in `sql/06`, `sql/09` and `sql/11`. Negative-test statements are commented out after one run, so a full re-run cannot reapply a test tag (F026).

## 4. What a pipeline must run as

Both the mask and the row filter apply to everyone, including table owners. A job that builds Silver or Gold from Bronze must therefore run as an identity in **both** `pii_readers` and `retail_all_regions`. Otherwise it fails silently in one of two ways: it builds from `*****` IDs (every customer collapses into one), or it builds from a subset of countries. The Silver reconciliation to Bronze (1,067,371 rows, 43 countries, distinct customers matching Bronze) is the check that catches this.

## 5. Platform limits (Free Edition)

- **One user.** Access was tested by changing that user's group memberships, not with separate accounts.
- **System tables can't be granted to a group.** The three audit views stay owned by the user, recorded as exceptions in `retail.dq.control_exceptions` with a 90-day review date.
- **Policies, tags and functions are created by hand in SQL.** There is no CI yet, so a policy could be dropped unnoticed. Controls D1–D3 are the safety net until they run on a schedule (planned with the gate job).

## 6. Open items

| # | Item | Proposed | Decision needed by |
| --- | --- | --- | --- |
| O1 | The row filter sits on Bronze. People should query Silver and Gold, not Bronze | Move the filter to Silver and Gold when they're built. Restrict Bronze to engineers and stewards (D016) | Silver build |
| O2 | No policy exists for `direct_id` or `quasi_id` | Create one before either value is first used. Control D1 will flag the gap until then | First use |
| O3 | Bronze IDs are redacted, so analysts can't count or join customers | A Silver surrogate key with a restricted mapping table, owned by stewards (D010) | Silver build |
| O4 | Controls run only when run by hand | Schedule D1–D3 in a job, with the result written to a DQ results table | Gate job |
| O5 | Access reviews | Quarterly review of `pii_readers` and `retail_all_regions` membership, and of `country_access` rows | Before any real users |

## 7. How to change protection

1. Record the decision in `docs/decisions.md`, and update this note and `definitions.md` section 5 if the vocabulary changes.
2. Change the policy, function or mapping table. Steward-owned objects can only be changed by stewards.
3. Rerun D1 and D2 straight away. When protection changes, the detection must change with it (F028).
4. Run the before-and-after tests in section 3 for anything that changed.
