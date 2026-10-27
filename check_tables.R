#!/usr/bin/env Rscript
#------------------------------------------------------------------------------
# check_tables.R
#
# Cross-checks the Pub 1304 tables that are not by size of AGI against the
# by-size tables, in the spirit of run_checks.R: every table here is built
# from the same weighted SOI sample, so a cell that two tables both print
# must agree exactly. A difference is a parse error, an SOI revision, or a
# published inconsistency -- never something to absorb into a tolerance.
#
#   1.3 vs 1.4   Table 1.3's all-returns column against Table 1.4's
#                all-returns totals, for every item both carry, each year.
#                Where 1.4 prints an item as net income and net loss and 1.3
#                prints it netted (estate and trust, farm, farm rental, other
#                income, sales of other property), 1.4's pair is netted here
#                first: amounts subtracted, counts added
#   1.3 vs 3.3   the same against Table 3.3 (also all returns) for the
#                credits, taxes and payments Table 1.4 does not carry
#   1.3 vs 2.1   the itemized deductions, which only itemizers report, so
#                all returns' totals equal Table 2.1's (crosswalk pairs only)
#   1.3 vs 1.2   Table 1.3's number of returns and AGI for each filing status
#                against Table 1.2's totals for that status
#   2.2 vs 2.1   Table 2.2's all-returns column against Table 2.1's totals,
#                every item both carry
#   4.3 vs 1.4-1.7  Table 4.3's all-returns row (returns excluding dependents)
#                against Table 1.4's total less Table 1.7's (dependent
#                filers), number of returns and AGI
#   4.1 vs 1.4-1.7  the same for Table 4.1's newest vintage, every year both
#                cover (4.1 prints AGI in $ millions: compared after
#                rounding the difference of the $-thousand totals)
#   4.1 vs 4.3   the number of returns and AGI of every top group both print
#
# Items are paired automatically when their cleaned labels hold the same
# words, ignoring order and the ' > ' between a spanner and its column
# ("business or profession net income" = "business or profession > net
# income"), first on the whole label, then on the by-size label less its
# first spanner ("statutory adjustments > ..."), then on its last part
# alone, accepting a pair only when it is the only candidate;
# checks/tables_crosswalk.csv adds the pairs that differ in wording. Every
# item of a national table that finds no partner in any check is listed in
# checks/_tables_unpaired.csv, so coverage cannot shrink unseen.
#
# Inputs:  <dest>/aligned/panel_*.csv   (harmonize_bysize.R)
#          checks/tables_crosswalk.csv, checks/tables_known_differences.csv
# Output:  <dest>/checks/_tables.csv          one row per comparison
#          <dest>/checks/_tables_unpaired.csv items compared with nothing
#
# Usage:
#   Rscript check_tables.R --dest /path/to/store
#
# Exits non-zero if any comparison differs by an amount not pinned in
# checks/tables_known_differences.csv.
#------------------------------------------------------------------------------

suppressMessages(library(data.table))

args = commandArgs(trailingOnly = TRUE)
script_dir = dirname(sub('--file=', '', grep('--file=', commandArgs(), value = TRUE)[1]))
if (is.na(script_dir) || script_dir == '') script_dir = '.'

dest = file.path(script_dir, 'data')
if (length(args) >= 2 && args[1] == '--dest') dest = args[2]

aligned_dir = file.path(dest, 'aligned')
panel = function(fam) fread(file.path(aligned_dir, sprintf('panel_%s.csv', fam)), na.strings = '',
                             integer64 = 'double')

CROSSWALK = fread(file.path(script_dir, 'checks', 'tables_crosswalk.csv'), na.strings = '')
KNOWN = fread(file.path(script_dir, 'checks', 'tables_known_differences.csv'), na.strings = '',
              integer64 = 'double')

#-----------------------
# Helpers
#-----------------------

# The all-returns total cells of a harmonized panel: one per (year, series,
# measure). Derived totals are kept (1.2's joint-plus-surviving-spouse group
# before TY2015 is one); NA fillers are not.
totals = function(d, pan = 'all returns') {
  d = d[panel == pan & row %in% 'total' & is.na(agi_lo) & (derived == TRUE | !is.na(value) | !is.na(flag))]
  d[, .(tax_year, series, measure, value, flag, derived)]
}

words = function(x) vapply(strsplit(gsub('[^a-z0-9 ]', ' ', gsub(' > ', ' ', x)), '\\s+'),
                           function(w) paste(sort(unique(w[w != ''])), collapse = ' '), character(1))

