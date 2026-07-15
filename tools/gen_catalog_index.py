#!/usr/bin/env python3
"""
Generates docs/index.json (machine-readable) + docs/changelog.json from the
sage-pkg source config files in src/. Run this any time categories.conf /
fetch-tools.conf / pip-tools.conf / tool-descriptions.conf change, then
commit docs/.

Versioning: compares the new catalog against the previously-committed
docs/index.json to auto-detect added/removed categories and tools, bumps
catalog_version (major.minor — minor +1 per run with changes), and appends
an entry to docs/changelog.json. Pass --note "custom message" to prepend a
human-written note to the auto-generated diff for that version.
"""
import json
import os
import sys
import datetime

SRC = os.path.join(os.path.dirname(__file__), "..", "src")
DOCS = os.path.join(os.path.dirname(__file__), "..", "docs")
INDEX_PATH = os.path.join(DOCS, "index.json")
CHANGELOG_PATH = os.path.join(DOCS, "changelog.json")


def parse_pipe_file(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            rows.append(line.split("|"))
    return rows


def bare_name(tok):
    return tok.split("@")[0]


def override_method(tok, default):
    if "@" in tok:
        return tok.split("@", 1)[1]
    return default


def build_categories():
    categories_rows = parse_pipe_file(os.path.join(SRC, "categories.conf"))
    fetch_rows = parse_pipe_file(os.path.join(SRC, "fetch-tools.conf"))
    pip_rows = parse_pipe_file(os.path.join(SRC, "pip-tools.conf"))
    desc_rows = parse_pipe_file(os.path.join(SRC, "tool-descriptions.conf"))

    fetch_map = {r[0]: {"github_repo": r[1], "asset_pattern": r[2]} for r in fetch_rows if len(r) >= 3}
    pip_map = {r[0]: r[1] if len(r) > 1 else "" for r in pip_rows}
    desc_map = {r[0]: r[1] for r in desc_rows if len(r) >= 2}

    categories = []
    total_tools = 0
    for row in categories_rows:
        if len(row) < 5:
            continue
        cat_id, display_name, description, pkgs, cat_type = row[0], row[1], row[2], row[3], row[4]
        tools = []
        for tok in pkgs.split():
            name = bare_name(tok)
            method = override_method(tok, cat_type)
            entry = {
                "name": name,
                "install_method": method,
                "description": desc_map.get(name, ""),
            }
            if method == "fetch" and name in fetch_map:
                entry["github_repo"] = fetch_map[name]["github_repo"]
                entry["asset_pattern"] = fetch_map[name]["asset_pattern"]
            if method == "pip" and name in pip_map:
                entry["pip_package"] = pip_map[name] or name
            tools.append(entry)
            total_tools += 1
        categories.append({
            "id": cat_id,
            "name": display_name,
            "description": description,
            "type": cat_type,
            "tool_count": len(tools),
            "tools": tools,
        })
    return categories, total_tools


def diff_categories(old_categories, new_categories):
    """Returns a list of human-readable change lines."""
    if old_categories is None:
        return None  # signal: no baseline, treat as initial version
    old_map = {c["id"]: c for c in old_categories}
    new_map = {c["id"]: c for c in new_categories}
    changes = []

    for cid, cat in new_map.items():
        if cid not in old_map:
            changes.append(f"Added category '{cat['name']}' ({cid}) — {cat['tool_count']} tools")
            continue
        old_tools = {t["name"]: t for t in old_map[cid]["tools"]}
        new_tools = {t["name"]: t for t in cat["tools"]}
        added = sorted(set(new_tools) - set(old_tools))
        removed = sorted(set(old_tools) - set(new_tools))
        method_changed = sorted(
            n for n in (set(new_tools) & set(old_tools))
            if new_tools[n]["install_method"] != old_tools[n]["install_method"]
        )
        if added:
            changes.append(f"{cid}: added tool(s) — {', '.join(added)}")
        if removed:
            changes.append(f"{cid}: removed tool(s) — {', '.join(removed)}")
        for n in method_changed:
            changes.append(f"{cid}/{n}: install method changed {old_tools[n]['install_method']} → {new_tools[n]['install_method']}")

    for cid, cat in old_map.items():
        if cid not in new_map:
            changes.append(f"Removed category '{cat['name']}' ({cid})")

    return changes


def bump_version(old_version):
    if not old_version:
        return "1.0"
    try:
        major, minor = old_version.split(".")
        return f"{major}.{int(minor) + 1}"
    except Exception:
        return "1.0"


def main():
    note = None
    if "--note" in sys.argv:
        i = sys.argv.index("--note")
        note = sys.argv[i + 1] if i + 1 < len(sys.argv) else None

    new_categories, total_tools = build_categories()

    old_index = None
    if os.path.exists(INDEX_PATH):
        with open(INDEX_PATH) as f:
            old_index = json.load(f)

    old_categories = old_index["categories"] if old_index else None
    old_version = old_index.get("catalog_version") if old_index else None

    changes = diff_categories(old_categories, new_categories)

    changelog = []
    if os.path.exists(CHANGELOG_PATH):
        with open(CHANGELOG_PATH) as f:
            changelog = json.load(f)

    now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

    if changes is None:
        # No prior versioned baseline — this run establishes v1.0.
        version = "1.0"
        entry_changes = [note] if note else []
        entry_changes.append(f"Initial versioned catalog: {len(new_categories)} categories, {total_tools} tools.")
        changelog.append({"version": version, "date": now, "changes": entry_changes})
    elif changes:
        version = bump_version(old_version)
        entry_changes = ([note] if note else []) + changes
        changelog.append({"version": version, "date": now, "changes": entry_changes})
    else:
        # No detected changes — keep the same version, don't add a changelog entry
        # unless the caller passed an explicit note.
        version = old_version or "1.0"
        if note:
            changelog.append({"version": version, "date": now, "changes": [note]})

    index = {
        "catalog_format_version": "1.0",
        "catalog_version": version,
        "generated_utc": now,
        "source_repo": "https://github.com/zackmsa777-a11y/sageos",
        "install_hint": "sage-pkg install <category id>",
        "update_hint": "sage-pkg update-catalog",
        "changelog_url": "changelog.json",
        "category_count": len(new_categories),
        "total_tool_count": total_tools,
        "categories": new_categories,
    }

    os.makedirs(DOCS, exist_ok=True)
    with open(INDEX_PATH, "w") as f:
        json.dump(index, f, indent=2)
    with open(CHANGELOG_PATH, "w") as f:
        json.dump(changelog, f, indent=2)

    # Also write a plain VERSION file sage-pkg can fetch cheaply (single line,
    # no JSON parsing needed in bash).
    version_path = os.path.join(SRC, "sage-pkg-catalog", "VERSION")
    with open(version_path, "w") as f:
        f.write(version + "\n")

    print(f"catalog_version {version} — {len(new_categories)} categories, {total_tools} tools")
    if changes:
        print("changes detected:")
        for c in changes:
            print(f"  - {c}")
    elif changes is None:
        print("(baseline version established, no prior index to diff against)")
    else:
        print("(no functional changes detected)")


if __name__ == "__main__":
    main()
