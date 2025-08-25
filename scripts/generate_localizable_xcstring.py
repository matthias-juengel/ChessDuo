#!/usr/bin/env python3
"""Generate a consolidated Localizable.xcstring file from existing *.lproj/Localizable.strings files.

Features:
 - Parses all <lang>.lproj/Localizable.strings files under a project directory.
 - Produces a pretty-printed JSON (Apple .xcstrings format) file.
 - Adds a version field.
 - Renames original Localizable.strings files to Localizable.strings.bak (configurable) to avoid Xcode conflicts.
 - Warns about duplicate keys or inconsistent base language entries.
 - Can run in dry-run mode to preview actions.

Usage:
  python scripts/generate_localizable_xcstring.py \
    --project-dir ChessDuo \
    --output ChessDuo/Localizable.xcstring \
    --source-language en \
    --version 1.0

Optional flags:
  --backup-extension .orig   (default: .bak)
  --keep-backups             (skip renaming if backup already exists)
  --dry-run                  (show what would happen, don't write/rename)
  --no-backup                (don't rename originals)

Apple .xcstrings simplified structure (sufficient for Xcode to import):
{
  "sourceLanguage": "en",
  "version": "1.0",
  "strings": {
    "key": {
      "extractionState": "manual",
      "localizations": {
        "en": { "stringUnit": { "state": "translated", "value": "Base text" } },
        "de": { "stringUnit": { "state": "translated", "value": "German text" } }
      }
    }
  }
}

This script purposefully omits advanced metadata (developer comments, plural rules) for brevity; extend as needed.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import OrderedDict, defaultdict
from typing import Dict, List, Tuple

STRING_LINE_RE = re.compile(r'\s*"(?P<key>(?:\\.|[^"\\])+)"\s*=\s*"(?P<value>(?:\\.|[^"\\])*)"\s*;\s*(?://.*)?$')
COMMENT_RE = re.compile(r'^\s*/\*.*\*/\s*$')


def parse_strings_file(path: str) -> Dict[str, str]:
    """Parse a .strings file into a dict of key->value.

    Ignores comments and blank lines. Does not evaluate escape sequences beyond removing escaped quotes.
    """
    data: Dict[str, str] = {}
    if not os.path.isfile(path):
        return data
    with open(path, 'r', encoding='utf-8') as f:
        for lineno, raw_line in enumerate(f, 1):
            line = raw_line.strip()
            if not line or line.startswith('//') or COMMENT_RE.match(line):
                continue
            m = STRING_LINE_RE.match(line)
            if not m:
                # Multi-line or malformed lines could be handled here; for simplicity warn.
                sys.stderr.write(f"[WARN] Unparsed line {path}:{lineno}: {raw_line}")
                continue
            # Avoid double unicode_escape decoding which can corrupt UTF-8 (mojibake).
            # Only unescape simple escaped quotes and backslashes.
            def unescape(s: str) -> str:
                return s.replace('\\"', '"').replace('\\n', '\n').replace('\\\n', '\n').replace('\\\\', '\\')
            key = unescape(m.group('key'))
            value = unescape(m.group('value'))
            if key in data:
                sys.stderr.write(f"[WARN] Duplicate key in {path}:{lineno}: {key} (overwriting)\n")
            data[key] = value
    return data


def discover_locales(project_dir: str, basename: str) -> List[Tuple[str, str]]:
    locales: List[Tuple[str, str]] = []
    for entry in sorted(os.listdir(project_dir)):
        if not entry.endswith('.lproj'):
            continue
        loc = entry[:-6]  # strip .lproj
        strings_path = os.path.join(project_dir, entry, f'{basename}.strings')
        if os.path.isfile(strings_path):
            locales.append((loc, strings_path))
    return locales


def build_xcstring(locales_data: Dict[str, Dict[str, str]], source_language: str, version: str) -> OrderedDict:
    # Collect all keys preserving order based on source language file, then others.
    ordered_keys: List[str] = []
    if source_language in locales_data:
        ordered_keys.extend(locales_data[source_language].keys())
    # Add any extra keys found in other locales.
    for loc, kv in locales_data.items():
        if loc == source_language:
            continue
        for k in kv.keys():
            if k not in ordered_keys:
                ordered_keys.append(k)

    strings_obj: OrderedDict[str, dict] = OrderedDict()
    for key in ordered_keys:
        locs: Dict[str, dict] = {}
        for lang, kv in locales_data.items():
            if key in kv:
                locs[lang] = {
                    "stringUnit": {
                        "state": "translated",  # could add fuzzy/untranslated logic
                        "value": kv[key],
                    }
                }
        strings_obj[key] = OrderedDict([
            ("extractionState", "manual"),
            ("localizations", locs)
        ])

    root = OrderedDict([
        ("sourceLanguage", source_language),
        ("version", str(version)),
        ("strings", strings_obj)
    ])
    return root


def rename_originals(locales: List[Tuple[str, str]], backup_ext: str, dry_run: bool, skip_if_exists: bool):
    for loc, path in locales:
        backup_path = path + backup_ext
        if os.path.exists(backup_path):
            if skip_if_exists:
                continue
            else:
                raise FileExistsError(f"Backup already exists: {backup_path}")
        print(f"[MOVE] {path} -> {backup_path}")
        if not dry_run:
            os.rename(path, backup_path)


def main():
    ap = argparse.ArgumentParser(description="Generate Localizable.xcstring from .strings files")
    ap.add_argument('--project-dir', default='ChessDuo', help='Directory containing <lang>.lproj folders')
    ap.add_argument('--basename', default='Localizable', help='Base name of .strings file (default: Localizable)')
    ap.add_argument('--output', default=None, help='Output .xcstrings path (default: <project-dir>/<basename>.xcstrings)')
    ap.add_argument('--source-language', default='en', help='Source/development language code (default: en)')
    ap.add_argument('--version', default='1.0', help='Version string to embed (default: 1.0)')
    ap.add_argument('--backup-extension', default='.bak', help='Extension to append when backing up originals (default: .bak)')
    ap.add_argument('--dry-run', action='store_true', help='Preview actions without writing or renaming')
    ap.add_argument('--no-backup', action='store_true', help="Don't rename/backup original .strings files")
    ap.add_argument('--keep-backups', action='store_true', help='If backups already exist, keep them and continue')
    args = ap.parse_args()

    project_dir = args.project_dir
    output = args.output or os.path.join(project_dir, f'{args.basename}.xcstrings')

    locales = discover_locales(project_dir, args.basename)
    if not locales:
        print(f"No {args.basename}.strings files found in {project_dir}", file=sys.stderr)
        return 1

    print(f"Discovered locales: {[loc for loc,_ in locales]}")

    locales_data: Dict[str, Dict[str, str]] = {}
    for loc, path in locales:
        locales_data[loc] = parse_strings_file(path)
        print(f"Parsed {len(locales_data[loc])} entries from {path}")

    if args.source_language not in locales_data:
        print(f"[WARN] Source language {args.source_language} not found among locales; proceeding anyway.")

    xc = build_xcstring(locales_data, args.source_language, args.version)
    json_text = json.dumps(xc, ensure_ascii=False, indent=2)

    print(f"Will write {output} ({len(xc['strings'])} keys, {sum(len(v['localizations']) for v in xc['strings'].values())} localized entries)")
    if not args.dry_run:
        with open(output, 'w', encoding='utf-8') as f:
            f.write(json_text)
        print(f"Wrote {output}")
    else:
        print("[DRY-RUN] Skipped writing output")

    if not args.no_backup:
        rename_originals(locales, args.backup_extension, args.dry_run, args.keep_backups)
    else:
        print("Skipping backup/rename of original .strings files (--no-backup)")

    return 0


if __name__ == '__main__':
    sys.exit(main())
