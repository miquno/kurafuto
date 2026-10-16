#!/usr/bin/env bash
# Fails when Localizable.xcstrings no longer matches the strings in the code, or when a
# translatable string lacks a finished German, Japanese or Simplified Chinese translation.
# Needs a build of the app target first; pass its derived data folder.
set -euo pipefail

derived=${1:?usage: check-localizations.sh <derived-data-path>}
catalog=Kurafuto/Resources/Localizable.xcstrings
languages="de ja zh-Hans"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The compiler records every localizable string of the app target in .stringsdata files; syncing a copy
# (same file name, so the table matches) shows what Xcode would add or mark stale.
find "$derived" -path '*-iphonesimulator/Kurafuto.build/*' -name '*.stringsdata' -print0 > "$tmp/stringsdata"
if [ ! -s "$tmp/stringsdata" ]; then
  echo "::error::No .stringsdata files under $derived. Build the Kurafuto target first."
  exit 1
fi
cp "$catalog" "$tmp/Localizable.xcstrings"
xargs -0 xcrun xcstringstool sync "$tmp/Localizable.xcstrings" --stringsdata < "$tmp/stringsdata"
if ! cmp -s "$catalog" "$tmp/Localizable.xcstrings"; then
  diff -u "$catalog" "$tmp/Localizable.xcstrings" || true
  echo "::error::$catalog is out of date. Build in Xcode (or run xcstringstool sync) and translate the new strings."
  exit 1
fi

python3 - "$catalog" $languages <<'PY'
import json, sys

path, languages = sys.argv[1], sys.argv[2:]
strings = json.load(open(path, encoding="utf-8"))["strings"]

def finished(localization):
    units = [localization.get("stringUnit")] if "stringUnit" in localization else [
        form.get("stringUnit") for variation in localization.get("variations", {}).values() for form in variation.values()]
    return bool(units) and all(u and u.get("state") == "translated" and u.get("value") for u in units)

missing = [f"{lang}: {key!r}" for key, entry in sorted(strings.items()) if entry.get("shouldTranslate", True)
           for lang in languages if not finished(entry.get("localizations", {}).get(lang, {}))]
for line in missing:
    print(f"::error::Missing translation {line}")
sys.exit(1 if missing else 0)
PY
echo "Localizations complete: $languages"
