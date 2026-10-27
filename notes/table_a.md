# Notes: Pub 1304 Table A, selected income and tax items (`national/table_a/`)

Compiled 2026-10-26, verified against the local files and an HTTP probe of
`{yy}intaba.xls` / `.xlsx` for TY2000–2024. Source: [SOI Tax Stats —
Individual income tax returns complete report (Publication 1304)][p1304],
which links only the newest file.

[p1304]: https://www.irs.gov/statistics/soi-tax-stats-individual-income-tax-returns-complete-report-publication-1304

## What it is

All returns, **every line of Form 1040 and its schedules that SOI tracks**
(391 item-and-measure pairs in the TY2023 file), as number of returns and
amount, **TY1990 to the file's own year**, in three bands:

- **current dollars** — amounts in $ thousands;
- **constant 1990 dollars** — amounts in $ thousands of 1990 prices (CPI-U,
  1990 = 100; the footnote lists each year's index); return counts repeated;
- **percent change** from the year before, for the file's own year only, in
  each of the two dollar bands.

Items are SOI's Form 1040 line items, so some differ from the items of the
basic tables (Table A's own footnote 1). A year in which an item did not
exist is `N/A` (flag `n/a`); about half the cells of a file.

## Coverage

`{yy}intaba.xls`, one file per year **TY2012–2023**; nothing earlier under
this stub and no TY2024 yet. Each file is a **vintage** carrying every year
from 1990, mirrored under the year it was published for.

## Layout

- Rows pair "Item: Number of returns" with an "Amount" row below it; a few
  items are one row ("Number of exemptions", "Exemption amount", "Adjusted
  gross income or loss (AGI): Amount").
- Indented rows are sub-items of the row above ("    Electronically filed
  returns" under each form type); `align_national.R` reads the raw label to
  keep that, giving "form 1040 returns > electronically filed returns".
- Footnote markers stand in for values: "[15] Percentage not computed",
  "[16] Less than 0.05 percent", "[17] Data from prior-year returns" (kept
  as the marker, value NA), and "[18] Data deleted to prevent disclosure"
  (flag `d`). Their numbers change between vintages; the flag is set from
  each file's own footnote text.

## Revisions between vintages

Of the 13,160 cells (item × measure × band × year, values only) that appear
in more than one vintage, **two differ**: TY2020's "charitable contributions
if took standard deduction" in constant 1990 dollars. The TY2020 file prints
20,904,255.05 returns — a deflated count, not a whole number — and a
deflated amount of 10,697,693; the TY2021–2023 files print 41,390,425
returns and 5,402,875. Every other cell is identical across the vintages
that carry it.

## Aligned and harmonized files

- `aligned/table_a.csv` (`align_national.R`): one row per published cell,
  every vintage (193,964 cells); `tax_year` is the column's year, `vintage`
  the file, `panel` the band, `col_group` the band as printed, `item` the
  cleaned label and `measure` returns, amount or value (exemptions).
- `aligned/panel_table_a.csv` (`harmonize_bysize.R`): the newest vintage of
  each tax year and band — the TY2023 file for every year 1990–2023, and
  each earlier file only for its own percent-change columns.

Spot values (TY2023 file, current dollars): TY2023 all returns 160,602,107;
AGI $15,286,017,359 thousand; salaries and wages $10,204,095,705 thousand
on 128,591,050 returns — the same as Tables 1.3 and 1.4.
