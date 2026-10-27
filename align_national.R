#!/usr/bin/env Rscript
#------------------------------------------------------------------------------
# align_national.R
#
# The aligned layer for the Pub 1304 tables that are NOT by size of AGI, the
# companion to align_bysize.R: one long panel per table, one row per published
# cell, every mirrored year stacked, read through the same cell reader and
# cleaned with the same label rules. Three layouts:
#
#   by_status  Tables 1.3 (all returns) and 2.2 (returns with itemized
#              deductions): items down the rows, filing statuses across.
#   tax_shares Tables 4.1 (descending cumulative percentiles of AGI) and 4.2
#              (ascending), time series in which each year's file is a
#              vintage; and Table 4.3 (one year per file: the descending
#              percentiles down the rows, items across).
#   table_a    Table A: items down the rows, tax years across, in current
#              and constant 1990 dollars; a time series like 4.1-4.2.
#
# Output, under <dest>/aligned/:
#   bystatus_{family}.csv   all_items (T1.3), itemizer_items (T2.2)
#   pctile_{family}.csv     top_shares (T4.1), bottom_shares (T4.2),
#                           top_items (T4.3)
#   table_a.csv             Table A
#     every one with the columns
#       tax_year, vintage, table, family, row_seq, panel, section, row_label,
#       col_seq, col_group, col_label, pctile_group, item, measure, unit,
#       value, flag
#     tax_year  the year the cell describes. vintage is the year of the file
#               it came from: the same as tax_year for 1.3, 2.2 and 4.3; for
#               the time series (4.1, 4.2, A) a file of vintage v carries
#               every year up to v, and each vintage is kept.
#     panel     the universe or block the cell belongs to, as published: the
#               filing status (1.3, 2.2); 'all returns excluding dependents'
#               or, in the TY2009 vintage of 4.1-4.2, 'returns with positive
#               adjusted gross income' (read from the title); 'current
#               dollars', 'constant 1990 dollars' or 'percent change' (A).
#     section   1.3/2.2 TY1996-2003 only: the group a 'Net income' / 'Net
#               loss' row sits under ("Business or profession"). 4.1/4.2:
#               the statistic block as published ("Adjusted gross income
#               floor on percentiles (current whole dollars)").
#     pctile_group  'all returns', 'top 0.001 percent' ... 'top 50 percent'
#               (4.1, 4.3), 'bottom 50 percent' ... 'bottom 99 percent' (4.2):
#               cumulative groups, so 'top 5 percent' includes 'top 1 percent'.
#     item      the series key, cleaned of differences of form exactly as the
#               by-size item is (alignment_helpers.R::item_key and
#               checks/bysize_label_synonyms.csv), without the measure.
#     measure   'returns', 'amount' or 'value' (a percent, a dollar floor, a
#               count of exemptions -- including the count column of 1.3's
#               and 2.2's exemptions row, which counts exemptions).
#     unit      the unit the value is published in: 'returns', '$ thousands',
#               '$ millions', 'whole dollars', 'whole dollars, constant 1990
#               prices' (or '1982-84 prices', TY2009 vintage), '$ thousands,
#               constant 1990 prices', 'percent', 'exemptions'. Nothing is
#               rescaled.
#     flag      as in align_bysize.R, plus 'n/a' ("N/A", not applicable) and
#               'rounded' (Table 4.3: a return count SOI rounded to protect
#               confidentiality; the value is the published count). A
#               cell whose mark the sheet's own footnotes define as data
#               deleted to prevent disclosure is 'd' (TY1996-2003 print that
#               as "**"; Table A uses a numbered footnote).
#   _national_labels.csv      coverage: the years each (family, item, measure)
#     appears in, with the published labels it gathers
#   _national_additivity.csv  the tables' own arithmetic: in 1.3 and 2.2 the
#     filing statuses against all returns, for every item; in 4.1-4.3 the
#     number of returns in each top or bottom group against that percent of
#     the total. Differences traced to the published cells are pinned, exact
#     value only, in checks/national_known_differences.csv ('known')
#
# Usage:
#   Rscript align_national.R --dest /path/to/store
#
# Exits non-zero if a status sum or a percentile count fails without a
# combined, suppressed or footnote cell to explain it. The reader needs
# python3 with xlrd and, for the .xlsx vintages, openpyxl.
#------------------------------------------------------------------------------

