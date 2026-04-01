from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import yaml

DEFAULT_SIGNATURE_PATH = Path(__file__).with_name("issue-signature.yml")
SECTION_HEADER_RE = re.compile(r"^##\s+(.+?)\s*$")
CHECKBOX_ITEM_RE = re.compile(r"^\s*[-*]\s+\[[ xX]\]\s+")
BULLET_ITEM_RE = re.compile(r"^\s*[-*]\s+")


def normalize_heading(value: str) -> str:
    lowered = (value or "").strip().lower().replace("&", " and ")
    lowered = re.sub(r"[^a-z0-9]+", " ", lowered)
    return " ".join(lowered.split())


def _normalize_multiline(value: str) -> str:
    return "\n".join(line.rstrip() for line in (value or "").strip().splitlines()).strip()


def _coerce_lines(section: dict[str, Any]) -> list[str]:
    lines = [str(item).rstrip() for item in section.get("placeholder_lines", []) if str(item).strip()]
    if lines:
        return lines
    title = section["title"]
    if section.get("kind") == "checklist":
        return [f"- [ ] Add at least one concrete item under {title}."]
    if section.get("kind") == "bullets":
        return [f"- Add at least one concrete item under {title}."]
    return [f"_Add concrete content for {title}._"]


def load_signature(config_path: str | Path | None = None) -> dict[str, Any]:
    path = Path(config_path) if config_path else DEFAULT_SIGNATURE_PATH
    raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    sections = []
    aliases: dict[str, str] = {}
    by_id: dict[str, dict[str, Any]] = {}
    managed_blocks: list[dict[str, Any]] = []
    for raw_block in raw.get("managed_blocks", []):
        managed_blocks.append(dict(raw_block))
    for raw_section in raw.get("sections", []):
        section = dict(raw_section)
        section["required"] = bool(section.get("required", False))
        section["todo_required"] = bool(section.get("todo_required", section.get("required", False)))
        section["kind"] = section.get("kind", "text")
        section["min_items"] = int(section.get("min_items", 0))
        section["placeholder_lines"] = _coerce_lines(section)
        section_aliases = [section["title"], *section.get("aliases", [])]
        for alias in section_aliases:
            aliases[normalize_heading(alias)] = section["id"]
        sections.append(section)
        by_id[section["id"]] = section
    return {
        "path": str(path),
        "version": raw.get("version", 1),
        "sections": sections,
        "section_by_id": by_id,
        "aliases": aliases,
        "managed_blocks": managed_blocks,
        "todo_gate": raw.get("todo_gate", {}),
    }


def get_managed_block_markers(signature: dict[str, Any], name: str) -> tuple[str, str]:
    for block in signature.get("managed_blocks", []):
        if block.get("name") == name:
            return block["start"], block["end"]
    raise KeyError(f"Managed block '{name}' was not found in the issue signature.")


def split_managed_blocks(body: str, signature: dict[str, Any]) -> tuple[list[str], str]:
    working = body or ""
    extracted: list[str] = []
    for block in signature.get("managed_blocks", []):
        pattern = re.compile(
            re.escape(block["start"]) + r".*?" + re.escape(block["end"]),
            re.DOTALL,
        )
        matches = list(pattern.finditer(working))
        for match in matches:
            extracted.append(match.group(0).strip())
        working = pattern.sub("\n", working)
    working = re.sub(r"\n{3,}", "\n\n", working).strip()
    return extracted, working


