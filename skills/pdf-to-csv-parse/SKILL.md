---
name: pdf-to-csv-parse
description: Write the Python PDF-to-CSV extraction script for a project. Use after /pdf-to-csv-analyze and /pdf-to-csv-scaffold. Requires the analysis output to be in context.
argument-hint: [project-directory]
---

# Write PDF-to-CSV Parser

Write `parse_{slug}.py` in the project directory `$ARGUMENTS` (or current directory if omitted).

**Prerequisite:** The `/pdf-to-csv-analyze` output must be in context. If it is not, run that skill first.

Read any existing files in the project directory before writing to understand what's already there.

---

## Script Structure

Every parser script follows this structure:

```python
#!/usr/bin/env python3
"""
Extract {facility type} roster data from Nebraska DHHS PDF to CSV.
Source: {PDF URL}
"""

import csv
import re
import sys
from datetime import date
from pathlib import Path

import pdfplumber
import requests

# --- Configuration ---
PDF_URL = "{PDF URL}"
PDF_DIR = Path("pdfs")
DATA_DIR = Path("data")

# --- Download ---

def download_pdf(url: str = PDF_URL) -> Path:
    """Download the current PDF roster and save with today's date stamp."""
    PDF_DIR.mkdir(exist_ok=True)
    date_str = date.today().strftime("%Y-%m-%d")
    filename = PDF_DIR / f"{Slug}_{date_str}.pdf"
    if filename.exists():
        print(f"PDF already exists: {filename}")
        return filename
    print(f"Downloading {url} ...")
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    filename.write_bytes(r.content)
    print(f"Saved to {filename}")
    return filename

# --- Extraction ---

def extract_records(pdf_path: Path, date_str: str = None) -> list[dict]:
    """Extract all records from the PDF."""
    if date_str is None:
        date_str = date.today().strftime("%Y-%m-%d")
    records = []
    with pdfplumber.open(pdf_path) as pdf:
        # [implementation based on parsing strategy]
    return records

# --- Output ---

def save_to_csv(records: list[dict], output_path: Path = None) -> Path:
    """Write records to a date-stamped CSV file."""
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

# --- Main ---

def main():
    pdf_path = download_pdf()
    date_str = date.today().strftime("%Y-%m-%d")
    records = extract_records(pdf_path, date_str)
    print(f"Extracted {len(records)} records")
    save_to_csv(records)

if __name__ == "__main__":
    main()
```

---

## Implementing extract_records()

Choose the implementation based on the analysis output.

### Strategy A: Line-by-Line Text (most common)

Use when `extract_text()` produces readable records in order.

```python
def extract_records(pdf_path: Path, date_str: str = None) -> list[dict]:
    records = []
    current = None

    # Regex that identifies the start of a new record (first line of each entry)
    HEADER_RE = re.compile(
        r'^([A-Z][A-Z\s\']+?)\s*\(([A-Z\s]+)\)\s*-\s*(\d{5})\s+(LICENSE_TYPE_PATTERN)\s*(.*)$'
    )

    with pdfplumber.open(pdf_path) as pdf:
        for page_num, page in enumerate(pdf.pages):
            if page_num < SKIP_PAGES:  # skip cover pages
                continue
            text = page.extract_text()
            if not text:
                continue
            lines = text.split('\n')
            for line_num, line in enumerate(lines):
                line = line.strip()
                if not line:
                    continue
                # Skip page headers (first N lines of each page)
                if line_num < HEADER_LINES_PER_PAGE:
                    continue
                # Stop at footer
                if line.startswith("Total "):
                    break

                m = HEADER_RE.match(line)
                if m:
                    if current:
                        records.append(current)
                    current = {
                        'town': m.group(1).strip(),
                        'county': m.group(2).strip(),
                        'zip_code': m.group(3),
                        'facility_type': m.group(4),
                        'date_parsed': date_str,
                        # initialize remaining fields as empty
                        'facility_name': '',
                        'license_number': '',
                        'address': '',
                        'phone': '',
                        'fax': '',
                        'licensee': '',
                        'administrator': '',
                    }
                    # parse anything on the first line after the type
                    remainder = m.group(5).strip()
                    # extract inline fields from remainder if needed
                elif current is not None:
                    # Parse continuation lines
                    _parse_continuation_line(line, current)

        if current:
            records.append(current)

    return records


def _parse_continuation_line(line: str, record: dict) -> None:
    """Update record dict with fields extracted from a continuation line."""
    # Phone + FAX pattern
    phone_fax = re.search(
        r'\((\d{3})\)\s*(\d{3}-\d{4})(?:.*?FAX:\s*\(?(\d{3})\)?\s*(\d{3}-\d{4}))?',
        line
    )
    if phone_fax:
        record['phone'] = f"({phone_fax.group(1)}) {phone_fax.group(2)}"
        if phone_fax.group(3):
            record['fax'] = f"({phone_fax.group(3)}) {phone_fax.group(4)}"
        return

    # License number pattern (adjust regex for this roster's format)
    lic = re.search(r'\b([A-Z]{2,5}\d{3,6})\b', line)
    if lic and not record.get('license_number'):
        record['license_number'] = lic.group(1)

    # Address: if it looks like a street address and facility_name is set
    if record.get('facility_name') and not record.get('address'):
        record['address'] = line
        return

    # Facility name: first non-header continuation line
    if not record.get('facility_name'):
        record['facility_name'] = line
        return
```