args = commandArgs(trailingOnly = TRUE)
script_dir = dirname(sub('--file=', '', grep('--file=', commandArgs(), value = TRUE)[1]))
if (is.na(script_dir) || script_dir == '') script_dir = '.'

dest = file.path(script_dir, 'data')
if (length(args) >= 2 && args[1] == '--dest') dest = args[2]

source(file.path(script_dir, 'alignment_helpers.R'))

aligned_dir = file.path(dest, 'aligned')
dir.create(aligned_dir, showWarnings = FALSE)

LABEL_SYNONYMS = utils::read.csv(file.path(script_dir, 'checks', 'bysize_label_synonyms.csv'),
                                 stringsAsFactors = FALSE)

# Store folder, aligned-file prefix and SOI table number of each family. The
# early-release files that preceded Tables 4.1-4.3 (TY2009-2018) number
# themselves Tables 1-3.
FAMILIES = data.frame(
  family = c('all_items', 'itemizer_items', 'top_shares', 'bottom_shares', 'top_items', 'table_a'),
  folder = c('by_status', 'by_status', 'tax_shares', 'tax_shares', 'tax_shares', 'table_a'),
  prefix = c('bystatus', 'bystatus', 'pctile', 'pctile', 'pctile', ''),
  table  = c('1.3', '2.2', '4.1', '4.2', '4.3', 'A'),
  early  = c(NA, NA, '1', '2', '3', NA),
  stringsAsFactors = FALSE)

OUT_COLS = c('tax_year', 'vintage', 'table', 'family', 'row_seq', 'panel', 'section', 'row_label',
             'col_seq', 'col_group', 'col_label', 'pctile_group', 'item', 'measure', 'unit',
             'value', 'flag')

# Rounding: every published cell is rounded to a whole unit, so a sum of n
# cells can miss its total by up to n/2 units; allow n, as align_bysize.R does
rounding_tolerance = function(n) n

#-----------------------
# Helpers
#-----------------------

table_number = function(title, fam, path) {
  no = regmatches(title, regexec('^Table ([0-9]+(\\.[0-9]+[A-Z]?)?|[A-Z])\\b', title))[[1]][2]
  f = FAMILIES[FAMILIES$family == fam, ]
  if (is.na(no) || !(no %in% c(f$table, f$early))) {
    stop(path, ': expected Table ', f$table, ', title reads "', title, '"')
  }
  f$table
}

# The sheet's own footnotes: marker ("**", "[18]") -> text, read from column A
# below the data. Old vintages use "**" for data DELETED to avoid disclosure
# (TY1996-2003) where later ones use it for data COMBINED; Table 4.3 TY2014
# uses it for return counts ROUNDED; Table A numbers its disclosure note. The
# flag a mark gets is decided by its footnote, not by the mark.
footnotes = function(m) {
  lab = trimws(m[, 1])
  hit = grepl('^(\\*+|\\[[0-9]+\\]|\u2020)\\s*\\S', lab)
  mark = sub('^(\\*+|\\[[0-9]+\\]|\u2020).*$', '\\1', lab[hit])
  stats::setNames(lab[hit], mark)
}
deletes = function(text) grepl('deleted to (prevent|avoid) disclosure', tolower(text))

remap_flags = function(d, notes) {
  for (mk in names(notes)) {
    if (!deletes(notes[[mk]])) next
    if (mk == '**') {
      d$value[d$flag %in% 'combined'] = NA_real_
      d$flag[d$flag %in% 'combined'] = 'd'
    } else {
      d$flag[d$flag %in% mk] = 'd'
    }
  }
  # Table 4.3 TY2014-2015 and 2017-2019: "** Return frequency rounded to
  # protect the confidentiality of tax return information". One count a year,
  # in the top 0.001 percent, printed rounded (TY2014: 1,396 returns with
  # taxable income, the group's own size). The value is the published count,
  # so it is kept under its own flag; a zero there would be no count at all.
  if ('**' %in% names(notes) && grepl('rounded', tolower(notes[['**']]))) {
    hit = d$flag %in% 'combined'
    if (any(hit & is.na(d$value))) stop('a "**" zero where the footnote means rounded')
    d$flag[hit] = 'rounded'
  }
  d
}

