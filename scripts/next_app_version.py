"""Choose a release version without falling below the checked-in shell version."""
import argparse
from pathlib import Path
import re
import subprocess


def next_version(current, tags, channel):
    floor = tuple(map(int, current.split(".")))
    all_versions = [tuple(map(int, match.groups())) for tag in tags
                    for match in [re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)(?:-alpha)?', tag)] if match]
    if all_versions:
        floor = max(floor, max(all_versions))
    suffix = "-alpha" if channel == "alpha" else ""
    pattern = re.compile(r"^v(\d+)\.(\d+)\.(\d+)" + suffix + r"$")
    versions = [tuple(map(int, match.groups())) for tag in tags
                for match in [pattern.fullmatch(tag)] if match]
    if versions:
        major, minor, patch = max(versions)
        floor = max(floor, (major, minor, patch + 1))
    return ".".join(map(str, floor))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("channel", choices=["alpha", "production"])
    args = parser.parse_args()
    pubspec = Path("pubspec.yaml").read_text(encoding="utf-8")
    current = re.search(r"^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$",
                        pubspec, re.M)
    if current is None:
        raise SystemExit("Expected a numeric application version in pubspec.yaml")
    tags = subprocess.run(["git", "tag", "--list"], check=True,
                          capture_output=True, text=True).stdout.splitlines()
    print(next_version(current.group(1), tags, args.channel))
