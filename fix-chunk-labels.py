#!/usr/bin/env python3
"""Convert inline R chunk labels to #| label: syntax in Quarto .qmd files.

Converts:  ```{r chunk-name}
To:        ```{r}
           #| label: chunk-name

Chunks without inline labels (```{r}) are left unchanged.

Usage:
    python3 fix-chunk-labels.py <file.qmd>
"""

import re
import sys


def replace_label(m):
    label = m.group(1)
    return "```{r}\n#| label: " + label


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 fix-chunk-labels.py <file.qmd>", file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]
    with open(filepath, "r") as f:
        content = f.read()

    new_content = re.sub(
        r"```\{r ([a-zA-Z][a-zA-Z0-9_-]*)\}", replace_label, content
    )

    n_replaced = content != new_content
    if not n_replaced:
        print(f"No inline chunk labels found in {filepath}")
        return

    # Count replacements
    count = len(re.findall(r"```\{r ([a-zA-Z][a-zA-Z0-9_-]*)\}", content))

    with open(filepath, "w") as f:
        f.write(new_content)

    print(f"Converted {count} inline chunk label(s) in {filepath}")


if __name__ == "__main__":
    main()
