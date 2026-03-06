---
name: pdf-to-csv-parse
description: Write the Python PDF-to-CSV extraction script for a project. Use after /pdf-to-csv-analyze and /pdf-to-csv-scaffold. Requires the analysis output to be in context.
argument-hint: [project-directory]
---

# Write PDF-to-CSV Parser

Write `parse_{slug}.py` in the project directory `$ARGUMENTS` (or current directory if omitted).

**Prerequisite:** The `/pdf-to-csv-analyze` output must be in context. If it is not, run that skill first.

Read any existing files in the project directory before writing.

---

## Universal Script Skeleton

Every parser follows this outer structure:

```python
#!/usr/bin/env python3
"""
Extract {description} from PDF to CSV.
Source: {PDF URL or local path}
"""

import csv
import re
import sys
from datetime import date
from pathlib import Path

import pdfplumber
import requests  # omit if no download needed

PDF_URL = "{URL}"        # omit if local files only
PDF_DIR = Path("pdfs")
DATA_DIR = Path("data")


def download_pdf(url: str = PDF_URL) -> Path:
    """Download the current PDF and save with today's date stamp."""
    PDF_DIR.mkdir(exist_ok=True)
    date_str = date.today().strftime("%Y-%m-%d")
    dest = PDF_DIR / f"{slug}_{date_str}.pdf"
    if dest.exists():
        print(f"Already downloaded: {dest}")
        return dest
    print(f"Downloading {url} ...")
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    dest.write_bytes(r.content)
    print(f"Saved: {dest}")
    return dest


def extract_records(pdf_path: Path, **kwargs) -> list[dict]:
    """Extract all records from the PDF. Implementation depends on PDF type."""
    # See strategy sections below
    ...


def save_to_csv(records: list[dict], output_path: Path = None) -> Path:
    """Write records to a date-stamped CSV."""
    DATA_DIR.mkdir(exist_ok=True)
    if output_path is None:
        date_str = date.today().strftime("%Y-%m-%d")
        output_path = DATA_DIR / f"{slug}_{date_str}.csv"
    if not records:
        print("No records to write.")
        return output_path
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(records[0].keys()))
        writer.writeheader()
        writer.writerows(records)
    print(f"Wrote {len(records)} records to {output_path}")
    return output_path


def main():
    # Adjust based on whether PDF is downloaded or local
    pdf_path = download_pdf()           # if URL source
    # pdf_path = next(PDF_DIR.glob("*.pdf"), None)  # if local files
    date_str = date.today().strftime("%Y-%m-%d")
    records = extract_records(pdf_path, date_str=date_str)
    print(f"Extracted {len(records)} records")
    save_to_csv(records)


if __name__ == "__main__":
    main()
```

---

## Strategy A: Roster/Directory (Record-Header Based)

Use when each entity spans multiple lines identified by a consistent header pattern.

```python
SKIP_PAGES = 1          # cover/title pages to skip
HEADER_LINES = 6        # repeated header lines at top of each data page
TOTAL_MARKER = "Total " # text that marks end of records on a page

# Regex matching the first line of each record
# Adjust to match the actual pattern from your analysis.
# Common form: LOCATION (REGION) - ID  TYPE
RECORD_RE = re.compile(
    r'^([A-Z][A-Z\s\']+?)\s*\(([A-Z\s]+)\)\s*-\s*(\d{5})\s+(\S+)\s*(.*)$'
)


def extract_records(pdf_path: Path, date_str: str = None) -> list[dict]:
    records = []
    current = None

    with pdfplumber.open(pdf_path) as pdf:
        for page_num, page in enumerate(pdf.pages):
            if page_num < SKIP_PAGES:
                continue
            text = page.extract_text()
            if not text:
                continue
            lines = [l.strip() for l in text.split('\n')]
            for line_num, line in enumerate(lines):
                if not line:
                    continue
                if line_num < HEADER_LINES:
                    continue
                if line.startswith(TOTAL_MARKER):
                    break

                m = RECORD_RE.match(line)
                if m:
                    if current:
                        records.append(current)
                    current = _new_record(m, date_str)
                elif current is not None:
                    _parse_continuation(line, current)

        if current:
            records.append(current)

    return records


def _new_record(match, date_str) -> dict:
    """Initialize a record dict from the header regex match."""
    return {
        'location':       match.group(1).strip(),
        'region':         match.group(2).strip(),
        'id_code':        match.group(3),
        'record_type':    match.group(4),
        # ... add all fields from analysis, initialized to ''
        'date_parsed':    date_str or date.today().isoformat(),
    }


def _parse_continuation(line: str, record: dict) -> None:
    """Extract fields from continuation lines into record."""
    # Phone + FAX
    m = re.search(r'\((\d{3})\)\s*(\d{3}-\d{4})', line)
    if m and not record.get('phone'):
        record['phone'] = f"({m.group(1)}) {m.group(2)}"
        fax = re.search(r'FAX:?\s*\(?(\d{3})\)?\s*(\d{3}-\d{4})', line)
        if fax:
            record['fax'] = f"({fax.group(1)}) {fax.group(2)}"
        return

    # License/ID number pattern — adjust regex to match this document's format
    lic = re.search(r'\b([A-Z]{2,5}\d{3,6}|\d{6})\b', line)
    if lic and not record.get('license_number'):
        record['license_number'] = lic.group(1)

    # Fill remaining fields in order of appearance
    if not record.get('entity_name'):
        record['entity_name'] = line
    elif not record.get('address'):
        record['address'] = line
    elif not record.get('licensee'):
        record['licensee'] = line
    elif not record.get('administrator'):
        record['administrator'] = line
```

