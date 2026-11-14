# shellcheck shell=bash
# Κοινές συναρτήσεις για τους ελέγχους σε emulator (smoke.sh, upgrade.sh, measure.sh). Φορτώνεται με «source».
# Η Flutter δίνει στο uiautomator τα ονόματα των στοιχείων (semantics, π.χ. «Σήμερα», «Άσκηση» στην κάτω μπάρα).
# adb από το Android SDK του runner (κάθε script τρέχει σε δικό του shell).
SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$SDK_DIR" ] && export PATH="$SDK_DIR/platform-tools:$PATH"
PKG=gr.ygeiaforma.ygeia_forma
ACT="$PKG/.MainActivity"
UI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHOTS="${SHOTS:-smoke_shots}"
mkdir -p "$SHOTS"

ui_py() { python3 -I "$UI_DIR/ui.py" "$@"; }

# Γράφει την ιεραρχία της οθόνης στο ui.xml. 0 = πέτυχε.
ui_dump() {
  for _ in 1 2 3; do
    rm -f ui.xml
    timeout 45 adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1
    timeout 20 adb exec-out cat /sdcard/ui.xml > ui.xml 2> /dev/null
    if [ -s ui.xml ] && grep -q '<hierarchy' ui.xml; then return 0; fi
    sleep 2
  done
  return 1
}

# sys_anr_wait: αν η οθόνη (ui.xml) δείχνει «… isn't responding» ΑΛΛΗΣ διεργασίας (π.χ. System UI του emulator), πατά
# «Wait», τυπώνει προειδοποίηση με την αιτία από το logcat και επιστρέφει 0. Για τη δική μας εφαρμογή: 1 (ui.py anr).
sys_anr_wait() {
  local who xy
  who=$(ui_py anr ui.xml) || return 1
  echo "::warning title=Emulator::Παράθυρο «$who isn't responding» πάνω από την εφαρμογή· πατήθηκε «Wait»"
  adb logcat -d 2> /dev/null | grep -a -A5 "ANR in " | grep -a -v "^--$" | tail -6 | sed 's/^/    /'
  xy=$(ui_py find ui.xml "Wait") && adb shell input tap $xy
  sleep 2
  return 0
}

# ui_wait "κείμενο" [δευτερόλεπτα]: περιμένει να φανεί στοιχείο που περιέχει το κείμενο. 0 = φάνηκε.
# Ένα παράθυρο «isn't responding» άλλης διεργασίας κλείνεται με «Wait» (sys_anr_wait) και ο χρόνος συνεχίζει να μετρά.
ui_wait() {
  local want="$1" end=$(( $(date +%s) + ${2:-40} ))
  while :; do
    if ui_dump; then
      ui_py find ui.xml "$want" > /dev/null && return 0
      sys_anr_wait
    fi
    [ "$(date +%s)" -ge "$end" ] && return 1
    sleep 3
  done
}

# ui_tap "κείμενο": πατά το στοιχείο που περιέχει το κείμενο. 0 = πατήθηκε.
ui_tap() {
  local xy
  ui_dump || return 1
  xy=$(ui_py find ui.xml "$1") || return 1
  adb shell input tap $xy
}