def parse_issue_body(body: str, signature: dict[str, Any]) -> dict[str, Any]:
    managed_blocks, working = split_managed_blocks(body, signature)
    preamble_lines: list[str] = []
    sections: list[dict[str, str]] = []
    current_title: str | None = None
    current_lines: list[str] = []

    def flush_current() -> None:
        nonlocal current_title, current_lines
        if current_title is None:
            return
        sections.append(
            {
                "title": current_title,
                "content": _normalize_multiline("\n".join(current_lines)),
            }
        )
        current_title = None
        current_lines = []

    for raw_line in working.splitlines():
        match = SECTION_HEADER_RE.match(raw_line.strip())
        if match:
            flush_current()
            current_title = match.group(1).strip()
            continue
        if current_title is None:
            preamble_lines.append(raw_line)
        else:
            current_lines.append(raw_line)
    flush_current()

    recognized_values: dict[str, str] = {}
    recognized_sequence: list[dict[str, str]] = []
    extras: list[dict[str, str]] = []
    for section in sections:
        section_id = signature["aliases"].get(normalize_heading(section["title"]))
        if section_id:
            recognized_sequence.append({"id": section_id, "title": section["title"]})
            existing = recognized_values.get(section_id, "")
            content = section["content"]
            if existing and content:
                recognized_values[section_id] = f"{existing}\n\n{content}".strip()
            elif content:
                recognized_values[section_id] = content
            else:
                recognized_values.setdefault(section_id, "")
        else:
            extras.append(section)

    preamble = _normalize_multiline("\n".join(preamble_lines))
    if preamble:
        context = recognized_values.get("context", "")
        recognized_values["context"] = f"{preamble}\n\n{context}".strip() if context else preamble

    return {
        "managedBlocks": managed_blocks,
        "sectionValues": recognized_values,
        "recognizedSequence": recognized_sequence,
        "extraSections": extras,
        "preamble": preamble,
    }


def _coerce_section_content(section: dict[str, Any], value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return _normalize_multiline(value)
    if isinstance(value, list):
        cleaned = [str(item).strip() for item in value if str(item).strip()]
        if not cleaned:
            return ""
        if section["kind"] == "checklist":
            return "\n".join(item if CHECKBOX_ITEM_RE.match(item) else f"- [ ] {item}" for item in cleaned)
        if section["kind"] == "bullets":
            return "\n".join(item if BULLET_ITEM_RE.match(item) else f"- {item}" for item in cleaned)
        return "\n\n".join(cleaned)
    return _normalize_multiline(str(value))


def render_placeholder_content(section: dict[str, Any]) -> str:
    return "\n".join(section.get("placeholder_lines", []))


def render_signature_sections(
    section_values: dict[str, Any],
    signature: dict[str, Any],
    *,
    include_optional_absent: bool = False,
) -> str:
    rendered_sections: list[str] = []
    for section in signature["sections"]:
        content = _coerce_section_content(section, section_values.get(section["id"]))
        if not content and not section["required"] and not include_optional_absent:
            continue
        if not content:
            content = render_placeholder_content(section)
        rendered_sections.append(f"## {section['title']}\n{content}".rstrip())
    return "\n\n".join(rendered_sections).rstrip() + ("\n" if rendered_sections else "")


def format_issue_body(
    body: str,
    signature: dict[str, Any],
    *,
    include_optional_absent: bool = False,
) -> str:
    parsed = parse_issue_body(body, signature)
    rendered_parts: list[str] = []
    if parsed["managedBlocks"]:
        rendered_parts.append("\n\n".join(parsed["managedBlocks"]).rstrip())

    rendered_sections = render_signature_sections(
        parsed["sectionValues"],
        signature,
        include_optional_absent=include_optional_absent,
    ).rstrip()
    if rendered_sections:
        rendered_parts.append(rendered_sections)

    for extra in parsed["extraSections"]:
        title = extra["title"].strip()
        content = extra["content"].strip()
        if title:
            extra_block = f"## {title}"
            if content:
                extra_block += f"\n{content}"
            rendered_parts.append(extra_block.rstrip())

    return "\n\n".join(part for part in rendered_parts if part.strip()).rstrip() + ("\n" if rendered_parts else "")


def upsert_managed_block(body: str, block_content: str, signature: dict[str, Any], *, block_name: str = "intake") -> str:
    start, end = get_managed_block_markers(signature, block_name)
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.DOTALL)
    working = body or ""
    if pattern.search(working):
        updated = pattern.sub(block_content.rstrip(), working, count=1)
    elif working.strip():
        updated = block_content.rstrip() + "\n\n" + working.strip()
    else:
        updated = block_content.rstrip()
    return updated.rstrip() + "\n"


