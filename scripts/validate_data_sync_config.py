"""Validate installed HTTPS sources and pinned public keys before public builds."""
import base64
import json
import re
from pathlib import Path
from urllib.parse import urlparse


def validate(path):
    config = json.loads(Path(path).read_text(encoding="utf-8"))
    if not config.get("sources") or not config.get("keys"):
        raise ValueError("Configure production sources and trusted signing keys before deployment")
    for source in config["sources"]:
        url = urlparse(source["url"])
        if (url.scheme != "https" or not url.hostname or url.username or url.password
                or url.query or url.fragment or not source.get("name")):
            raise ValueError("Expected named, anonymous HTTPS source")
    for key_id, encoded in config["keys"].items():
        if encoded == "kN+rVKo4tJcMnnZPeMuHoaMdiDVIEAeV9DodaK8Ul84=":
            raise ValueError("The public example key cannot be a production trust anchor")
        if key_id in {"example-only", "test-key"} or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", key_id):
            raise ValueError("Production builds cannot trust example/test keys")
        raw = base64.b64decode(encoded, validate=True)
        if len(raw) != 32 or base64.b64encode(raw).decode("ascii") != encoded:
            raise ValueError("Expected canonical 32-byte Ed25519 public key")
    print("Data sync configuration validated")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", default="assets/data_sync_config.json")
    validate(parser.parse_args().path)