# ui_find_scroll "κείμενο" [φορές]: ψάχνει το κείμενο κυλώντας προς τα κάτω. 0 = βρέθηκε.
ui_find_scroll() {
  local size w h
  size=$(adb shell wm size | tr -d '\r' | awk -F': ' '/size/ {s=$2} END {print s}')
  w=${size%x*}; h=${size#*x}
  for _ in $(seq 0 "${2:-6}"); do
    if ui_dump && ui_py find ui.xml "$1" > /dev/null; then return 0; fi
    adb shell input swipe $((w / 2)) $((h * 7 / 10)) $((w / 2)) $((h * 3 / 10)) 400
    sleep 2
  done
  return 1
}

# shot <όνομα>: στιγμιότυπο (png για το artifact) και έλεγχος ότι η οθόνη ΔΕΝ είναι σχεδόν μονόχρωμη.
# 0 = έχει περιεχόμενο. Τυπώνει την ανάλυση.
shot() {
  timeout 30 adb exec-out screencap -p > "$SHOTS/$1.png" 2> /dev/null || true
  timeout 30 adb exec-out screencap > screen.raw 2> /dev/null || return 1
  ui_py screen screen.raw
}

app_pid() { adb shell pidof "$PKG" | tr -d '\r'; }

# Ουρά σφαλμάτων της εφαρμογής (files/errq): κάθε σφάλμα Dart (FlutterError, ό,τι ξεφεύγει) και Kotlin μπαίνει εκεί
# στην έκδοση release (δεν γράφεται στο logcat). Χωρίς δίκτυο μένει στην ουρά. Θέλει root (emulator google_apis).
# errq_clear: σβήνει την ουρά. errq_check <φάση>: 0 = άδεια· αλλιώς τυπώνει είδος, μήνυμα (πρώτη γραμμή) και οθόνη.
errq_root() { [ "$(adb shell id -u 2> /dev/null | tr -d '\r')" = 0 ]; }
errq_clear() { errq_root && adb shell "rm -f /data/data/$PKG/files/errq/*.json" > /dev/null 2>&1; return 0; }
errq_check() {
  if ! errq_root; then echo "$1: χωρίς root, η ουρά σφαλμάτων δεν ελέγχθηκε"; return 0; fi
  local files f n=0
  files=$(adb shell "ls /data/data/$PKG/files/errq/ 2>/dev/null" | tr -d '\r' | grep '\.json$' || true)
  for f in $files; do
    n=$((n + 1))
    adb shell "cat /data/data/$PKG/files/errq/$f" > errq_event.json 2> /dev/null
    python3 -I -c '
import json, sys
e = json.load(open("errq_event.json"))
v = (e.get("exception") or {}).get("values") or [{}]
fr = [f for f in (v[0].get("stacktrace") or {}).get("frames", []) if f.get("in_app")]
where = fr[-1] if fr else {}
print("  - {} : {} · οθόνη «{}» · {} {}".format(v[0].get("type"), v[0].get("value"), (e.get("tags") or {}).get("screen"),
      where.get("filename", ""), where.get("lineno", "")))
' 2> /dev/null || echo "  - (αρχείο $f)"
  done
  if [ "$n" -gt 0 ]; then echo "$1: $n σφάλματα στην ουρά της εφαρμογής (Dart/Kotlin):"; return 1; fi
  echo "$1: κανένα σφάλμα Dart/Kotlin στην ουρά"
  return 0
}

# crash_check <φάση>: κρασάρισμα της δικής μας διεργασίας (Java/Kotlin, native) ή σφάλμα της μηχανής Flutter.
crash_check() {
  local ok=0
  timeout 30 adb logcat -b crash -d > crash.log 2>&1 || true
  if grep -q "Process: $PKG\|>>> $PKG <<<" crash.log; then
    echo "$1: κρασάρισμα:"; grep -A30 "Process: $PKG\|>>> $PKG <<<" crash.log | head -40; ok=1
  fi
  timeout 30 adb logcat -d -v brief -s flutter:E > flutter.log 2>&1 || true
  if grep -q "E/flutter" flutter.log; then
    echo "$1: σφάλμα Flutter στο logcat:"; grep "E/flutter" flutter.log | head -20; ok=1
  fi
  return $ok
}

# launch: άνοιγμα από την αρχή (κρύο).
launch() {
  adb shell am force-stop "$PKG"; sleep 2
  timeout 60 adb shell am start -W -n "$ACT" > /dev/null
}

# Εγκατάσταση με ξαναδοκιμή (10/11): στον emulator Android 17 η υπηρεσία package έσπαγε πού και πού αμέσως μετά την
# εκκίνηση («Broken pipe», «Can't find service: package»). Μόνο σφάλματα υποδομής ξαναδοκιμάζονται· ένα πραγματικό
# «INSTALL_FAILED_…» (π.χ. άλλο κλειδί, μικρότερος versionCode) αποτυγχάνει αμέσως, όπως πριν.
apk_install() {
  local i
  for i in 1 2 3 4; do
    [ "$i" = 4 ] && set -- --no-streaming "$@"
    adb install "$@" > install.log 2>&1 && return 0
    grep -q 'INSTALL_FAILED\|INSTALL_PARSE_FAILED' install.log && return 1
    echo "Εγκατάσταση: ξαναδοκιμή $i ($(tr -d '\r' < install.log | tail -1))"
    timeout 120 adb wait-for-device > /dev/null 2>&1
    for _ in $(seq 1 30); do adb shell pm path android 2> /dev/null | grep -q '^package:' && break; sleep 2; done
    sleep 10
  done
  timeout 20 adb logcat -b crash -d 2> /dev/null | tail -30
  return 1
}
