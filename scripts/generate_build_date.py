#!/usr/bin/env python3
"""Generate UTC+08 build metadata for CI workflows.

Outputs key-value lines suitable for appending to $GITHUB_OUTPUT:
- build_date: YYYYMMDD (UTC+08)
- build_time: YYYYMMDDHHMM (UTC+08)
- build_code: epoch minutes (monotonic integer, Android-safe)
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

tz_cst = timezone(timedelta(hours=8))
now_cst = datetime.now(tz_cst)
build_date = now_cst.strftime("%Y%m%d")
build_time = now_cst.strftime("%Y%m%d%H%M")
build_code = int(now_cst.timestamp() // 60)

# Validate date/time payload shape.
datetime.strptime(build_date, "%Y%m%d")
datetime.strptime(build_time, "%Y%m%d%H%M")
if build_code <= 0:
    raise SystemExit(f"Invalid build_code generated: {build_code}")

print(f"build_date={build_date}")
print(f"build_time={build_time}")
print(f"build_code={build_code}")
