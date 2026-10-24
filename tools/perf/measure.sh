#!/usr/bin/env bash
# Μέτρηση απόδοσης σε emulator Android (GitHub Actions, perf.yml).
# Οι αριθμοί είναι για ΣΥΓΚΡΙΣΗ μεταξύ εκδόσεων, όχι ακριβείς τιμές του Fold:
# ο emulator δεν έχει Samsung Health (άρα ούτε δεδομένα) και ζωγραφίζει με λογισμικό.
set -u
APK="$1"
OUT="${2:-perf.md}"
PKG=gr.ygeiaforma.ygeia_forma
ACT="$PKG/.MainActivity"

say() { echo "$*" | tee -a "$OUT"; }
cpu_ticks() { # utime + stime της διεργασίας, σε «ticks» (συνήθως 1/100 s)
  local pid; pid=$(adb shell pidof "$PKG" | tr -d '\r')
  [ -z "$pid" ] && { echo -1; return; }
  adb shell cat "/proc/$pid/stat" | tr -d '\r' | awk '{print $14 + $15}'
}
pss() { adb shell dumpsys meminfo "$PKG" | tr -d '\r' | awk '/TOTAL PSS:/ {print $3; exit} /^ *TOTAL / {print $2; exit}'; }
tap_label() { # πατάει το στοιχείο με αυτή την ετικέτα (Flutter semantics → uiautomator)
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  local b; b=$(adb shell cat /sdcard/ui.xml | tr -d '\r' | tr '>' '\n' | grep -m1 "content-desc=\"$1\"" | sed -E 's/.*bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]".*/\1 \2 \3 \4/')
  if [ -n "$b" ]; then
    set -- $b
    adb shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
    return 0
  fi
  return 1
}

: > "$OUT"
say "## Μέτρηση απόδοσης · $(date -u +%Y-%m-%d) · emulator $(adb shell getprop ro.build.version.release | tr -d '\r')"
say ""
say "- Μέγεθος APK (x86_64, για τον emulator): $(du -k "$APK" | cut -f1) KB"

adb install -r "$APK" >/dev/null

say ""
say "### Άνοιγμα (κρύο, 3 φορές)"
for i in 1 2 3; do
  adb shell am force-stop "$PKG"; sleep 2
  t=$(adb shell am start -W -n "$ACT" | tr -d '\r' | awk -F': ' '/TotalTime/ {print $2}')
  say "- Φορά $i: ${t:-?} ms"
  sleep 6
done
crash=$(adb logcat -d -b crash | grep -c "$PKG" || true)
say "- Κρασαρίσματα στο logcat: $crash"

sleep 5
say ""
say "### Μνήμη (PSS, KB)"
say "- Μετά το άνοιγμα (Σήμερα): $(pss)"
for tab in "Υγεία" "Διατροφή" "Άσκηση" "Σήμερα"; do
  if tap_label "$tab"; then sleep 3; else say "- (δεν βρέθηκε το κουμπί «$tab»)"; fi
done
sleep 3
say "- Αφού ανοίξουν όλες οι κατηγορίες: $(pss)"
adb shell dumpsys meminfo "$PKG" | tr -d '\r' | grep -E "Java Heap:|Native Heap:|Graphics:|Code:" | sed 's/^ */- /' | tee -a "$OUT"

say ""
say "### Επεξεργαστής (CPU), χρόνος μέσα στο διάστημα"
a=$(cpu_ticks); sleep 30; b=$(cpu_ticks)
say "- Ανοιχτή, χωρίς άγγιγμα, 30 s: $(( (b - a) * 10 )) ms"
adb shell input keyevent KEYCODE_HOME; sleep 5
a=$(cpu_ticks); sleep 60; b=$(cpu_ticks)
if [ "$a" = -1 ] || [ "$b" = -1 ]; then
  say "- Στο παρασκήνιο, 60 s: η διεργασία δεν τρέχει (το Android την έκλεισε)"
else
  say "- Στο παρασκήνιο, 60 s: $(( (b - a) * 10 )) ms"
fi

say ""
say "### Τι μένει να τρέχει στο παρασκήνιο"
svc=$(adb shell dumpsys activity services "$PKG" | tr -d '\r' | grep -c "ServiceRecord" || true)
jobs=$(adb shell dumpsys jobscheduler | tr -d '\r' | grep -c "$PKG" || true)
alarms=$(adb shell dumpsys alarm | tr -d '\r' | grep -c "$PKG" || true)
wl=$(adb shell dumpsys power | tr -d '\r' | grep -i "wake" | grep -c "$PKG" || true)
say "- Services: $svc · Jobs: $jobs · Alarms: $alarms · Wakelocks: $wl"

say ""
say "### Λεπτομέρειες παρασκηνίου"
adb shell dumpsys activity services "$PKG" | tr -d '\r' | grep -E "ServiceRecord|intent=" | head -6 | sed 's/^ */- /' | tee -a "$OUT"
adb shell dumpsys jobscheduler | tr -d '\r' | grep "$PKG" | grep -E "JOB #|Job #|#u0" | head -6 | sed 's/^ */- /' | tee -a "$OUT"
