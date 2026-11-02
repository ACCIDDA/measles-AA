# Build a submission from long-form estimates and school/county geography.
# Required: INPUT_DIR, META_PATH, OUT_DIR. See docs/BUILDERS.md.
suppressMessages({library(data.table); library(jsonlite)})

HELPERS <- Sys.getenv("PRODUCER_HELPERS",
                      unset = "scripts/build-data/R/producer-helpers.R")
source(HELPERS)

for (key in c("INPUT_DIR", "META_PATH", "OUT_DIR")) {
  if (!nzchar(Sys.getenv(key))) stop(paste("Set", key))
}
IN <- Sys.getenv("INPUT_DIR")
OUT <- Sys.getenv("OUT_DIR")
if (file.exists(OUT)) stop("OUT_DIR must be a new directory")
meta <- read_state_metadata()
GRADE_AGES <- c("5_6","6_7","7_8","8_9","9_10","10_11")
GRADE_LAB  <- c("K","1","2","3","4","5")
names(GRADE_LAB) <- GRADE_AGES
THRESHOLD <- 0.95
# null-safe property accessor: geojson props may be JSON null -> R NULL, which
# would silently drop a data.table column. Coerce missing to NA.
nz <- function(v) if (is.null(v) || length(v) == 0) NA else v

# ---- load + split geojson ----
g <- fromJSON(file.path(IN, "locations.geojson"), simplifyVector = FALSE)
if (!identical(g$type, "FeatureCollection")) stop("Expected a GeoJSON FeatureCollection")
feats <- g$features
types <- vapply(feats, function(f) f$geometry$type, character(1))
if (!all(types %in% c("Point", "Polygon"))) stop("Only Point and single-ring Polygon geometries are supported")
if (!all(c("Point", "Polygon") %in% types)) stop("Supply school points and county polygons")
for (feature in feats) {
  if (feature$geometry$type == "Polygon" && length(feature$geometry$coordinates) != 1L)
    stop("Polygon holes are unsupported; resolve county assignments upstream")
  coords <- if (feature$geometry$type == "Point") list(feature$geometry$coordinates) else feature$geometry$coordinates[[1]]
  if (!length(coords) || any(!vapply(coords, function(p) length(p) == 2L &&
      all(vapply(p, function(v) is.numeric(v) && length(v) == 1L && is.finite(v), logical(1))), logical(1))))
    stop("Coordinates must be finite two-dimensional numeric positions")
  if (feature$geometry$type == "Polygon" && (length(coords) < 4L || !identical(coords[[1]], coords[[length(coords)]])))
    stop("Polygon rings must be closed with at least four positions")
}
is_poly  <- vapply(feats, function(f) f$geometry$type == "Polygon", logical(1))
schools_geo <- feats[!is_poly]
county_geo  <- feats[is_poly]
message(sprintf("geojson: %d school points, %d county polygons", length(schools_geo), length(county_geo)))

# county polygons -> bbox + outer ring (for PIP) and the coverage props
counties <- build_counties(county_geo, nz)
county_names <- vapply(counties, function(c) as.character(nz(c$name)), character(1))
if (anyNA(county_names) || any(!nzchar(trimws(county_names))) || anyDuplicated(county_names))
  stop("County names must be nonempty and unique")

# school points -> id, name, overall coverage, county (via PIP)
sch <- rbindlist(lapply(schools_geo, function(f) {
  xy <- f$geometry$coordinates
  data.table(location_id = as.character(nz(f$properties$location_id)), school_name = nz(f$properties$NAME),
             coverage = nz(f$properties$coverage), ci_low = nz(f$properties$cov_low),
             ci_high = nz(f$properties$cov_high), x = xy[[1]], y = xy[[2]])
}))
if (anyNA(sch$location_id) || any(!nzchar(trimws(sch$location_id))) || anyDuplicated(sch$location_id))
  stop("School location IDs must be nonempty and unique")
sch[, county_name := mapply(function(x, y) assign_county(x, y, counties), x, y)]
message(sprintf("schools assigned to a county: %d/%d", sum(!is.na(sch$county_name)), nrow(sch)))

if (anyNA(sch$county_name)) stop("Every school must match a county polygon")

# ---- per-grade wide from estimates.csv ----
est <- fread(file.path(IN, "estimates.csv"), colClasses = c(id = "character", age_group = "character"), na.strings = "")
if (!all(c("id", "est", "ci_low", "ci_high", "population", "age_group") %in% names(est)))
  stop("Estimates require id, est, ci_low, ci_high, population, age_group")
if (anyNA(est$id) || any(!nzchar(trimws(est$id))) || any(!est$id %in% sch$location_id))
  stop("Every estimate ID must match a school location")
