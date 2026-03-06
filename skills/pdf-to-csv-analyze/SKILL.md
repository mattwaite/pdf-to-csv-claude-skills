---
name: pdf-to-csv-analyze
description: Analyze a government roster PDF to understand its structure before writing an extractor. Use at the start of a new PDF-to-CSV project. Takes a PDF path or URL as argument.
argument-hint: [pdf-path-or-url]
---

# PDF Roster Analysis

Analyze the PDF at `$ARGUMENTS` and produce a structured analysis report that will guide parser development.

## Steps

### 1. Obtain the PDF

Write and run a short Python script to inspect the PDF:

```python
import pdfplumber, requests, tempfile, sys

source = "$ARGUMENTS"
if source.startswith("http"):
    r = requests.get(source)
    tmp = tempfile.NamedTemporaryFile(suffix=".pdf", delete=False)
    tmp.write(r.content); tmp.close()
    pdf_path = tmp.name
else:
    pdf_path = source

with pdfplumber.open(pdf_path) as pdf:
    print(f"Total pages: {len(pdf.pages)}")
    for i, page in enumerate(pdf.pages[:4]):
        print(f"\n--- PAGE {i+1} ---")
        text = page.extract_text()
        print(text[:2000] if text else "[no text]")
    # Also check last page
    print(f"\n--- LAST PAGE ({len(pdf.pages)}) ---")
    print(pdf.pages[-1].extract_text()[-1000:])
```

### 2. Identify Page Structure

From the output, determine:
- Is page 1 a title/cover page with no record data? (usual answer: yes)
- How many pages of actual record data are there?
- What text repeats at the top of each data page? (those are headers to skip)
- Does the last page (or any page footer) contain "Total Facilities:", "Total Clinics:", or similar? Note that count.

### 3. Identify the Record Header Pattern

Look for what marks the START of each new facility/provider record. In Nebraska DHHS rosters, the pattern is almost always:

```
TOWN (COUNTY) - ZIPCODE  LICENSE_TYPE
```

Try to write a regex for it. Common examples:
- `^([A-Z][A-Z\s']+?)\s*\(([A-Z\s]+)\)\s*-\s*(\d{5})\s+(ALF|CDD|RHC-\w+|HOSP-\w+|PSYCH?)\s*(.*)$`
- Numeric IDs in the first column (for tabular rosters)

Also check: are records identified by something other than town/county (like a numeric license number at start of line)?

### 4. Determine Parsing Strategy

Run this test to decide between line-by-line vs word-position parsing:

```python
with pdfplumber.open(pdf_path) as pdf:
    page = pdf.pages[1]  # first data page

    print("=== TEXT EXTRACTION ===")
    text = page.extract_text()
    print(text[:3000] if text else "[none]")

    print("\n=== WORD POSITIONS (first 40 words) ===")
    words = page.extract_words()
    for w in words[:40]:
        print(f"  x={w['x0']:6.1f}  y={w['top']:6.1f}  '{w['text']}'")
```

**Choose line-by-line text strategy** if:
- `extract_text()` produces clearly readable records in the right order
- Records run top-to-bottom with no side-by-side columns
- Used by: ALF, Hospitals, Rural Health Clinics projects

**Choose word-position (x/y coordinate) strategy** if:
- `extract_text()` scrambles text from adjacent columns together
- The PDF has 2-3 columns side by side on each page
- x-coordinate ranges clearly separate columns
- Used by: CDD, Community Pharmacies projects

### 5. Count Lines Per Record and Extract Fields

Pick one complete record from the output. Count the lines it spans. List every field you see, noting which line each appears on. Common fields in DHHS rosters:

- Line 1: town, county, zip_code, facility_type (from header pattern)
- Line 2: facility_name, license_number
- Line 3: address
- Line 4: phone, fax
- Line 5: licensee
- Line 6: administrator
- Line 7 (optional): care_of / mailing address

Note any fields that:
- Are sometimes absent (optional fields)
- Span multiple lines (long addresses)
- Contain embedded sub-fields (beds, services, accreditation on same line)

### 6. Sample 3 Complete Records

Extract and display 3 raw record blocks in full (all lines) so the structure is clear.

### 7. Identify Potential Parsing Challenges

Look for:
- Multi-word county names (BOX BUTTE, SCOTTS BLUFF, RED WILLOW)
- City names with apostrophes (O'NEILL)
- Optional fields that appear on some records but not others
- Page breaks that split a record across pages
- Header/footer text that could be mistaken for records

---

## Output Format

Produce this structured report when done:

```
## PDF Analysis: [filename or URL]

**Total pages:** N
**Cover/title pages to skip:** N
**Header lines per data page:** N (list them)
**Total records (from PDF footer):** N
**Record identification pattern:**
  Regex: `PATTERN`
  Example line: [exact text from PDF]

**Lines per record:** Fixed N / Variable (min N, max N)
**Parsing strategy:** Line-by-line text OR Word-position coordinates
**Reason:** [one sentence]

**Column boundaries (if word-position):**
  col1: x=0-NNN (field name)
  col2: x=NNN-NNN (field name)

**Fields (in order):**
  1. town — line 1, from header regex group 1
  2. county — line 1, from header regex group 2
  ... (complete list)

**Optional/conditional fields:** [list]

**Parsing challenges to watch for:**
  - [challenge 1]
  - [challenge 2]

**Sample record 1 (raw lines):**
[all lines]

**Sample record 2 (raw lines):**
[all lines]

**Sample record 3 (raw lines):**
[all lines]

**Recommended next steps:**
  /pdf-to-csv-scaffold [project-name] [pdf-url]
  /pdf-to-csv-parse (with this analysis in context)
```