### Strategy B: Word-Position / Coordinate-Based

Use when the PDF has multi-column layout that scrambles text extraction.

```python
# Define column x-coordinate boundaries from analysis
COLUMNS = {
    'col1_name': (0, 200),
    'col2_name': (200, 400),
    'col3_name': (400, 600),
}

def get_column_text(words: list, x_min: float, x_max: float) -> str:
    """Extract and join words within an x-coordinate range."""
    return ' '.join(
        w['text'] for w in words
        if x_min <= w['x0'] < x_max
    ).strip()

def group_words_into_lines(words: list, y_tolerance: float = 4.0) -> list[list]:
    """Group words into lines by proximity of their y (top) coordinate."""
    if not words:
        return []
    lines = []
    current_y = words[0]['top']
    current_line = []
    for w in sorted(words, key=lambda w: (round(w['top'] / y_tolerance), w['x0'])):
        if abs(w['top'] - current_y) > y_tolerance:
            if current_line:
                lines.append(current_line)
            current_line = [w]
            current_y = w['top']
        else:
            current_line.append(w)
    if current_line:
        lines.append(current_line)
    return lines

def extract_records(pdf_path: Path, date_str: str = None) -> list[dict]:
    records = []
    HEADER_RE = re.compile(r'TOWN_PATTERN')  # adjust to this PDF

    with pdfplumber.open(pdf_path) as pdf:
        for page_num, page in enumerate(pdf.pages):
            if page_num < SKIP_PAGES:
                continue
            words = page.extract_words()
            lines = group_words_into_lines(words)

            record_lines = []
            for line_words in lines:
                line_text = ' '.join(w['text'] for w in line_words)
                if HEADER_RE.match(line_text):
                    if record_lines:
                        rec = _parse_record_block(record_lines, date_str)
                        if rec:
                            records.append(rec)
                    record_lines = [line_words]
                elif record_lines:
                    record_lines.append(line_words)

            if record_lines:
                rec = _parse_record_block(record_lines, date_str)
                if rec:
                    records.append(rec)

    return records
```

---

## Field Extraction Helpers

Always use these helpers (adapt patterns as needed):

```python
def _extract_phone(text: str) -> str:
    m = re.search(r'\((\d{3})\)\s*(\d{3}-\d{4})', text)
    return f"({m.group(1)}) {m.group(2)}" if m else ''

def _extract_fax(text: str) -> str:
    m = re.search(r'FAX:?\s*\(?(\d{3})\)?\s*(\d{3}-\d{4})', text)
    return f"({m.group(1)}) {m.group(2)}" if m else ''

def _extract_zip(text: str) -> str:
    m = re.search(r'\b(\d{5})(?:-\d{4})?\b', text)
    return m.group(1) if m else ''
```

---

## Constants to Define

At the top of the script, define these based on the analysis:

```python
SKIP_PAGES = N          # number of cover/title pages to skip (usually 1-2)
HEADER_LINES = N        # lines to skip at top of each data page (usually 5-7)
TOTAL_FOOTER = "Total " # text that signals end of records on a page
```

---

## After Writing

1. Run the script against the actual PDF to confirm it works: `python parse_{slug}.py`
2. Report: how many records extracted, first 3 records as sample output
3. If count is far off from the PDF total (from analysis), diagnose and fix
4. Update CLAUDE.md with the actual parsing strategy and field list
5. Prompt: "Parser working. Run `/pdf-to-csv-validate` to add the test suite."
