---
name: quarto-bioinfo
description: >
  Bioinformatics Quarto document authoring, review, and repair. Triggers when
  working on .qmd files involving single-cell RNA-seq, differential expression,
  gene set enrichment, or other bioinformatics analyses. Covers plot readability,
  method citations, R coding conventions, and Quarto formatting for
  bioinformatics reports.
user_invocable: true
---

# Bioinformatics Quarto Authoring Skill

When this skill is active, also load these companion skills for general Quarto guidance:

- `quarto:quarto-authoring` — document structure, cross-references, code cells
- `quarto:quarto-alt-text` — accessible alt text for figures

## R Coding Rules

- Always use `dplyr::filter()` (never bare `filter()`) to avoid `stats::filter()` conflicts.
- Use `here::here(<path relative to project root>)` for all file paths, because Quarto renders in the directory containing the `.qmd` file.
- Use namespace-qualified calls for functions that have common name collisions (e.g. `dplyr::select()`, `dplyr::rename()`).
- **Suppress diagnostic output from `gc()`**: `gc()` returns a matrix of memory
  statistics and prints it to the console. Always wrap in `invisible(gc())` to
  keep rendered output clean.

## Quarto YAML Header

Every bioinformatics `.qmd` must use this YAML structure:

```yaml
---
title: "Document Title"
subtitle: "Source: `path/to/file.qmd`"
author: "Steve Rozen (sr110@duke.edu, steverozen@pm.me)"
date: last-modified
date-format: "YYYY-MM-DD HH:mm"
format:
  html:
    page-layout: full
    include-in-header:
      text: |
        <style>
          .quarto-container, .page-columns, .main-container {
            max-width: 100% !important;
          }
        </style>
---
```

## Code Block Labels

Never use `` ```{r label-text} ``. Always use:

````markdown
```{r}
#| label: label-text
```
````

To bulk-convert existing inline labels, run:

```bash
python3 ~/.claude/skills/quarto-bioinfo/fix-chunk-labels.py <file.qmd>
```

## Dynamic Values

Never hard-code computed values as fixed text. Always use inline R expressions (`` `r ...` ``) or dynamically generated tables so values update when data changes.

## Plotly Sizing

Specify `height` and `width` in `plot_ly()` or `ggplotly()`, **not** in `layout()` (deprecated, produces warnings).

## Wide Content

Wrap wide content (plotly widgets, wide tables) in full-viewport divs:

```markdown
:::{.column-screen}
... wide content ...
:::
```

## Tables

- **Never use `cat()` + `table()` or `cat()` + `print()` to display tabular
  data.** These produce plain-text console output that looks poor in HTML.
  Instead, convert to a data frame and render with `knitr::kable()` or
  `DT::datatable()`. For cross-tabulations, use `as.data.frame.matrix()` on
  the `table()` result:
  ```r
  knitr::kable(as.data.frame.matrix(table(sce$condition, sce$donor_id)))
  ```
- **Row names handling**: Before displaying any table, check whether the row
  names are redundant with an existing column (e.g. row names like `NNAT...1`,
  `KIF26B...2` that duplicate a `gene` column — R's `make.unique()` suffixes
  are a strong signal of redundancy). Apply these rules:
  - **Redundant**: suppress with `rownames = FALSE` (`DT::datatable()`) or
    `row.names = FALSE` (`knitr::kable()`).
  - **Not redundant** (row names carry meaningful information not in any column):
    promote them to a proper column so they are filterable/sortable:
    ```r
    df <- tibble::rownames_to_column(df, var = "row_id")
    DT::datatable(df, rownames = FALSE, filter = "top")
    ```
- When a table contains gene symbols or gene IDs, make them clickable links (e.g. to NCBI Gene, Ensembl, or GeneCards).

## Gene Set Enrichment and Pathway Analysis

Use **clusterProfiler** and **enrichplot** for GSEA and pathway enrichment — not
manual fgsea + ggplot. clusterProfiler wraps fgsea internally and provides
publication-ready plotting via enrichplot, with correct semantics for dotplots,
ridgeplots, enrichment maps, and cnetplots.

### Preferred workflow

```r
library(clusterProfiler)
library(enrichplot)
library(msigdbr)

