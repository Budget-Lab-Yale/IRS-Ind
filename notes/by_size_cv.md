# Notes: Coefficients of variation for Tables 1.4, 2.1, 3.3 (`national/by_size_cv/`)

Compiled 2026-10-26, verified against the local files and an HTTP probe of
`{yy}in{nn}cv.xls` / `.xlsx` for every Pub 1304 table number, TY1993–2024.

## What they are

SOI's estimates of **sampling error** for three by-size tables. Each workbook
is laid out cell for cell like its table — same panels (all, taxable,
nontaxable returns), same AGI rows, same numbered columns — and each cell
holds the **coefficient of variation in percent**: the estimate's standard
error as a percent of the estimate. Pub 1304's "Description of the sample"
names them ("Tables 1.4 CV, 2.1 CV, and 3.3 CV contain estimated CVs for the
estimates included in Tables 1.4, 2.1, and 3.3"), but **no SOI page links
them**; they were found by probing.

| Repo file | Describes | Tax years | SOI file |
|---|---|---|---|
| `income_sources_cv_{year}.xls` | Table 1.4 | 1997–2023 | `{yy}in14cv.xls` |
| `itemized_deductions_cv_{year}.xls` | Table 2.1 | 2003–2023 | `{yy}in21cv.xls` |
| `tax_liability_cv_{year}.xls` | Table 3.3 | 2003–2023 | `{yy}in33cv.xls` |

No other table has one (1.1, 1.2, 1.4A, 1.6, 1.7, 2.3, 2.5, 2.7, 3.1, 3.1A,
3.2, 3.5 probed); no TY2024 yet. The files are named after the by-size
family they describe, so a CV joins to its cell on family, year and cell.

## What a CV covers

Sampling error only: not misreporting, not processing error, not the
difference between SOI's concept and a user's. A CV of **0** is printed for
every nonzero cell of the **$10,000,000-or-more** class, which SOI samples
in full (3,946 of the 4,284 nonzero published cells with a zero CV,
TY2011–2023); the other zero CVs sit in strata SOI also takes nearly whole.
A cell SOI combined (`**`) has no CV of its own: its CV cell is marked
`**` too.

## Quirks

- **TY2018 Table 3.3 CV prints column 111 as "11"** in its column-number
  row. The reader repairs one misprinted number whose neighbours are k − 1
  and k + 1 (`alignment_helpers.R::numrow_run`); no other row is affected.
- **TY1997 Table 1.4 CV prints one combined cell as `**'`**, a stray quote;
  read as `**`.
- The pre-2005 workbooks carry the marks as text (`**`, `--`), later ones as
  number formats, as the tables do.

## Aligned file (`aligned/cv_bysize.csv`)

`align_cv.R`, after `align_bysize.R`. One row per CV cell, every year SOI
published (302,325 cells from 69 workbooks), with the published value
joined on tax year, family, panel, row label and published column number:
`cv` (percent), `cv_flag`, `value` and `flag` (the published cell), `unit`
of the value, and `std_error = value × cv / 100` in that unit. `match`:

| match | Cells | Meaning |
|---|---|---|
| matched | 168,003 | same cell, same item |
| label differs | 174 | same cell, worded differently in the CV workbook: TY2017 2.1 CV doubles "income" in the section 965 column and adds "loss" to "miscellaneous deductions other than gambling"; TY2016 3.3 CV says "credited to 2016 estimated tax" where the table says 2017. All wording |
| table not mirrored | 134,148 | TY1997–2010: the by-size tables are mirrored from TY2011, so the CV has no published value here |

**Every published cell of Tables 1.4, 2.1 and 3.3, TY2011–2023 (168,177
cells), has its CV cell**; the script stops if one does not. 96 published
values have no CV number, every one because the CV cell is combined (`**`).
`aligned/_bysize_cv_coverage.csv` counts these per family, year and panel.

Example, Table 1.4 TY2019, all returns: 157,796,807 returns, CV 0.06
percent, standard error about 95,000 returns; AGI $11.97 trillion, CV 0.08
percent, standard error about $9.6 billion.
