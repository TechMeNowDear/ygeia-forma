#!/usr/bin/env bash
# Χτίζει, για τη δοκιμή αναβάθμισης (tools/perf/upgrade.sh), το APK x86_64 του κώδικα της ΤΕΛΕΥΤΑΙΑΣ ΕΚΔΟΣΗΣ
# (ετικέτα «latest» στο Releases), με το ίδιο κλειδί debug του runner με το νέο APK (ώστε να μπαίνει το ένα πάνω στο
# άλλο). Το πραγματικό APK της έκδοσης δεν κάνει: είναι arm64 και έχει το σταθερό κλειδί, που δεν μπαίνει ποτέ σε
# αυτόν τον έλεγχο.
#
# Χρήση: bash tools/ci/build_old_apk.sh <έξοδος.apk> <νέο.apk>
# Έξοδος 0 = έτοιμο· 3 = δεν βρέθηκε/δεν χτίστηκε η παλιά (η δοκιμή παραλείπεται με προειδοποίηση, δεν κρύβεται).
set -u
out="$1"
new="$2"
refs=$(git ls-remote origin 'refs/tags/latest' 'refs/tags/latest^{}' 2> /dev/null)
sha=$(printf '%s\n' "$refs" | awk '/\^\{\}$/ {print $1}' | head -1)
[ -n "$sha" ] || sha=$(printf '%s\n' "$refs" | awk 'NR==1 {print $1}')
[ -n "$sha" ] || { echo "Δεν βρέθηκε η ετικέτα «latest»"; exit 3; }
echo "Τελευταία έκδοση: commit $sha"
if [ "$sha" = "$(git rev-parse HEAD)" ]; then
  echo "Ίδιος κώδικας με τον τρέχοντα: η «παλιά» είναι το ίδιο APK (αναβάθμιση πάνω σε υπάρχοντα δεδομένα)"
  cp "$new" "$out"
  exit 0
fi
dir="${RUNNER_TEMP:-/tmp}/ygeia-old"
rm -rf "$dir"
git fetch --no-tags --depth=1 origin "$sha" > /dev/null 2>&1 || { echo "Δεν κατέβηκε το commit $sha"; exit 3; }
git worktree add --detach "$dir" "$sha" > /dev/null 2>&1 || { echo "Δεν φτιάχτηκε φάκελος για το $sha"; exit 3; }
bash "$(dirname "$0")/prepare_android.sh" "$dir" > old-prepare.log 2>&1 || { tail -20 old-prepare.log; exit 3; }
if ! (cd "$dir" && flutter build apk --release --target-platform android-x64 --build-number=1) > old-build.log 2>&1; then
  grep -E "error|Error|FAILURE" old-build.log | head -20
  exit 3
fi
cp "$dir/build/app/outputs/flutter-apk/app-release.apk" "$out"
ls -lh "$out"
