test_that("title_case capitalizes the first letter of each word", {
  expect_equal(title_case("central valley"), "Central Valley")
  expect_equal(title_case("north river valley"), "North River Valley")
  expect_equal(title_case("west"), "West")
})

test_that("title_case lowercases all-caps and mixed input first", {
  expect_equal(title_case("CENTRAL VALLEY"), "Central Valley")
  expect_equal(title_case("Central VALLEY"), "Central Valley")
})

test_that("title_case is vectorized", {
  expect_equal(title_case(c("west", "east", "south valley")),
               c("West", "East", "South Valley"))
})

test_that("title_case preserves word boundaries across hyphens", {
  # us-atlas has hyphenated/compound names; the \\b boundary should capitalize
  # the letter after a hyphen too.
  expect_equal(title_case("river-hill"), "River-Hill")
})

test_that("title_case handles NA without erroring", {
  expect_true(is.na(title_case(NA_character_)))
})
