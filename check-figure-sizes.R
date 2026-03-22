#!/usr/bin/env Rscript
#
# check-figure-sizes.R — Analyze a .qmd file for figure readability issues
#
# Parses code chunks to extract fig-width, fig-height, theme base_size,
# and facet structure. Calculates effective rendered text size assuming
# the browser displays the figure at a given page width (default 10 inches).
#
# Usage:
#   Rscript check-figure-sizes.R <file.qmd> [display_width_inches] [min_pt]
#
# Arguments:
#   file.qmd              Path to the .qmd file to check
#   display_width_inches  Assumed browser display width in inches (default: 10)
#   min_pt                Minimum acceptable effective text size in pt (default: 6)

library(argparser)

p <- arg_parser("Check figure text sizes in a Quarto .qmd file")
p <- add_argument(p, "qmd_file", help = "Path to .qmd file")
p <- add_argument(p, "--display-width", default = 10,
                  help = "Assumed browser display width in inches")
p <- add_argument(p, "--min-pt", default = 6,
                  help = "Minimum acceptable effective text size in pt")
args <- parse_args(p)

lines <- readLines(args$qmd_file)

# --- Extract code chunks with their options ---
# Find chunk starts: ```{r}
chunk_starts <- grep("^```\\{r", lines)
chunk_ends   <- integer(length(chunk_starts))

for (i in seq_along(chunk_starts)) {
  # Find the closing ``` after this chunk start
  candidates <- grep("^```\\s*$", lines)
  candidates <- candidates[candidates > chunk_starts[i]]
  if (length(candidates) > 0) {
    chunk_ends[i] <- candidates[1]
  } else {
    chunk_ends[i] <- length(lines)
  }
}

# --- Parse each chunk ---
results <- list()

