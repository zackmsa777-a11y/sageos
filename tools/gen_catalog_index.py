#!/usr/bin/env python3
"""
Generates docs/index.json (machine-readable) from the sage-pkg source
config files in src/. Run this any time categories.conf / fetch-tools.conf /
pip-tools.conf / tool-descriptions.conf change, then commit docs/index.json.
"""
import json
import os
import datetime

SRC = os.path.join(os.path.dirname(__file__), "..", "src")
DOCS = os.path.join(os.path.dirname(__file__), "..", "docs")


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


def main():
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

    index = {
        "catalog_format_version": "1.0",
        "generated_utc": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source_repo": "https://github.com/zackmsa777-a11y/sageos",
        "install_hint": "sage-pkg install <category id>",
        "update_hint": "sage-pkg update-catalog",
        "category_count": len(categories),
        "total_tool_count": total_tools,
        "categories": categories,
    }

    os.makedirs(DOCS, exist_ok=True)
    out_path = os.path.join(DOCS, "index.json")
    with open(out_path, "w") as f:
        json.dump(index, f, indent=2)
    print(f"wrote {out_path} — {len(categories)} categories, {total_tools} tools")


if __name__ == "__main__":
    main()
