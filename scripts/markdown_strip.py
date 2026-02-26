"""Deterministic markdown-to-prose conversion for the normalize stage.

Strips all markdown formatting and converts structured elements (lists, tables,
code blocks, headers) into clean prose that segments reliably on sentence boundaries.

Order of operations:
1. Remove XML tags (<antThinking>, etc.)
2. Remove fenced code blocks (``` ... ```)
3. Remove indented code blocks (4+ space indent with no list context)
4. Convert markdown tables to row-per-sentence prose
5. Convert bullet lists to comma-delimited prose sentences
6. Convert numbered lists to sequential sentences
7. Strip bold/italic markers
8. Strip header markers
9. Strip inline code backticks
10. Strip markdown links, keep link text
11. Collapse excessive whitespace

Each function is a leaf: one transform, no side effects.
"""

import re


# --- 1. XML tags ---

_XML_TAG_BLOCK = re.compile(
    r"<antThinking>.*?</antThinking>",
    re.DOTALL,
)

_GENERIC_XML_TAG = re.compile(r"</?[a-zA-Z][^>]*>")


def strip_xml_tags(text: str) -> str:
    """Remove <antThinking>...</antThinking> blocks and stray XML tags."""
    text = _XML_TAG_BLOCK.sub("", text)
    text = _GENERIC_XML_TAG.sub("", text)
    return text


# --- 2. Fenced code blocks ---

_FENCED_CODE = re.compile(r"```[^\n]*\n.*?```", re.DOTALL)


def strip_fenced_code(text: str) -> str:
    """Remove fenced code blocks (``` ... ```)."""
    return _FENCED_CODE.sub("", text)


# --- 3. Indented code blocks ---

_INDENTED_CODE_LINE = re.compile(r"^(    |\t)\S", re.MULTILINE)


def strip_indented_code(text: str) -> str:
    """Remove lines that look like indented code blocks.

    Only removes lines starting with 4+ spaces or tab WHEN preceded by a blank line
    (standard markdown indented code). Does not strip indented list continuations.
    """
    lines = text.split("\n")
    result = []
    in_code_block = False

    for i, line in enumerate(lines):
        stripped = line.lstrip()
        indent = len(line) - len(stripped)

        # Detect indented code: 4+ spaces/tab after a blank line, not a list item
        is_blank_before = (i == 0) or (result and result[-1].strip() == "")
        is_indented = indent >= 4 or line.startswith("\t")
        is_list_continuation = bool(re.match(r"^\s+[-*]\s", line)) or bool(re.match(r"^\s+\d+\.\s", line))

        if is_indented and is_blank_before and not is_list_continuation and stripped:
            in_code_block = True
            continue
        elif in_code_block and is_indented and not is_list_continuation:
            continue
        else:
            in_code_block = False
            result.append(line)

    return "\n".join(result)


# --- 4. Markdown tables ---

_TABLE_ROW = re.compile(r"^\|(.+)\|$")
_SEPARATOR_ROW = re.compile(r"^\|[\s:|-]+\|$")


def _parse_table(lines: list[str]) -> tuple[list[str], list[list[str]]]:
    """Parse a markdown table into headers and data rows."""
    headers: list[str] = []
    rows: list[list[str]] = []

    for line in lines:
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        if _SEPARATOR_ROW.match(stripped):
            continue

        # Split cells, strip whitespace and <br> tags
        cells = [
            cell.strip().replace("<br>", "; ")
            for cell in stripped.strip("|").split("|")
        ]

        if not headers:
            headers = cells
        else:
            rows.append(cells)

    return headers, rows


def _linearize_table(headers: list[str], rows: list[list[str]]) -> str:
    """Convert table to row-per-sentence prose.

    Each row becomes: "HeaderValue: Column1 is Value1. Column2 is Value2."
    The first column is treated as the row identifier.
    """
    sentences = []
    for row in rows:
        if not row or not any(cell.strip() for cell in row):
            continue

        # First cell is the row label
        row_label = row[0].strip() if row else ""
        parts = []

        for col_idx in range(1, min(len(headers), len(row))):
            header = headers[col_idx].strip()
            value = row[col_idx].strip()
            if value and value != "-" and value != "N/A":
                parts.append(f"{header}: {value}")

        if parts and row_label:
            sentences.append(f"{row_label} -- {'. '.join(parts)}.")
        elif parts:
            sentences.append(f"{'. '.join(parts)}.")

    return " ".join(sentences)


