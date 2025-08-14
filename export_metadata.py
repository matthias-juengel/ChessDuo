#!/usr/bin/env python3
import os, re, sys, pathlib

SRC = pathlib.Path("app-names-and-store-info.txt")  # Pfad anpassen, falls nötig
OUT = pathlib.Path("fastlane/metadata")

# Mapping Sprachen -> App Store Locale
LOCALES = {
    "German":       "de-DE",
    "English":      "en-US",
    "Spanish":      "es-ES",
    "French":       "fr-FR",
    "Simplified Chinese": "zh-Hans",
}

# Felder, die wir pro Sprache erwarten
FIELDS = ["Name", "Subtitle", "Keywords", "Promotional Text"]

# Datei einlesen
text = SRC.read_text(encoding="utf-8")

# Blöcke nach "== <Language> ==" schneiden
lang_blocks = re.split(r"\n==\s*(.+?)\s*==\n", text)
# Ergebnis ist: [prefix, lang1, content1, lang2, content2, ...]
pairs = list(zip(lang_blocks[1::2], lang_blocks[2::2]))

def clean_desc(desc: str) -> str:
    # Entferne führende Leerzeilen
    desc = re.sub(r"^\s+", "", desc, flags=re.MULTILINE)
    return desc.strip() + "\n"

# Export
for lang_name, content in pairs:
    if lang_name not in LOCALES:
        continue
    locale = LOCALES[lang_name]
    target = OUT / locale
    target.mkdir(parents=True, exist_ok=True)

    # Einzel-Felder holen
    data = {}
    for field in FIELDS:
        m = re.search(rf"^{field}:\s*(.*)$", content, flags=re.MULTILINE)
        data[field] = (m.group(1).strip() if m else "")

    # Beschreibung ist: alles nach "Promotional Text:"-Zeile bis zum nächsten "== ..."
    # Also: position von "Promotional Text:\n" finden, ab dort nächste Leerzeile und dann Text bis nächstes "=="
    promo_pos = re.search(r"^Promotional Text:\s*$", content, flags=re.MULTILINE)
    desc_text = ""
    if promo_pos:
        start = promo_pos.end()
        # danach erste Zeile = der Promo-Text selbst; Beschreibung beginnt nach dieser Promo-Zeile
        # Wir haben den Promo-Text schon als data["Promotional Text"], also ab nächster Zeile den Rest sammeln
        after = content[start:]
        # Erste Zeile entfernen
        after = after.splitlines()
        if after:
            after = after[1:]  # Beschreibung beginnt nach der Promo-Zeile
        desc_text = "\n".join(after)
    else:
        # Fallback: nimm gesamten Content
        desc_text = content

    # Beschreibung bis zum nächsten Sprachheader kappen (sollte durch split schon erledigt sein)
    # und Leading/Trailing-Noise trimmen
    description = clean_desc(desc_text)

    # Dateien schreiben
    (target / "name.txt").write_text(data["Name"] + "\n", encoding="utf-8")
    (target / "subtitle.txt").write_text(data["Subtitle"] + "\n", encoding="utf-8")
    (target / "keywords.txt").write_text(data["Keywords"] + "\n", encoding="utf-8")
    (target / "promotional_text.txt").write_text(data["Promotional Text"] + "\n", encoding="utf-8")
    (target / "description.txt").write_text(description, encoding="utf-8")

print("✓ Export complete -> fastlane/metadata/<locale>/*.txt")