"""Tests for markdown_strip.py deterministic text cleaning rules.

Each test covers one transform function. Tests use real patterns
found in the 33 golden source files.
"""

import pytest
from markdown_strip import (
    strip_xml_tags,
    strip_fenced_code,
    strip_indented_code,
    convert_tables,
    convert_bullet_lists,
    convert_numbered_lists,
    strip_bold_italic,
    strip_headers,
    strip_inline_code,
    strip_links,
    collapse_whitespace,
    strip_markdown,
)


# --- strip_xml_tags ---

class TestStripXmlTags:
    def test_removes_ant_thinking_block(self):
        text = "Before.\n\n<antThinking>This is internal reasoning.</antThinking>\n\nAfter."
        assert "<antThinking>" not in strip_xml_tags(text)
        assert "Before." in strip_xml_tags(text)
        assert "After." in strip_xml_tags(text)

    def test_removes_multiline_ant_thinking(self):
        text = "Start.\n<antThinking>\nLine one.\nLine two.\n</antThinking>\nEnd."
        result = strip_xml_tags(text)
        assert "Line one" not in result
        assert "Start." in result
        assert "End." in result

    def test_preserves_text_without_tags(self):
        text = "No tags here. Just plain text."
        assert strip_xml_tags(text) == text


# --- strip_fenced_code ---

class TestStripFencedCode:
    def test_removes_fenced_code_block(self):
        text = "Before.\n\n```python\ndef foo():\n    pass\n```\n\nAfter."
        result = strip_fenced_code(text)
        assert "def foo" not in result
        assert "Before." in result
        assert "After." in result

    def test_removes_fenced_code_without_language(self):
        text = "Before.\n\n```\nsome code\n```\n\nAfter."
        result = strip_fenced_code(text)
        assert "some code" not in result

    def test_preserves_text_without_code(self):
        text = "No code blocks here."
        assert strip_fenced_code(text) == text


# --- strip_indented_code ---

class TestStripIndentedCode:
    def test_removes_indented_code_after_blank_line(self):
        text = "Before.\n\n    int x = 5;\n    return x;\n\nAfter."
        result = strip_indented_code(text)
        assert "int x" not in result
        assert "After." in result

    def test_preserves_indented_list_continuations(self):
        text = "- Item one\n  continued here\n- Item two"
        result = strip_indented_code(text)
        assert "continued here" in result

    def test_preserves_normal_text(self):
        text = "Normal paragraph.\n\nAnother paragraph."
        assert strip_indented_code(text) == text


# --- convert_tables ---

class TestConvertTables:
    def test_simple_two_column_table(self):
        text = (
            "| Name | Age |\n"
            "|------|-----|\n"
            "| Alice | 30 |\n"
            "| Bob | 25 |"
        )
        result = convert_tables(text)
        assert "Alice" in result
        assert "Age: 30" in result
        assert "Bob" in result
        assert "Age: 25" in result
        assert "|" not in result

    def test_multi_column_table_from_golden_data(self):
        text = (
            "| Approach | Timeline | Cost |\n"
            "|----------|----------|------|\n"
            "| HOA Transformation | 3-5 years | Low-Medium |\n"
            "| Greenfield Development | 5-10 years | Very High |"
        )
        result = convert_tables(text)
        assert "HOA Transformation" in result
        assert "Timeline: 3-5 years" in result
        assert "Cost: Low-Medium" in result
        assert "Greenfield Development" in result
        assert "|" not in result

    def test_table_with_br_tags(self):
        text = (
            "| Metric | Human |\n"
            "|--------|-------|\n"
            "| Speed | Voice: ~150 wpm<br>Typing: ~40 wpm |"
        )
        result = convert_tables(text)
        # <br> tags should become semicolons
        assert "Voice: ~150 wpm; Typing: ~40 wpm" in result
        assert "<br>" not in result

    def test_preserves_text_around_table(self):
        text = "Before the table.\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\nAfter the table."
        result = convert_tables(text)
        assert "Before the table." in result
        assert "After the table." in result

    def test_no_table_passthrough(self):
        text = "No tables here. Just pipe | characters in text."
        assert convert_tables(text) == text