def convert_tables(text: str) -> str:
    """Find and convert all markdown tables in text to prose."""
    lines = text.split("\n")
    result_lines = []
    table_lines: list[str] = []
    in_table = False

    for line in lines:
        stripped = line.strip()
        is_table_line = stripped.startswith("|") and stripped.endswith("|") and stripped.count("|") >= 3

        if is_table_line:
            in_table = True
            table_lines.append(line)
        else:
            if in_table and table_lines:
                # Flush accumulated table
                headers, rows = _parse_table(table_lines)
                if headers and rows:
                    prose = _linearize_table(headers, rows)
                    result_lines.append(prose)
                else:
                    # Malformed table, keep as-is
                    result_lines.extend(table_lines)
                table_lines = []
                in_table = False
            result_lines.append(line)

    # Flush any trailing table
    if table_lines:
        headers, rows = _parse_table(table_lines)
        if headers and rows:
            prose = _linearize_table(headers, rows)
            result_lines.append(prose)
        else:
            result_lines.extend(table_lines)

    return "\n".join(result_lines)


# --- 5. Bullet lists ---

_BULLET_ITEM = re.compile(r"^(\s*)([-*])\s+(.+)$")


def _collect_list_block(lines: list[str], start: int) -> tuple[list[str], str, int]:
    """Collect consecutive bullet list items starting at `start`.

    Returns (item_texts, lead_in_text, end_index).
    lead_in_text is the line before the list if it ends with a colon.
    """
    items = []
    idx = start

    # Check if previous line is a lead-in ending with colon
    lead_in = ""
    if start > 0:
        prev = lines[start - 1].strip()
        if prev.endswith(":"):
            lead_in = prev.rstrip(":")

    while idx < len(lines):
        match = _BULLET_ITEM.match(lines[idx])
        if match:
            items.append(match.group(3).strip())
            idx += 1
        elif lines[idx].strip() == "":
            # Blank line might separate list groups
            if idx + 1 < len(lines) and _BULLET_ITEM.match(lines[idx + 1]):
                idx += 1  # skip blank, continue collecting
            else:
                break
        elif lines[idx].startswith("  ") and items:
            # Continuation line (indented under previous item)
            items[-1] += " " + lines[idx].strip()
            idx += 1
        else:
            break

    return items, lead_in, idx


def convert_bullet_lists(text: str) -> str:
    """Convert bullet lists to comma-delimited prose sentences.

    "Key features:\n- A\n- B\n- C" -> "Key features: A, B, and C."
    """
    lines = text.split("\n")
    result_lines = []
    idx = 0

    while idx < len(lines):
        if _BULLET_ITEM.match(lines[idx]):
            items, lead_in, end_idx = _collect_list_block(lines, idx)
            if items:
                prose = _join_list_items(items, lead_in)
                # Remove the lead-in line if we consumed it
                if lead_in and result_lines and result_lines[-1].strip().rstrip(":") == lead_in:
                    result_lines.pop()
                result_lines.append(prose)
            idx = end_idx
        else:
            result_lines.append(lines[idx])
            idx += 1

    return "\n".join(result_lines)


def _join_list_items(items: list[str], lead_in: str) -> str:
    """Join list items into a prose sentence with Oxford comma."""
    # Strip trailing punctuation from items for clean joining
    cleaned = []
    for item in items:
        item = item.rstrip(".")
        cleaned.append(item)

    if len(cleaned) == 1:
        joined = cleaned[0]
    elif len(cleaned) == 2:
        joined = f"{cleaned[0]} and {cleaned[1]}"
    else:
        joined = ", ".join(cleaned[:-1]) + f", and {cleaned[-1]}"

    if lead_in:
        return f"{lead_in}: {joined}."
    return f"{joined}."


# --- 6. Numbered lists ---

_NUMBERED_ITEM = re.compile(r"^(\s*)(\d+)\.\s+(.+)$")