year_of_file = function(f) as.integer(sub('.*_([0-9]{4})\\.xlsx?$', '\\1', f))

measure_of = function(col_label) {
  x = tolower(col_label)
  ifelse(grepl('^number of returns$', x), 'returns', ifelse(x == 'amount', 'amount', 'value'))
}

# 'Top 0.001 percent', '.001 percent', 'Bottom 50 percent', 'Total' -> the
# cumulative group, lower case, leading zero restored
pctile_label = function(x, direction) {
  x = tolower(normalize_label(x))
  x = sub('^(all returns)(, total)?$', 'all returns', x)
  x = ifelse(x == 'total', 'all returns', x)
  x = gsub('(^|\\s)\\.([0-9])', '\\10.\\2', x)
  ifelse(x == 'all returns' | grepl('^(top|bottom) ', x), x, paste(direction, x))
}

#-----------------------
# Tables 1.3 and 2.2
#-----------------------

# Through TY2003 three income items are printed as a label-only group row
# ("Business or profession:") over 'Net income' / 'Net loss' rows, and one
# label wraps onto a second row ("Earned income credit used to offset income"
# / "tax before credits"). The extractor files both under 'section'; here the
# group applies only to the 'Net ...' rows directly under it, and a wrapped
# label is rejoined.
fix_status_rows = function(d) {
  d = d[order(d$row_seq, d$col_seq), ]
  rows = unique(d[, c('row_seq', 'section', 'row_label')])
  open = FALSE
  grp = rep(NA_character_, nrow(rows))
  lab = rows$row_label
  prev = NA_character_
  for (i in seq_len(nrow(rows))) {
    s = rows$section[i]
    if (!identical(s, prev)) open = TRUE          # a label-only row came between
    prev = s
    if (!is.na(s) && grepl('^[a-z]', lab[i])) {   # the second line of a wrapped label
      lab[i] = paste(s, lab[i])
      open = FALSE
    } else if (open && !is.na(s) && grepl('^net ', tolower(lab[i]))) {
      grp[i] = s
    } else {
      open = FALSE
    }
  }
  k = match(d$row_seq, rows$row_seq)
  d$section = grp[k]
  d$row_label = lab[k]
  d
}

align_status = function(path, fam, year) {
  d = extract_bysize_sheet(path, script_dir)
  tbl = table_number(attr(d, 'title'), fam, path)
  m = read_bysize_sheet(path, script_dir)$m
  d = fix_status_rows(d)
  # the filing status is the spanner over each Number / Amount pair; the
  # all-returns pair is 'All returns' (TY1996-2003 stack it as 'All' over
  # 'returns' in the column's own header, so it lands in col_label)
  status = ifelse(d$col_group != '', d$col_group,
                  sub('\\s*(number of returns|amount)$', '', d$col_label, ignore.case = TRUE))
  measure_label = ifelse(d$col_group != '', d$col_label,
                         regmatches(d$col_label, regexpr('(Number of returns|Amount)$', d$col_label,
                                                         ignore.case = TRUE)))
  if (any(status == '')) stop(path, ': a column with no filing status')
  # TY1996-2006 print each status on two header rows, each its own spanner
  # ("Joint returns of" over "married persons"): one name, as printed
  status = gsub(' > ', ' ', status, fixed = TRUE)
  out = data.frame(
    tax_year = year, vintage = year, table = tbl, family = fam, row_seq = d$row_seq,
    panel = status, section = d$section, row_label = d$row_label, col_seq = d$col_seq,
    col_group = d$col_group, col_label = d$col_label, pctile_group = NA_character_,
    item = item_key(fam, ifelse(is.na(d$section), '', d$section), d$row_label, year, LABEL_SYNONYMS),
    measure = measure_of(measure_label), unit = NA_character_,
    value = d$value, flag = d$flag, stringsAsFactors = FALSE)
  if (any(out$measure == 'value')) stop(path, ': a column that is neither a count nor an amount')
  out$unit = ifelse(out$measure == 'returns', 'returns', '$ thousands')
  # The exemptions row's count column holds the NUMBER OF EXEMPTIONS, not of
  # returns (TY2016 1.3: 289,752,892 against 150,272,157 returns) -- checked
  # here for every year: the all-returns count must exceed the AGI row's
  ex = out$item == 'exemptions' & out$measure == 'returns'
  if (any(ex)) {
    n_ex  = out$value[ex & tolower(out$panel) == 'all returns']
    n_ret = out$value[out$item == 'adjusted gross income less deficit' & out$measure == 'returns' &
                        tolower(out$panel) == 'all returns']
    if (fam == 'all_items' && !isTRUE(n_ex > n_ret)) stop(path, ': the exemptions count is not a count of exemptions')
    out$measure[ex] = 'value'
    out$unit[ex] = 'exemptions'
  }
  remap_flags(out, footnotes(m))
}