**Word-position variant** (when columns are side-by-side and scramble text order):

```python
def _group_into_lines(words: list, y_tol: float = 4.0) -> list[list]:
    lines = []
    if not words:
        return lines
    current_y, current = words[0]['top'], []
    for w in sorted(words, key=lambda w: (round(w['top'] / y_tol), w['x0'])):
        if abs(w['top'] - current_y) > y_tol:
            if current:
                lines.append(current)
            current, current_y = [w], w['top']
        else:
            current.append(w)
    if current:
        lines.append(current)
    return lines


def _col_text(words: list, x_min: float, x_max: float) -> str:
    return ' '.join(w['text'] for w in words if x_min <= w['x0'] < x_max).strip()


# Define column x-ranges from analysis:
COLS = {'col_a': (0, 200), 'col_b': (200, 400), 'col_c': (400, 600)}
```

---

## Strategy B: Formatted Table

Use when data is in rows and columns with a header row; pdfplumber can find tables.

```python
SKIP_PAGES = 0   # adjust

def extract_records(pdf_path: Path, date_str: str = None) -> list[dict]:
    records = []
    with pdfplumber.open(pdf_path) as pdf:
        for page_num, page in enumerate(pdf.pages):
            if page_num < SKIP_PAGES:
                continue
            tables = page.extract_tables()
            for table in tables:
                if not table:
                    continue
                # First table on first page may have the header row
                # Subsequent pages repeat the header — skip it
                for row in table:
                    if _is_header_row(row) or _is_skip_row(row):
                        continue
                    rec = _row_to_dict(row, date_str)
                    if rec:
                        records.append(rec)
    return records


def _is_header_row(row: list) -> bool:
    """Return True if this row is a column header, not data."""
    # Check first cell against known header text
    return row and row[0] and row[0].strip().upper() in {'NAME', 'FACILITY', 'LICENSE NO', '#'}


def _is_skip_row(row: list) -> bool:
    """Return True for blank or total rows."""
    if not any(cell and cell.strip() for cell in row):
        return True
    first = (row[0] or '').strip().upper()
    return first.startswith('TOTAL') or first.startswith('SUBTOTAL')


def _row_to_dict(row: list, date_str: str) -> dict | None:
    """Map table row cells to field names. Adjust indices from analysis."""
    if not row or not row[0]:
        return None
    return {
        'field_1':    (row[0] or '').strip(),
        'field_2':    (row[1] or '').strip(),
        # ... map all columns
        'date_parsed': date_str or date.today().isoformat(),
    }
```

If `page.extract_tables()` returns nothing, fall back to line-by-line text with column x-positions (Strategy A word-position variant).

---

## Strategy C: Fixed-Format / Right-to-Left Lines

Use when each line has structured fields with numbers at the right end and text at the left. Common in payroll, salary, and account listing documents.

