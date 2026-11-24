# Business definitions and critical data elements

Status: **reviewed 2026-11-11**. Definitions are taken from profiling evidence (`docs/findings.md`). Items marked *Open* need a business owner's decision before Gold; until then Gold reports them separately rather than guessing.

## 1. Business terms

| Term | Definition | Derived from | Evidence |
| --- | --- | --- | --- |
| Invoice | One customer transaction, identified by a 6-digit number. A prefix of `C` marks a cancellation; `A` marks a bad-debt adjustment | `invoice` | F011 |
| Invoice line | One row of an invoice: one stock code, a quantity and a unit price. The Silver grain is one invoice line after exact duplicates are removed | Source row | F008 |
| Line type | What an invoice line represents: `product`, `postage`, `fee`, `discount`, `manual`, `bad_debt`, `voucher`, `test` or `stock_adjustment`. Assigned from the stock-code reference list, not from the code's pattern | `stock_code` + reference list | F012, F013, F016, F019 |
| Product sale | An invoice line with line type `product` on a normal (not `C`, not `A`) invoice, with quantity > 0 and price > 0 | Derived | F009, F010 |
| Cancellation | An invoice line on a `C` invoice. Quantity is negative. It reverses all or part of an earlier sale | `invoice`, `quantity` | F009, F011, F013 |
| Free item | A product line with price 0 on a normal invoice. Counts as units shipped, not as revenue | `price` | F010 |
| Stock adjustment | A negative-quantity line on a normal invoice, with price 0 and no customer. A warehouse write-off, not a customer transaction | Derived | F013, F021 |
| Line value | `quantity × price`, in GBP. Negative on cancellations | Derived | |
| Gross product sales | Sum of line value over product sales | Derived | |
| Net product sales | Gross product sales plus line value of product-line cancellations (which are negative) | Derived | *Open:* do discount (`D`) lines reduce net sales? Is postage revenue reported separately? |
| Customer | A business customer identified by a 5-digit `customer_id`. Lines with no ID are kept and flagged; they are not one "unknown customer" | `customer_id` | F006 |
| Transaction country | The country recorded on the invoice line. The only country used for geographic reporting | `country` + country reference table | F022, F023 |
| Customer country | The transaction country on the customer's most recent invoice. Descriptive only | Derived | F023 *Open:* 13 conflicting IDs |
| Trading day | A day on which the business is expected to trade: not a Saturday, not a UK bank holiday, not within the Christmas shutdown (24–31 Dec). Loaded from the trading calendar, not calculated | Trading calendar | F015 |
| Product description | The single description chosen for a stock code: the most frequent cleaned description on its product sales | Derived | F014, F024 |

## 2. Critical data elements

A field is critical if an error in it changes revenue, customer counts or a regulatory-style report. `description` is not critical: it is a label, and an error in it doesn't change any number.

| CDE | Source column | Silver type | Why critical | Rules (planned) | Findings |
| --- | --- | --- | --- | --- | --- |
| Invoice number | `invoice` | STRING | Drives invoice type (sale, cancellation, bad debt) and order counts | Not null; matches `^[CA]?[0-9]{6}$`; unknown prefix → quarantine | F011 |
| Stock code | `stock_code` | STRING | Drives line type, so decides what counts as a product sale | Not null; trimmed; found in stock-code reference list, else quarantine | F012, F019, F020 |
| Quantity | `quantity` | INT | Every unit and value measure | Is integer; not 0 (none found, so any zero is new); sign consistent with invoice type and line type | F009, F013 |
| Unit price | `price` | DECIMAL(12,4) | Every value measure | Is numeric; ≥ 0 except bad-debt lines; 0 allowed only as free item or non-sale line | F010, F018 |
| Invoice date | `invoice_date` | TIMESTAMP | Period reporting, freshness | Parses as `yyyy-MM-dd HH:mm:ss`; within the expected range; assumed UK local time | F015 |
| Customer ID | `customer_id` | STRING | Customer counts, retention, customer value | 5 digits when present; missing allowed and flagged `has_customer = false` | F006, F023 |
| Country | `country` | STRING (ISO 3166 alpha-2) | Geographic revenue | Mapped through the country reference table; unmapped → quarantine | F022, F023 |
| Line type | Derived | STRING | Separates revenue from postage, fees and adjustments | Every line gets exactly one value from the allowed list | F016 |
| Line value | Derived | DECIMAL(14,4) | Every revenue figure | Equals `quantity × price`; reconciles to Bronze totals | |

## 3. Reference data needed

| Reference table | Content | Why it can't be a rule in code | Findings |
| --- | --- | --- | --- |
| Stock-code classification | Non-product codes and their line type | Products and non-products share code patterns and lengths | F012, F016, P11 |
| Country | Source value → ISO code, region flag | Free-text values, placeholders, regions | F022 |
| Trading calendar | Non-trading days | One-off and substitute holidays can't be calculated | F015 |
| Write-off reason | Free-text reason → controlled reason code | Reasons typed with inconsistent spelling | F021 |

## 4. Open questions for the business owner

1. Do discount lines reduce net product sales, or are they reported separately?
2. Is postage reported as revenue, and if so on its own line?
3. For the 13 customers with two countries: one customer with several sites, or several customers sharing an ID? (F023)
4. Is the Christmas shutdown (24–31 Dec) a standing rule? (F015)
5. Should test records (TEST001, TEST002) be removed at source? (F019)

## 5. Classification tags

Tags are labels stored in Unity Catalog. Databricks gives them no meaning; the meaning is defined here, and the controls listed below check that it is followed. Only the keys and values in this table may be used.

| Tag key | Allowed values | Meaning | Applied to |
| --- | --- | --- | --- |
| `cde` | `true` | A critical data element (section 2) | `invoice`, `stock_code`, `quantity`, `price`, `invoice_date`, `customer_id`, `country` |
| `pii` | `direct_id` | Identifies a person on its own (e.g. name, email) | None in this dataset |
| `pii` | `pseudonymous_id` | Identifies a person or business only through a lookup | `customer_id` |
| `pii` | `quasi_id` | Could identify someone in combination with other columns | None tagged yet |
| `data_owner` | An account group name | The group accountable for the data (DAMA data owner); business ownership, separate from the Unity Catalog `OWNER` | Catalog `retail`: `retail_data_owners` |
| `data_steward` | An account group name | The group responsible for definitions, rules and quality | Catalog `retail`: `retail_data_stewards` |

**Rules**

1. Any column tagged `pii`, whatever its value, must have a column mask. A tag alone does not protect anything: the mask function sets who sees what, and `ALTER COLUMN … SET MASK` attaches it to the column. Checked by the PII mask coverage control in `sql/06_governance_masking.sql` (expected result: 0 rows).
2. Unmasked access to `pii` columns is granted only through membership of the account group `pii_readers` (D011).
3. Tag keys and values are lower case and must come from the table above. A tag outside this list is an exception to be corrected.

Until attribute-based access control (ABAC) policies are available, rule 1 is enforced by the control query, not by the platform. With ABAC, a policy on the `pii` tag would apply the mask automatically.
