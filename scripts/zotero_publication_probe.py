#!/usr/bin/env python3
"""Probe one Zotero publication item robustly for site enrichment.

The Zotero local API is fast and useful for item metadata, citations and
BibTeX. Indexed attachment full text is not always available, so this script
falls back to the attachment file URL and extracts PDF text locally when pypdf
is installed.
"""

from __future__ import annotations

import argparse
import contextlib
import html
import io
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_BASE_URL = "http://127.0.0.1:23119"
API_HEADERS = {"Zotero-API-Version": "3"}


def request(base_url: str, path: str, timeout: float) -> dict[str, Any]:
    started = time.time()
    url = base_url.rstrip("/") + path
    try:
        req = urllib.request.Request(url, headers=API_HEADERS)
        with urllib.request.urlopen(req, timeout=timeout) as response:
            text = response.read().decode("utf-8", errors="replace")
            return {
                "ok": 200 <= response.status < 300,
                "status": response.status,
                "content_type": response.headers.get("Content-Type", ""),
                "text": text,
                "seconds": round(time.time() - started, 3),
                "url": url,
            }
    except urllib.error.HTTPError as exc:
        return {
            "ok": False,
            "status": exc.code,
            "content_type": exc.headers.get("Content-Type", ""),
            "text": exc.read().decode("utf-8", errors="replace"),
            "seconds": round(time.time() - started, 3),
            "url": url,
            "error": str(exc),
        }
    except Exception as exc:
        return {
            "ok": False,
            "status": None,
            "content_type": "",
            "text": "",
            "seconds": round(time.time() - started, 3),
            "url": url,
            "error": f"{type(exc).__name__}: {exc}",
        }


def parse_json(response: dict[str, Any]) -> Any:
    if "json" not in response.get("content_type", "").lower():
        return None
    try:
        return json.loads(response.get("text") or "null")
    except json.JSONDecodeError:
        return None


def creators_from_item(item: dict[str, Any]) -> list[str]:
    data = item.get("data", item)
    creators = []
    for creator in data.get("creators", []) or []:
        name = creator.get("name")
        if not name:
            name = " ".join(
                part for part in [creator.get("firstName"), creator.get("lastName")] if part
            )
        if name:
            creators.append(name)
    return creators


def summarize_item(item: dict[str, Any]) -> dict[str, Any]:
    data = item.get("data", item)
    date = data.get("date") or ""
    year_match = re.search(r"\d{4}", date)
    return {
        "key": item.get("key") or data.get("key"),
        "itemType": data.get("itemType"),
        "title": data.get("title"),
        "creators": creators_from_item(item),
        "year": year_match.group(0) if year_match else None,
        "doi": data.get("DOI"),
        "url": data.get("url"),
        "abstract": data.get("abstractNote"),
    }


def words(value: str) -> set[str]:
    return {
        part
        for part in re.sub(r"[^a-z0-9]+", " ", value.lower()).split()
        if len(part) > 2
    }


def best_search_match(query: str, items: list[dict[str, Any]]) -> dict[str, Any] | None:
    query_words = words(query)
    best_score = 0.0
    best_item = None
    for item in items:
        title_words = words((item.get("data") or {}).get("title") or item.get("title") or "")
        if not query_words or not title_words:
            continue
        matched = len(query_words & title_words)
        score = max(matched / len(query_words), matched / len(query_words | title_words))
        if score > best_score:
            best_score = score
            best_item = item
    return best_item if best_score >= 0.5 else None


def pdf_text(path: Path, pages: int) -> dict[str, Any]:
    try:
        from pypdf import PdfReader
    except Exception as exc:
        return {"ok": False, "error": f"pypdf unavailable: {exc}"}

    try:
        warnings = io.StringIO()
        with contextlib.redirect_stderr(warnings):
            reader = PdfReader(str(path))
            chunks = []
            for page in reader.pages[:pages]:
                chunks.append(page.extract_text() or "")
        text = "\n".join(chunks).strip()
        return {
            "ok": True,
            "pages_total": len(reader.pages),
            "pages_read": pages,
            "warnings": warnings.getvalue().splitlines()[:8],
            "text": text,
        }
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def file_url_to_path(url: str) -> Path | None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "file":
        return None
    return Path(urllib.parse.unquote(parsed.path))


