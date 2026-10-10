# County-name title-casing (build_state.R title_case).
#
# This is the bug that shipped twice during #54: linkage_key ships county names
# lowercased ("los angeles"), but the dashboard joins schools/counties to the
# us-atlas polygon names ("Los Angeles"). A mismatch produced gray counties and
# then 0-schools. title_case must capitalize the first letter of every word.

test_that("title_case capitalizes the first letter of each word", {
  expect_equal(title_case("los angeles"), "Los Angeles")
  expect_equal(title_case("san luis obispo"), "San Luis Obispo")
  expect_equal(title_case("yolo"), "Yolo")
})

test_that("title_case lowercases all-caps and mixed input first", {
  expect_equal(title_case("LOS ANGELES"), "Los Angeles")
  expect_equal(title_case("Los ANGELES"), "Los Angeles")
})

test_that("title_case is vectorized", {
  expect_equal(title_case(c("yolo", "yuba", "san diego")),
               c("Yolo", "Yuba", "San Diego"))
})

test_that("title_case preserves word boundaries across hyphens", {
  # us-atlas has hyphenated/compound names; the \\b boundary should capitalize
  # the letter after a hyphen too.
  expect_equal(title_case("winston-salem"), "Winston-Salem")
})

test_that("title_case handles NA without erroring", {
  expect_true(is.na(title_case(NA_character_)))
})