# Pair the national table's series with the by-size table's: crosswalk
# first, then the same words, then the same words less the by-size label's
# first spanner. A national measure 'amount' pairs with a by-size 'amount' or
# a single-column 'value' (Table 1.4's AGI and taxable income columns).
pair_series = function(check, a, b, auto = TRUE) {
  sa = unique(a[, .(series_a = series, measure_a = measure)])
  sb = unique(b[, .(series_b = series, measure_b = measure)])
  sb[, `:=`(w = words(series_b), w1 = words(sub('^[^>]+ > ', '', series_b)),
            w2 = words(sub('^.* > ', '', series_b)))]
  sa[, w := words(series_a)]
  fits = function(ma, mb) ma == mb | (ma == 'amount' & mb == 'value')
  cw = CROSSWALK[check_name == check]
  out = list()
  for (i in seq_len(nrow(sa))) {
    x = sa[i]
    hit = cw[series_a == x$series_a & measure_a == x$measure_a]
    if (nrow(hit) > 0) {
      out[[i]] = data.table(x[, .(series_a, measure_a)], hit[, .(series_b, measure_b)], how = 'crosswalk')
      next
    }
    if (!auto) {
      out[[i]] = data.table(x[, .(series_a, measure_a)], series_b = NA_character_, measure_b = NA_character_,
                            how = 'no partner')
      next
    }
    c1 = sb[w == x$w & fits(x$measure_a, measure_b)]
    if (nrow(c1) == 1) { out[[i]] = data.table(x[, .(series_a, measure_a)], c1[, .(series_b, measure_b)], how = 'same words'); next }
    c2 = sb[w1 == x$w & fits(x$measure_a, measure_b)]
    if (nrow(c1) == 0 && nrow(c2) == 1) {
      out[[i]] = data.table(x[, .(series_a, measure_a)], c2[, .(series_b, measure_b)], how = 'same words less spanner')
      next
    }
    c3 = sb[w2 == x$w & fits(x$measure_a, measure_b)]
    if (nrow(c1) == 0 && nrow(c2) == 0 && nrow(c3) == 1) {
      out[[i]] = data.table(x[, .(series_a, measure_a)], c3[, .(series_b, measure_b)], how = 'same last part')
      next
    }
    out[[i]] = data.table(x[, .(series_a, measure_a)], series_b = NA_character_, measure_b = NA_character_,
                          how = if (nrow(c1) + nrow(c2) + nrow(c3) > 1) 'ambiguous' else 'no partner')
  }
  rbindlist(out)
}

compare = function(check, a, b, pairs, scale = 1) {
  p = pairs[!is.na(series_b)]
  x = merge(a, p, by.x = c('series', 'measure'), by.y = c('series_a', 'measure_a'))
  x = merge(x, b, by.x = c('tax_year', 'series_b', 'measure_b'), by.y = c('tax_year', 'series', 'measure'),
            suffixes = c('_a', '_b'))
  x[, .(check_name = check, tax_year, series_a = series, measure_a = measure, series_b, measure_b,
        how, value_a, flag_a, value_b = value_b / scale, flag_b, derived_a, derived_b)]
}

#-----------------------
# The comparisons
#-----------------------

t14 = panel('income_sources');   t12 = panel('marital_status');  t17 = panel('dependent_returns')
t21 = panel('itemized_deductions'); t33 = panel('tax_liability')
t13 = panel('all_items');        t22 = panel('itemizer_items')
t41 = panel('top_shares');       t43 = panel('top_items')

res = list()
unpaired = list()

# Table 1.4 prints these as net income and net loss; 1.3 nets them. The
# netted 1.4 value: amounts subtracted, return counts added (a return has
# either a net income or a net loss from a source)
NET_14 = c('estate and trust', 'farm', 'farm rental', 'other income',
           'sales of property other than capital assets')