def text_excerpt(text: str, limit: int) -> str:
    return re.sub(r"\s+", " ", text).strip()[:limit]


def clean_pdf_text(text: str) -> str:
    text = re.sub(r"([A-Za-zÄÖÜäöüß])- *\n *([a-zäöüß])", r"\1\2", text)
    text = text.replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def sentence_excerpt(text: str, limit: int = 1000, count: int = 5) -> str:
    compact = re.sub(r"\s+", " ", text).strip()
    compact = re.sub(r"^\d+\s+", "", compact)
    parts = [
        part.strip()
        for part in re.findall(r"[^.!?]+[.!?]+|[^.!?]+\Z", compact)
        if len(part.strip()) >= 25
    ]
    if parts:
        compact = " ".join(parts[:count])
    if len(compact) > limit:
        compact = compact[: limit - 1].rsplit(" ", 1)[0] + "…"
    return compact.strip()


def abstract_candidate(text: str) -> str | None:
    text = clean_pdf_text(text)
    if not text:
        return None

    window = text[:12000]
    marker = re.search(
        r"(?im)(?:^|\n)\s*(?:\d+\s+)?(?:abstract|zusammenfassung)\b\s*[:.]?\s*",
        window,
    )
    if not marker:
        marker = re.search(r"(?i)\b(?:abstract|zusammenfassung)\b\s*[:.]?\s+", window[:2500])
    if not marker:
        return None

    tail = window[marker.end() :]
    stop_patterns = [
        r"(?im)\n\s*(?:keywords?|key words|schl[üu]sselw[öo]rter|stichw[öo]rter)\b",
        r"(?im)\n\s*(?:1\.?\s+)?(?:introduction|einleitung)\b",
        r"(?im)\n\s*\d+\.?\s+[A-ZÄÖÜ][^\n]{3,90}\n",
        r"(?im)\n\s*(?:literatur|references|bibliography)\b",
        r"(?i)\s+I\s+n\s+der\s+",
    ]
    stops = [m.start() for pattern in stop_patterns for m in [re.search(pattern, tail)] if m]
    if stops:
        tail = tail[: min(stops)]

    candidate = sentence_excerpt(tail, limit=1000, count=4)
    if len(candidate) < 80:
        return None
    if candidate.lower().startswith(("keywords", "key words", "schlüsselwörter")):
        return None
    return candidate


