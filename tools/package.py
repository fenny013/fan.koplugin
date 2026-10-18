import hashlib
import argparse
import re
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.fullmatch(r'return "(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)"\s*', (ROOT / "fan_version.lua").read_text(encoding="utf-8")).group(1)
RUNTIME = [
    "_meta.lua", "main.lua", "client.lua", "fan_fs.lua", "fan_html.lua",
    "fan_http.lua", "fan_i18n.lua", "fan_native.lua", "fan_progress.lua", "fan_zip.lua", "fan_version.lua",
]
DOCS = ["README.md", "LICENSE", "THIRD_PARTY.md"]
ASSETS = [".github/fan.webp"]
SOURCE = RUNTIME + DOCS + ASSETS + [
    ".gitignore", "tools/package.py", "RELEASING.md", ".github/workflows/release.yml",
    ".github/ISSUE_TEMPLATE/bug_report.md", ".github/pull_request_template.md",
]


def build(files, destination):
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(files):
            path = ROOT / name
            if not path.is_file():
                raise FileNotFoundError(path)
            entry = zipfile.ZipInfo("fan.koplugin/" + name, date_time=(2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, path.read_bytes())
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Archive integrity check failed")
    checksum = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix(".zip.sha256").write_text(checksum + "  " + destination.name + "\n", encoding="ascii")
    return destination


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag")
    args = parser.parse_args()
    if args.tag and args.tag != "v" + VERSION:
        parser.error(f"Tag must match fan_version.lua: v{VERSION}")
    destination = ROOT / "dist"
    destination.mkdir(exist_ok=True)
    print(build(RUNTIME + DOCS + ASSETS, destination / f"fan.koplugin-{VERSION}.zip"))
    print(build(SOURCE, destination / f"fan.koplugin-source-{VERSION}.zip"))


if __name__ == "__main__":
    main()