#-----------------------
# Tables 4.1 and 4.2
#-----------------------

universe_of = function(title) {
  t = tolower(gsub('\\s+', ' ', title))
  if (grepl('returns with positive adjusted gross income', t)) return('returns with positive adjusted gross income')
  if (grepl('all individual returns excluding dependents', t)) return('all returns excluding dependents')
  stop('no universe in title "', title, '"')
}

# The constant-dollar base, from the footnote that defines it
cpi_base = function(notes) {
  hit = regmatches(notes, regexpr('CPI-U, (1982-84|1990)\\s*=\\s*100', notes))
  if (length(unique(hit)) != 1) stop('constant-dollar base not found in the footnotes')
  sub('CPI-U, (1982-84|1990).*', '\\1', hit[1])
}

# The AGI floors are whole dollars in every vintage; the TY2009 vintage words
# them "(current dollars)", later ones "(current whole dollars)"
shares_unit = function(section, base) {
  s = tolower(section)
  floor = grepl('floor|threshold', s)
  ifelse(grepl('number of returns', s), 'returns',
  ifelse(floor & grepl('constant', s), paste0('whole dollars, constant ', base, ' prices'),
  ifelse(floor & grepl('current', s), 'whole dollars',
  ifelse(grepl('millions of dollars', s), '$ millions',
  ifelse(grepl('percentage|share|rate', s), 'percent', NA_character_)))))
}

align_shares = function(path, fam, vintage) {
  d = extract_bysize_sheet(path, script_dir)
  title = attr(d, 'title')
  tbl = table_number(title, fam, path)
  m = read_bysize_sheet(path, script_dir)$m
  notes = footnotes(m)
  yr = suppressWarnings(as.numeric(d$row_label))
  if (anyNA(yr) || any(yr != round(yr))) {
    stop(path, ': a data row whose label is not a tax year: ',
         paste(unique(d$row_label[is.na(yr)]), collapse = '; '))
  }
  if (anyNA(d$section)) stop(path, ': a data row under no statistic')
  base = if (any(grepl('constant', tolower(d$section)))) cpi_base(notes) else NA_character_
  unit = shares_unit(d$section, base)
  if (anyNA(unit)) stop(path, ': no unit for ', paste(unique(d$section[is.na(unit)]), collapse = '; '))
  out = data.frame(
    tax_year = as.integer(yr), vintage = vintage, table = tbl, family = fam, row_seq = d$row_seq,
    panel = universe_of(title), section = d$section, row_label = d$row_label,
    col_seq = d$col_seq, col_group = d$col_group, col_label = d$col_label,
    pctile_group = pctile_label(d$col_label, if (fam == 'top_shares') 'top' else 'bottom'),
    item = item_key(fam, rep('', nrow(d)), d$section, vintage, LABEL_SYNONYMS),
    measure = ifelse(unit == 'returns', 'returns', ifelse(unit == 'percent', 'value', 'amount')),
    unit = unit, value = d$value, flag = d$flag, stringsAsFactors = FALSE)
  remap_flags(out, notes)
}