# Build gene set term-to-gene mapping for clusterProfiler
hallmark_t2g <- msigdbr(species = "Homo sapiens", collection = "H") |>
  dplyr::select(gs_name, gene_symbol)

# Create a named, sorted gene list (e.g. limma t-statistics)
gene_list <- setNames(de_results$t, de_results$gene)
gene_list <- sort(gene_list, decreasing = TRUE)

# Run GSEA via clusterProfiler (uses fgsea internally)
gsea_res <- clusterProfiler::GSEA(
  geneList = gene_list,
  TERM2GENE = hallmark_t2g,
  minGSSize = 15,
  maxGSSize = 500,
  pvalueCutoff = 1.0   # keep all for exploration
)

# Dotplot (enrichplot)
enrichplot::dotplot(gsea_res, showCategory = 15, title = "GSEA: Hallmark")

# Ridgeplot
enrichplot::ridgeplot(gsea_res, showCategory = 15)

# Running-score plot for a specific pathway
enrichplot::gseaplot2(gsea_res, geneSetID = "HALLMARK_E2F_TARGETS")
```

### Why not raw fgsea + ggplot?

- **enrichplot::dotplot()** handles label wrapping, NES coloring, gene-ratio
  sizing, and faceting correctly out of the box. Hand-rolled ggplot dotplots
  often have sizing, labeling, or faceting issues.
- **clusterProfiler::GSEA()** returns a proper `gseaResult` S4 object that
  enrichplot functions know how to render, with correct column names and
  metadata. Raw fgsea returns a plain data frame that requires manual
  wrangling for every plot type.
- enrichplot also provides `cnetplot()`, `emapplot()`, `treeplot()`, and
  `heatplot()` — none of which have simple ggplot equivalents.

### Per-cell-type GSEA

When running GSEA across multiple cell types, loop and collect:

```r
gsea_list <- lapply(names(de_results_list), function(ct) {
  gene_list <- setNames(de_results_list[[ct]]$t, de_results_list[[ct]]$gene)
  gene_list <- sort(gene_list, decreasing = TRUE)
  res <- clusterProfiler::GSEA(
    geneList = gene_list, TERM2GENE = hallmark_t2g,
    minGSSize = 15, maxGSSize = 500, pvalueCutoff = 1.0
  )
  res@result$cell_type <- ct
  res
})
```

Use `enrichplot::dotplot()` on individual results, or bind `res@result`
data frames for a combined faceted view.

## Session Info

End every document with:

````markdown
::: {.callout-note collapse="true"}
## Session Info

```{r}
#| label: session-info
#| echo: false
#| comment: ""
sessioninfo::session_info(info = "all")
```

:::
````

## Plot Text Sizing Rules

All text in ggplot figures must scale from `base_size` so that readability
can be verified from a single number.

0. **Always name to global variable for base size `base_size`**

1. **Set `base_size` once** — either per-document via `theme_set(theme_bw(base_size = 14))`
   or per-plot via `+ theme_bw(base_size = 14)`.

2. **Never use absolute `size = N` in `element_text()`** — always use `rel()`:
   ```r
   theme(
     strip.text.y.left = element_text(angle = 0, size = rel(0.65)),
     strip.text.x      = element_text(size = rel(0.7)),
     axis.text.x        = element_text(angle = 45, hjust = 1, size = rel(0.6))
   )
   ```
   This ensures every text element stays proportional to `base_size`.

3. **If a plot needs to be wider than the page, increase `base_size`** to
   compensate for browser downscaling, rather than setting individual absolute
   sizes.

4. **`geom_text()` / `geom_text_repel()` size must scale with `base_size`.**
   These geoms use a `size` parameter in **mm** (not pt), and by default it
   does NOT scale with the theme's `base_size`. To make it scale, express
   size as a fraction of `base_size` converted to mm:
   ```r
   geom_text_repel(
     ...,
     size = cex * base_size / ggplot2::.pt
   )
   ```
   `ggplot2::.pt` (≈ 2.845) converts pt → mm. This way the text scales
   with `base_size` and the effective-size calculation from rule #3 applies
   uniformly. **Never use a raw numeric `size`** (e.g. `size = 3`) in
   `geom_text` / `geom_text_repel` / `geom_label`.

   **Choosing `cex`**: The `cex` value must account for browser downscaling.
   For a figure wider than the display, the effective rendered size is:
   ```
   effective_pt = cex × base_size × min(1, display_width / fig_width)
   ```
   So for `fig-width: 16` displayed at 10 inches (scale = 0.625):
   - `cex = 0.5` → 0.5 × 14 × 0.625 = **4.4 pt** — too small
   - `cex = 0.7` → 0.7 × 14 × 0.625 = **6.1 pt** — minimum acceptable
   - `cex = 0.9` → 0.9 × 14 × 0.625 = **7.9 pt** — good

   Rule of thumb: for wide figures, use `cex ≈ 1 / scale_factor × 0.5`
   to get ~7 pt effective. For `fig-width ≤ 10` (no scaling), `cex = 0.5`
   is fine.

### Effective text size calculation

When the browser renders a figure, it may shrink it to fit the page width
(typically ~10 inches). The effective rendered text size is:

```
scale_factor   = min(1, display_width / fig_width)
effective_size = base_size × scale_factor
```

The minimum acceptable `effective_size` is **6 pt**. For example:
- `base_size = 14`, `fig-width: 16` → 14 × (10/16) = **8.75 pt** ✓
- `base_size = 14`, `fig-width: 24` → 14 × (10/24) = **5.8 pt** ✗ — increase `base_size` to 15+
- `base_size = 11`, `fig-width: 16` → 11 × (10/16) = **6.9 pt** ✓ (barely)

### rel() values compound with scale factor

When `rel()` is used inside `element_text()`, the effective rendered size compounds
the base_size, scale factor, and rel value:

```
effective_rel_size = base_size × scale_factor × rel_value
min_rel = min_pt / (base_size × scale_factor)
```

Examples for min_pt = 6:
- fig-width: 10, base_size: 14 → scale = 1.0, min_rel = 0.43
- fig-width: 16, base_size: 14 → scale = 0.625, min_rel = 0.69
- fig-width: 16, base_size: 11 → scale = 0.625, min_rel = 0.87

A `rel(0.6)` that looks fine at `fig-width: 10` can produce unreadably small
text at `fig-width: 16`. The checker now validates these compounded sizes.

### Automated check script

After authoring or modifying a `.qmd`, run the figure-size checker:

```bash
Rscript ~/.claude/skills/quarto-bioinfo/check-figure-sizes.R <file.qmd>
```

The script parses every plot chunk, calculates effective text sizes, flags
absolute `element_text(size = N)` usage, and warns about faceted plots that
need manual panel-count review. Fix all warnings before rendering.

## Plot Readability

1. **Pathway enrichment dotplots / barplots** — Plots with long pathway names
   on the y-axis (GSEA, clusterProfiler, enrichR, etc.) need full figure width
   for the labels. Use `facet_wrap(~cell_type, scales = "free_y", ncol = 1)`
   to stack panels vertically (one per row), never side by side. Use a tall
   figure (e.g. `fig-width: 10`, `fig-height: 14` for 3 panels).

2. **Dense faceted plots** — If a `facet_grid()` or `facet_wrap()` produces
   more than ~15 panels, the individual panels become too small to see the
   data (no font-size increase fixes this). **Split the plot** into groups
   of 5–7 items per figure.

   **Pattern for splitting a gene × cell-type violin grid:**

   ```r
   genes_per_plot <- 6
   gene_groups <- split(
     unique(expr_long$gene),
     ceiling(seq_along(unique(expr_long$gene)) / genes_per_plot)
   )

   for (i in seq_along(gene_groups)) {
     p <- expr_long |>
       dplyr::filter(gene %in% gene_groups[[i]]) |>
       ggplot(aes(condition, expression, fill = condition)) +
       geom_violin(scale = "width", alpha = 0.7, linewidth = 0.3) +
       scale_fill_manual(values = condition_colors) +
       facet_grid(gene ~ cell_type, scales = "free_y", switch = "y") +
       theme(
         strip.placement = "outside",
         strip.text.y.left = element_text(angle = 0, size = rel(0.65)),
         strip.text.x = element_text(size = rel(0.7)),
         axis.text.x = element_text(angle = 45, hjust = 1, size = rel(0.6))
       ) +
       labs(
         title = paste0("VPA-response genes (group ", i, " of ", length(gene_groups), ")"),
         x = NULL, y = "log1p expression", fill = "Condition"
       )
     print(p)
   }
   ```

3. **Facet strip labels** — In `facet_grid(row_var ~ col_var)`, place row
   strip labels on the left:
   ```r
   facet_grid(gene ~ cell_type, scales = "free_y", switch = "y") +
     theme(strip.placement = "outside")
   ```

4. **Max 2 plots per row** — When arranging multiple plots with `wrap_plots()`,
   `plot_grid()`, or patchwork `+` / `|` operators, never put more than 2
   plots side by side (`ncol <= 2`). Wide multi-plot rows shrink each panel
   too much for labels and annotations to remain readable. Prefer taller
   figures with more rows instead.

   ```r
   # Bad — 5 plots squeezed into one row:
   wrap_plots(plot_list, nrow = 1)

   # Good — at most 2 per row, tall figure:
   wrap_plots(plot_list, ncol = 2)
   ```

   When switching from a single wide row to `ncol = 2`, also adjust the
   chunk's `fig-width` and `fig-height` accordingly (e.g. `fig-width: 10`,
   `fig-height: 15` for 5 plots in a 3 × 2 grid).

5. **Color accessibility** — Use colorblind-friendly palettes. Never use
   red-and-green together in heatmaps or color scales (indistinguishable for
   red-green colorblind viewers). Prefer diverging palettes like `RdBu`
   (red–blue) or `PuOr` (purple–orange), and sequential palettes from
   viridis. Check that all fill/color encodings are distinguishable.

## Bioinformatics Method References

Every bioinformatics report should include a **References** section citing the methods and tools used. For each reference provide: author(s), year, title, and a verified web link.

**Before including any link, fetch it and confirm it resolves to the correct paper.** Prefer Internet Archive (`https://archive.org`) for book references.

