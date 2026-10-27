# Notes: Tax shares by AGI percentile (`national/tax_shares/`)

Compiled 2026-10-26, verified against the local files and an HTTP probe of
every stub below for TY2000–2024. Source: [SOI Tax Stats — Individual
statistical tables by tax rate and income percentile][tr], section "All
individual income tax returns excluding dependents classified by tax
percentile".

[tr]: https://www.irs.gov/statistics/soi-tax-stats-individual-statistical-tables-by-tax-rate-and-income-percentile

## What they are

Returns **excluding dependent filers**, ranked by AGI, in cumulative
percentile groups. Unlike the by-size tables the groups are defined by rank,
not by dollar class, and each group comes with its AGI floor.

| Repo file | SOI table | Rows × columns | One file holds |
|---|---|---|---|
| `top_shares_{year}.xls[x]` | **4.1** | statistic × tax year, by **descending** group (top 0.001% … top 50%) | every tax year from 2001 (1986 in the TY2009 file) to `{year}` |
| `bottom_shares_{year}.xls` | **4.2** | the same by **ascending** group (bottom 50% … bottom 99%) | the same |
| `top_items_{year}.xls` | **4.3** | descending group × item | one tax year |

Statistics in 4.1 and 4.2: number of returns; AGI floor of each group in
current and in constant dollars (4.1 only); AGI and total income tax in
**$ millions**; AGI share, income tax share and average tax rate in
**percent**. Table 4.3 adds about twenty items — wages, interest, dividends,
capital gains, business and partnership income, adjustments, standard and
itemized deductions, QBI deduction, taxable income, AMT, credits, total
income tax — as numbers of returns and **$ thousands**, with each group's
AGI floor in **whole dollars**.

**Groups are cumulative**: "top 5 percent" includes "top 1 percent". Take
differences for brackets.

## Coverage and file names

| Table | Tax years (files) | Stub |
|---|---|---|
| 4.1 | 2009–2018 | `{yy}in01etr.xls` (the "early release" Table 1) |
| | 2019–2022 | `{yy}in41ts.xls` |
| | 2023 | `23in41ts.xlsx` — the only `.xlsx` in the family |
| 4.2 | 2009–2018 | `{yy}in02etr.xls` (Table 2) |
| | 2019–2023 | `{yy}in42ts.xls` |
| 4.3 | 2014–2018 | `{yy}in03etr.xls` (Table 3) |
| | 2019–2023 | `{yy}in43ts.xls` |

- **The SOI page links only the newest 4.1 and 4.2**; the earlier files are
  unlinked but live, and each is mirrored as a **vintage** under the year it
  was published for.
- **`{yy}in03etr.xls` for TY2009–2011 is not Table 4.3.** It is a third time
  series (expanded descending percentiles, 2001 on), not mirrored. TY2012
  and TY2013 have no Table 4.3 at all.
- `12in01ts.xls`, `13in01ts.xls[x]`, `15in01ts.xlsx` and their Table 2
  companions are a parallel, shorter series ("AGI threshold", from 2003 or
  2004) on the same page; not mirrored.
- No TY2024 file yet.

## Universe: one break

- **TY2009 vintage (4.1, 4.2): returns with positive AGI**, 1986–2009,
  constant dollars at CPI-U 1982–84 = 100.
- **Every later vintage: all returns excluding dependents**, 2001 on,
  constant dollars at CPI-U 1990 = 100.

The aligned files carry the universe as `panel`, read from each file's
title, and the harmonized panels keep the two as separate panels. They are
never spliced: 1986–2000 exist only in the positive-AGI universe.

## Units and marks

- The AGI floor is whole dollars in every vintage; TY2009–2020 label it
  "(current dollars)", TY2021 on "(current whole dollars)". `unit` says
  `whole dollars` or `whole dollars, constant 1990 prices` (`1982-84
  prices` in the TY2009 vintage).
- `N/A` (the floor of all returns) is flag `n/a`, value NA.
- Table 4.3 TY2014–2015 and 2017–2019 mark one count a year with `**`,
  footnoted "Return frequency rounded to protect the confidentiality of tax
  return information" (e.g. TY2014, 1,396 returns with taxable income in the
  top 0.001 percent, the group's own size). The value is the published
  count; flag `rounded`. TY2016 uses `**` for combined cells.
- In Table 4.3 the exemptions "number of returns" (TY2014–2017) counts
  exemptions (TY2014: 290,409,266 against 139,562,034 returns): `measure =
  value`, `unit = exemptions`.

## Aligned and harmonized files

- `aligned/pctile_top_shares.csv`, `pctile_bottom_shares.csv`,
  `pctile_top_items.csv` (`align_national.R`): one row per published cell,
  every vintage; `tax_year` is the year the cell describes, `vintage` the
  file; `pctile_group` the cumulative group. 27,360, 9,180 and 9,720 cells.
- `aligned/panel_top_shares.csv`, `panel_bottom_shares.csv`,
  `panel_top_items.csv` (`harmonize_bysize.R`): for 4.1 and 4.2 the
  **newest vintage of each tax year within each universe** (2023 for
  2001–2023; 2009 for the positive-AGI years), with `vintage` and `unit`;
  `row` is the group.

## Revisions between vintages

Cells that appear in more than one vintage are identical, with two
exceptions (values only; 2,596 such cells in 4.1, 792 in 4.2):

- **Table 4.1, TY2017, the constant-dollar AGI floors** (14 cells, every
  group): the TY2017 file prints them about 16 percent lower than every later
  file (top 0.001 percent: 28,294,880 against 33,829,397 in 1990 prices).
  The current-dollar floors agree, so the deflator differs: the later files
  divide the current floor (63,430,119) by 1.875, the TY2017 file by about
  2.242. The cause is not stated in the files.
- **Table 4.2, TY2012, total income tax of the bottom 75 percent**:
  $160,932 million in the TY2012 file, $160,934 million in every later one.

The harmonized panels take the newest vintage, so they carry the later
figures.

## Checks

- Own arithmetic (`aligned/_national_additivity.csv`): every group of x
  percent holds x percent of the returns, to within one return, in every
  vintage and year. The exception is the TY2009 vintage of 4.2 in TY1989,
  1990 and 1992: the bottom groups miss by 1–2 returns, and by 9 in 1992's
  bottom 75 percent (84,489,560 printed against 84,489,569). Pinned in
  `checks/national_known_differences.csv`.
- Against the by-size tables (`check_tables.R`): Table 4.3's all-returns row
  equals **Table 1.4's total less Table 1.7's (dependent filers)**, number of
  returns and AGI, every year TY2014–2023, to within one unit (the
  subtraction of two rounded totals; 5 of 20 comparisons differ by one).
  Table 4.1's newest vintage agrees the same way, TY2012–2023 (1 of 24
  differs by one). So the
  universe "all returns excluding dependents" includes returns with
  negative AGI. Table 4.1 and Table 4.3 agree exactly on the number of
  returns and AGI of every top group both print (300 comparisons).
