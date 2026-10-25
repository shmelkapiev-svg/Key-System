#!/usr/bin/env python3
"""Generate LATEST_VERSIONS.md. Never deletes or moves files."""
import re
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "LATEST_VERSIONS.md"
VERSION_RE = re.compile(r"(?i)v(\d+(?:\.\d+)+)")
SKIP_DIRS = {".git", ".github", "__pycache__", ".venv", "venv", "node_modules"}


def version_key(v):
    return tuple(int(x) for x in v.split("."))


def family_name(stem, match):
    name = stem[:match.start()] + stem[match.end():]
    name = re.sub(r"[\s._-]+", " ", name)
    return re.sub(r"[^a-z0-9]+", "", name.casefold())


def main():
    groups = defaultdict(list)
    unversioned = []

    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(ROOT)
        if path.name == OUTPUT.name or any(part in SKIP_DIRS for part in rel.parts):
            continue
        match = VERSION_RE.search(path.stem)
        if not match:
            unversioned.append(rel)
            continue

        version = match.group(1)
        family = family_name(path.stem, match)
        # Keep extensions separate, but compare files across folders.
        groups[(family, path.suffix.casefold())].append({
            "path": rel, "version": version, "key": version_key(version),
            "stem": path.stem,
        })

    latest = []
    for _, files in groups.items():
        files.sort(key=lambda f: (f["key"], -len(f["path"].parts),
                                  f["path"].as_posix().casefold()))
        latest.append((files, files[-1]))
    latest.sort(key=lambda pair: pair[1]["path"].as_posix().casefold())

    all_versioned = sum(len(files) for files, _ in latest)
    older = sum(len(files) - 1 for files, _ in latest)
    out = [
        "# Latest file versions", "",
        "<!-- Generated automatically. Do not edit by hand. -->", "",
        "Only the newest detected version per filename family is listed below. "
        "Older files remain in the repository; this script does not delete anything.", "",
        f"- Versioned files scanned: **{all_versioned}**",
        f"- Version groups: **{len(latest)}**",
        f"- Older versions not selected: **{older}**", "",
        "## Latest version in each group", "",
    ]
    if latest:
        out += ["| File | Version | Other versions found |", "|---|---:|---|"]
        for files, chosen in latest:
            older_files = [f for f in files if f is not chosen]
            versions = ", ".join(f"`{f['version']}`" for f in reversed(older_files)) or "—"
            p = chosen["path"].as_posix()
            link = p.replace(" ", "%20")
            out.append(f"| [`{p}`]({link}) | `{chosen['version']}` | {versions} |")
    else:
        out.append("No filenames containing a version like `v1.2` were found.")

    out += ["", "## Files without a detected version", "",
            "These are listed separately because their names do not contain a `vX.Y`-style version.", ""]
    if unversioned:
        for p in sorted(unversioned, key=lambda x: x.as_posix().casefold()):
            s = p.as_posix()
            out.append(f"- [`{s}`]({s.replace(' ', '%20')})")
    else:
        out.append("None.")

    out += ["", "## Rules", "",
            "- Versions are compared numerically: `v2.0` > `v1.9`, and `v1.10` > `v1.9`.",
            "- Joined names are supported, e.g. `MyScriptV2.1.lua`; matching is case-insensitive.",
            "- Files are grouped by their filename after removing the version; extensions stay separate.",
            "- If versions tie, the shallower path wins, then alphabetical order.",
            "- This tool only generates this report. It never deletes, renames, or moves files.", ""]
    OUTPUT.write_text("\n".join(out), encoding="utf-8")
    print(f"Updated {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
