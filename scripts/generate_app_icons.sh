#!/usr/bin/env bash
set -euo pipefail

# Generate App Icons from icon.png for both legacy (iOS 15+) and single-size setups
# - Default input: ../icon.png (override with first arg)
# - Generates full legacy set (iPhone/iPad + ios-marketing 1024) required on real devices
# - Generates mandatory sizes only (no extra dark/tinted marketing variants) for minimal maintenance.
#   Optional flags retained: --dark / --tinted (ignored unless --include-extra specified).
#
# Usage:
#   scripts/generate_app_icons.sh [path/to/icon.png] [--include-extra --dark path/to/dark.png --tinted path/to/tinted.png]
#
# Requirements: macOS 'sips'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/scripts}"
INPUT_ICON="${1:-$REPO_ROOT/icon.png}"
shift || true

INCLUDE_EXTRA=0
DARK_ICON=""
TINTED_ICON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-extra)
      INCLUDE_EXTRA=1; shift ;;
    --dark)
      DARK_ICON="$2"; shift 2 ;;
    --tinted)
      TINTED_ICON="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

APPICONSET="$REPO_ROOT/ChessDuo/Assets.xcassets/AppIcon.appiconset"
# Fallback if structure differs
if [[ ! -d "$APPICONSET" ]]; then
  ALT_APPICONSET="$REPO_ROOT/ChessDuo/ChessDuo/Assets.xcassets/AppIcon.appiconset"
  if [[ -d "$ALT_APPICONSET" ]]; then
    APPICONSET="$ALT_APPICONSET"
  fi
fi
CONTENTS_JSON="$APPICONSET/Contents.json"

if ! command -v sips >/dev/null 2>&1; then
  echo "Error: 'sips' not found. This script requires macOS 'sips'." >&2
  exit 1
fi

if [[ ! -f "$INPUT_ICON" ]]; then
  echo "Error: Input icon not found: $INPUT_ICON" >&2
  exit 1
fi

if [[ ! -d "$APPICONSET" ]]; then
  echo "Error: AppIcon set not found: $APPICONSET" >&2
  exit 1
fi

# Prepare file names
LIGHT_OUT="$APPICONSET/AppIcon-1024.png"
DRK_OUT="$APPICONSET/AppIcon-1024-dark.png"
TNT_OUT="$APPICONSET/AppIcon-1024-tinted.png"

# Function to resize to 1024x1024 PNG
resize_1024() {
  local src="$1" dst="$2"
  # Ensure PNG and size 1024x1024. -z takes height width.
  sips -s format png "$src" -z 1024 1024 --out "$dst" >/dev/null
}

echo "Generating app icons from $INPUT_ICON"

# Helper to write JSON entries
json_entries=()
add_entry() {
  local idiom="$1" sizept="$2" scale="$3" filename="$4"
  json_entries+=(
"    {\n      \"size\" : \"${sizept}\",\n      \"idiom\" : \"${idiom}\",\n      \"filename\" : \"${filename}\",\n      \"scale\" : \"${scale}\"\n    }"
  )
}

# Resize function for arbitrary pixels
resize_to() {
  local src="$1" dst="$2" px="$3"
  sips -s format png "$src" -z "$px" "$px" --out "$dst" >/dev/null
}

# Define legacy sizes (points x scale)
# iPhone
declare -a IPHONE_SIZES=(
  "20 2" "20 3"
  "29 2" "29 3"
  "40 2" "40 3"
  "60 2" "60 3"
)
# iPad
declare -a IPAD_SIZES=(
  "20 1" "20 2"
  "29 1" "29 2"
  "40 1" "40 2"
  "76 1" "76 2"
  "83.5 2"
)

# Generate iPhone icons
for pair in "${IPHONE_SIZES[@]}"; do
  pts="${pair% *}"; scl="${pair#* }";
  # compute pixel: pts * scl
  # Use bc for float (83.5*2); format without decimal
  px=$(printf '%s*%s\n' "$pts" "$scl" | bc)
  px=${px%.*}
  base="AppIcon-${pts}@${scl}x-iphone.png"
  out="$APPICONSET/$base"
  resize_to "$INPUT_ICON" "$out" "$px"
  add_entry iphone "${pts}x${pts}" "${scl}x" "$base"
done

# Generate iPad icons
for pair in "${IPAD_SIZES[@]}"; do
  pts="${pair% *}"; scl="${pair#* }";
  px=$(printf '%s*%s\n' "$pts" "$scl" | bc)
  px=${px%.*}
  base="AppIcon-${pts}@${scl}x-ipad.png"
  out="$APPICONSET/$base"
  resize_to "$INPUT_ICON" "$out" "$px"
  add_entry ipad "${pts}x${pts}" "${scl}x" "$base"
done

# ios-marketing 1024 (App Store)
resize_1024 "$INPUT_ICON" "$LIGHT_OUT"
add_entry ios-marketing "1024x1024" "1x" "$(basename "$LIGHT_OUT")"

if [[ $INCLUDE_EXTRA -eq 1 ]]; then
  echo "Including optional dark/tinted marketing variants"
  if [[ -n "$DARK_ICON" && -f "$DARK_ICON" ]]; then
    resize_1024 "$DARK_ICON" "$DRK_OUT"
    json_entries+=(
"    {\n      \"size\" : \"1024x1024\",\n      \"idiom\" : \"ios-marketing\",\n      \"filename\" : \"$(basename \"$DRK_OUT\")\",\n      \"scale\" : \"1x\",\n      \"appearances\" : [ { \"appearance\" : \"luminosity\", \"value\" : \"dark\" } ]\n    }"
    )
  fi
  if [[ -n "$TINTED_ICON" && -f "$TINTED_ICON" ]]; then
    resize_1024 "$TINTED_ICON" "$TNT_OUT"
    json_entries+=(
"    {\n      \"size\" : \"1024x1024\",\n      \"idiom\" : \"ios-marketing\",\n      \"filename\" : \"$(basename \"$TNT_OUT\")\",\n      \"scale\" : \"1x\"\n    }"
    )
  fi
fi

# Build Contents.json
{
  echo '{'
  echo '  "images" : ['
  first=1
  for entry in "${json_entries[@]}"; do
    if [[ $first -eq 1 ]]; then first=0; else echo '    ,'; fi
    echo -e "$entry"
  done
  echo '  ],'
  echo '  "info" : { "author" : "xcode", "version" : 1 }'
  echo '}'
} > "$CONTENTS_JSON"

echo "Done. Updated icons and Contents.json for legacy devices."
echo "AppIcon set: $APPICONSET"