#-----------------------
# Table 4.3
#-----------------------

items_unit = function(item, measure) {
  ifelse(measure == 'returns', 'returns',
  ifelse(grepl('floor|cutoff', item), 'whole dollars',
  ifelse(grepl('percentage', item), 'percent', '$ thousands')))
}

align_top_items = function(path, fam, year) {
  d = extract_bysize_sheet(path, script_dir)
  title = attr(d, 'title')
  tbl = table_number(title, fam, path)
  m = read_bysize_sheet(path, script_dir)$m
  key = item_key(fam, d$col_group, d$col_label, year, LABEL_SYNONYMS)
  measure = ifelse(grepl('(^| > )number of returns$', key), 'returns',
                   ifelse(grepl('(^| > )amount$', key), 'amount', 'value'))
  series = sub('(^| > )(number of returns|amount)$', '', key)
  series[series == ''] = 'all'
  out = data.frame(
    tax_year = year, vintage = year, table = tbl, family = fam, row_seq = d$row_seq,
    panel = universe_of(title), section = NA_character_, row_label = d$row_label,
    col_seq = d$col_seq, col_group = d$col_group, col_label = d$col_label,
    pctile_group = pctile_label(d$row_label, 'top'), item = series, measure = measure,
    unit = items_unit(series, measure), value = d$value, flag = d$flag, stringsAsFactors = FALSE)
  # as in 1.3 and 2.2, the exemptions count counts exemptions (TY2014, all
  # returns: 290,409,266 against 139,562,034 returns)
  ex = out$item == 'exemptions' & out$measure == 'returns'
  if (any(ex)) {
    n_ret = out$value[out$item == 'all' & out$pctile_group == 'all returns']
    if (!isTRUE(out$value[ex & out$pctile_group == 'all returns'] > n_ret)) {
      stop(path, ': the exemptions count is not a count of exemptions')
    }
    out$measure[ex] = 'value'
    out$unit[ex] = 'exemptions'
  }
  bad = !grepl('^(all returns|top [0-9.]+ percent)$', out$pctile_group)
  if (any(bad)) stop(path, ': rows that are no percentile group: ',
                     paste(unique(out$row_label[bad]), collapse = '; '))
  remap_flags(out, footnotes(m))
}

#-----------------------
# Table A
#-----------------------