def _matches_placeholder(section: dict[str, Any], content: str) -> bool:
    return _normalize_multiline(content) == _normalize_multiline(render_placeholder_content(section))


def _count_items(content: str, kind: str) -> int:
    matcher = CHECKBOX_ITEM_RE if kind == "checklist" else BULLET_ITEM_RE
    return sum(1 for line in (content or "").splitlines() if matcher.match(line))


def summarize_signature_issues(report: dict[str, Any]) -> str:
    details: list[str] = []
    if report["missingRequired"]:
        details.append("missing " + ", ".join(report["missingRequired"]))
    if report["placeholderSections"]:
        details.append("placeholders in " + ", ".join(report["placeholderSections"]))
    if report["invalidChecklistSections"]:
        details.append("checklists in " + ", ".join(report["invalidChecklistSections"]))
    return "; ".join(details)


def _needs_structural_formatting(parsed: dict[str, Any], signature: dict[str, Any]) -> bool:
    observed_order: list[str] = []
    canonical_titles = {section["id"]: section["title"] for section in signature["sections"]}

    for entry in parsed["recognizedSequence"]:
        section_id = entry["id"]
        if section_id not in observed_order:
            observed_order.append(section_id)
        if entry["title"] != canonical_titles[section_id]:
            return True

    canonical_order = [section["id"] for section in signature["sections"] if section["id"] in observed_order]
    return observed_order != canonical_order


def evaluate_issue_body(body: str, signature: dict[str, Any]) -> dict[str, Any]:
    parsed = parse_issue_body(body, signature)
    missing_required: list[str] = []
    placeholder_sections: list[str] = []
    invalid_checklists: list[str] = []
    present_sections: list[str] = []
    section_reports: dict[str, dict[str, Any]] = {}

    required_ids = list(signature.get("todo_gate", {}).get("required_sections", []))
    if not required_ids:
        required_ids = [section["id"] for section in signature["sections"] if section["required"]]

    for section in signature["sections"]:
        content = parsed["sectionValues"].get(section["id"], "").strip()
        present = bool(content)
        placeholder = _matches_placeholder(section, content) if present else False
        item_count = _count_items(content, section["kind"]) if present and section["kind"] in {"checklist", "bullets"} else 0
        min_items = section.get("min_items", 0)
        invalid_checklist = bool(
            present
            and section["kind"] == "checklist"
            and not placeholder
            and min_items
            and item_count < min_items
        )

        if present:
            present_sections.append(section["title"])
        if section["id"] in required_ids and not present:
            missing_required.append(section["title"])
        if section["id"] in required_ids and placeholder:
            placeholder_sections.append(section["title"])
        if section["id"] in required_ids and invalid_checklist:
            invalid_checklists.append(section["title"])

        section_reports[section["id"]] = {
            "title": section["title"],
            "present": present,
            "placeholder": placeholder,
            "kind": section["kind"],
            "minItems": min_items,
            "itemCount": item_count,
            "requiredForTodo": section["id"] in required_ids,
        }

    formatted_body = format_issue_body(body, signature)
    ready_for_todo = not missing_required and not placeholder_sections and not invalid_checklists

    report = {
        "readyForTodo": ready_for_todo,
        "requiredSections": [signature["section_by_id"][section_id]["title"] for section_id in required_ids],
        "presentSections": present_sections,
        "missingRequired": missing_required,
        "placeholderSections": placeholder_sections,
        "invalidChecklistSections": invalid_checklists,
        "extraSections": [section["title"] for section in parsed["extraSections"]],
        "managedBlockCount": len(parsed["managedBlocks"]),
        "managedBlockNames": [block.splitlines()[0] for block in parsed["managedBlocks"]],
        "needsFormatting": _needs_structural_formatting(parsed, signature),
        "summary": "",
        "sectionReports": section_reports,
        "formattedBody": formatted_body,
    }
    report["summary"] = "ready" if ready_for_todo else summarize_signature_issues(report)
    return report
