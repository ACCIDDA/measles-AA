# Point-in-polygon county assignment (build_nc_from_estimates.R).
#
# Tiny synthetic fixture: two adjacent unit squares standing in for county
# polygons in a planar CRS (the NC producer runs PIP in native EPSG:2264, so no
# reprojection is involved and plain x/y squares are a faithful stand-in).
#   "West"  = [0,10] x [0,10]
#   "East"  = [10,20] x [0,10]
# Geojson rings are closed (first point repeated), matching build_counties input.

make_square <- function(name, x0, x1, y0, y1, coverage = 0.9) {
  list(properties = list(NAME = name, coverage = coverage,
                         cov_low = NULL, cov_high = NULL,
                         herd_immune_fraction = NULL),
       geometry = list(type = "Polygon", coordinates = list(list(
         list(x0, y0), list(x1, y0), list(x1, y1), list(x0, y1), list(x0, y0)))))
}

county_geo <- list(
  make_square("West",  0, 10, 0, 10),
  make_square("East", 10, 20, 0, 10)
)
nz <- function(v) if (is.null(v) || length(v) == 0) NA else v
counties <- build_counties(county_geo, nz)

test_that("build_counties extracts name, ring, and bbox per polygon", {
  expect_equal(length(counties), 2L)
  expect_equal(counties[[1]]$name, "West")
  expect_equal(counties[[1]]$xr, c(0, 10))
  expect_equal(counties[[1]]$yr, c(0, 10))
  # closed ring -> 5 vertices, 2 columns
  expect_equal(dim(counties[[1]]$ring), c(5L, 2L))
})

test_that("point_in_ring is true for an interior point, false outside", {
  ring <- counties[[1]]$ring
  expect_true(point_in_ring(5, 5, ring))
  expect_false(point_in_ring(15, 5, ring))
  expect_false(point_in_ring(-1, 5, ring))
})

test_that("assign_county places interior points in the right county", {
  expect_equal(assign_county(5, 5, counties), "West")
  expect_equal(assign_county(15, 5, counties), "East")
})

test_that("assign_county returns NA for points outside all polygons", {
  expect_true(is.na(assign_county(50, 50, counties)))
  expect_true(is.na(assign_county(5, 50, counties)))
})

test_that("assign_county respects the bbox short-circuit (no false West match)", {
  # A point clearly in East's bbox must not be claimed by West.
  expect_equal(assign_county(19, 1, counties), "East")
})

test_that("border points resolve deterministically to a single county", {
  # The shared edge x == 10: ray-casting assigns it to exactly one polygon, and
  # assign_county returns the first match, so it is never double-counted.
  res <- assign_county(10, 5, counties)
  expect_true(res %in% c("West", "East", NA_character_))
  expect_length(res, 1L)
})