net_items = function(d) {
  rbindlist(lapply(NET_14, function(base) {
    gain = if (base == 'sales of property other than capital assets') 'net gain' else 'net income'
    loss = 'net loss'
    x = merge(d[series == paste(base, '>', gain)], d[series == paste(base, '>', loss)],
              by = c('tax_year', 'measure'), suffixes = c('', '_loss'))
    x[, .(tax_year, series = paste(base, '>', sub('net ', 'net ', gain), 'less loss'), measure,
          value = fifelse(measure == 'returns', value + value_loss, value - value_loss),
          flag = fcoalesce(flag, flag_loss), derived = TRUE)]
  }))
}
b14 = totals(t14)
b14 = rbind(b14, net_items(b14))
# 1.3's "Sales of capital assets net gain" is the capital gain in AGI: 1.4's
# Schedule D taxable net gain plus the capital gain distributions reported
# directly on Form 1040 (verified 2026-10-26: equal, or within one unit of
# rounding, every year TY2011-2023). The two groups do not overlap -- a
# return with a Schedule D reports its distributions there -- so counts add.
cg = merge(b14[series == 'sales of capital assets reported on form 1040, schedule d > taxable net gain'],
           b14[series == 'capital gain distributions reported on form 1040'],
           by = c('tax_year', 'measure'), suffixes = c('', '_dist'))
b14 = rbind(b14, cg[, .(tax_year, series = 'capital gain in agi (schedule d taxable net gain plus form 1040 distributions)',
                        measure, value = value + value_dist, flag = fcoalesce(flag, flag_dist), derived = TRUE)])

# 1.3 vs 1.4, 1.3 vs 3.3, 1.3 vs 2.1 and 2.2 vs 2.1: every item both carry
for (cmp in list(list('1.3 vs 1.4', t13, b14, TRUE), list('1.3 vs 3.3', t13, totals(t33), TRUE),
                 list('1.3 vs 2.1', t13, totals(t21), FALSE), list('2.2 vs 2.1', t22, totals(t21), TRUE))) {
  a = totals(cmp[[2]])
  b = cmp[[3]]
  a = a[tax_year %in% b$tax_year]
  pr = pair_series(cmp[[1]], a, b, auto = cmp[[4]])
  res[[cmp[[1]]]] = compare(cmp[[1]], a, b, pr)
  unpaired[[cmp[[1]]]] = cbind(check_name = cmp[[1]], table = sub(' vs.*', '', cmp[[1]]), pr)
}

# 1.3 vs 1.2: number of returns and AGI of each filing status
STATUSES = c('returns of married persons filing jointly and returns of surviving spouses',
             'returns of married persons filing jointly', 'returns of surviving spouses',
             'returns of married persons filing separately', 'returns of heads of households',
             'returns of single persons')
b12 = totals(t12)
for (st in STATUSES) {
  a = totals(t13, st)[series == 'adjusted gross income less deficit' & measure %in% c('returns', 'amount')]
  a = a[tax_year %in% b12$tax_year]
  b = b12[series == st & measure == 'returns' |
            series == paste(st, '> adjusted gross income less deficit')]
  b[, `:=`(series = 'adjusted gross income less deficit', measure = fifelse(measure == 'returns', 'returns', 'amount'))]
  pr = data.table(series_a = 'adjusted gross income less deficit', measure_a = c('returns', 'amount'),
                  series_b = 'adjusted gross income less deficit', measure_b = c('returns', 'amount'),
                  how = 'filing status')
  x = compare(paste('1.3 vs 1.2:', st), a, b, pr)
  res[[st]] = x
}

# 4.3 and 4.1 vs 1.4 less 1.7: all returns excluding dependents
less_dependents = function(series_14, series_17, measure_14, measure_17) {
  x = merge(totals(t14)[series == series_14 & measure == measure_14, .(tax_year, v14 = value, f14 = flag)],
            totals(t17)[series == series_17 & measure == measure_17, .(tax_year, v17 = value, f17 = flag)],
            by = 'tax_year')
  x[, .(tax_year, value = v14 - v17, flag = fcoalesce(f14, f17), derived = TRUE)]
}
b_ret = less_dependents('all', 'all', 'returns', 'returns')
b_agi = less_dependents('adjusted gross income less deficit', 'adjusted gross income less deficit', 'value', 'value')
b_ex = rbind(b_ret[, `:=`(series = 'returns', measure = 'returns')],
             b_agi[, `:=`(series = 'agi', measure = 'amount')])
a43 = t43[panel == 'all returns excluding dependents' & row == 'all returns' &
            ((series == 'all' & measure == 'returns') | series == 'adjusted gross income less deficit'),
          .(tax_year, series = fifelse(series == 'all', 'returns', 'agi'),
            measure = fifelse(series == 'all', 'returns', 'amount'), value, flag, derived)]
pr = data.table(series_a = c('returns', 'agi'), measure_a = c('returns', 'amount'),
                series_b = c('returns', 'agi'), measure_b = c('returns', 'amount'), how = '1.4 less 1.7')