```python
SKIP_PAGES = 2     # title/TOC pages
HEADER_LINES = 10  # lines at top of each page that are headers

# Pattern for a data line: starts with a code, ends with numbers
# Adjust to match the actual format
DATA_LINE_RE = re.compile(r'^\s*(\d{6})\s+(.+)$')  # cost element + rest


def extract_records(pdf_path: Path, date_str: str = None) -> list[dict]:
    records = []
    current_context = {}  # accumulated from page/section headers

    with pdfplumber.open(pdf_path) as pdf:
        for page_num, page in enumerate(pdf.pages):
            if page_num < SKIP_PAGES:
                continue
            # layout=True preserves column alignment for fixed-format docs
            text = page.extract_text(layout=True)
            if not text:
                continue
            lines = text.split('\n')

            # Update context from page header (first few lines)
            _update_context(lines[:HEADER_LINES], current_context)

            for line in lines[HEADER_LINES:]:
                if _is_skip_line(line):
                    continue
                rec = _parse_data_line(line, current_context, date_str)
                if rec:
                    records.append(rec)

    return records


def _update_context(header_lines: list[str], context: dict) -> None:
    """Extract campus, department, fund, year etc. from page header lines."""
    for line in header_lines:
        line = line.strip()
        # Example: detect campus name
        if 'CAMPUS NAME' in line:
            context['campus'] = line.split('CAMPUS NAME')[-1].strip()
        # Add detection logic for other context fields from analysis


def _is_skip_line(line: str) -> bool:
    """Return True for blank lines, headers, totals, pool entries."""
    stripped = line.strip()
    if not stripped:
        return True
    upper = stripped.upper()
    # Skip totals and subtotals
    if upper.startswith(('TOTAL', 'SUBTOTAL', 'SUB-TOTAL')):
        return True
    # Skip pool/placeholder entries (common in budget/payroll docs)
    POOL_KEYWORDS = {'POOL', 'ADJUSTMENT', 'ADJ', 'REVERSION', 'TBA', 'TBB', 'TBC'}
    words = set(upper.split())
    if words & POOL_KEYWORDS:
        return True
    return False


def _parse_data_line(line: str, context: dict, date_str: str) -> dict | None:
    """
    Parse a fixed-format data line right-to-left.
    Numbers appear at the end; text/name at the start.
    Adjust field extraction to match the actual line format.
    """
    line = line.strip()
    if not line:
        return None

    # Extract trailing numbers first (salary, FTE, counts, etc.)
    # Then extract codes from middle (position, job class, etc.)
    # Remainder at left is the name/description

    # Example right-to-left parse for salary data:
    salary = _extract_trailing_number(line)
    fte = _extract_fte(line)
    # ... extract other numeric fields

    # Extract structured code (e.g., 6-digit cost element)
    m = DATA_LINE_RE.match(line)
    if not m:
        return None

    code = m.group(1)
    remainder = m.group(2)
    name = _extract_name(remainder)

    return {
        **context,            # spread in campus/department/fund context
        'code':       code,
        'name':       name,
        'salary':     salary,
        'fte':        fte,
        'date_parsed': date_str or date.today().isoformat(),
    }


def _extract_trailing_number(line: str) -> str:
    """Extract the last number from a line (salary, total, etc.)."""
    m = re.search(r'([\d,]+(?:\.\d+)?)\s*$', line)
    return m.group(1).replace(',', '') if m else ''


def _extract_fte(line: str) -> str:
    """Extract FTE value (format: X.XXX)."""
    m = re.search(r'\b(\d\.\d{3})\b', line)
    return m.group(1) if m else ''
```

---

## Strategy D: Hierarchical / Context-Per-Page

Use when page headers define the grouping (department, campus, fund type) and data rows only make sense in that context. Combine with any of A/B/C for the row-level parsing.