if (any(!est$age_group %in% GRADE_AGES)) stop("Unsupported age_group")
if (anyDuplicated(est[, .(id, age_group)])) stop("Duplicate school/age_group estimates")
for (column in c("est", "ci_low", "ci_high", "population")) {
  value <- est[[column]]
  if (!is.numeric(value) && !all(is.na(value))) stop(paste("Invalid numeric column", column))
  if (any(!is.na(value) & (!is.finite(value) | value < 0))) stop(paste("Invalid", column))
  if (column != "population" && any(value > 1, na.rm = TRUE)) stop("Coverage must be a proportion")
  if (column == "population" && any(value != floor(value), na.rm = TRUE)) stop("Population must be an integer")
}
if (any(est$ci_low > est$ci_high, na.rm = TRUE)) stop("Reversed estimate interval")
est[, grade := GRADE_LAB[age_group]]
wide_val <- function(col, prefix) {
  d <- data.table(id = unique(est$id))
  for (grade in unname(GRADE_LAB)) {
    indices <- which(est$grade == grade)
    values <- est[indices]
    set(d, j = paste0(prefix, grade), value = as.numeric(values[[col]][match(d$id, values$id)]))
  }
  d
}
pg  <- wide_val("est", "coverage_")
plo <- wide_val("ci_low", "coverage_ci_low_")
phi <- wide_val("ci_high", "coverage_ci_high_")
pen <- est[, .(enrollment = if (all(is.na(population))) NA_real_ else max(population, na.rm = TRUE)), by = id]   # enrollment = max across grades

# Join per-grade estimates to school identity and overall coverage.
schools <- Reduce(function(a,b) merge(a,b,by="id",all=TRUE), list(pg,plo,phi,pen))
# attach identity + overall coverage from geojson points (join id == location_id)
schools <- merge(sch[, .(id = location_id, school_name, county_name,
                         coverage, coverage_ci_low = ci_low, coverage_ci_high = ci_high)],
                 schools, by = "id", all.x = TRUE)
schools[, prob_below_95 := NA_real_]   # not recoverable from point estimates alone
schools[, tier := covtier(coverage)]

# ---- county rows: coverage straight from geojson polygons ----
cty_stat <- schools[!is.na(county_name),
  .(n_schools = .N, pct_schools_below_95 = safe_mean(coverage < THRESHOLD)), by = county_name]
counties_dt <- rbindlist(lapply(counties, function(c) data.table(
  county = c$name, county_fips = NA_character_,
  coverage = c$coverage, coverage_ci_low = c$cov_low, coverage_ci_high = c$cov_high)))
counties_dt <- merge(counties_dt, cty_stat, by.x="county", by.y="county_name", all.x=TRUE)
for (g in GRADE_LAB) {                       # county per-grade not provided -> blank
  counties_dt[, (paste0("coverage_",g)) := NA_real_]
  counties_dt[, (paste0("coverage_ci_low_",g)) := NA_real_]
  counties_dt[, (paste0("coverage_ci_high_",g)) := NA_real_]
}
counties_dt[, prob_below_95 := NA_real_][, tier := covtier(coverage)]

# ---- state row: enrollment-weighted school overall ----
st_cov <- schools[!is.na(coverage), safe_weighted_mean(coverage, enrollment)]
state_dt <- data.table(state=meta$code, state_fips=meta$fips, state_name=meta$fullName,
  n_schools = nrow(schools),
  pct_schools_below_95 = schools[, safe_mean(coverage < THRESHOLD)],
  coverage = st_cov, coverage_ci_low = NA_real_, coverage_ci_high = NA_real_)
for (g in GRADE_LAB) {
  state_dt[, (paste0("coverage_",g)) :=
    schools[, safe_weighted_mean(get(paste0("coverage_",g)), enrollment)]]
  state_dt[, (paste0("coverage_ci_low_",g)) := NA_real_]
  state_dt[, (paste0("coverage_ci_high_",g)) := NA_real_]
}
state_dt[, prob_below_95 := NA_real_][, tier := covtier(coverage)]

# Export coordinates only after an upstream transformation to longitude/latitude.
schools_all <- copy(schools)
setnames(schools_all, c("id", "county_name"), c("school_id", "county"))
schools_all[, `:=`(lon = NA_real_, lat = NA_real_)]
measure_cols <- c("coverage", paste0("coverage_", unname(GRADE_LAB)))
schools_all[, no_data := as.integer(rowSums(!is.na(.SD)) == 0), .SDcols = measure_cols]
counties_dt[is.na(n_schools), n_schools := 0L]
write_submission(state_dt, counties_dt, schools_all, OUT, meta)
message("Wrote submission under ", OUT, "; run prepare.py before publication")