# --- convert_bullet_lists ---

class TestConvertBulletLists:
    def test_simple_bullet_list(self):
        text = "- Alpha\n- Beta\n- Gamma"
        result = convert_bullet_lists(text)
        assert "Alpha, Beta, and Gamma." in result
        assert "-" not in result.replace("- ", "")  # no stray dashes

    def test_bullet_list_with_lead_in(self):
        text = "Key features:\n- Fast\n- Reliable\n- Cheap"
        result = convert_bullet_lists(text)
        assert "Key features: Fast, Reliable, and Cheap." in result

    def test_single_bullet_item(self):
        text = "- Only one item"
        result = convert_bullet_lists(text)
        assert "Only one item." in result

    def test_two_bullet_items(self):
        text = "- First\n- Second"
        result = convert_bullet_lists(text)
        assert "First and Second." in result

    def test_nested_bullet_list_with_sub_items(self):
        """Sub-items indented under a bullet are continuation text."""
        text = "- Main item\n  with continuation\n- Second item"
        result = convert_bullet_lists(text)
        assert "Main item with continuation" in result

    def test_asterisk_bullets(self):
        text = "* Alpha\n* Beta"
        result = convert_bullet_lists(text)
        assert "Alpha and Beta." in result

    def test_preserves_surrounding_text(self):
        text = "Intro paragraph.\n\n- A\n- B\n\nOutro paragraph."
        result = convert_bullet_lists(text)
        assert "Intro paragraph." in result
        assert "Outro paragraph." in result


# --- convert_numbered_lists ---

class TestConvertNumberedLists:
    def test_simple_numbered_list(self):
        text = "1. First step\n2. Second step\n3. Third step"
        result = convert_numbered_lists(text)
        assert "First step." in result
        assert "Second step." in result
        assert "Third step." in result
        # No bare numbers at start of lines
        assert not any(line.strip().startswith("1.") for line in result.split("\n") if line.strip())

    def test_numbered_list_with_lead_in(self):
        text = "Steps to follow:\n1. Do A\n2. Do B\n3. Do C"
        result = convert_numbered_lists(text)
        assert "Steps to follow: Do A. Do B. Do C." in result

    def test_preserves_surrounding_text(self):
        text = "Before.\n\n1. Item\n2. Item\n\nAfter."
        result = convert_numbered_lists(text)
        assert "Before." in result
        assert "After." in result

    def test_numbered_list_with_continuation(self):
        text = "1. First item\n  with more detail\n2. Second item"
        result = convert_numbered_lists(text)
        assert "First item with more detail" in result


# --- strip_bold_italic ---

class TestStripBoldItalic:
    def test_strips_bold(self):
        assert strip_bold_italic("This is **bold** text.") == "This is bold text."

    def test_strips_italic(self):
        assert strip_bold_italic("This is *italic* text.") == "This is italic text."

    def test_strips_both(self):
        result = strip_bold_italic("**Bold** and *italic* text.")
        assert result == "Bold and italic text."

    def test_preserves_plain_text(self):
        text = "No formatting here."
        assert strip_bold_italic(text) == text

    def test_strips_orphaned_double_asterisks(self):
        """STT artifacts and truncated bold produce unmatched ** markers."""
        text = "alright ** fine let's move on"
        assert "**" not in strip_bold_italic(text)

    def test_strips_trailing_orphaned_bold(self):
        text = "Feature modules**: ui, transcript"
        assert "**" not in strip_bold_italic(text)


# --- strip_headers ---

class TestStripHeaders:
    def test_strips_h1(self):
        assert strip_headers("# Title").strip() == "Title"

    def test_strips_h3(self):
        assert strip_headers("### Section Name").strip() == "Section Name"

    def test_strips_mixed_headers(self):
        text = "# Title\n\nParagraph.\n\n## Section\n\nMore text."
        result = strip_headers(text)
        assert "# " not in result
        assert "## " not in result
        assert "Title" in result
        assert "Section" in result


