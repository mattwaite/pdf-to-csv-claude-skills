---
name: pdf-to-csv-scaffold
description: Create standard project boilerplate for a new PDF-to-CSV extraction project. Use after /pdf-to-csv-analyze, before /pdf-to-csv-parse.
argument-hint: [project-name] [pdf-url]
---

# PDF-to-CSV Project Scaffold

Set up the standard directory structure and boilerplate files for a new PDF-to-CSV project.

**Arguments:** `$ARGUMENTS`
- Argument 1: project directory name (e.g., `dhhs-nursing-homes`)
- Argument 2: PDF download URL

If arguments are missing, ask the user before proceeding.

Derive a short slug from the project name for use in filenames (e.g., `dhhs-nursing-homes` → `nursing_homes`, `dhhs-rural-health-clinics` → `rhc_roster`). Ask the user to confirm the slug.

---

## Directory Structure to Create

```
{project-name}/
├── parse_{slug}.py          # Main script — created by /pdf-to-csv-parse
├── test_parse_{slug}.py     # Tests — created by /pdf-to-csv-validate
├── requirements.txt
├── README.md
├── CLAUDE.md
├── LICENSE
├── .gitignore
├── data/
│   └── .gitkeep
└── pdfs/
    └── .gitkeep
```

Note: some projects use `pdf/` (singular) instead of `pdfs/`. Use `pdfs/` for consistency.

---

## File Contents

### requirements.txt
```
pdfplumber
requests
pytest
```

### .gitignore
```
# Data outputs (committed selectively or not at all)
*.csv
*.pdf

# Python
__pycache__/
*.pyc
*.pyo
.pytest_cache/
*.egg-info/
dist/
build/
.venv/
venv/
```

Do NOT gitignore `data/` or `pdfs/` directories themselves. The `.gitkeep` files ensure they exist.

### README.md

```markdown
# {Project Title}

Extracts Nebraska DHHS {facility type} roster data from the monthly PDF and converts it to a structured CSV.

**Source:** {PDF URL}
**Published by:** Nebraska DHHS Division of Public Health – Licensure Unit
**Update frequency:** [Monthly / Quarterly / As needed]

## Usage

```bash
pip install -r requirements.txt
python parse_{slug}.py
```

The script downloads the current PDF, extracts all records, and writes output to `data/{slug}_{YYYY-MM-DD}.csv`.

## Output Fields

| Field | Description |
|-------|-------------|
| [fill in after /pdf-to-csv-parse] | |

## Testing

```bash
pytest test_parse_{slug}.py -v
```

## Data Archive

Downloaded PDFs are saved to `pdfs/` and CSVs to `data/`, both with date stamps.
```

### CLAUDE.md

```markdown
# {Project Title}

## Purpose
Extract Nebraska DHHS {facility type} roster data from PDF to structured CSV.

## Source PDF
URL: {PDF URL}
Downloaded to: `pdfs/{Slug}_{YYYY-MM-DD}.pdf`

## Running
```bash
python parse_{slug}.py
```

## Testing
```bash
pytest test_parse_{slug}.py -v
```

## Output
CSV written to: `data/{slug}_{YYYY-MM-DD}.csv`

## Key Implementation Notes
- [Leave a placeholder: "Parsing strategy: TBD — see /pdf-to-csv-analyze output"]
- [Leave a placeholder: "Fields: TBD — see /pdf-to-csv-parse"]
```

Update CLAUDE.md after /pdf-to-csv-parse adds implementation notes.

### LICENSE

Use MIT License:

```
MIT License

Copyright (c) {current year} {ask user for name, or leave as "[Your Name]"}

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### .github/workflows/update-roster.yml

Ask the user: "What schedule should the GitHub Actions workflow run on? (Monthly on the 15th is standard for DHHS rosters. Some are quarterly — January, April, July, October.)"

```yaml
name: Update {Project Title}

on:
  schedule:
    # [Monthly: 15th at noon UTC / Quarterly: 15th of Jan/Apr/Jul/Oct]
    - cron: '{CRON_EXPRESSION}'
  workflow_dispatch:

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Run parser
        run: python parse_{slug}.py

      - name: Commit updated data
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add data/ pdfs/
          git diff --staged --quiet || git commit -m "Update {slug} roster $(date +%Y-%m-%d)"
          git push
```

Common cron expressions:
- Monthly on 15th at noon UTC: `0 12 15 * *`
- Monthly on 16th at 9 AM UTC: `0 9 16 * *`
- Quarterly (Jan/Apr/Jul/Oct, 15th): `0 12 15 1,4,7,10 *`

---

## After Creating Files

Report the tree structure created, then prompt:

> Files created. Next steps:
> 1. Run `/pdf-to-csv-parse` to write the extraction script (keep your `/pdf-to-csv-analyze` output in context)
> 2. Run `/pdf-to-csv-validate` after the parser is working to add the test suite
