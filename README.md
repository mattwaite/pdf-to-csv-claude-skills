# pdf-to-csv Claude Code Skills

A set of [Claude Code](https://claude.ai/code) skills for extracting structured data from government roster PDFs and converting them to CSV.

Extracted from a series of Nebraska DHHS licensure roster projects, but designed to work with any government PDF roster that follows common conventions: multi-line records identified by location headers, repeating page structure, and consistent field layouts.

## Skills

| Skill | What it does |
|-------|-------------|
| `/pdf-to-csv-analyze` | Inspects a PDF, identifies record structure, recommends a parsing strategy |
| `/pdf-to-csv-scaffold` | Creates standard project boilerplate (directories, requirements.txt, README, CLAUDE.md, LICENSE, GitHub Actions) |
| `/pdf-to-csv-parse` | Writes the Python extraction script based on the analysis |
| `/pdf-to-csv-validate` | Writes a pytest test suite for data quality, fill rates, and format validation |

## Installation

```bash
git clone https://github.com/mattwaite/pdf-to-csv-claude-skills.git
cd pdf-to-csv-claude-skills
bash install.sh
```

This copies the skill folders to `~/.claude/skills/`. Restart Claude Code and the skills will be available in any project.

To scope skills to a single project instead of globally, copy the `skills/` subfolders into your project's `.claude/skills/` directory.

## Workflow

### Starting a new project

```
/pdf-to-csv-analyze https://example.gov/docs/SomeRoster.pdf
```

This inspects the PDF and produces a structured analysis: record identification pattern, fields list, parsing strategy, page structure, and sample records.

```
/pdf-to-csv-scaffold my-project-name https://example.gov/docs/SomeRoster.pdf
```

Creates the project directory with standard structure, configuration files, and a GitHub Actions workflow for automated updates.

```
/pdf-to-csv-parse my-project-name
```

Writes the Python extraction script (`parse_{slug}.py`) based on the analysis from the previous step. Keep the analyze output in context when running this.

```
/pdf-to-csv-validate my-project-name
```

Writes the pytest test suite after the parser is working.

### Full example

```
/pdf-to-csv-analyze https://dhhs.ne.gov/licensure/Documents/ALF%20Roster.pdf
/pdf-to-csv-scaffold dhhs-assisted-living https://dhhs.ne.gov/licensure/Documents/ALF%20Roster.pdf
/pdf-to-csv-parse dhhs-assisted-living
/pdf-to-csv-validate dhhs-assisted-living
```

## What kinds of PDFs work well

These skills work best with government roster/directory PDFs that have:

- Repeating multi-line records (one entry per facility, provider, or licensee)
- A consistent header pattern per record (often `TOWN (COUNTY) - ZIP  LICENSE_TYPE`)
- Page headers and footers that repeat on each page
- A total count footer somewhere in the document

They support two parsing strategies, chosen automatically based on PDF structure:

- **Line-by-line text** — for PDFs where `extract_text()` produces records in reading order
- **Word-position (x/y coordinates)** — for PDFs with multi-column layouts that scramble text extraction

## Dependencies

Generated projects use:

- [pdfplumber](https://github.com/jsvine/pdfplumber) — PDF text and word extraction
- [requests](https://docs.python-requests.org/) — PDF download
- [pytest](https://pytest.org/) — test suite

## Background

These skills were extracted from a set of Nebraska DHHS licensure data projects. If you're working with Nebraska DHHS PDFs specifically, the patterns here are calibrated to that format. See the original projects for reference implementations.

## License

MIT