res[['4.3']] = compare('4.3 vs 1.4 less 1.7', a43, b_ex, pr)
a41 = t41[panel == 'all returns excluding dependents' & row == 'all returns' &
            series %in% c('number of returns', 'adjusted gross income (millions of dollars)'),
          .(tax_year, series = fifelse(series == 'number of returns', 'returns', 'agi'),
            measure = fifelse(series == 'number of returns', 'returns', 'amount'), value, flag, derived)]
x41 = compare('4.1 vs 1.4 less 1.7', a41, b_ex, pr)
x41[series_a == 'agi', value_b := round(value_b / 1000)]   # $ thousands to the $ millions 4.1 prints
res[['4.1']] = x41

# 4.1 vs 4.3: the top groups both print
g43 = t43[panel == 'all returns excluding dependents' &
            ((series == 'all' & measure == 'returns') | series == 'adjusted gross income less deficit'),
          .(tax_year, group = row, series = fifelse(series == 'all', 'returns', 'agi'), value43 = value, flag43 = flag)]
g41 = t41[panel == 'all returns excluding dependents' &
            series %in% c('number of returns', 'adjusted gross income (millions of dollars)'),
          .(tax_year, group = row, series = fifelse(series == 'number of returns', 'returns', 'agi'),
            value41 = value, flag41 = flag, vintage)]
g = merge(g41, g43, by = c('tax_year', 'group', 'series'))
res[['4.1 vs 4.3']] = g[, .(check_name = '4.1 vs 4.3', tax_year, series_a = paste(group, series),
                            measure_a = fifelse(series == 'returns', 'returns', 'amount'),
                            series_b = paste(group, series), measure_b = fifelse(series == 'returns', 'returns', 'amount'),
                            how = paste('4.1 vintage', vintage), value_a = value41, flag_a = flag41,
                            value_b = fifelse(series == 'agi', round(value43 / 1000), value43),
                            flag_b = flag43, derived_a = FALSE, derived_b = FALSE)]

report = rbindlist(res, fill = TRUE)
report[, diff := value_a - value_b]
# A side built here from two rounded cells (a net of income and loss, a total
# less dependents, a sum of two statuses) can miss a single printed cell by
# one unit; that is reported as 'rounding', counted, and never widened
report[, status := fifelse(is.na(value_a) | is.na(value_b), 'not comparable',
                   fifelse(diff == 0, 'ok',
                   fifelse(abs(diff) <= 1 & (derived_a %in% TRUE | derived_b %in% TRUE), 'rounding', 'MISMATCH')))]

# Differences already traced to the published cells, pinned at their exact size
key = function(z) paste(z$check_name, z$tax_year, z$series_a, z$measure_a, sprintf('%.0f', z$diff))
report[status == 'MISMATCH' & key(report) %in% key(KNOWN), status := 'known diff']
report[KNOWN, on = .(check_name, tax_year, series_a, measure_a), reason := i.reason]
stale = KNOWN[!key(KNOWN) %in% key(report)]
if (nrow(stale) > 0) stop('checks/tables_known_differences.csv entries no comparison produced:\n',
                          paste(key(stale), collapse = '\n'))
setorder(report, check_name, tax_year, series_a, measure_a)

dir.create(file.path(dest, 'checks'), recursive = TRUE, showWarnings = FALSE)
fwrite(report, file.path(dest, 'checks', '_tables.csv'), na = '')
# an item is unpaired when no check found it a partner
unp = rbindlist(unpaired)
unp = unp[, .(paired = any(!is.na(series_b)), how = paste(unique(how), collapse = '; ')),
          by = .(table, series_a, measure_a)][paired == FALSE, !'paired']
fwrite(unp, file.path(dest, 'checks', '_tables_unpaired.csv'), na = '')

#-----------------------
# Report
#-----------------------

print(report[, .N, by = .(check = sub(':.*', '', check_name), status)][order(check, status)])
cat('\nItems of the national table with no partner (see checks/_tables_unpaired.csv):\n')
print(unp[, .N, by = .(table, how)])
bad = report[status == 'MISMATCH']
if (nrow(bad) > 0) {
  cat('\nUnexplained differences:\n')
  print(bad[, .(check_name, tax_year, series_a, measure_a, value_a, value_b, diff)], nrows = 200)
  quit(status = 1)
}
cat('\nEvery comparison agrees exactly or is a pinned, explained difference.\n')
