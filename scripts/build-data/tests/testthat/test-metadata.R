metadata_schema <- normalizePath(file.path(build_data, "..", "..", "schema", "meta-schema.json"))
metadata_example <- normalizePath(file.path(build_data, "..", "..", "data", "examples", "meta.json"))

read_test_metadata <- function(json, schema_path = metadata_schema) {
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeLines(json, path)
  previous <- Sys.getenv("META_PATH", unset = NA_character_)
  on.exit(if (is.na(previous)) Sys.unsetenv("META_PATH") else Sys.setenv(META_PATH = previous), add = TRUE)
  Sys.setenv(META_PATH = path)
  read_state_metadata(schema_path)
}

test_that("metadata is preserved and checked against the shared schema", {
  example <- jsonlite::fromJSON(metadata_example, simplifyVector = FALSE)
  encode <- function(meta) jsonlite::toJSON(meta, auto_unbox = TRUE, null = "null")
  expect_equal(read_test_metadata(encode(example)), example)

  for (field in names(example)) {
    missing <- example
    missing[[field]] <- NULL
    expect_error(read_test_metadata(encode(missing)))
    for (value in list("", 1, TRUE, NULL, list("value"))) {
      invalid <- example
      invalid[field] <- list(value)
      expect_error(read_test_metadata(encode(invalid)))
    }
  }
  expect_error(read_test_metadata(encode(c(example, list(extra = "value")))))
  for (json in c("[]", "null", '"text"', "{broken")) {
    expect_error(read_test_metadata(json))
  }
  for (field in c("code", "name", "fips", "dataDir", "sourceUrl")) {
    invalid <- example
    invalid[[field]] <- "invalid value"
    expect_error(read_test_metadata(encode(invalid)))
  }
  # A one-item JSON array must not become a valid scalar during R parsing.
  invalid <- example
  invalid$code <- list("aa")
  expect_error(read_test_metadata(encode(invalid)))
})

test_that("metadata keeps whitespace and cross-field checks", {
  meta <- jsonlite::fromJSON(metadata_example)
  for (value in c(" ", " Example State", "Example State ")) {
    meta$fullName <- value
    expect_error(read_test_metadata(jsonlite::toJSON(meta, auto_unbox = TRUE)), "trimmed strings")
  }
  meta$fullName <- "Example State"
  meta$name <- "BB"
  expect_error(read_test_metadata(jsonlite::toJSON(meta, auto_unbox = TRUE)), "metadata identity")
})

test_that("new constraints in the schema are honored without R field rules", {
  schema <- jsonlite::fromJSON(metadata_schema, simplifyVector = FALSE)
  schema$properties$sourceLabel$const <- "Required provider"
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  jsonlite::write_json(schema, path, auto_unbox = TRUE)
  expect_error(read_test_metadata(readLines(metadata_example), path))
  meta <- jsonlite::fromJSON(metadata_example)
  meta$sourceLabel <- "Required provider"
  expect_equal(read_test_metadata(jsonlite::toJSON(meta, auto_unbox = TRUE), path), meta)
})

test_that("missing metadata is rejected before validation", {
  previous <- Sys.getenv("META_PATH", unset = NA_character_)
  on.exit(if (is.na(previous)) Sys.unsetenv("META_PATH") else Sys.setenv(META_PATH = previous))
  for (path in c("", tempfile())) {
    Sys.setenv(META_PATH = path)
    expect_error(read_state_metadata(metadata_schema), "META_PATH must name")
  }
})
