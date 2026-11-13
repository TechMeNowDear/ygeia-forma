#!/usr/bin/env bash
# Έλεγχος ανοίγματος σε emulator (check.yml, android.yml): καθαρή εγκατάσταση, άνοιγμα 3 φορές. Αποτυγχάνει αν:
# - η εφαρμογή κλείσει (κρασάρισμα Java/Kotlin/native) ή δεν τρέχει μετά από 25 δευτερόλεπτα (μετά την #62, που έκλεινε
#   στο άνοιγμα από κανόνα R8 που έλειπε, ενώ όλοι οι άλλοι έλεγχοι ήταν πράσινοι),
# - δεν φανεί η πρώτη οθόνη: η κάτω μπάρα με «Σήμερα» και «Άσκηση» (έλεγχος 9/11, V-A-22: ένα σφάλμα Dart στην
#   εκκίνηση ΔΕΝ σκοτώνει τη διεργασία· η εφαρμογή μένει σε γκρι/κενή οθόνη και ο παλιός έλεγχος έβγαινε πράσινος),
# - η οθόνη είναι σχεδόν μονόχρωμη (κενή, γκρι οθόνη σφάλματος της Flutter ή μόνο η οθόνη εκκίνησης),
# - μπήκε οποιοδήποτε σφάλμα Dart/Kotlin στην ουρά αναφορών της εφαρμογής (files/errq), ή «E/flutter» στο logcat.
# Τα στιγμιότυπα μένουν στο smoke_shots/ (artifact του job).
set -u
. "$(dirname "$0")/ui.sh"
APK="$1"

adb uninstall "$PKG" > /dev/null 2>&1 || true
apk_install -r "$APK" || { cat install.log; echo "Η εγκατάσταση απέτυχε"; exit 2; }
# Χωρίς παράθυρο αδειών πάνω από την πρώτη οθόνη.
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS > /dev/null 2>&1 || true
adb logcat -c || true
adb logcat -b crash -c || true
errq_clear

ok=1
for i in 1 2 3; do
  launch
  start=$(date +%s)
  if ui_wait "Σήμερα" 45; then
    if ui_py find ui.xml "Άσκηση" > /dev/null; then
      echo "Φορά $i: φάνηκε η πρώτη οθόνη (Σήμερα, Άσκηση) σε ~$(( $(date +%s) - start )) s"
    else
      echo "Φορά $i: φάνηκε «Σήμερα» αλλά όχι η κάτω μπάρα («Άσκηση»)"; ok=0
    fi
  elif [ -s ui.xml ] && [ "$(ui_py nodes ui.xml)" = 0 ]; then
    # Το uiautomator δεν πήρε καμία ετικέτα (π.χ. η Flutter δεν άνοιξε τα semantics): μένει ο έλεγχος εικόνας.
    echo "::warning title=Άνοιγμα::Φορά $i: το uiautomator δεν είδε ετικέτες· έλεγχος μόνο με την εικόνα της οθόνης"
  else
    echo "Φορά $i: η πρώτη οθόνη δεν φάνηκε σε 45 s (λείπει «Σήμερα»)"; ok=0
    tr '>' '\n' < ui.xml 2> /dev/null | grep -o 'text="[^"]*"\|content-desc="[^"]*"' | grep -v '=""' | head -15
  fi
  if ! shot "open_$i"; then echo "Φορά $i: η οθόνη είναι κενή ή μονόχρωμη"; ok=0; fi
  left=$(( 25 - ($(date +%s) - start) )); [ "$left" -gt 0 ] && sleep "$left"
  pid=$(app_pid)
  if [ -z "$pid" ]; then echo "Φορά $i: η εφαρμογή δεν τρέχει μετά από 25 s"; ok=0; else echo "Φορά $i: τρέχει (pid $pid)"; fi
done

# Έλεγχος 13/11 (S10-1): άνοιγμα όπως θα το έκανε ΑΛΛΗ εφαρμογή του κινητού, με extras της Flutter στο Intent. Πρέπει να
# ανοίγει η κανονική εφαρμογή (κάτω μπάρα), όχι η ρύθμιση widget («route»), και να μην κλείνει («cached_engine_id»,
# «background_mode» που δεν υπάρχουν). Ό,τι κρασάρισμα γίνει το πιάνει και το crash_check παρακάτω.
adb shell am force-stop "$PKG"; sleep 2
timeout 60 adb shell am start -W -n "$ACT" --es route /widget --es cached_engine_id x --es dart_entrypoint x \
  --es background_mode x > /dev/null
if ui_wait "Σήμερα" 45 && ui_py find ui.xml "Άσκηση" > /dev/null; then
  echo "Άνοιγμα με ξένα extras: άνοιξε η κανονική εφαρμογή (Σήμερα, Άσκηση)"
elif [ -s ui.xml ] && [ "$(ui_py nodes ui.xml)" = 0 ]; then
  echo "::warning title=Άνοιγμα::Άνοιγμα με ξένα extras: το uiautomator δεν είδε ετικέτες· έλεγχος μόνο για κρασάρισμα"
else
  echo "Άνοιγμα με ξένα extras (route, cached_engine_id, dart_entrypoint, background_mode): ΔΕΝ άνοιξε η κανονική εφαρμογή"; ok=0
fi
shot "open_extras" > /dev/null || true
[ -n "$(app_pid)" ] || { echo "Άνοιγμα με ξένα extras: η εφαρμογή δεν τρέχει"; ok=0; }

errq_check "Άνοιγμα" || ok=0
crash_check "Άνοιγμα" || ok=0

# Αυτοέλεγχος: ένα ψεύτικο σφάλμα στην ουρά ΠΡΕΠΕΙ να πιάνεται (αλλιώς ο έλεγχος δεν βλέπει τίποτα και βγαίνει πράσινος).
if errq_root; then
  ev='{"event_id":"selftest","exception":{"values":[{"type":"StateError","value":"αυτοέλεγχος smoke"}]},"tags":{"screen":"Σήμερα"}}'
  adb shell "mkdir -p /data/data/$PKG/files/errq && echo '$ev' > /data/data/$PKG/files/errq/00000000000000_selftest.json"
  if errq_check "Αυτοέλεγχος" > /dev/null; then echo "Αυτοέλεγχος: ο έλεγχος ΔΕΝ είδε ψεύτικο σφάλμα στην ουρά"; ok=0; else echo "Αυτοέλεγχος: ο έλεγχος πιάνει σφάλμα στην ουρά"; fi
  errq_clear
fi
[ "$ok" = 1 ] && echo "Άνοιγμα: εντάξει" && exit 0
exit 1
