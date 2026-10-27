#!/usr/bin/env Rscript
#------------------------------------------------------------------------------
# align_cv.R
#
# SOI's coefficients of variation for Pub 1304 Tables 1.4, 2.1 and 3.3
# (national/by_size_cv/), parsed into one long file and joined to the
# published cells they describe in the aligned by-size panels.
#
# A CV workbook is laid out cell for cell like its table: the same panels,
# AGI rows and numbered columns, each cell holding the estimate's coefficient
# of variation in percent (its standard error as a percent of the estimate).
# It is read with the same extractor and label cleanup as the table itself
# (alignment_helpers.R), and each CV cell is matched to the published cell on
# tax year, family, panel, row label and published column number.
#
# Output, under <dest>/aligned/:
#   cv_bysize.csv  one row per CV cell, every year SOI published (named so
#     that harmonize_bysize.R's bysize_*.csv pattern does not take it for a
#     table):
#       tax_year, table, family, row_seq, panel, section, row_label,
#       row_agi_lo, row_agi_hi, col_seq, col_group, col_label, item, cv,
#       cv_flag, value, flag, unit, std_error, match
#     cv         the coefficient of variation, percent, as published
#     cv_flag    the CV cell's own mark (a '**' cell has no CV: SOI combined
#                the estimate, so its CV is that of the combined cell)
#     value, flag  the published estimate and its mark, from
#                aligned/bysize_{family}.csv
#     unit       of value and std_error: 'returns' or '$ thousands'
#     std_error  value x cv / 100, in the unit of the value
#     item       the published cell's item where it was found, else the CV
#                workbook's own
#     match      'matched' (same cell, same item), 'label differs' (same
#                cell, the two files word the column differently; every one
#                checked by eye is wording only), 'no published cell' (a year
#                the table is mirrored for, but no cell at that position),
#                'table not mirrored' (TY1997-2010: the by-size tables are
#                mirrored from TY2011)
#   _bysize_cv_coverage.csv  per (family, tax year, panel): published cells,
#     cells with a CV cell, cells with a CV number, nonzero values with a CV
#     of exactly 0 (the $10,000,000-or-more class is sampled in full)
#
# Usage:
#   Rscript align_cv.R --dest /path/to/store      # after align_bysize.R
#
# Stops if a workbook cannot be parsed, or if a published cell of a mirrored
# year has no CV cell.
#------------------------------------------------------------------------------

args = commandArgs(trailingOnly = TRUE)
script_dir = dirname(sub('--file=', '', grep('--file=', commandArgs(), value = TRUE)[1]))
if (is.na(script_dir) || script_dir == '') script_dir = '.'

dest = file.path(script_dir, 'data')
if (length(args) >= 2 && args[1] == '--dest') dest = args[2]

source(file.path(script_dir, 'alignment_helpers.R'))

cv_dir = file.path(dest, 'national', 'by_size_cv')
aligned_dir = file.path(dest, 'aligned')

LABEL_SYNONYMS = utils::read.csv(file.path(script_dir, 'checks', 'bysize_label_synonyms.csv'),
                                 stringsAsFactors = FALSE)

TABLE = c(income_sources = '1.4', itemized_deductions = '2.1', tax_liability = '3.3')

#-----------------------
# Extract
#-----------------------

files = sort(list.files(cv_dir, pattern = '^[a-z_]+_cv_[0-9]{4}\\.xls$'))
if (length(files) == 0) stop('no CV workbooks under ', cv_dir)

parts = lapply(files, function(f) {
  fam = sub('_cv_[0-9]{4}\\.xls$', '', f)
  year = as.integer(sub('.*_([0-9]{4})\\.xls$', '\\1', f))
  d = extract_bysize_sheet(file.path(cv_dir, f), script_dir)
  title = attr(d, 'title')
  if (!grepl(sprintf('^Table %s ?CV', gsub('.', '\\.', TABLE[[fam]], fixed = TRUE)), title)) {
    stop(f, ': expected Table ', TABLE[[fam]], 'CV, title reads "', title, '"')
  }
  d = cbind(tax_year = year, table = TABLE[[fam]], family = fam, d, stringsAsFactors = FALSE)
  d$item = item_key(fam, d$col_group, d$col_label, year, LABEL_SYNONYMS)
  d
})
cv = do.call(rbind, parts)
names(cv)[names(cv) == 'value'] = 'cv'
names(cv)[names(cv) == 'flag'] = 'cv_flag'

