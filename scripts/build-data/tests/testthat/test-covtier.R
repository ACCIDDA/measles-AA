# Coverage-tier derivation (covtier), the H/M/L thresholds the schema enum pins.
#
# Fit-independent and shared by both producers. schema.js declares tier in
# {H, M, L}; covtier must produce exactly those for in-range coverage and NA for
# missing coverage (no_data schools, NC blank per-grade county rows).

test_that("covtier applies the H/M/L thresholds", {
  expect_equal(covtier(0.99), "H")   # >= 0.95
  expect_equal(covtier(0.95), "H")   # boundary inclusive
  expect_equal(covtier(0.93), "M")   # >= 0.90
  expect_equal(covtier(0.90), "M")   # boundary inclusive
  expect_equal(covtier(0.80), "L")   # < 0.90
})

test_that("covtier returns NA_character_ for missing coverage", {
  expect_true(is.na(covtier(NA_real_)))
})

test_that("covtier is vectorized and only emits enum values", {
  out <- covtier(c(0.99, 0.92, 0.5, NA_real_))
  expect_equal(out, c("H", "M", "L", NA_character_))
  expect_true(all(out[!is.na(out)] %in% c("H", "M", "L")))
})