# Read directly from the sheet rather than through extract_bysize_sheet: the
# columns are tax years under three bands (current dollars, the percent change
# from the year before, constant 1990 dollars, and its percent change), and
# the rows pair "Item: Number of returns" with an "Amount" row below it, with
# indented sub-items ("    Electronically filed returns") that belong to the
# row above. Both need the raw label, before normalize_label trims it.
align_table_a = function(path, fam, vintage) {
  sh = read_bysize_sheet(path, script_dir)
  m = sh$m
  raw = read_bysize_sheet(path, script_dir, trim = FALSE)$m
  blk = find_numrows(m)
  if (length(blk) != 1) stop(path, ': expected one column-number row')
  blk = blk[[1]]
  cols = blk$cols
  hdr = seq_len(blk$row - 1)
  title = gsub('\\s+', ' ', m[1, 1])
  tbl = table_number(title, fam, path)

  # each data column's band (the header text nearest to its left in a header
  # row, read top-down, a higher row winning) and year (an integer between
  # 1950 and 2100 in its own header cells)
  year = rep(NA_integer_, length(cols))
  band = rep(NA_character_, length(cols))
  for (i in hdr) {
    cur = NA_character_
    for (k in seq_along(cols)) {
      left = if (k == 1) 2 else cols[k - 1] + 1
      for (j in left:cols[k]) {
        txt = normalize_label(m[i, j])
        if (grepl('dollars|percent change', tolower(txt))) cur = txt
      }
      if (is.na(band[k]) && !is.na(cur)) band[k] = cur
    }
  }
  for (k in seq_along(cols)) {
    v = suppressWarnings(as.numeric(m[hdr, cols[k]]))
    v = v[!is.na(v) & v == round(v) & v >= 1950 & v <= 2100]
    if (length(v) == 1) year[k] = as.integer(v)
  }
  pct = grepl('^percent change', tolower(band))
  # "Percent change, 2022 to 2023": the year it describes is the later one
  year[pct] = as.integer(sub('.*to ([0-9]{4}).*', '\\1', band[pct]))
  panel = ifelse(pct, 'percent change',
                 ifelse(grepl('^current dollars', tolower(band)), 'current dollars',
                        ifelse(grepl('^constant 1990 dollars', tolower(band)), 'constant 1990 dollars',
                               NA_character_)))
  if (anyNA(panel) || anyNA(year)) stop(path, ': a column with no band or no year')
  # the percent-change band that follows the constant-dollar columns
  const_start = min(which(panel == 'constant 1990 dollars'))
  panel[pct & seq_along(cols) > const_start] = 'percent change, constant 1990 dollars'
  panel[panel == 'percent change'] = 'percent change, current dollars'

  note_regex = '^(notes?\\s*:|source\\s*:|n/a\\b|\\*|\\[)'
  out = list()
  parent = NA_character_
  last_item = NA_character_
  for (i in seq(blk$row + 1, nrow(m))) {
    lab_raw = raw[i, 1]
    if (grepl(note_regex, tolower(trimws(lab_raw)))) break
    cells = m[i, cols]
    if (trimws(lab_raw) == '' && all(cells == '')) next
    if (all(cells == '')) stop(path, ': label-only row ', i, ': "', lab_raw, '"')
    indented = grepl('^\\s', lab_raw)
    lab = normalize_label(lab_raw)
    mm = regmatches(lab, regexec('^(.*):\\s*(number of returns|amount)$', lab, ignore.case = TRUE))[[1]]
    if (length(mm) == 3) {
      item = mm[2]
      meas = if (tolower(mm[3]) == 'amount') 'amount' else 'returns'
    } else if (tolower(lab) == 'amount') {
      if (is.na(last_item)) stop(path, ': an Amount row with no item above it, row ', i)
      item = last_item
      meas = 'amount'
    } else {
      item = lab
      meas = if (grepl('returns$', tolower(lab))) 'returns'
             else if (grepl('^number of', tolower(lab))) 'value' else 'amount'
    }
    if (indented && tolower(lab) != 'amount') {
      if (is.na(parent)) stop(path, ': an indented row with no row above it, row ', i)
      item = paste(parent, '>', item)
    } else if (!indented) {
      parent = item
    }
    last_item = item
    cleaned = mapply(clean_value, cells, sh$flag[i, cols], SIMPLIFY = FALSE)
    out[[length(out) + 1]] = data.frame(
      tax_year = year, vintage = vintage, table = tbl, family = fam, row_seq = i,
      panel = panel, section = NA_character_, row_label = lab, col_seq = blk$vals,
      col_group = band, col_label = as.character(year), pctile_group = NA_character_,
      item = item, measure = meas, unit = NA_character_,
      value = unname(vapply(cleaned, function(v) v$value, numeric(1))),
      flag  = unname(vapply(cleaned, function(v) v$flag,  character(1))),
      row.names = NULL, stringsAsFactors = FALSE)
  }
  d = do.call(rbind, out)
  if (is.null(d) || length(unique(d$row_seq)) < 50) stop(path, ': parsed too few rows')
  d$item = item_key(fam, rep('', nrow(d)), d$item, vintage, LABEL_SYNONYMS)
  d$unit = ifelse(grepl('^percent change', d$panel), 'percent',
           ifelse(d$measure == 'returns', 'returns',
           ifelse(d$measure == 'value', 'exemptions',
           ifelse(d$panel == 'constant 1990 dollars', '$ thousands, constant 1990 prices',
                  '$ thousands'))))
  if (any(d$measure == 'value' & !grepl('^number of exemptions', d$item))) {
    stop(path, ': a count that is neither returns nor exemptions')
  }
  remap_flags(d, footnotes(m))
}