### Common Methods and Key Papers

| Method / Tool | Key Reference |
|---|---|
| **limma** | Ritchie ME et al. (2015) "limma powers differential expression analyses for RNA-sequencing and microarray studies." *Nucleic Acids Res* 43(7):e47. https://doi.org/10.1093/nar/gkv007 |
| **voom** | Law CW et al. (2014) "voom: precision weights unlock linear model analysis tools for RNA-seq read counts." *Genome Biol* 15:R29. https://doi.org/10.1186/gb-2014-15-2-r29 |
| **edgeR** | Robinson MD, McCarthy DJ, Smyth GK (2010) "edgeR: a Bioconductor package for differential expression analysis of digital gene expression data." *Bioinformatics* 26(1):139–140. https://doi.org/10.1093/bioinformatics/btp616 |
| **DESeq2** | Love MI, Huber W, Anders S (2014) "Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2." *Genome Biol* 15:550. https://doi.org/10.1186/s13059-014-0550-8 |
| **fgsea** | Korotkevich G et al. (2021) "Fast gene set enrichment analysis." *bioRxiv*. https://doi.org/10.1101/060012 |
| **Seurat** | Hao Y et al. (2024) "Dictionary learning for integrative, multimodal and scalable single-cell analysis." *Nat Biotechnol* 42:293–304. https://doi.org/10.1038/s41587-023-01767-y |
| **UMAP** | McInnes L, Healy J, Melville J (2018) "UMAP: Uniform Manifold Approximation and Projection for Dimension Reduction." *arXiv:1802.03426*. https://doi.org/10.48550/arXiv.1802.03426 |
| **Pseudobulk DE** | Squair JW et al. (2021) "Confronting false discoveries in single-cell differential expression." *Nat Commun* 12:5692. https://doi.org/10.1038/s41467-021-25960-2 |
| **MSigDB** | Liberzon A et al. (2015) "The Molecular Signatures Database Hallmark Gene Set Collection." *Cell Syst* 1(6):417–425. https://doi.org/10.1016/j.cels.2015.12.004 |
| **SingleCellExperiment** | Amezquita RA et al. (2020) "Orchestrating single-cell analysis with Bioconductor." *Nat Methods* 17:137–145. https://doi.org/10.1038/s41592-019-0654-x |
| **scran** | Lun ATL, McCarthy DJ, Marioni JC (2016) "A step-by-step workflow for low-level analysis of single-cell RNA-seq data with Bioconductor." *F1000Research* 5:2122. https://doi.org/10.12688/f1000research.9501.2 |
| **clusterProfiler** | Wu T et al. (2021) "clusterProfiler 4.0: A universal enrichment tool for interpreting omics data." *Innovation* 2(3):100141. https://doi.org/10.1016/j.xinn.2021.100141 |

