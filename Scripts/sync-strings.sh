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

# Xcode retains translated keys as stale after their last caller is removed. Retire only those
# compiler-confirmed keys, preserving the catalog's formatting (including its empty objects).
python3 - "$CATALOG" <<'PY'
import json
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
catalog = json.loads(path.read_text())
catalog["strings"] = {
    key: entry for key, entry in catalog["strings"].items()
    if entry.get("extractionState") != "stale"
}
text = json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : "))
text = re.sub(r"^(\s*)(.*) : \{\}$", lambda m: m[1] + m[2] + " : {\n\n" + m[1] + "}", text, flags=re.M)
path.write_text(text)
PY

node Scripts/check-localizations.js