#-----------------------
# Extract
#-----------------------

panels = list()
for (k in seq_len(nrow(FAMILIES))) {
  fam = FAMILIES$family[k]
  dir = file.path(dest, 'national', FAMILIES$folder[k])
  files = sort(list.files(dir, pattern = sprintf('^%s_[0-9]{4}\\.xlsx?$', fam)))
  if (length(files) == 0) stop('no ', fam, ' files under ', dir)
  fn = switch(FAMILIES$folder[k],
              by_status  = align_status,
              tax_shares = if (fam == 'top_items') align_top_items else align_shares,
              table_a    = align_table_a)
  p = do.call(rbind, lapply(files, function(f) fn(file.path(dir, f), fam, year_of_file(f))))
  p = p[, OUT_COLS]
  # a cleanup rule that folds two published cells of one file together has
  # merged a difference of meaning, not of form
  cell = paste(p$vintage, p$tax_year, p$panel, p$section, p$pctile_group, p$item, p$measure)
  if (anyDuplicated(cell)) {
    stop(fam, ': two published cells share one key, e.g. ', cell[duplicated(cell)][1])
  }
  panels[[fam]] = p
  name = if (FAMILIES$prefix[k] == '') fam else paste0(FAMILIES$prefix[k], '_', fam)
  utils::write.csv(p, file.path(aligned_dir, paste0(name, '.csv')), row.names = FALSE, na = '')
  cat(sprintf('%-16s Table %-4s %2d files (vintages %d-%d), tax years %d-%d, %7d cells\n',
              fam, p$table[1], length(files), min(p$vintage), max(p$vintage),
              min(p$tax_year), max(p$tax_year), nrow(p)))
}

#-----------------------
# Label coverage
#-----------------------

labels = do.call(rbind, lapply(panels, function(d) {
  u = unique(d[, c('family', 'table', 'item', 'measure', 'vintage')])
  a = aggregate(vintage ~ family + table + item + measure, u,
                function(y) paste(sort(y), collapse = ' '))
  names(a)[names(a) == 'vintage'] = 'vintages'
  a$n_vintages = lengths(strsplit(a$vintages, ' '))
  lab = ifelse(is.na(d$section) | d$family %in% c('top_shares', 'bottom_shares'),
               ifelse(d$family %in% c('top_shares', 'bottom_shares'), d$section,
                      ifelse(d$family == 'top_items',
                             ifelse(d$col_group == '', d$col_label, paste(d$col_group, '>', d$col_label)),
                             d$row_label)),
               paste(d$section, '>', d$row_label))
  pub = unique(data.frame(k = paste(d$item, d$measure), lab = lab, stringsAsFactors = FALSE))
  a$published_labels = vapply(paste(a$item, a$measure), function(k)
    paste(unique(pub$lab[pub$k == k]), collapse = ' || '), character(1))
  a
}))
utils::write.csv(labels, file.path(aligned_dir, '_national_labels.csv'), row.names = FALSE)

#-----------------------
# The tables' own arithmetic
#-----------------------

explains_missing = function(flags) flags %in% c('combined', 'd', 'n/a') | grepl('^\\[', flags)

sum_status = function(total, total_flag, parts, flags) {
  if (is.na(total)) return(if (explains_missing(total_flag)) 'no_total' else 'blank')
  if (any(flags %in% 'combined')) {
    diff = total - sum(parts, na.rm = TRUE)
    return(if (abs(diff) <= rounding_tolerance(length(parts))) 'ok' else 'combined')
  }
  if (any(flags %in% 'd')) return('suppressed')
  if (any(is.na(parts) & !explains_missing(flags))) return('blank')
  if (anyNA(parts)) return('footnote')
  if (abs(total - sum(parts)) <= rounding_tolerance(length(parts))) 'ok' else 'fail'
}

