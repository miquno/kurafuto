#!/usr/bin/env bash
# Fails when a String Catalog (Localizable, AppShortcuts) no longer matches the strings in the code, or when a
# translatable string or Siri phrase lacks a finished German, Japanese or Simplified Chinese translation.
# Needs a build of the app target first; pass its derived data folder.
set -euo pipefail

derived=${1:?usage: check-localizations.sh <derived-data-path>}
catalogs="Kurafuto/Resources/Localizable.xcstrings Kurafuto/Resources/AppShortcuts.xcstrings"
languages="de ja zh-Hans"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The compiler records every localizable string of the app and widget targets (they share the catalog) in
# .stringsdata files; syncing a copy (same file name, so the table matches) shows what Xcode would add or mark stale.
find "$derived" \( -path '*-iphonesimulator/Kurafuto.build/*' -o -path '*-iphonesimulator/KurafutoWidgets.build/*' \) \
  -name '*.stringsdata' -print0 > "$tmp/stringsdata"
if [ ! -s "$tmp/stringsdata" ]; then
  echo "::error::No .stringsdata files under $derived. Build the Kurafuto target first."
  exit 1
fi
# Siri phrases (AppShortcuts table) and every other string (Localizable table) live in separate catalogs.
for catalog in $catalogs; do
  copy="$tmp/$(basename "$catalog")"
  cp "$catalog" "$copy"
  xargs -0 xcrun xcstringstool sync "$copy" --stringsdata < "$tmp/stringsdata"
  if ! cmp -s "$catalog" "$copy"; then
    diff -u "$catalog" "$copy" || true
    echo "::error::$catalog is out of date. Build in Xcode (or run xcstringstool sync) and translate the new strings."
    exit 1
  fi
done

python3 - $languages -- $catalogs <<'PY'
import json, sys

args = sys.argv[1:]
languages, paths = args[:args.index("--")], args[args.index("--") + 1:]
strings = {}
for path in paths:
    strings.update(json.load(open(path, encoding="utf-8"))["strings"])

def finished(localization):
    if "stringSet" in localization:
        phrases = localization["stringSet"]
        return phrases.get("state") == "translated" and bool(phrases.get("values"))
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