def convert_numbered_lists(text: str) -> str:
    """Convert numbered lists to sequential sentences.

    "1. Do A\n2. Do B\n3. Do C" -> "Do A. Do B. Do C."

    If preceded by a lead-in with colon, include it:
    "Steps:\n1. Do A\n2. Do B" -> "Steps: Do A. Do B."
    """
    lines = text.split("\n")
    result_lines = []
    idx = 0

    while idx < len(lines):
        match = _NUMBERED_ITEM.match(lines[idx])
        if match:
            items = []
            lead_in = ""

            # Check lead-in
            if result_lines and result_lines[-1].strip().endswith(":"):
                lead_in = result_lines[-1].strip().rstrip(":")
                result_lines.pop()

            while idx < len(lines):
                m = _NUMBERED_ITEM.match(lines[idx])
                if m:
                    items.append(m.group(3).strip())
                    idx += 1
                elif lines[idx].strip() == "" and idx + 1 < len(lines) and _NUMBERED_ITEM.match(lines[idx + 1]):
                    idx += 1  # skip blank between numbered items
                elif lines[idx].startswith("  ") and items:
                    # Continuation line
                    items[-1] += " " + lines[idx].strip()
                    idx += 1
                else:
                    break

            # Join into sentences
            joined_items = []
            for item in items:
                # Ensure each item ends with sentence punctuation
                item = item.rstrip(".")
                joined_items.append(item)

            if lead_in:
                result_lines.append(f"{lead_in}: {'. '.join(joined_items)}.")
            else:
                result_lines.append(f"{'. '.join(joined_items)}.")
        else:
            result_lines.append(lines[idx])
            idx += 1

    return "\n".join(result_lines)


# --- 7. Bold/italic ---

_BOLD = re.compile(r"\*\*([^*]+)\*\*")
_ITALIC = re.compile(r"(?<!\*)\*([^*]+)\*(?!\*)")
_ORPHANED_DOUBLE_ASTERISK = re.compile(r"\*\*")


def strip_bold_italic(text: str) -> str:
    """Remove bold (**text**) and italic (*text*) markers, keep content."""
    text = _BOLD.sub(r"\1", text)
    text = _ITALIC.sub(r"\1", text)
    text = _ORPHANED_DOUBLE_ASTERISK.sub("", text)
    return text


# --- 8. Headers ---

_HEADER = re.compile(r"^#{1,6}\s+", re.MULTILINE)


def strip_headers(text: str) -> str:
    """Remove markdown header markers (# through ######), keep text."""
    return _HEADER.sub("", text)


# --- 9. Inline code ---

_INLINE_CODE = re.compile(r"`([^`]+)`")


def strip_inline_code(text: str) -> str:
    """Remove backtick markers from inline code, keep content."""
    return _INLINE_CODE.sub(r"\1", text)


# --- 10. Links ---

_LINK = re.compile(r"\[([^\]]+)\]\([^)]+\)")


def strip_links(text: str) -> str:
    """Remove markdown link syntax, keep link text."""
    return _LINK.sub(r"\1", text)


# --- 11. Whitespace collapse ---

def collapse_whitespace(text: str) -> str:
    """Collapse multiple blank lines to single blank, strip trailing spaces."""
    # Collapse 3+ newlines to 2 (one blank line)
    text = re.sub(r"\n{3,}", "\n\n", text)
    # Strip trailing spaces per line
    text = "\n".join(line.rstrip() for line in text.split("\n"))
    return text.strip()


# --- Orchestrator ---

def strip_markdown(text: str) -> str:
    """Full markdown-to-prose pipeline. Deterministic, no LLM.

    Input: raw text potentially containing markdown formatting.
    Output: clean prose suitable for sentence segmentation.
    """
    text = strip_xml_tags(text)
    text = strip_fenced_code(text)
    text = strip_indented_code(text)
    text = convert_tables(text)
    text = convert_bullet_lists(text)
    text = convert_numbered_lists(text)
    text = strip_bold_italic(text)
    text = strip_headers(text)
    text = strip_inline_code(text)
    text = strip_links(text)
    text = collapse_whitespace(text)
    return text
