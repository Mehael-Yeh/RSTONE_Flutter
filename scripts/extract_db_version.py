#!/usr/bin/env python3
"""从版本信息 Markdown 中提取数据库版本号。"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def extract_db_version(markdown_text: str) -> str | None:
    pattern = re.compile(r"^\s*-\s*版本号[：:]\s*(.+?)\s*$", re.MULTILINE)
    match = pattern.search(markdown_text)
    if not match:
        return None
    version = match.group(1).strip()
    return version or None


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: extract_db_version.py <version_info_markdown_path>", file=sys.stderr)
        return 2

    markdown_path = Path(sys.argv[1])
    if not markdown_path.exists():
        return 1

    content = markdown_path.read_text(encoding="utf-8", errors="ignore")
    version = extract_db_version(content)
    if not version:
        return 1

    print(version)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