```python
def extract_records(pdf_path: Path, date_str: str = None) -> list[dict]:
    records = []
    context = {}

    with pdfplumber.open(pdf_path) as pdf:
        for page_num, page in enumerate(pdf.pages):
            text = page.extract_text(layout=True)
            if not text:
                continue
            lines = [l.rstrip() for l in text.split('\n')]

            # Step 1: Classify this page and extract its context
            page_context = _classify_page(lines)
            if page_context is None:
                continue  # skip non-data pages
            context.update(page_context)

            # Step 2: Parse data rows using whichever row strategy fits
            for line in lines[HEADER_LINES:]:
                if _is_skip_line(line):
                    continue
                rec = _parse_row(line, context, date_str)
                if rec:
                    records.append(rec)

    return records


def _classify_page(lines: list[str]) -> dict | None:
    """
    Return context dict from page header, or None to skip the page.
    Implement based on the analysis — what appears in the first N lines
    that tells you what this page is about?
    """
    context = {}
    for line in lines[:8]:
        line = line.strip()
        # Example: detect and skip non-data pages
        if 'TABLE OF CONTENTS' in line or 'EXCLUDING' in line:
            return None
        # Example: detect campus/department/fund
        if line.startswith('CAMPUS:'):
            context['campus'] = line.split(':', 1)[1].strip()
        # Add more detection from analysis
    return context if context else None
```

---

## Multi-Year Batch Processing

When the project processes multiple PDFs (e.g., annual archives):

```python
def main():
    # Process all PDFs in pdfs/ directory
    pdf_files = sorted(PDF_DIR.glob("*.pdf"))
    if not pdf_files:
        print("No PDFs found in pdfs/. Add PDFs and re-run.")
        sys.exit(1)

    all_records = []
    for pdf_path in pdf_files:
        year = _extract_year(pdf_path)
        print(f"Processing {pdf_path.name} ({year})...")
        records = extract_records(pdf_path, year=year)
        print(f"  → {len(records)} records")
        all_records.extend(records)

        # Optionally save per-year file
        save_to_csv(records, DATA_DIR / f"{slug}_{year}.csv")

    # Also save combined file
    if all_records:
        save_to_csv(all_records, DATA_DIR / f"{slug}_all.csv")


def _extract_year(pdf_path: Path) -> str:
    """Extract fiscal/calendar year from filename. Handles common formats."""
    name = pdf_path.stem
    # Full fiscal year: YYYY-YYYY or YYYY_YYYY
    m = re.search(r'(20\d{2})[-_](20\d{2})', name)
    if m:
        return f"{m.group(1)}-{m.group(2)}"
    # Short year: YY-YY
    m = re.search(r'(2\d)[-_](\d{2})', name)
    if m:
        return f"20{m.group(1)}-20{m.group(2)}"
    # Single year: YYYY
    m = re.search(r'(20\d{2})', name)
    if m:
        return m.group(1)
    return "unknown"
```

---

## Number Parsing Helpers

Always include these when working with financial data:

```python
def _parse_number(val: str) -> float | None:
    """Parse a number string, handling commas and parentheses for negatives."""
    if not val or not val.strip():
        return None
    val = val.strip().replace(',', '')
    if val.startswith('(') and val.endswith(')'):
        val = '-' + val[1:-1]
    try:
        return float(val)
    except ValueError:
        return None
```

---

## Multi-Source Record Consolidation

When one person/entity appears on multiple lines due to multiple funding sources:

```python
def _consolidate_by_key(records: list[dict], key_field: str) -> list[dict]:
    """
    Merge records that share the same key (e.g., person name).
    Keeps the first record's fields; appends secondary identifiers
    (e.g., cost elements, fund sources) as semicolon-separated lists.
    """
    seen = {}
    for rec in records:
        key = rec[key_field].strip().upper()
        if key not in seen:
            seen[key] = rec.copy()
            seen[key]['_sources'] = [rec.get('source_id', '')]
        else:
            # Accumulate secondary source IDs
            seen[key]['_sources'].append(rec.get('source_id', ''))
            # Optionally sum numeric fields
            for field in ('salary', 'fte'):
                if rec.get(field):
                    try:
                        seen[key][field] = str(
                            float(seen[key].get(field) or 0) + float(rec[field])
                        )
                    except (ValueError, TypeError):
                        pass
    # Flatten sources back to semicolon string
    result = []
    for rec in seen.values():
        rec['source_ids'] = ';'.join(filter(None, rec.pop('_sources', [])))
        result.append(rec)
    return result
```

---

## After Writing

1. Run the script: `python parse_{slug}.py`
2. Report: how many records extracted, first 3 as sample output
3. If count differs significantly from the PDF total (from analysis), diagnose and fix
4. Update CLAUDE.md with the actual parsing strategy and field list
5. Prompt: "Parser working. Run `/pdf-to-csv-validate` to add the test suite."