When writing the References section:

1. Scan the `.qmd` for all bioinformatics packages and methods used.
2. Match each to its canonical citation from the table above (or find the correct one if not listed).
3. Fetch each DOI/URL to verify it resolves correctly.
4. Format as a markdown list or table at the end of the document, before the Session Info section.

## Post-render HTML Inspection

After rendering, run the HTML warning checker:

```bash
Rscript ~/.claude/skills/quarto-bioinfo/check-html-warnings.R <file.html>
```

This script finds all `cell-output-stderr` blocks in the rendered HTML —
the only reliable way to detect R warnings and messages. **Do NOT grep the
raw HTML for "Warning"** — this produces false positives from CSS variables
(`--bs-warning`), JavaScript libraries, and Bootstrap theming that are
impossible to filter reliably.

The script classifies each issue:

- **WARNING** — An R `warning()` that leaked into the output. **Fix the root
  cause** (e.g. deprecated function arguments, type mismatches). Only suppress
  with `#| warning: false` if confirmed as a known false positive, and
  document why in a code comment.

- **PACKAGE_MESSAGE** — Package loading chatter (`Attaching package`,
  `Loading required package`, masked-object notices). Suppress with
  `#| message: false` in the chunk that loads the package.

- **STDERR** — Other stderr output. Investigate; may be a message, warning,
  or `cat(..., file = stderr())` call.

