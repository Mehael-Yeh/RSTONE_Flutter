"""Generate a scoped, content-versioned cache worker for the built app shell."""
import hashlib
import json
import re
from pathlib import Path


def prepare(root):
    root = Path(root)
    bootstrap = root / "flutter_bootstrap.js"
    text = bootstrap.read_text(encoding="utf-8")
    # New Flutter SDKs ship an unregistering stub; older ones auto-register
    # their generic worker. Only the RSTONE worker should own this app's scope.
    text, _ = re.subn(
        r"_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*\{[^{}]*\}\s*,?\s*\}\);",
        "_flutter.loader.load();", text)
    load_call = text[text.rfind("_flutter.loader.load("):]
    if "serviceWorkerSettings:" in load_call:
        raise ValueError("Review the changed Flutter bootstrap before deployment")
    bootstrap.write_text(text, encoding="utf-8")
    excluded = {"rstone_offline_worker.js", "flutter_service_worker.js", ".last_build_id"}
    resources = {}
    for file in sorted(root.rglob("*")):
        if not file.is_file() or file.name in excluded or file.suffix == ".map":
            continue
        resources[file.relative_to(root).as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
    template = Path(__file__).with_name("web_offline_worker.js").read_text(encoding="utf-8")
    digest = hashlib.sha256((template + json.dumps(resources, sort_keys=True)).encode("utf-8")).hexdigest()
    template = template.replace("__RSTONE_BUILD_HASH__", json.dumps(digest))
    template = template.replace("__RSTONE_RESOURCE_LIST__", json.dumps(resources, ensure_ascii=True))
    (root / "rstone_offline_worker.js").write_text(template, encoding="utf-8")
    print("Prepared offline shell cache:", len(resources), "resources")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", default="build/web")
    prepare(parser.parse_args().path)
