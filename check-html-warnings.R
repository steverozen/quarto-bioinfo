#!/usr/bin/env Rscript
#
# check-html-warnings.R — Check rendered Quarto HTML for R warnings/messages
#
# Parses the rendered HTML file and extracts all R stderr output that leaked
# into the document. In Quarto/knitr output, R warnings and messages appear
# inside <div class="cell-output cell-output-stderr"> blocks. This script
# finds all such blocks and reports their contents.
#
# This is more reliable than grepping for "Warning" in the raw HTML, which
# produces false positives from CSS variables (--bs-warning), JavaScript
# libraries, and Bootstrap theming.
#
# Usage:
#   Rscript check-html-warnings.R <file.html>
#

library(argparser)

p <- arg_parser("Check rendered Quarto HTML for R warnings and messages")
p <- add_argument(p, "html_file", help = "Path to rendered .html file")
args <- parse_args(p)

if (!file.exists(args$html_file)) {
  stop("File not found: ", args$html_file)
}

html <- readLines(args$html_file, warn = FALSE)
html_text <- paste(html, collapse = "\n")

issues <- list()

# --- Find all cell-output-stderr blocks ---
# Quarto/knitr wraps R stderr output (warnings, messages, package chatter) in:
#   <div class="cell-output cell-output-stderr">
#   <pre><code>...</code></pre>
#   </div>
#
# This is the ONLY reliable way to find R warnings in rendered HTML.
# Searching for bare "Warning" text produces false positives from CSS/JS.

stderr_pattern <- '(?s)<div class="cell-output cell-output-stderr">\\s*<pre><code>(.*?)</code></pre>'
stderr_matches <- gregexpr(stderr_pattern, html_text, perl = TRUE)
stderr_texts <- regmatches(html_text, stderr_matches)[[1]]

if (length(stderr_texts) > 0) {
  for (st in stderr_texts) {
    # Extract the text content between <pre><code>...</code></pre>
    content <- sub(
      '(?s).*<pre><code>(.*?)</code></pre>.*', '\\1', st, perl = TRUE
    )
    # Unescape HTML entities
    content <- gsub("&lt;", "<", content)
    content <- gsub("&gt;", ">", content)
    content <- gsub("&amp;", "&", content)
    content <- gsub("&#39;", "'", content)
    content <- gsub("&quot;", '"', content)
    content <- trimws(content)

    # Classify the issue
    if (grepl("^Warning", content)) {
      issue_type <- "WARNING"
    } else if (grepl("Attaching package|Loading required|masked from|Registered S3",
                      content)) {
      issue_type <- "PACKAGE_MESSAGE"
    } else {
      issue_type <- "STDERR"
    }

    # Truncate for display
    display <- substr(content, 1, 300)
    if (nchar(content) > 300) display <- paste0(display, "...")

    issues[[length(issues) + 1]] <- list(
      type = issue_type,
      text = display
    )
  }
}

# --- Report ---
cat(sprintf("File: %s\n", args$html_file))
cat(strrep("=", 70), "\n\n")

if (length(issues) == 0) {
  cat("No warnings, messages, or stderr output found in rendered HTML.\n")
} else {
  cat(sprintf("Found %d issue(s):\n\n", length(issues)))
  for (i in seq_along(issues)) {
    iss <- issues[[i]]
    cat(sprintf("[%s] %s\n\n", iss$type, iss$text))
  }

  cat(strrep("-", 70), "\n")
  cat("How to fix:\n")
  cat("  WARNING        — Fix the root cause in R code (e.g. deprecated args,\n")
  cat("                   type mismatches). Only suppress with #| warning: false\n")
  cat("                   if confirmed as a known false positive, and document why.\n")
  cat("  PACKAGE_MESSAGE — Add #| message: false to the chunk loading the package.\n")
  cat("  STDERR         — Investigate; may be a message, warning, or cat() to stderr.\n")
}