checks = list()
# 1.3, 2.2: the filing statuses are mutually exclusive and exhaustive, so
# every item's statuses add to its all-returns column, counts and amounts
for (fam in c('all_items', 'itemizer_items')) {
  d = panels[[fam]]
  is_all = tolower(d$panel) == 'all returns'
  key = paste(d$tax_year, d$item, d$measure, sep = '\r')
  res = lapply(split(seq_len(nrow(d)), key), function(ix) {
    t = ix[is_all[ix]]
    p = ix[!is_all[ix]]
    if (length(t) != 1) stop(fam, ': not one all-returns cell for ', key[ix[1]])
    data.frame(family = fam, tax_year = d$tax_year[t], vintage = d$vintage[t],
               check = 'statuses add to all returns', item = d$item[t], measure = d$measure[t],
               group = NA_character_, total = d$value[t], parts = sum(d$value[p], na.rm = TRUE),
               n_parts = length(p),
               status = sum_status(d$value[t], d$flag[t], d$value[p], d$flag[p]),
               stringsAsFactors = FALSE)
  })
  checks[[fam]] = do.call(rbind, res)
}
# 4.1, 4.2, 4.3: a cumulative group of x percent holds x percent of the
# returns, rounded to a whole return
for (fam in c('top_shares', 'bottom_shares', 'top_items')) {
  d = panels[[fam]]
  d = d[d$measure == 'returns' & (fam != 'top_items' | d$item == 'all'), ]
  tot = d[d$pctile_group == 'all returns', c('vintage', 'tax_year', 'panel', 'value')]
  grp = d[d$pctile_group != 'all returns', ]
  x = merge(grp, tot, by = c('vintage', 'tax_year', 'panel'), suffixes = c('', '_total'))
  if (nrow(x) != nrow(grp)) stop(fam, ': a percentile group with no all-returns count')
  share = as.numeric(sub('^(top|bottom) ([0-9.]+) percent$', '\\2', x$pctile_group)) / 100
  expected = x$value_total * share
  checks[[fam]] = data.frame(
    family = fam, tax_year = x$tax_year, vintage = x$vintage,
    check = 'group holds its percent of all returns', item = x$item, measure = x$measure,
    group = x$pctile_group, total = expected, parts = x$value, n_parts = 1L,
    status = ifelse(is.na(x$value), ifelse(explains_missing(x$flag), 'footnote', 'blank'),
                    ifelse(abs(x$value - expected) <= 1, 'ok', 'fail')),
    stringsAsFactors = FALSE)
}
checks = do.call(rbind, checks)
checks$diff = checks$total - checks$parts

# Differences already traced to the published cells. Each entry pins the
# exact difference for one comparison; any other difference still fails, and
# an entry no comparison produces stops the run (as in align_bysize.R)
known = utils::read.csv(file.path(script_dir, 'checks', 'national_known_differences.csv'),
                        stringsAsFactors = FALSE, na.strings = '')
key = function(z) sprintf('%s %d %d %s %s %s %.2f', z$family, z$vintage, z$tax_year, z$item,
                          z$measure, ifelse(is.na(z$group), '', z$group), z$diff)
checks$status[checks$status == 'fail' & key(checks) %in% key(known)] = 'known'
stale = known[!key(known) %in% key(checks), ]
if (nrow(stale) > 0) {
  stop('checks/national_known_differences.csv entries no comparison produced:\n',
       paste(key(stale), collapse = '\n'))
}
utils::write.csv(checks, file.path(aligned_dir, '_national_additivity.csv'), row.names = FALSE, na = '')

#-----------------------
# Report
#-----------------------

cat('\nOwn arithmetic (statuses against all returns; percentile counts):\n')
print(table(checks$family, checks$status))
bad = checks[checks$status %in% c('fail', 'blank'), ]
if (nrow(bad) > 0) {
  cat('\nUnexplained:\n')
  print(utils::head(bad[, c('family', 'vintage', 'tax_year', 'item', 'measure', 'group',
                            'total', 'parts', 'diff', 'status')], 40), row.names = FALSE)
  cat(sprintf('\n%d unexplained comparison(s) failed; see aligned/_national_additivity.csv\n', nrow(bad)))
  quit(status = 1)
}
cat('\nAll comparisons pass or are explained by combined, suppressed or footnote cells.\n')
