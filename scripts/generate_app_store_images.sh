#!/usr/bin/env bash
set -euo pipefail
DEBUG=${DEBUG:-0}

# Generate minimal App Store placeholder screenshots from icon.png
# Creates portraits for iPhone 6.5", iPhone 5.5", and iPad Pro 12.9".
# Places identical placeholders into all locale screenshot folders so `deliver` can upload them.
# Requirements: macOS `sips`
# Usage: scripts/generate_app_store_images.sh [path/to/icon.png]
# Note: Make this script executable before running (chmod +x scripts/generate_app_store_images.sh)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/scripts}"
ICON_INPUT="${1:-$REPO_ROOT/icon.png}"

WITH_TITLE=0
shift || true
for arg in "$@"; do
  case "$arg" in
    --with-title)
      WITH_TITLE=1
      ;;
  esac
done

if ! command -v sips >/dev/null 2>&1; then
  echo "Error: 'sips' not found. This script requires macOS 'sips'." >&2
  exit 1
fi
if [[ ! -f "$ICON_INPUT" ]]; then
  echo "Error: icon not found at: $ICON_INPUT" >&2
  exit 1
fi

# Target sizes (portrait)
IPHONE65_W=1242; IPHONE65_H=2688   # iPhone 6.5"
IPHONE55_W=1242; IPHONE55_H=2208   # iPhone 5.5"
IPAD129_W=2048;  IPAD129_H=2732    # iPad Pro 12.9"

# Locales to populate (match your metadata locales)
LOCALES=(de-DE en-US es-ES fr-FR zh-Hans)

local_title() {
  case "$1" in
    de-DE) echo "Mein Schachbrett" ;;
    en-US) echo "My Chess Board" ;;
    es-ES) echo "Mi Tablero de Ajedrez" ;;
    fr-FR) echo "Mon Échiquier" ;;
    zh-Hans) echo "我的棋盘" ;;
    *) echo "My Chess Board" ;;
  esac
}

# Helper: create a padded canvas from square icon to exact WxH
make_placeholder() {
  local src="$1" w="$2" h="$3" out="$4"
  local tmp
  tmp="$(mktemp -t iconfit.XXXXXX).png"
  # Fit square icon to min(w,h), then pad to exact size (white background)
  local fit
  if [[ "$w" -lt "$h" ]]; then fit="$w"; else fit="$h"; fi
  sips -s format png "$src" -z "$fit" "$fit" --out "$tmp"
  sips -s format png "$tmp" --padToHeightWidth "$h" "$w" --out "$out"
  if [[ ! -s "$out" ]]; then echo "ERROR: Failed to create '$out'" >&2; exit 1; fi
  rm -f "$tmp"
}

overlay_title_on_image() {
  local img="$1" title="$2"
  if ! command -v convert >/dev/null 2>&1; then
    echo "Warning: ImageMagick 'convert' not found; skipping title overlay for $img" >&2
    return 0
  fi
  # Determine width to set a sensible point size
  local w
  w=$(identify -format "%w" "$img" 2>/dev/null || echo 1242)
  local pts=$(( w / 12 ))
  # Draw a semi-transparent black strip behind the text at the top for readability
  convert "$img" \
    -gravity north \
    -fill white \
    -undercolor '#00000080' \
    -pointsize "$pts" \
    -annotate +0+40 "$title" \
    "$img"
}

# Output to each locale folder
for L in "${LOCALES[@]}"; do
  OUT_DIR="$REPO_ROOT/fastlane/screenshots/$L"
  mkdir -p "$OUT_DIR"
  make_placeholder "$ICON_INPUT" "$IPHONE65_W" "$IPHONE65_H" "$OUT_DIR/01_iphone65_portrait.png"
  make_placeholder "$ICON_INPUT" "$IPHONE55_W" "$IPHONE55_H" "$OUT_DIR/02_iphone55_portrait.png"
  make_placeholder "$ICON_INPUT" "$IPAD129_W"  "$IPAD129_H"  "$OUT_DIR/03_ipad129_portrait.png"
  if [[ "$WITH_TITLE" -eq 1 ]]; then
    TITLE=$(local_title "$L")
    overlay_title_on_image "$OUT_DIR/01_iphone65_portrait.png" "$TITLE"
    overlay_title_on_image "$OUT_DIR/02_iphone55_portrait.png" "$TITLE"
    overlay_title_on_image "$OUT_DIR/03_ipad129_portrait.png"  "$TITLE"
  fi
  echo "Wrote placeholders to $OUT_DIR"
done

if [[ "$DEBUG" -eq 1 ]]; then
  echo "\nDEBUG: Listing created screenshot files:"
  for L in "${LOCALES[@]}"; do
    OUT_DIR="$REPO_ROOT/fastlane/screenshots/$L"
    echo "-- $OUT_DIR"; ls -l "$OUT_DIR" || true
  done
fi

echo "Done. Placeholders ready for deliver upload."