for (i in seq_along(chunk_starts)) {
  start <- chunk_starts[i]
  end   <- chunk_ends[i]
  chunk_lines <- lines[start:end]
  chunk_code  <- paste(chunk_lines, collapse = "\n")

  # Extract label
  label_match <- regmatches(chunk_code,
    regexpr("#\\|\\s*label:\\s*([^\\n]+)", chunk_code, perl = TRUE))
  label <- if (length(label_match) > 0) {
    sub("#\\|\\s*label:\\s*", "", label_match)
  } else {
    paste0("chunk-line-", start)
  }

  # Extract fig-width and fig-height from #| options
  fw_match <- regmatches(chunk_code,
    regexpr("#\\|\\s*fig-width:\\s*([0-9.]+)", chunk_code, perl = TRUE))
  fh_match <- regmatches(chunk_code,
    regexpr("#\\|\\s*fig-height:\\s*([0-9.]+)", chunk_code, perl = TRUE))

  fig_width  <- if (length(fw_match) > 0) {
    as.numeric(sub("#\\|\\s*fig-width:\\s*", "", fw_match))
  } else {
    7  # knitr default
  }

  fig_height <- if (length(fh_match) > 0) {
    as.numeric(sub("#\\|\\s*fig-height:\\s*", "", fh_match))
  } else {
    5  # knitr default
  }

  # Extract base_size from theme_*() calls
  base_match <- regmatches(chunk_code,
    regexpr("theme_\\w+\\(\\s*base_size\\s*=\\s*([0-9.]+)", chunk_code,
            perl = TRUE))
  base_size <- if (length(base_match) > 0) {
    as.numeric(sub(".*base_size\\s*=\\s*", "", base_match))
  } else {
    NA  # Will use document-level default
  }

  # Check for absolute text sizes (element_text with size = <number>)
  abs_size_matches <- gregexpr(
    "element_text\\([^)]*size\\s*=\\s*([0-9.]+)", chunk_code, perl = TRUE)
  abs_sizes <- regmatches(chunk_code, abs_size_matches)[[1]]
  has_absolute_sizes <- length(abs_sizes) > 0
  absolute_size_values <- if (has_absolute_sizes) {
    as.numeric(sub(".*size\\s*=\\s*", "", abs_sizes))
  } else {
    numeric(0)
  }

  # Check for rel() usage (good)
  has_rel_sizes <- grepl("element_text\\([^)]*size\\s*=\\s*rel\\(", chunk_code,
                         perl = TRUE)

  # Check for geom_text / geom_text_repel / geom_label size parameters
  # Good: size = cex * base_size / ggplot2::.pt  (scales with base_size)
  # Bad:  size = 3  (raw numeric, won't scale)
  has_raw_geom_text_size <- FALSE
  geom_text_call_re <- "geom_(text|text_repel|label|label_repel)\\("
  if (grepl(geom_text_call_re, chunk_code, perl = TRUE)) {
    chunk_lines_vec <- strsplit(chunk_code, "\n")[[1]]
    in_geom_text <- FALSE
    paren_depth <- 0
    geom_text_block <- ""
    for (cl in chunk_lines_vec) {
      if (!in_geom_text && grepl(geom_text_call_re, cl, perl = TRUE)) {
        in_geom_text <- TRUE
        paren_depth <- 0
        geom_text_block <- ""
      }
      if (in_geom_text) {
        geom_text_block <- paste0(geom_text_block, cl)
        paren_depth <- paren_depth +
          nchar(gsub("[^(]", "", cl)) - nchar(gsub("[^)]", "", cl))
        if (paren_depth <= 0) {
          # Check if size = <bare number> (not involving base_size or .pt)
          has_size <- grepl(",\\s*size\\s*=", geom_text_block, perl = TRUE)
          uses_base_size <- grepl("size\\s*=.*base_size", geom_text_block,
                                  perl = TRUE)
          if (has_size && !uses_base_size) {
            has_raw_geom_text_size <- TRUE
          }
          in_geom_text <- FALSE
        }
      }
    }
  }

  # Detect faceting
  has_facet_grid <- grepl("facet_grid\\(", chunk_code)
  has_facet_wrap <- grepl("facet_wrap\\(", chunk_code)
  has_facets <- has_facet_grid || has_facet_wrap

  # Try to estimate facet panel count from the data context
  # This is heuristic — we look for ncol/nrow hints in facet_wrap
  facet_ncol <- NA
  facet_nrow <- NA
  if (has_facet_wrap) {
    ncol_match <- regmatches(chunk_code,
      regexpr("facet_wrap\\([^)]*ncol\\s*=\\s*([0-9]+)", chunk_code,
              perl = TRUE))
    nrow_match <- regmatches(chunk_code,
      regexpr("facet_wrap\\([^)]*nrow\\s*=\\s*([0-9]+)", chunk_code,
              perl = TRUE))
    if (length(ncol_match) > 0) {
      facet_ncol <- as.numeric(sub(".*ncol\\s*=\\s*", "", ncol_match))
    }
    if (length(nrow_match) > 0) {
      facet_nrow <- as.numeric(sub(".*nrow\\s*=\\s*", "", nrow_match))
    }
  }

  # For facet_grid, count the ~ formula variables (can't know levels without
  # running code, but flag it for review)
  facet_formula <- NA
  if (has_facet_grid) {
    fm <- regmatches(chunk_code,
      regexpr("facet_grid\\(([^)]+)\\)", chunk_code, perl = TRUE))
    if (length(fm) > 0) {
      facet_formula <- sub("facet_grid\\(\\s*", "", sub("\\s*\\)$", "", fm))
    }
  }

  # Only store chunks that have ggplot or plot_ly calls
  is_plot_chunk <- grepl("ggplot\\(|plot_ly\\(|geom_|wrap_plots\\(", chunk_code)

  if (is_plot_chunk) {
    results[[length(results) + 1]] <- list(
      label              = label,
      line               = start,
      fig_width          = fig_width,
      fig_height         = fig_height,
      base_size          = base_size,
      has_absolute_sizes = has_absolute_sizes,
      absolute_sizes     = absolute_size_values,
      has_rel_sizes          = has_rel_sizes,
      has_raw_geom_text_size = has_raw_geom_text_size,
      has_facets             = has_facets,
      facet_formula      = facet_formula,
      facet_ncol         = facet_ncol,
      facet_nrow         = facet_nrow
    )
  }
}

