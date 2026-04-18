#!/usr/bin/env python3
"""Generate a UTC build date in strict YYYYMMDD format."""
from __future__ import annotations

from datetime import datetime, timezone

now = datetime.now(timezone.utc)
build_date = now.strftime("%Y%m%d")

# Hard validation to prevent accidental format regressions (e.g. using minutes instead of month).
parsed = datetime.strptime(build_date, "%Y%m%d")
if (parsed.year, parsed.month, parsed.day) != (now.year, now.month, now.day):
    raise SystemExit(f"Invalid build date generated: {build_date}")

print(build_date)
