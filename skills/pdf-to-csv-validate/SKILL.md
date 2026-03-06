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

    def test_no_duplicate_primary_keys(self, records):
        # Replace 'primary_key_field' with the field that should be unique
        # (e.g., 'license_number', 'name', 'id', 'cost_object_code')
        key_field = 'primary_key_field'
        keys = [r[key_field] for r in records if r.get(key_field)]
        assert len(keys) == len(set(keys)), (
            f"Duplicate values in '{key_field}' field"
        )
```

Set `EXPECTED_MIN` and `EXPECTED_MAX` based on the actual count from the PDF footer (±5%). If no footer count exists, use ±10% of the actual extracted count.

### 2. TestRequiredColumns

```python
class TestRequiredColumns:
    """Verify that critical columns are filled at acceptable rates."""

    # Thresholds based on field criticality. Set these by reading the actual CSV
    # output and deciding what fill rate is acceptable for each field.
    #
    # Suggested starting points:
    # - 95%+ for fields that should always be present (primary identifiers, names)
    # - 80%+ for important but occasionally absent fields (phone, address, amount)
    # - 50%+ for truly optional fields (fax, secondary contact, notes)
    #
    # Replace these field names with the actual fields from this project:
    FILL_RATE_THRESHOLDS = {
        'primary_id_field': 0.95,      # e.g., license_number, name, id
        'name_field': 0.95,            # e.g., facility_name, entity_name
        'address_or_location': 0.85,   # e.g., address, zip_code, city
        'contact_field': 0.80,         # e.g., phone, email
        # Add/remove fields based on what this document actually contains
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

Write format-validation tests for each field type present in this document. Only include tests for fields that actually exist. Pick from the templates below based on what applies.

```python
class TestDataFormats:
    """Verify field values conform to expected formats."""

    # --- ID / Code fields ---

    def test_id_field_matches_pattern(self, records):
        # Replace field name and regex with the actual ID format for this document
        # Examples: r'^\d{6}$' for 6-digit codes, r'^[A-Z]{2,5}\d{3,6}$' for license numbers
        PATTERN = re.compile(r'^ID_PATTERN$')
        field = 'id_field_name'
        bad = [r[field] for r in records
               if r.get(field) and not PATTERN.match(r[field])]
        assert not bad, f"Invalid {field} values: {bad[:5]}"

    # --- Contact fields ---

    def test_phone_numbers_are_formatted(self, records):
        # Only include if this document has phone numbers
        PHONE_RE = re.compile(r'^\(\d{3}\) \d{3}-\d{4}$')
        bad = [r['phone'] for r in records
               if r.get('phone') and not PHONE_RE.match(r['phone'])]
        assert len(bad) / len(records) < 0.05, (
            f"Too many malformed phone numbers ({len(bad)}): {bad[:5]}"
        )

    # --- Geographic fields ---

    def test_zip_codes_are_5_digits(self, records):
        # Only include if this document has zip codes
        bad = [r['zip_code'] for r in records
               if r.get('zip_code') and not re.match(r'^\d{5}$', r['zip_code'])]
        assert not bad, f"Invalid zip codes: {bad[:5]}"

    # --- Numeric / financial fields ---

    def test_numeric_field_is_numeric(self, records):
        # Replace 'amount_field' with actual field name (salary, total_beds, fte, etc.)
        field = 'amount_field'
        bad = []
        for r in records:
            val = str(r.get(field, '')).replace(',', '').strip()
            if val and not re.match(r'^-?\d+(\.\d+)?$', val):
                bad.append(val)
        assert len(bad) / max(len(records), 1) < 0.05, (
            f"Non-numeric values in '{field}': {bad[:5]}"
        )

    # --- Date fields ---

    def test_date_field_format(self, records):
        # Only include if document has date fields
        # Adjust format string to match (YYYY-MM-DD, MM/DD/YYYY, etc.)
        DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
        field = 'date_field_name'
        bad = [r[field] for r in records
               if r.get(field) and not DATE_RE.match(r[field])]
        assert not bad, f"Invalid date formats in '{field}': {bad[:5]}"

    # --- Text casing fields (roster/directory documents) ---

    def test_name_field_is_uppercase(self, records):
        # Only include if this document stores names/locations in ALL CAPS
        field = 'name_or_location_field'
        bad = [r[field] for r in records
               if r.get(field) and r[field] != r[field].upper()]
        assert not bad, f"'{field}' values not uppercase: {bad[:5]}"
```

Read the actual CSV output before writing these tests. Only add tests for formats that can meaningfully be validated against this document's real data.

### 4. TestCSVOutput

```python
class TestCSVOutput:
    """Verify the CSV file is well-formed."""

    EXPECTED_COLUMNS = [
        # Read the actual CSV output first, then list all columns here in order.
        # Example: 'id', 'name', 'address', 'phone', 'date_parsed'
        # Replace this list with the real column names from this project.
        'column_1', 'column_2',  # ... fill in from actual output
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

    def test_known_record_present(self, records):
        """Verify a specific well-known entry appears in the output.

        Choose something stable — a large organization, a permanent department,
        or a long-running entry unlikely to disappear between document versions.
        Read the actual CSV output to find good candidates.
        """
        # Replace with the actual field and value to check
        field = 'name_field'
        expected = 'KNOWN STABLE ENTRY NAME'
        values = [r.get(field, '').upper() for r in records]
        assert any(expected in v for v in values), (
            f"Expected entry '{expected}' not found in '{field}' — check for parsing regression"
        )
```

Read the actual CSV output to choose 1-2 stable entries to spot-check. Good candidates: large well-known organizations, permanent government departments, or entries that appear in every historical version of this document.

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