# --- Find document-level base_size ---
# Look for theme_set(theme_*(base_size = N)) outside of specific plot chunks
all_code <- paste(lines, collapse = "\n")
doc_base_match <- regmatches(all_code,
  regexpr("theme_set\\(\\s*theme_\\w+\\(\\s*base_size\\s*=\\s*([0-9.]+)",
          all_code, perl = TRUE))
doc_base_size <- if (length(doc_base_match) > 0) {
  as.numeric(sub(".*base_size\\s*=\\s*", "", doc_base_match))
} else {
  11  # ggplot2 default
}

# --- Report ---
display_width <- args$display_width
min_pt        <- args$min_pt
warnings_found <- 0

cat(sprintf("File: %s\n", args$qmd_file))
cat(sprintf("Document-level base_size: %g pt\n", doc_base_size))
cat(sprintf("Assumed display width: %g inches\n", display_width))
cat(sprintf("Minimum text size: %g pt\n", min_pt))
cat(strrep("=", 70), "\n\n")

for (r in results) {
  base <- if (!is.na(r$base_size)) r$base_size else doc_base_size

  # Effective scale factor: how much the figure shrinks on screen
  scale_factor <- min(1, display_width / r$fig_width)
  effective_base <- base * scale_factor

  # For absolute sizes, calculate their effective size too
  effective_abs <- r$absolute_sizes * scale_factor

  issues <- character(0)

  if (effective_base < min_pt) {
    issues <- c(issues, sprintf(
      "Effective base_size = %.1f pt (%.0f × %.2f) < %.0f pt minimum",
      effective_base, base, scale_factor, min_pt))
  }

  if (r$has_absolute_sizes) {
    issues <- c(issues, sprintf(
      "Uses absolute text sizes: %s pt (use rel() instead)",
      paste(r$absolute_sizes, collapse = ", ")))
    small_abs <- effective_abs[effective_abs < min_pt]
    if (length(small_abs) > 0) {
      issues <- c(issues, sprintf(
        "Absolute sizes render at: %s pt (below %.0f pt minimum)",
        paste(round(small_abs, 1), collapse = ", "), min_pt))
    }
  }

  # Check geom_text / geom_text_repel uses base_size-relative sizing
  if (r$has_raw_geom_text_size) {
    issues <- c(issues,
      "geom_text/repel uses raw size = N (use cex * base_size / ggplot2::.pt instead)")
  }

  if (r$has_facets && !is.na(r$facet_formula)) {
    # Flag facet_grid formulas with row ~ col for manual panel count review
    issues <- c(issues, sprintf(
      "facet_grid(%s) — verify panel count ≤ 15; if more, split the plot",
      r$facet_formula))
  }

  status <- if (length(issues) == 0) "OK" else "WARNING"

  cat(sprintf("[%s] %s (line %d)\n", status, r$label, r$line))
  cat(sprintf("  fig: %g × %g in | base_size: %g pt | effective: %.1f pt | scale: %.2f\n",
              r$fig_width, r$fig_height, base, effective_base, scale_factor))

  if (length(issues) > 0) {
    warnings_found <- warnings_found + length(issues)
    for (issue in issues) {
      cat(sprintf("  ⚠ %s\n", issue))
    }
  }
  cat("\n")
}

cat(strrep("=", 70), "\n")
if (warnings_found == 0) {
  cat("✓ No issues found.\n")
} else {
  cat(sprintf("Found %d issue(s) to review.\n", warnings_found))
}
