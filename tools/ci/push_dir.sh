#!/usr/bin/env bash
# Ανεβάζει έναν φάκελο (στιγμιότυπα) ως ΜΟΝΟ commit σε έναν κλάδο του repository (force push).
# Τρέχει σε μικρό job με δικαίωμα εγγραφής, ΧΩΡΙΣ χτίσιμο ή εξαρτήσεις (έλεγχος 9/11): τα jobs που χτίζουν έχουν μόνο
# ανάγνωση, ώστε μια παραβιασμένη εξάρτηση να μη μπορεί να γράψει στο repository.
# Χρήση: GH_TOKEN=… bash tools/ci/push_dir.sh <φάκελος> <κλάδος> <μήνυμα>
set -eu
dir="$1"; branch="$2"; msg="$3"
[ -d "$dir" ] && [ -n "$(ls -A "$dir")" ] || { echo "Ο φάκελος $dir είναι κενός· τίποτα για ανέβασμα"; exit 0; }
cd "$dir"
rm -rf .git
git init -q
git checkout -q -b "$branch"
git add .
git -c user.name="ygeia-ci" -c user.email="ci@ygeia.local" commit -qm "$msg"
auth=$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 -w0)
git -c http.extraheader="AUTHORIZATION: basic $auth" push -qf "https://github.com/${GITHUB_REPOSITORY}.git" "$branch"
echo "Ανέβηκε στο $branch: $msg"
