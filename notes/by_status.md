# Notes: National tables by filing status (`national/by_status/`)

Compiled 2026-10-26, verified against the local files and an HTTP probe of
every stub below for TY1993–2024. Source: [SOI Tax Stats — Individual
statistical tables by filing status][fs].

[fs]: https://www.irs.gov/statistics/soi-tax-stats-individual-statistical-tables-by-filing-status

## What they are

Two Pub 1304 basic tables with **no AGI cut**: every income item,
adjustment, deduction, credit, tax and payment, down the rows, by filing
status across the columns (all returns, joint, separate, head of household,
surviving spouse, single), each as a number of returns and an amount.
Money amounts are **$ thousands**.

| Repo file | SOI table | Universe |
|---|---|---|
| `all_items_{year}.xls` | **1.3** | All returns |
| `itemizer_items_{year}.xls` | **2.2** | Returns with itemized deductions |

Table 1.3 is the only Pub 1304 table that carries every line by filing
status: Table 1.2 has eight items by status and AGI class, Table 1.4 every
item but no status. Table 2.2 is the same layout for itemizers, the status
companion of Table 2.1.

## Coverage: TY1996–2023, every year, four stubs

| Tax years | Table 1.3 | Table 2.2 |
|---|---|---|
| 1996 | `96in13ar.xls` | `96in22ms.xls` |
| 1997 | bare `97in13.xls` | bare `97in22.xls` |
| 1998–2000 | `{yy}in13ar.xls` | `{yy}in22id.xls` |
| 2001–2023 | `{yy}in13ms.xls` | `{yy}in22ms.xls` |

Nothing before TY1996 under any of these stubs; no TY2024 yet. TY1997 drops
the suffix, as every Pub 1304 table does that year. **TY1996–2003 are BIFF4**
(the format `readxl` cannot open; `xlrd` can, through `read_xls_cells.py`).

## Layout changes over time

- **Columns printed in two blocks, TY1996–2003.** The first three statuses
  sit in one block of rows and the other three in a second block below it
  ("—Continued"), with column numbers continuing (1–6, then 7–12). The same
  layout as Table 2.3's old vintages, and read the same way.
- **Group rows, TY1996–2003.** Three items are printed as a label-only row
  over two rows: "Business or profession:" over "Net income" / "Net loss",
  likewise "Sales of capital assets:" and "Rent and royalty:". The aligned
  file keeps the group in `section` for those rows only; the label cleanup
  then joins them into the flat labels used from TY2005.
- **A wrapped label, TY1996–2003**: "Earned income credit used to offset
  income" / "tax before credits" on two rows; rejoined.
- **Status headers on two rows, TY1996–2006** ("Joint returns of" over
  "married persons"), joined into one name. "Joint returns of married
  persons" and "Separate returns of married persons" are the old wording of
  the same statuses.
- **Joint filers and surviving spouses: separate through TY2014, one status
  from TY2015** — as in Tables 1.2 and 1.6.
- Many items enter and leave with the law; see the label coverage file.

## Disclosure marks change meaning

The marks are text through TY2004 and number formats after, and **what a
mark means is set by each sheet's own footnote**, not by the mark:

| Mark | Footnote | Read as |
|---|---|---|
| `**` TY1996 | "Data deleted to avoid disclosure" | `d` (suppressed) |
| `†` TY1997 | "Data deleted to avoid disclosure" | `d` |
| `**` from TY1999 | "Data combined to avoid disclosure" | `combined` |
| `*` | "Estimate should be used with caution" | `caution` |

`align_national.R` reads each sheet's footnotes and assigns the flag from
the footnote text.

## The exemptions row counts exemptions

In both tables (TY2016–2017, the only years they print it) the "number"
column of the exemptions row holds the **number of exemptions**, not of
returns: TY2016 Table 1.3, 289,752,892 exemptions against 150,272,157
returns. The aligned and panel files give it `measure = value`, `unit =
exemptions`.

## Aligned and harmonized files

- `aligned/bystatus_all_items.csv`, `aligned/bystatus_itemizer_items.csv`
  (`align_national.R`): one row per published cell; `panel` is the filing
  status as printed, `item` the row label cleaned of differences of form by
  the same rules as the by-size tables (`checks/bysize_label_synonyms.csv`,
  rules scoped to these two families, each with its reason and, where the
  wording changed more than trivially, the amounts either side of the
  change). 24,114 cells in 1.3, 23,242 in 2.2.
- `aligned/panel_all_items.csv`, `aligned/panel_itemizer_items.csv`
  (`harmonize_bysize.R`): `row = 'total'`, `panel` the harmonized status,
  `series` the item. Concept map (`checks/bysize_concepts.csv`): joint plus
  surviving spouses as one consistent status in every year (the sum before
  TY2015); the taxpayer's and spouse's IRA payments (TY1996–1997) as the
  components of "IRA payments"; the TY2018 combined IRA and pension item,
  exemptions and the child credits flagged `other`. Every item printed in
  only some years is flagged `other` automatically.

## Checks

The tables' own arithmetic (`aligned/_national_additivity.csv`): for every
item, the five or six statuses add to the all-returns column within rounding,
or the difference is explained by a combined or suppressed cell. Four
differences (three items, one in two measures) are in the published sheets and pinned in
`checks/national_known_differences.csv`:

- TY2000 Table 1.3, tax-exempt interest: statuses add to $600 thousand more
  than all returns.
- TY1996 Table 2.2, taxable income: statuses add to 1,034,264 returns and
  $4.84 billion more than all itemizers.
- TY2016 Table 2.2, exemptions: the all-returns cell prints 45,153,109, the
  number of itemizing returns, where the number of exemptions (103,583,713,
  as Table 2.1 prints) belongs.

Against the by-size tables (`check_tables.R`, `checks/_tables.csv`), for
every year both cover (TY2011–2023):

- **1.3 against 1.4** (and 3.3 for credits, taxes and payments, 2.1 for the
  itemized deductions): equal, apart from one-unit rounding where 1.4's value
  is a net of two printed cells. Table 1.3's "Sales of capital assets net
  gain" is **Table 1.4's Schedule D taxable net gain plus the capital gain
  distributions reported directly on Form 1040**, to the unit every year; it
  is not the Schedule D gain alone.
- **1.3 against 1.2**, number of returns and AGI of every status: equal,
  except single persons' AGI in TY2015 and TY2017, $1 thousand apart (two
  single cells rounded independently).
- **1.3 against 2.1**, TY2020: Table 1.3 counts eight more returns with the
  contributions deduction ($1.8 million more) and with taxes paid ($81
  thousand more) than Table 2.1; Table 2.2 agrees with 2.1. Not explained in
  the sheets.
- **2.2 against 2.1**, TY2022 taxable income: 2.2 prints 140 returns and
  $95.8 million more than 2.1. Each table adds up on its own; which is right
  is not in the sheets.