def html_to_text(value: str | None) -> str | None:
    if not value:
        return None
    without_spans = re.sub(r"<span\\b[^>]*>.*?</span>", "", value, flags=re.I | re.S)
    without_tags = re.sub(r"<[^>]+>", " ", without_spans)
    text = html.unescape(re.sub(r"\s+", " ", without_tags).strip())
    return re.sub(r"\s+([,.;:])", r"\1", text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--item-key")
    source.add_argument("--query")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--timeout", type=float, default=6.0)
    parser.add_argument("--style", default="apa")
    parser.add_argument("--pdf-pages", type=int, default=2)
    parser.add_argument("--excerpt-chars", type=int, default=2200)
    args = parser.parse_args()

    diagnostics: list[dict[str, Any]] = []

    item_key = args.item_key
    search_results: list[dict[str, Any]] = []
    if args.query:
        params = urllib.parse.urlencode({"q": args.query})
        response = request(args.base_url, f"/api/users/0/items/top?{params}", args.timeout)
        diagnostics.append({"step": "search", **{k: response.get(k) for k in ["status", "seconds", "error", "url"]}})
        if not response["ok"]:
            print(json.dumps({"ok": False, "diagnostics": diagnostics}, indent=2), file=sys.stderr)
            return 2
        raw_items = parse_json(response) or []
        search_results = [summarize_item(item) for item in raw_items]
        match = best_search_match(args.query, raw_items)
        if match is None:
            print(json.dumps({"ok": False, "search_results": search_results, "diagnostics": diagnostics}, indent=2))
            return 1
        item_key = match.get("key")

    assert item_key is not None
    quoted_key = urllib.parse.quote(item_key)

    item_response = request(
        args.base_url,
        f"/api/users/0/items/{quoted_key}?include=data,bib,citation&style={urllib.parse.quote(args.style)}",
        args.timeout,
    )
    diagnostics.append({"step": "item", **{k: item_response.get(k) for k in ["status", "seconds", "error", "url"]}})
    if not item_response["ok"]:
        print(json.dumps({"ok": False, "diagnostics": diagnostics}, indent=2), file=sys.stderr)
        return 2
    item = parse_json(item_response) or {}

    bibtex_response = request(args.base_url, f"/api/users/0/items/{quoted_key}?format=bibtex", args.timeout)
    diagnostics.append({"step": "bibtex", **{k: bibtex_response.get(k) for k in ["status", "seconds", "error", "url"]}})
    bibtex = bibtex_response["text"] if bibtex_response["ok"] else None

    children_response = request(args.base_url, f"/api/users/0/items/{quoted_key}/children", args.timeout)
    diagnostics.append({"step": "children", **{k: children_response.get(k) for k in ["status", "seconds", "error", "url"]}})
    children_raw = parse_json(children_response) if children_response["ok"] else []
    children = [summarize_item(child) for child in (children_raw or [])]

    attachments = []
    for child in children:
        if child.get("itemType") != "attachment":
            continue
        attachment_key = child.get("key")
        if not attachment_key:
            continue
        quoted_attachment = urllib.parse.quote(attachment_key)
        fulltext_response = request(
            args.base_url,
            f"/api/users/0/items/{quoted_attachment}/fulltext",
            args.timeout,
        )
        diagnostics.append(
            {
                "step": f"fulltext:{attachment_key}",
                **{k: fulltext_response.get(k) for k in ["status", "seconds", "error", "url"]},
            }
        )
        fulltext_data = parse_json(fulltext_response) if fulltext_response["ok"] else None
        content = fulltext_data.get("content") if isinstance(fulltext_data, dict) else None

        file_url_response = request(
            args.base_url,
            f"/api/users/0/items/{quoted_attachment}/file/view/url",
            args.timeout,
        )
        diagnostics.append(
            {
                "step": f"file-url:{attachment_key}",
                **{k: file_url_response.get(k) for k in ["status", "seconds", "error", "url"]},
            }
        )
        file_url = file_url_response["text"].strip() if file_url_response["ok"] else None
        local_path = file_url_to_path(file_url) if file_url else None
        extracted = None
        if not content and local_path and local_path.exists() and local_path.suffix.lower() == ".pdf":
            extracted = pdf_text(local_path, args.pdf_pages)
            if extracted.get("ok"):
                content = extracted.get("text")
        pdf_abstract = abstract_candidate(content or "")

        attachments.append(
            {
                **child,
                "indexed_fulltext_available": bool(fulltext_response["ok"] and content),
                "file_url": file_url,
                "file_path": str(local_path) if local_path else None,
                "file_exists": bool(local_path and local_path.exists()),
                "pdf_extract": {k: v for k, v in (extracted or {}).items() if k != "text"} if extracted else None,
                "text_excerpt": text_excerpt(content or "", args.excerpt_chars) if content else None,
                "abstract_candidate": pdf_abstract,
            }
        )

    output = {
        "ok": True,
        "item": summarize_item(item),
        "citation": item.get("citation"),
        "bibliography": item.get("bib"),
        "bibliography_text": html_to_text(item.get("bib")),
        "bibtex": bibtex,
        "search_results": search_results,
        "children": children,
        "attachments": attachments,
        "diagnostics": diagnostics,
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
