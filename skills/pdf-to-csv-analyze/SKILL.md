---
name: pdf-to-csv-analyze
description: Analyze a PDF to understand its structure before writing an extractor. Use at the start of a new PDF-to-CSV project. Takes a PDF path or URL as argument.
argument-hint: [pdf-path-or-url]
---

# PDF Structure Analysis

Analyze the PDF at `$ARGUMENTS` and produce a structured report to guide parser development.

## Steps

### 1. Obtain the PDF

```python
import pdfplumber, requests, tempfile

source = "$ARGUMENTS"
if source.startswith("http"):
    r = requests.get(source, timeout=30)
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
    print(f"\n--- LAST PAGE ({len(pdf.pages)}) ---")
    print(pdf.pages[-1].extract_text()[-1000:])
```

### 2. Classify the PDF Type

From the output, determine which type best describes this PDF:

**Type A — Roster/Directory** (one multi-line record per entity)
- Each entry is a named facility, person, or organization
- Entries are identified by a consistent header pattern (e.g., location, ID number)
- Fields span several lines per entry
- Examples: licensing rosters, personnel directories, vendor lists

**Type B — Formatted Table** (rows and columns of data)
- Data is arranged in columns with a header row
- Each row is one record; columns are fields
- May span many pages with headers repeating
- Examples: budget line items, expenditure tables, license lists with columns

**Type C — Fixed-Format Data Lines** (structured columns by character position or right-to-left)
- Each data line contains the same fields in the same positions
- Numbers appear at the right end of each line; text at the left
- Often used for payroll, account codes, or financial data
- Examples: salary rosters, general ledger exports, account listings

**Type D — Hierarchical/Contextual** (page headers define context for data rows)
- Page headers establish context (department, campus, fund type, year)
- Data rows within a page only make sense with that context
- Often multiple pages share the same structure, different context
- Examples: university budget books, annual reports by department

A PDF can combine types (e.g., Type D with Type B tables inside each section).

### 3. Identify Page Structure

Determine:
- How many pages are title/cover/TOC (no data)? These should be skipped.
- What text repeats at the top of each data page? (Those are headers to skip.)
- Does the last page (or any footer) contain a total count or sum? Note it.
- Do page headers carry context (campus name, department, fund type)?

### 4. Run the Right Detection Test

**For Type A (Roster):** Find the record identification pattern.

```python
with pdfplumber.open(pdf_path) as pdf:
    page = pdf.pages[1]  # first data page
    text = page.extract_text()
    print(text[:3000])
```

Look for a consistent line that starts each record. Common patterns:
- `TOWN (COUNTY) - ZIPCODE  TYPE` — government licensure rosters
- A numeric ID or license number at line start
- An all-caps name followed by an address
- A date, code, or identifier that always opens a block

Try to write a regex for it.

Also test word-position (needed if columns are side-by-side):
```python
words = page.extract_words()
for w in words[:40]:
    print(f"  x={w['x0']:6.1f}  y={w['top']:6.1f}  '{w['text']}'")
```

**For Type B (Table):** Check if pdfplumber sees tables.

```python
with pdfplumber.open(pdf_path) as pdf:
    page = pdf.pages[1]
    tables = page.extract_tables()
    print(f"Tables found: {len(tables)}")
    if tables:
        for row in tables[0][:5]:
            print(row)
    # Also try text to see if it reads well without tables
    print(page.extract_text()[:2000])
```

**For Type C (Fixed-Format):** Test layout-preserving extraction.

```python
with pdfplumber.open(pdf_path) as pdf:
    page = pdf.pages[1]
    # layout=True preserves column alignment
    text = page.extract_text(layout=True)
    print(text[:3000])
```

Look for: numbers at line ends, consistent field positions, cost element codes (XX-XXXX-XXXX), salary/FTE values.

**For Type D (Hierarchical):** Identify the context signal.

```python
with pdfplumber.open(pdf_path) as pdf:
    for i in [1, 2, 10, 20]:
        if i < len(pdf.pages):
            print(f"\n--- PAGE {i+1} HEADER ---")
            text = pdf.pages[i].extract_text()
            if text:
                print('\n'.join(text.split('\n')[:8]))
```

Look for what changes between pages that defines the grouping (department name, campus, fund category, etc.).

### 5. Extract Fields

Pick one complete record or row from the data. List every distinct field:
- Which line/column it appears on
- Whether it's always present or optional
- Whether it needs post-processing (splitting, cleaning, unit conversion)

Watch for:
- Numbers with commas or parentheses for negatives: `(1,234)` = -1234
- Codes with structured formats: `21-6102-0002`, `ALF066`, `511000`
- Fields embedded together on one line (name + salary + FTE all on line 3)
- Multi-line fields (addresses, long names, multi-fund sources)
- Pool/placeholder rows to filter out (POOL, TBA, ADJUSTMENT, SUBTOTAL lines that aren't real records)

### 6. Sample 3 Complete Records

Extract and display 3 full records/rows showing all raw content.

### 7. Identify Parsing Challenges

- Lines that look like records but are headers/totals/subtotals
- Data that wraps across page breaks
- Inconsistent spacing or alignment between pages
- Entries that appear multiple times (multi-funding records that need consolidation)
- Records with optional fields that shift other fields' positions

---

## Output Format

```
## PDF Analysis: [filename or URL]

**Total pages:** N
**Pages to skip (cover/TOC/headers):** N (pages 1-N)
**PDF type:** [A: Roster / B: Table / C: Fixed-Format / D: Hierarchical / combination]

**Page structure:**
  - Header lines per data page: N
  - Context in page headers: [yes — what info / no]
  - Footer/total detection: [text that signals end of records]
  - Total record count (from PDF): N (source: [footer text / summary page / not found])

**Record identification:**
  [For Type A] Regex: `PATTERN`  |  Example: [exact text from PDF]
  [For Type B] Table columns: [list]  |  Header row: [exact text]
  [For Type C] Line format: [describe fields left-to-right]  |  Key right-end pattern: [regex]
  [For Type D] Context signal: [what field changes per page]  |  Data row pattern: [describe]

**Parsing strategy:**
  Primary: [line-by-line text / word-position x/y / table extraction / layout=True fixed-format]
  Reason: [one sentence]
  [If Type D] Context accumulation: [what to carry from page headers into each row]

**Fields (complete list):**
  1. field_name — [how to extract it]
  2. ...

**Rows/entries to filter out:**
  [List any non-data lines: SUBTOTAL, POOL, TBA, page headers repeating mid-page, etc.]

**Multi-source consolidation needed?** [Yes — describe / No]

**Sample record 1 (raw):**
[all lines]

**Sample record 2 (raw):**
[all lines]

**Sample record 3 (raw):**
[all lines]

**Recommended next steps:**
  /pdf-to-csv-scaffold [project-name] [pdf-url-or-local]
  /pdf-to-csv-parse (keep this analysis in context)
```