# --- strip_inline_code ---

class TestStripInlineCode:
    def test_strips_backticks(self):
        assert strip_inline_code("Use `ObjectBox` for storage.") == "Use ObjectBox for storage."

    def test_multiple_inline_code(self):
        text = "Both `foo` and `bar` are used."
        assert strip_inline_code(text) == "Both foo and bar are used."

    def test_preserves_plain_text(self):
        text = "No code here."
        assert strip_inline_code(text) == text


# --- strip_links ---

class TestStripLinks:
    def test_strips_markdown_link(self):
        assert strip_links("See [the docs](https://example.com) for details.") == "See the docs for details."

    def test_multiple_links(self):
        text = "[A](url1) and [B](url2)."
        assert strip_links(text) == "A and B."


# --- collapse_whitespace ---

class TestCollapseWhitespace:
    def test_collapses_triple_newlines(self):
        text = "A.\n\n\n\nB."
        assert collapse_whitespace(text) == "A.\n\nB."

    def test_strips_trailing_spaces(self):
        text = "Line one.   \nLine two.  "
        result = collapse_whitespace(text)
        assert not any(line.endswith(" ") for line in result.split("\n"))

    def test_strips_leading_trailing_whitespace(self):
        text = "\n\n  Content.  \n\n"
        result = collapse_whitespace(text)
        assert result == "Content."


# --- strip_markdown (orchestrator) ---

class TestStripMarkdown:
    def test_combined_formatting(self):
        text = "## **Important Section**\n\nUse `ObjectBox` for *fast* storage."
        result = strip_markdown(text)
        assert "#" not in result
        assert "**" not in result
        assert "*" not in result.replace("fast", "")  # italic marker gone
        assert "`" not in result
        assert "Important Section" in result
        assert "ObjectBox" in result

    def test_real_golden_data_pattern(self):
        """Pattern from actual golden source: antThinking + bullet list + bold."""
        text = (
            "<antThinking>Planning notes here.</antThinking>\n\n"
            "Key changes include:\n\n"
            "1. **Maintenance Infrastructure**:\n"
            "   - 15,000 sq ft facility\n"
            "   - Full service capabilities\n\n"
            "2. **Quality Standards**:\n"
            "   - Clear vehicle age parameters\n"
            "   - Rigorous maintenance schedules"
        )
        result = strip_markdown(text)
        # antThinking gone
        assert "Planning notes" not in result
        # Bold markers gone
        assert "**" not in result
        # Content preserved
        assert "15,000 sq ft facility" in result
        assert "Maintenance Infrastructure" in result
        # List structure converted to prose
        assert result.endswith(".")

    def test_table_in_context(self):
        text = (
            "Here is a comparison:\n\n"
            "| Feature | Cost |\n"
            "|---------|------|\n"
            "| Basic | $10 |\n"
            "| Premium | $50 |\n\n"
            "Choose wisely."
        )
        result = strip_markdown(text)
        assert "|" not in result
        assert "Basic" in result
        assert "Cost: $10" in result
        assert "Choose wisely." in result

    def test_max_sentence_words_after_strip(self):
        """After stripping, no period-delimited segment should exceed 50 words.

        This is the heuristic that originally failed on bullet lists.
        """
        text = (
            "4. Special Circumstances provisions for:\n"
            "   - Medical necessity\n"
            "   - Family emergencies\n"
            "   - Educational opportunities\n"
            "   - Community service projects\n\n"
            "This system aims to balance:\n"
            "- Individual freedom for longer trips\n"
            "- Fair access to limited resources\n"
            "- Community needs for local transportation\n"
            "- Environmental considerations\n"
            "- System sustainability"
        )
        result = strip_markdown(text)
        sentences = [s.strip() for s in result.split(".") if s.strip()]
        for sentence in sentences:
            word_count = len(sentence.split())
            assert word_count <= 50, f"Sentence has {word_count} words: {sentence[:80]}..."


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
