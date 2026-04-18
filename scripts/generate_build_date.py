#!/usr/bin/env python3
"""Generate UTC build metadata for CI workflows.

Outputs key-value lines suitable for appending to $GITHUB_OUTPUT:
- build_date: YYYYMMDD
- build_time: YYYYMMDDHHMM
- build_code: epoch minutes (monotonic integer, Android-safe)
"""
from __future__ import annotations

from datetime import datetime, timezone

now = datetime.now(timezone.utc)
build_date = now.strftime("%Y%m%d")
build_time = now.strftime("%Y%m%d%H%M")
build_code = int(now.timestamp() // 60)

# Validate date/time payload shape.
datetime.strptime(build_date, "%Y%m%d")
datetime.strptime(build_time, "%Y%m%d%H%M")
if build_code <= 0:
    raise SystemExit(f"Invalid build_code generated: {build_code}")

print(f"build_date={build_date}")
print(f"build_time={build_time}")
print(f"build_code={build_code}")
