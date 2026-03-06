---
name: pdf-to-csv-validate
description: Write the pytest test suite for a PDF-to-CSV extraction project. Use after /pdf-to-csv-parse to validate data quality, field fill rates, and format correctness.
argument-hint: [project-directory]
---

# Write PDF-to-CSV Test Suite

Write `test_parse_{slug}.py` in the project directory `$ARGUMENTS` (or current directory if omitted).

**Prerequisites:**
- The parser (`parse_{slug}.py`) must already exist and produce output
- Run the parser first if no CSV exists yet: `python parse_{slug}.py`
- Read the CSV output and the parser script before writing tests

---

## Test File Structure

```python
"""
Tests for parse_{slug}.py
Run: pytest test_parse_{slug}.py -v
"""

import csv
import re
from pathlib import Path

import pytest

from parse_{slug} import extract_records, save_to_csv

# --- Fixtures ---

PDF_PATH = next(Path("pdfs").glob("*.pdf"), None)  # most recent PDF in pdfs/

@pytest.fixture(scope="module")
def records():
    """Load records from the most recent PDF (or cached CSV)."""
    assert PDF_PATH is not None, "No PDF found in pdfs/ — run the parser first"
    date_str = PDF_PATH.stem.split("_")[-1]  # extract date from filename
    return extract_records(PDF_PATH, date_str)

@pytest.fixture(scope="module")
def csv_path(records, tmp_path_factory):
    """Write records to a temp CSV and return its path."""
    out = tmp_path_factory.mktemp("data") / "test_output.csv"
    save_to_csv(records, out)
    return out
```

---

## Test Classes to Write

### 1. TestRecordCount

```python
class TestRecordCount:
    """Verify the number of extracted records is reasonable."""

    EXPECTED_MIN = N   # set from the PDF footer total (allow 5% slack)
    EXPECTED_MAX = N   # same total + 5% slack

    def test_record_count_in_range(self, records):
        count = len(records)
        assert self.EXPECTED_MIN <= count <= self.EXPECTED_MAX, (
            f"Expected {self.EXPECTED_MIN}–{self.EXPECTED_MAX} records, got {count}"
        )

    def test_no_duplicate_license_numbers(self, records):
        license_numbers = [r['license_number'] for r in records if r.get('license_number')]
        assert len(license_numbers) == len(set(license_numbers)), (
            "Duplicate license numbers found"
        )
```

Set `EXPECTED_MIN` and `EXPECTED_MAX` based on the actual count from the PDF footer (±5%). If no footer count exists, use ±10% of the actual extracted count.

### 2. TestRequiredColumns

```python
class TestRequiredColumns:
    """Verify that critical columns are filled at acceptable rates."""

    # Thresholds based on field criticality:
    # - 95%+ for truly required fields (town, zip, facility_name, license_number)
    # - 80%+ for important but sometimes absent fields (phone, beds)
    # - 50%+ for optional fields (fax, administrator)

    FILL_RATE_THRESHOLDS = {
        'town': 0.95,
        'county': 0.95,
        'zip_code': 0.95,
        'facility_name': 0.95,
        'license_number': 0.90,
        'address': 0.85,
        'phone': 0.80,
        # Add other fields with appropriate thresholds
    }

    @pytest.mark.parametrize("field,threshold", FILL_RATE_THRESHOLDS.items())
    def test_fill_rate(self, records, field, threshold):
        total = len(records)
        filled = sum(1 for r in records if r.get(field, '').strip())
        rate = filled / total
        assert rate >= threshold, (
            f"Field '{field}' fill rate {rate:.1%} is below threshold {threshold:.0%} "
            f"({filled}/{total} records)"
        )
```

### 3. TestDataFormats

Write format-validation tests for each field type present in this roster. Use only the patterns that apply:

