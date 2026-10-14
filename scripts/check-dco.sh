#!/usr/bin/env bash
# Verifies that every non-merge commit in BASE..HEAD carries a Signed-off-by
# trailer that matches its author exactly (Developer Certificate of Origin 1.1).
set -euo pipefail

base=${1:?usage: check-dco.sh <base-sha> <head-sha>}
head=${2:?usage: check-dco.sh <base-sha> <head-sha>}

missing=0
for sha in $(git rev-list --no-merges "$base..$head"); do
  name=$(git show -s --format='%an' "$sha")
  email=$(git show -s --format='%ae' "$sha")
  subject=$(git show -s --format='%s' "$sha")
  expected="Signed-off-by: $name <$email>"
  if git show -s --format='%(trailers:key=Signed-off-by)' "$sha" | grep -qiF -- "$expected"; then
    echo "ok      $sha $subject"
  else
    echo "::error::$sha is missing '$expected'"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "Fix with: git rebase --signoff $base && git push --force-with-lease"
  exit 1
fi
