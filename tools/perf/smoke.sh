#!/usr/bin/env bash
# Έλεγχος ανοίγματος σε emulator (check.yml): εγκαθιστά το APK, το ανοίγει 3 φορές και αποτυγχάνει
# αν κλείσει (κρασάρισμα) ή αν δεν τρέχει μετά από 25 δευτερόλεπτα. Γράφτηκε μετά την #62, που έκλεινε
# στο άνοιγμα από κανόνα R8 που έλειπε, ενώ όλοι οι άλλοι έλεγχοι ήταν πράσινοι.
set -u
APK="$1"
PKG=gr.ygeiaforma.ygeia_forma
ACT="$PKG/.MainActivity"

adb install -r "$APK" > install.log 2>&1 || { cat install.log; echo "Η εγκατάσταση απέτυχε"; exit 2; }
adb logcat -b crash -c || true
ok=1
for i in 1 2 3; do
  adb shell am force-stop "$PKG"; sleep 2
  adb shell am start -W -n "$ACT" > /dev/null
  sleep 25
  pid=$(adb shell pidof "$PKG" | tr -d '\r')
  if [ -z "$pid" ]; then echo "Φορά $i: η εφαρμογή δεν τρέχει μετά από 25 s"; ok=0; else echo "Φορά $i: τρέχει (pid $pid)"; fi
done
adb logcat -b crash -d > crash.log 2>&1 || true
if grep -q "FATAL EXCEPTION\|Fatal signal" crash.log; then
  echo "Βρέθηκε κρασάρισμα:"; grep -v "^---" crash.log | head -40; ok=0
fi
[ "$ok" = 1 ] && echo "Άνοιγμα: εντάξει" && exit 0
exit 1
