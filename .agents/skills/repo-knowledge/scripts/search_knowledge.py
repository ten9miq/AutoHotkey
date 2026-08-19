#!/usr/bin/env python3
"""Search repository knowledge with Python 3.6+ and no third-party packages.

Default mode searches the compact INDEX.md. Use --content to search knowledge
Markdown bodies when the index is insufficient.
"""
from __future__ import print_function

import argparse
import io
import os
import re
import sys


def repo_root():
    here = os.path.abspath(__file__)
    # .agents/skills/repo-knowledge/scripts/search_knowledge.py -> repo root
    return os.path.abspath(os.path.join(os.path.dirname(here), "..", "..", "..", ".."))


def read_text(path):
    with io.open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def normalized_terms(values):
    terms = []
    for value in values:
        for part in re.split(r"\s+", value.strip()):
            if part:
                terms.append(part.lower())
    return terms


def score_text(text, terms):
    lower = text.lower()
    matched = [term for term in terms if term in lower]
    return len(matched), matched


def search_index(index_path, terms, limit):
    if not os.path.isfile(index_path):
        return []
    results = []
    with io.open(index_path, "r", encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, 1):
            if not line.startswith("|") or "---" in line:
                continue
            score, matched = score_text(line, terms)
            if score:
                results.append((score, lineno, line.rstrip("\n"), matched))
    results.sort(key=lambda item: (-item[0], item[1]))
    return results[:limit]


def iter_markdown_files(knowledge_dir):
    for base, dirs, files in os.walk(knowledge_dir):
        dirs[:] = [name for name in dirs if name != "templates"]
        for name in sorted(files):
            if not name.endswith(".md") or name in ("INDEX.md", "README.md"):
                continue
            yield os.path.join(base, name)


def search_content(knowledge_dir, terms, limit):
    results = []
    for path in iter_markdown_files(knowledge_dir):
        text = read_text(path)
        score, matched = score_text(text, terms)
        if score:
            rel = os.path.relpath(path, knowledge_dir).replace(os.sep, "/")
            summary = ""
            for line in text.splitlines():
                if line.startswith("summary:"):
                    summary = line.split(":", 1)[1].strip().strip("\"'")
                    break
            results.append((score, rel, summary, matched))
    results.sort(key=lambda item: (-item[0], item[1]))
    return results[:limit]


def main():
    parser = argparse.ArgumentParser(description="Search docs/knowledge without rg")
    parser.add_argument("query", nargs="+", help="search words or quoted phrases")
    parser.add_argument("--content", action="store_true", help="search knowledge document bodies instead of INDEX.md")
    parser.add_argument("--limit", type=int, default=12, help="maximum results (default: 12)")
    args = parser.parse_args()

    terms = normalized_terms(args.query)
    if not terms:
        parser.error("at least one non-empty query is required")

    root = repo_root()
    knowledge = os.path.join(root, "docs", "knowledge")
    if not os.path.isdir(knowledge):
        print("not found: {0}".format(knowledge), file=sys.stderr)
        return 2

    if args.content:
        results = search_content(knowledge, terms, args.limit)
        for score, rel, summary, matched in results:
            print("score={0}  {1}".format(score, rel))
            if summary:
                print("  summary: {0}".format(summary))
            print("  matched: {0}".format(", ".join(matched)))
    else:
        index = os.path.join(knowledge, "INDEX.md")
        results = search_index(index, terms, args.limit)
        for score, lineno, line, matched in results:
            print("score={0} line={1} matched={2}".format(score, lineno, ",".join(matched)))
            print(line)

    if not results:
        print("No matches.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
