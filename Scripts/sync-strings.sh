#!/bin/bash
# Merge the strings the compiler extracted into Localizable.xcstrings, as an Xcode build in the IDE
# does; `xcodebuild` alone never writes them back. Run after changing any UI text.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

DERIVED=build/strings
xcodebuild build -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
    CODE_SIGNING_ALLOWED=NO -derivedDataPath "$DERIVED" -quiet

# A read loop rather than `mapfile`, which is bash 4 — macOS ships bash 3.2.
args=()
while IFS= read -r f; do args+=(--stringsdata "$f"); done < <(
    find "$DERIVED/Build/Intermediates.noindex/Tinycast.build/Debug/Tinycast.build" \
        -name '*.stringsdata'
)
# The catalog's file name is its table, so only `Localizable` strings land in it.
CATALOG=Tinycast/Resources/Localizable.xcstrings
xcrun xcstringstool sync "$CATALOG" "${args[@]}"

# Only compiler-proven unused strings are pruned; shared strings keep their translations.
node - "$CATALOG" <<'JS'
const fs = require("fs");
const file = process.argv[2];
const catalog = JSON.parse(fs.readFileSync(file, "utf8"));
for (const [key, entry] of Object.entries(catalog.strings)) {
  if (entry.extractionState === "stale") delete catalog.strings[key];
}
const json = JSON.stringify(catalog, null, 2).replace(/^(\s*"(?:[^"\\]|\\.)*"):/gm, "$1 :");
fs.writeFileSync(file, json + "\n");
JS

node Scripts/check-localizations.js
