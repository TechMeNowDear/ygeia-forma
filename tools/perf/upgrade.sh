#!/usr/bin/env bash
# Δοκιμή αναβάθμισης σε emulator (έλεγχος 9/11, V-A-22): η νέα έκδοση μπαίνει ΠΑΝΩ στην προηγούμενη (όπως στο Fold,
# «adb install -r» = «Εγκατάσταση» πάνω στην παλιά) και πρέπει να ανοίγει και να διαβάζει τα δεδομένα που υπάρχουν.
#
# Χρήση: bash tools/perf/upgrade.sh <παλιό apk> <νέο apk>
# Τα δύο APK πρέπει να έχουν το ίδιο κλειδί (στο CI: το κλειδί debug του ίδιου runner) και η «παλιά» να είναι ο κώδικας
# της τελευταίας έκδοσης (ετικέτα «latest»).
#
# Βήματα:
# 1. Καθαρή εγκατάσταση της παλιάς, άνοιγμα (φτιάχνει τα δικά της αρχεία: ρυθμίσεις, βάση).
# 2. Δείγμα δεδομένων (ΣΥΝΘΕΤΙΚΟ, όχι αληθινά δεδομένα): training.json με όριο παλμών 137 και μία προπόνηση, στη
#    μορφή της #89. Μπαίνει με root, όπως θα το είχε γράψει η εφαρμογή.
# 3. Άνοιγμα της παλιάς: πρέπει να δείχνει «137 bpm» στην Άσκηση (αλλιώς το δείγμα δεν είναι έγκυρο: προειδοποίηση).
# 4. «adb install -r» της νέας ΧΩΡΙΣ απεγκατάσταση.
# 5. Η νέα πρέπει: να ανοίγει (πρώτη οθόνη, όχι μονόχρωμη), να δείχνει «137 bpm» και ΟΧΙ «Δεν διαβάστηκαν οι
#    προπονήσεις», να κρατά όλα τα αρχεία της παλιάς, το training.json να διαβάζεται και να έχει ακόμα το δείγμα, και
#    να μην υπάρχει κανένα σφάλμα Dart/Kotlin στην ουρά ή κρασάρισμα.
set -u
. "$(dirname "$0")/ui.sh"
OLD="$1"
NEW="$2"
D="/data/data/$PKG"
ok=1
fail() { echo "ΑΠΟΤΥΧΙΑ: $*"; ok=0; }

if ! errq_root; then
  echo "::warning title=Αναβάθμιση::Χωρίς root στον emulator: η δοκιμή αναβάθμισης γίνεται χωρίς δείγμα δεδομένων"
fi

# 1. Παλιά έκδοση, καθαρή.
adb uninstall "$PKG" > /dev/null 2>&1 || true
adb install "$OLD" > install.log 2>&1 || { cat install.log; echo "Η εγκατάσταση της παλιάς έκδοσης απέτυχε"; exit 2; }
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS > /dev/null 2>&1 || true
old_ver=$(adb shell dumpsys package "$PKG" | tr -d '\r' | grep -o 'versionCode=[0-9]*' | head -1 | cut -d= -f2)
launch
ui_wait "Σήμερα" 60 || echo "Παλιά έκδοση: δεν φάνηκε η πρώτη οθόνη (συνεχίζω)"
sleep 5
adb shell am force-stop "$PKG"

# 2. Δείγμα δεδομένων (συνθετικό).
seeded=0
if errq_root; then
  now=$(date +%s)
  start=$(( (now - 2 * 86400) * 1000 ))
  end=$(( start + 35 * 60 * 1000 ))
  cat > seed_training.json <<JSON
{"v":1,"hrLimit":137,"programs":[],"active":null,"sessions":[{"id":"ci-seed-1","w":"","name":"Δοκιμή αναβάθμισης","prog":"","start":$start,"end":$end,"items":[],"hrAvg":101,"hrMax":118,"cmin":35,"hr":[[0,92],[60,101],[120,118]]}],"del":[]}
JSON
  uid=$(adb shell stat -c %u "$D" | tr -d '\r')
  adb push seed_training.json /data/local/tmp/seed_training.json > /dev/null
  adb shell "mkdir -p $D/files && cp /data/local/tmp/seed_training.json $D/files/training.json && chown -R $uid:$uid $D/files && chmod 600 $D/files/training.json && restorecon -R $D/files" \
    && seeded=1
  adb shell rm -f /data/local/tmp/seed_training.json
