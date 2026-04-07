# Skills for R/bioinformatics-oriented quarto documents

# This is a work in progress; use at your own risk.

Bioinformatics Quarto document authoring, review, and repair. 

Triggers when working on .qmd files involving single-cell RNA-seq, differential expression, gene set enrichment, or other bioinformatics analyses. 

Also user-invocable at the Claude Code command promp e.g.
```
❯ /quarto-bioinfo @some_doc.qmd
```

Covers plot and table readability, literature citations for methods, 
R coding conventions and preferred package uses, and and general 
Quarto formatting for bioinformatics reports.

`check-figure-sizes.R` tries to reivew figures for legibility, incluidng text size.
It is not always successful.

`check-html-warnings.R` reviews the rendered HTML for warnings generated during
rendering and reports them to Claude for correction.