```python
class TestDataFormats:
    """Verify field values conform to expected formats."""

    def test_zip_codes_are_5_digits(self, records):
        bad = [r['zip_code'] for r in records
               if r.get('zip_code') and not re.match(r'^\d{5}$', r['zip_code'])]
        assert not bad, f"Invalid zip codes: {bad[:5]}"

    def test_license_numbers_match_pattern(self, records):
        # Adjust PATTERN to match this roster's license format
        # Examples: ALF\d{3}, CDD\d{3}, \d{6}, RHC-[A-Z]
        PATTERN = re.compile(r'^LICENSE_PATTERN$')
        bad = [r['license_number'] for r in records
               if r.get('license_number') and not PATTERN.match(r['license_number'])]
        assert not bad, f"Invalid license numbers: {bad[:5]}"

    def test_phone_numbers_are_formatted(self, records):
        PHONE_RE = re.compile(r'^\(\d{3}\) \d{3}-\d{4}$')
        bad = [r['phone'] for r in records
               if r.get('phone') and not PHONE_RE.match(r['phone'])]
        assert len(bad) / len(records) < 0.05, (
            f"Too many malformed phone numbers ({len(bad)}): {bad[:5]}"
        )

    def test_towns_are_uppercase(self, records):
        bad = [r['town'] for r in records
               if r.get('town') and r['town'] != r['town'].upper()]
        assert not bad, f"Towns not uppercase: {bad[:5]}"

    def test_counties_are_uppercase(self, records):
        bad = [r['county'] for r in records
               if r.get('county') and r['county'] != r['county'].upper()]
        assert not bad, f"Counties not uppercase: {bad[:5]}"

    # Add numeric field tests if applicable:
    def test_bed_counts_are_numeric(self, records):
        """Only include if roster has a beds/capacity field."""
        bad = [r['total_beds'] for r in records
               if r.get('total_beds') and not r['total_beds'].isdigit()]
        assert not bad, f"Non-numeric bed counts: {bad[:5]}"
```

Only include tests for fields that actually exist in this roster. Remove the beds test if there's no beds field.

### 4. TestCSVOutput

```python
class TestCSVOutput:
    """Verify the CSV file is well-formed."""

    EXPECTED_COLUMNS = [
        # List all column names from the actual script output
        'town', 'county', 'zip_code', 'facility_name', 'license_number',
        'address', 'phone', 'fax', 'licensee', 'administrator', 'date_parsed',
        # ... add all columns
    ]

    def test_csv_exists(self, csv_path):
        assert csv_path.exists()
        assert csv_path.stat().st_size > 0

    def test_csv_has_expected_columns(self, csv_path):
        with open(csv_path, newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            actual = reader.fieldnames
        assert actual == self.EXPECTED_COLUMNS, (
            f"Column mismatch.\nExpected: {self.EXPECTED_COLUMNS}\nActual:   {actual}"
        )

    def test_csv_row_count_matches_records(self, records, csv_path):
        with open(csv_path, newline='', encoding='utf-8') as f:
            rows = list(csv.DictReader(f))
        assert len(rows) == len(records)
```

### 5. TestKnownRecords (optional but valuable)

```python
class TestKnownRecords:
    """Spot-check specific known records to catch regression."""

    def test_known_facility_present(self, records):
        """Verify a specific well-known facility appears in the output."""
        # Choose a facility unlikely to be delicensed (large, well-known)
        names = [r.get('facility_name', '').upper() for r in records]
        assert any('KNOWN FACILITY NAME' in n for n in names), (
            "Expected facility not found — check for parsing regression"
        )
```

Choose 1-2 well-known facilities from the actual output to spot-check. Read the CSV to find stable candidates.

---

## After Writing Tests

Run the full suite and report results:

```bash
pytest test_parse_{slug}.py -v
```

If any tests fail:
1. Check if it's a threshold issue (fill rate slightly below threshold) — adjust the threshold and note it
2. Check if it's a format issue — fix the parser if needed
3. Check if it's a count issue — re-check the PDF footer and adjust expected range

Report: number of tests passed, any failures and their cause.