fi

# 3. Η παλιά διαβάζει το δείγμα;
if [ "$seeded" = 1 ]; then
  launch
  ui_wait "Σήμερα" 60 > /dev/null || true
  if ui_tap "Άσκηση" && sleep 3 && ui_find_scroll "137 bpm" 6; then
    echo "Παλιά έκδοση ($old_ver): διαβάζει το δείγμα (137 bpm)"
  else
    echo "::warning title=Αναβάθμιση::Η παλιά έκδοση δεν έδειξε το δείγμα (137 bpm)· ελέγχεται μόνο ότι η νέα το διαβάζει"
  fi
  shot "upgrade_old" > /dev/null || true
  adb shell am force-stop "$PKG"
fi

# Τι αρχεία έχει η παλιά (ονόματα μόνο).
list_files() { adb shell "cd $D && find files databases shared_prefs no_backup -type f 2>/dev/null | grep -v '^files/errq/'" | tr -d '\r' | LC_ALL=C sort; }
if errq_root; then list_files > files_before.txt; echo "Αρχεία της παλιάς: $(wc -l < files_before.txt)"; fi
errq_clear
adb logcat -c || true
adb logcat -b crash -c || true

# 4. Η νέα ΠΑΝΩ στην παλιά.
if ! adb install -r "$NEW" > install.log 2>&1; then
  cat install.log; echo "ΑΠΟΤΥΧΙΑ: η νέα έκδοση δεν μπαίνει πάνω στην παλιά"; exit 1
fi
new_ver=$(adb shell dumpsys package "$PKG" | tr -d '\r' | grep -o 'versionCode=[0-9]*' | head -1 | cut -d= -f2)
echo "Αναβάθμιση $old_ver → $new_ver: εγκαταστάθηκε πάνω στην παλιά"

# 5. Η νέα ανοίγει και διαβάζει.
launch
if ui_wait "Σήμερα" 60; then echo "Νέα έκδοση: φάνηκε η πρώτη οθόνη"; else fail "η νέα έκδοση δεν έδειξε την πρώτη οθόνη μετά την αναβάθμιση"; fi
shot "upgrade_new_today" || fail "η οθόνη της νέας έκδοσης είναι κενή ή μονόχρωμη"
if [ "$seeded" = 1 ]; then
  if ui_tap "Άσκηση"; then
    sleep 3
    if ui_dump && ui_py find ui.xml "Δεν διαβάστηκαν οι προπονήσεις" > /dev/null; then
      fail "η νέα έκδοση ΔΕΝ διάβασε το training.json της παλιάς («Δεν διαβάστηκαν οι προπονήσεις»)"
    fi
    if ui_find_scroll "137 bpm" 6; then echo "Νέα έκδοση: διαβάζει τα δεδομένα της παλιάς (137 bpm)"; else fail "η νέα έκδοση δεν δείχνει το όριο παλμών της παλιάς (137 bpm)"; fi
    shot "upgrade_new_training" > /dev/null || true
  else
    fail "δεν βρέθηκε το κουμπί «Άσκηση»"
  fi
fi
sleep 5
[ -n "$(app_pid)" ] || fail "η νέα έκδοση δεν τρέχει μετά το άνοιγμα"

if errq_root; then
  list_files > files_after.txt
  missing=$(LC_ALL=C comm -23 files_before.txt files_after.txt)
  if [ -n "$missing" ]; then fail "χάθηκαν αρχεία στην αναβάθμιση:"; echo "$missing"; else echo "Κανένα αρχείο δεν χάθηκε ($(wc -l < files_after.txt) αρχεία)"; fi
  if [ "$seeded" = 1 ]; then
    adb shell cat "$D/files/training.json" > training_after.json
    if python3 -I -c '
import json, sys
j = json.load(open("training_after.json"))
assert j.get("hrLimit") == 137, "hrLimit"
assert any(s.get("id") == "ci-seed-1" for s in j.get("sessions", [])), "session"
'; then echo "training.json μετά την αναβάθμιση: διαβάζεται, έχει το δείγμα"; else fail "το training.json μετά την αναβάθμιση δεν έχει το δείγμα"; fi
  fi
fi
errq_check "Αναβάθμιση" || ok=0
crash_check "Αναβάθμιση" || ok=0

[ "$ok" = 1 ] && echo "Αναβάθμιση: εντάξει" && exit 0
exit 1