#-----------------------
# Join to the published cells
#-----------------------

published = do.call(rbind, lapply(names(TABLE), function(fam) {
  v = utils::read.csv(file.path(aligned_dir, sprintf('bysize_%s.csv', fam)),
                      stringsAsFactors = FALSE, na.strings = '')
  v[, c('tax_year', 'family', 'panel', 'row_label', 'col_seq', 'item', 'value', 'flag')]
}))
names(published)[names(published) == 'item'] = 'published_item'

key = function(z) paste(z$tax_year, z$family, z$panel, z$row_label, z$col_seq, sep = '\r')
if (anyDuplicated(key(cv))) stop('two CV cells share one position: ', key(cv)[duplicated(key(cv))][1])
if (anyDuplicated(key(published))) stop('two published cells share one position')
k = match(key(cv), key(published))
cv$value = published$value[k]
cv$flag = published$flag[k]
mirrored = unique(published[, c('tax_year', 'family')])
in_mirror = paste(cv$tax_year, cv$family) %in% paste(mirrored$tax_year, mirrored$family)
cv$match = ifelse(!in_mirror, 'table not mirrored',
           ifelse(is.na(k), 'no published cell',
           ifelse(cv$item == published$published_item[k], 'matched', 'label differs')))
cv$item = ifelse(is.na(k), cv$item, published$published_item[k])

# Every published cell of a year both files cover has its CV cell
pub_cv = paste(published$tax_year, published$family) %in% paste(cv$tax_year, cv$family)
lost = published[pub_cv & !(key(published) %in% key(cv)), ]
if (nrow(lost) > 0) {
  stop(nrow(lost), ' published cells have no CV cell, e.g. ',
       paste(lost$tax_year[1], lost$family[1], lost$panel[1], lost$row_label[1], lost$col_seq[1]))
}

# A count or an amount: SOI pairs "Number of returns" with "Amount" under each
# item; the stand-alone first columns are the number of returns and AGI
cv$unit = ifelse(grepl('(^| > )number of returns$', cv$item), 'returns', '$ thousands')
cv$std_error = cv$value * cv$cv / 100

out = cv[order(cv$family, cv$tax_year, cv$row_seq, cv$col_seq),
         c('tax_year', 'table', 'family', 'row_seq', 'panel', 'section', 'row_label',
           'row_agi_lo', 'row_agi_hi', 'col_seq', 'col_group', 'col_label', 'item',
           'cv', 'cv_flag', 'value', 'flag', 'unit', 'std_error', 'match')]
utils::write.csv(out, file.path(aligned_dir, 'cv_bysize.csv'), row.names = FALSE, na = '')

#-----------------------
# Coverage
#-----------------------

pub = published[pub_cv, ]
kp = match(key(pub), key(cv))
pub$cv = cv$cv[kp]
cov = aggregate(cbind(published_cells = 1, with_cv_cell = !is.na(kp),
                      with_cv_number = !is.na(pub$cv),
                      value_without_cv = !is.na(pub$value) & is.na(pub$cv),
                      nonzero_value_cv_zero = !is.na(pub$value) & pub$value != 0 &
                        !is.na(pub$cv) & pub$cv == 0) ~ family + tax_year + panel,
                data = pub, FUN = sum, na.action = na.pass)
utils::write.csv(cov, file.path(aligned_dir, '_bysize_cv_coverage.csv'), row.names = FALSE)

cat(sprintf('%d CV workbooks, %d CV cells\n', length(files), nrow(out)))
print(table(paste(out$family, ifelse(out$tax_year < 2011, '1997-2010', '2011+')), out$match))
cat('\nPublished cells with a value but no CV number, by the CV cell\'s mark:\n')
nv = cv[cv$match %in% c('matched', 'label differs') & !is.na(cv$value) & is.na(cv$cv), ]
print(table(nv$family, ifelse(is.na(nv$cv_flag), 'none', nv$cv_flag)))