Fix all issues, re-render, and re-run the checker until clean. The goal is
zero `cell-output-stderr` blocks in the final HTML.

## Post-render figure inspection

Look at the figures and re-do or resize if text is too small or if there is superimposed text.

## Review Checklist

When reviewing or authoring a bioinformatics `.qmd`, verify:

- [ ] YAML header follows the template (author, date, page-layout, CSS)
- [ ] Code blocks use `#| label:` syntax (not inline labels)
- [ ] All computed values are dynamic (inline R or generated tables)
- [ ] `dplyr::filter()` used instead of bare `filter()`
- [ ] File paths use `here::here()`
- [ ] No `cat()` + `table()` or `cat()` + `print()` for tabular data (use `kable` or `DT`)
- [ ] Tables handle row names correctly (suppress if redundant with a column; promote to a filterable column if meaningful)
- [ ] Gene symbols/IDs are clickable links
- [ ] GSEA uses clusterProfiler::GSEA() + enrichplot (not raw fgsea + manual ggplot)
- [ ] No faceted plot has more than ~15 panels (split if needed)
- [ ] Multi-plot layouts have at most 2 plots per row (`ncol <= 2`; run `check-figure-sizes.R` to verify)
- [ ] `gc()` calls wrapped in `invisible()` to suppress diagnostic output
- [ ] All `element_text(size = ...)` uses `rel()`, never absolute values
- [ ] Effective base_size ≥ 6 pt and all `rel()` elements ≥ 6 pt effective (run `check-figure-sizes.R` to verify)
- [ ] Facet strip labels placed correctly (`switch = "y"`, `strip.placement = "outside"`)
- [ ] Plotly sizing in `plot_ly()`/`ggplotly()`, not `layout()`
- [ ] Wide content wrapped in `:::{.column-screen}`
- [ ] References section cites all methods used, with verified links
- [ ] Session Info is the last section (collapsible callout)
- [ ] No warnings or stray messages in rendered HTML (run `check-html-warnings.R` to verify)
- [ ] Text in figures is big enough and there is no superimposed text in figures
- [ ] No red-green color combinations in heatmaps or color scales (use `RdBu`, `PuOr`, or viridis)
- [ ] Alt text provided for key figures (invoke `quarto:quarto-alt-text`)
