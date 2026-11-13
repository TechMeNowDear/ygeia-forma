#!/usr/bin/env bash
# Χτίζει, για τη δοκιμή αναβάθμισης (tools/perf/upgrade.sh), το APK x86_64 του κώδικα της ΤΕΛΕΥΤΑΙΑΣ ΕΚΔΟΣΗΣ
# (ετικέτα «latest» στο Releases), με το ίδιο κλειδί debug του runner με το νέο APK (ώστε να μπαίνει το ένα πάνω στο
# άλλο). Το πραγματικό APK της έκδοσης δεν κάνει: είναι arm64 και έχει το σταθερό κλειδί, που δεν μπαίνει ποτέ σε
# αυτόν τον έλεγχο.
#
# Χρήση: bash tools/ci/build_old_apk.sh <έξοδος.apk> <νέο.apk>
# Έξοδος (έλεγχος 13/11, S10-6 / S12-10): το workflow ξεχωρίζει το «δεν υπάρχει τίποτα να δοκιμαστεί» από το «υπάρχει
# προηγούμενη έκδοση αλλά η δοκιμή δεν μπόρεσε να γίνει». Πριν, και τα δύο έβγαζαν 3 και στο main η έκδοση δημοσιευόταν
# χωρίς δοκιμή αναβάθμισης, με μία προειδοποίηση που κανείς δεν διαβάζει.
#   0 = έτοιμο
#   3 = δεν υπάρχει προηγούμενη έκδοση (καμία ετικέτα «latest» ή «build-…»): η δοκιμή παραλείπεται, σωστά
#   4 = υπάρχει προηγούμενη έκδοση, αλλά το APK της δεν βγήκε (το GitHub δεν απάντησε μετά από ξαναδοκιμές, ή ο παλιός
#       κώδικας δεν χτίζεται): στο main η έκδοση ΔΕΝ βγαίνει χωρίς τη δοκιμή (android.yml)
set -u
out="$1"
new="$2"

# Ετικέτες από το GitHub, με ξαναδοκιμή (το δίκτυο αποτυγχάνει πού και πού· και η «latest» λείπει για λίγα δευτερόλεπτα
# όσο ένα άλλο χτίσιμο τη σβήνει και την ξαναφτιάχνει). Τυπώνει τις γραμμές του «git ls-remote».
# 0 = βρέθηκαν · 2 = το GitHub απάντησε και ΔΕΝ υπάρχει τέτοια ετικέτα · 1 = δεν απάντησε.
remote_refs() {
  local i rc found
  for i in 1 2 3 4 5; do
    found=$(git ls-remote --exit-code origin "$@" 2> /dev/null); rc=$?
    if [ "$rc" = 0 ]; then printf '%s\n' "$found"; return 0; fi
    # «Δεν υπάρχει»: δύο ακόμα ερωτήσεις μετά από λίγο (η «latest» μπορεί να ξαναφτιάχνεται αυτή τη στιγμή).
    if [ "$rc" = 2 ] && [ "$i" -ge 3 ]; then return 2; fi
    echo "git ls-remote: ξαναδοκιμή $i" >&2
    sleep $((i * 10))
  done
  return 1
}

refs=$(remote_refs 'refs/tags/latest' 'refs/tags/latest^{}'); rc=$?
if [ "$rc" = 2 ]; then
  # Έλεγχος 13/11 (S10-8): χωρίς «latest» (π.χ. μια δημοσίευση που κόπηκε ανάμεσα στο σβήσιμο και στη δημιουργία της) η
  # τελευταία έκδοση είναι η νεότερη «build-N» του Releases.
  refs=$(remote_refs 'refs/tags/build-*'); rc=$?
  if [ "$rc" = 2 ]; then
    echo "Δεν υπάρχει προηγούμενη έκδοση (καμία ετικέτα «latest» ή «build-…»)"
    exit 3
  fi
  if [ "$rc" = 0 ]; then
    # Μόνο ετικέτες «build-N» ακριβώς (και η μορφή «build-N^{}»), όχι π.χ. «build-100-rc».
    top=$(printf '%s\n' "$refs" | grep -E 'refs/tags/build-[0-9]+(\^\{\})?$' | sed -n 's#.*refs/tags/build-\([0-9][0-9]*\).*#\1#p' | sort -n | tail -1)
    if [ -z "$top" ]; then
      echo "Δεν υπάρχει προηγούμενη έκδοση (καμία ετικέτα «latest» ή «build-N»)"
      exit 3
    fi
    refs=$(printf '%s\n' "$refs" | grep -E "refs/tags/build-$top(\\^\\{\\})?\$")
    echo "Η ετικέτα «latest» λείπει· τελευταία έκδοση = build-$top"
  fi
fi
if [ "$rc" != 0 ]; then
  echo "Το GitHub δεν απάντησε για τις ετικέτες των εκδόσεων (5 προσπάθειες)"
  exit 4
fi
sha=$(printf '%s\n' "$refs" | awk '/\^\{\}$/ {print $1}' | head -1)
[ -n "$sha" ] || sha=$(printf '%s\n' "$refs" | awk 'NR==1 {print $1}')
[ -n "$sha" ] || { echo "Δεν διαβάστηκε το commit της τελευταίας έκδοσης"; exit 4; }
echo "Τελευταία έκδοση: commit $sha"
if [ "$sha" = "$(git rev-parse HEAD)" ]; then
  echo "Ίδιος κώδικας με τον τρέχοντα: η «παλιά» είναι το ίδιο APK (αναβάθμιση πάνω σε υπάρχοντα δεδομένα)"
  cp "$new" "$out"
  exit 0
fi
dir="${RUNNER_TEMP:-/tmp}/ygeia-old"
rm -rf "$dir"
fetched=0
for i in 1 2 3; do
  if git fetch --no-tags --depth=1 origin "$sha" > /dev/null 2>&1; then fetched=1; break; fi
  echo "git fetch: ξαναδοκιμή $i"
  sleep $((i * 10))
done
[ "$fetched" = 1 ] || { echo "Δεν κατέβηκε το commit $sha"; exit 4; }
git worktree prune > /dev/null 2>&1 || true
git worktree add --detach "$dir" "$sha" > /dev/null 2>&1 || { echo "Δεν φτιάχτηκε φάκελος για το $sha"; exit 4; }
bash "$(dirname "$0")/prepare_android.sh" "$dir" > old-prepare.log 2>&1 || { tail -20 old-prepare.log; exit 4; }
# Δύο προσπάθειες: το παλιό δέντρο μπορεί να θέλει βιβλιοθήκες που δεν είναι στη μνήμη του Gradle (κατέβασμα).
built=0
for i in 1 2; do
  if (cd "$dir" && flutter build apk --release --target-platform android-x64 --build-number=1) > old-build.log 2>&1; then
    built=1; break
  fi
  echo "Χτίσιμο της τελευταίας έκδοσης: αποτυχία $i"
  grep -E "error|Error|FAILURE" old-build.log | head -20
  sleep 20
done
[ "$built" = 1 ] || exit 4
cp "$dir/build/app/outputs/flutter-apk/app-release.apk" "$out"
ls -lh "$out"
