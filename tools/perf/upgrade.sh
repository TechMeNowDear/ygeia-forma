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
labels() { tr '>' '\n' < ui.xml 2> /dev/null | grep -o 'text="[^"]*"\|content-desc="[^"]*"' | grep -v '=""' | head -25 | tr '\n' ' '; echo; }
food_mine() { # Διατροφή › Τα δικά μου › το προϊόν-δείγμα
  ui_tap "Διατροφή" || { echo "  (δεν βρέθηκε «Διατροφή»)"; return 1; }
  sleep 3
  ui_tap "Τα δικά μου" || { echo "  (δεν βρέθηκε «Τα δικά μου»: $(labels))"; return 1; }
  sleep 3
  # Η καρτέλα δείχνει μια κάρτα «Τα προϊόντα μου · N προϊόν»· η λίστα ανοίγει με πάτημα.
  ui_tap "Τα προϊόντα μου" || { echo "  (δεν βρέθηκε η κάρτα «Τα προϊόντα μου»: $(labels))"; return 1; }
  sleep 3
  ui_find_scroll "Προϊόν δοκιμής αναβάθμισης" 4 && { adb shell input keyevent KEYCODE_BACK; sleep 2; return 0; }
  echo "  (στην οθόνη: $(labels))"
  return 1
}

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

# 2β. Δείγμα στη βάση (έλεγχος 9/11, S-11): ένα «προϊόν μου» στον πίνακα my_foods, για να δοκιμάζεται και η αναβάθμιση της
#     βάσης ΜΕ γραμμές (όχι μόνο άδειο αρχείο). Θέλει το sqlite3 της εικόνας του emulator· αν λείπει, προειδοποίηση.
food_seeded=0
DB="$D/databases/ygeia.db"
if errq_root; then
  if [ -z "$(adb shell 'command -v sqlite3' | tr -d '\r')" ]; then
    echo "::warning title=Αναβάθμιση::Ο emulator δεν έχει sqlite3· η βάση δοκιμάζεται χωρίς γραμμές"
  elif [ "$(adb shell "test -f $DB && echo y" | tr -d '\r')" != y ]; then
    echo "::warning title=Αναβάθμιση::Η παλιά έκδοση δεν έφτιαξε ακόμα τη βάση· η βάση δοκιμάζεται χωρίς γραμμές"
  else
    ms=$(( $(date +%s) * 1000 ))
    cat > seed_food.sql <<SQL
INSERT OR REPLACE INTO my_foods(id, json, updated) VALUES('ci-seed-food', '{"id":"ci-seed-food","name":"Προϊόν δοκιμής αναβάθμισης","cat":"","source":"Ετικέτα","n":{"kcal":123,"protein":4,"carbs":20,"fat":3}}', $ms);
SQL
    adb push seed_food.sql /data/local/tmp/seed_food.sql > /dev/null
    uid=$(adb shell stat -c %u "$D" | tr -d '\r')
    if adb shell "sqlite3 $DB < /data/local/tmp/seed_food.sql && chown -R $uid:$uid $D/databases && restorecon -R $D/databases"; then
      food_seeded=1
      echo "Βάση: my_foods = $(adb shell "sqlite3 $DB 'SELECT count(*) FROM my_foods'" | tr -d '\r') γραμμές · $(adb shell "ls -lZ $D/databases" | tr -d '\r' | awk '{print $NF, $3, $5}' | tr '\n' ' ')"
    else
      fail "δεν μπήκε το δείγμα στη βάση της παλιάς έκδοσης (my_foods)"
    fi
    adb shell rm -f /data/local/tmp/seed_food.sql
  fi
fi

# 3. Η παλιά διαβάζει το δείγμα;
if [ "$seeded" = 1 ]; then
  launch
  ui_wait "Σήμερα" 60 > /dev/null || true
  # Έλεγχος 9/11, S-9: αν η παλιά δεν διαβάζει το δείγμα, η δοκιμή δεν δοκιμάζει τίποτα → αποτυχία με σωστή εξήγηση.
  if ui_tap "Άσκηση" && sleep 3 && ui_find_scroll "137 bpm" 6; then
    echo "Παλιά έκδοση ($old_ver): διαβάζει το δείγμα (137 bpm)"
  else
    fail "η παλιά έκδοση δεν διάβασε το δείγμα: ενημέρωσε το seed_training.json (tools/perf/upgrade.sh) στη μορφή της «latest»"
  fi
  shot "upgrade_old" > /dev/null || true
  if [ "$food_seeded" = 1 ]; then
    if food_mine; then
      echo "Παλιά έκδοση: διαβάζει το δείγμα της βάσης («Τα δικά μου»)"
    else
      fail "η παλιά έκδοση δεν έδειξε το προϊόν-δείγμα: ενημέρωσε το seed_food.sql (tools/perf/upgrade.sh) στη μορφή της «latest»"
    fi
  fi
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
if [ "$food_seeded" = 1 ]; then
  if food_mine; then
    echo "Νέα έκδοση: διαβάζει τη βάση της παλιάς («Τα δικά μου»)"
  else
    fail "η νέα έκδοση δεν δείχνει το προϊόν της παλιάς βάσης («Τα δικά μου»)"
  fi
  shot "upgrade_new_food" > /dev/null || true
fi
sleep 5
[ -n "$(app_pid)" ] || fail "η νέα έκδοση δεν τρέχει μετά το άνοιγμα"

if errq_root; then
  list_files > files_after.txt
  missing=$(LC_ALL=C comm -23 files_before.txt files_after.txt)
  if [ -n "$missing" ]; then fail "χάθηκαν αρχεία στην αναβάθμιση:"; echo "$missing"; else echo "Κανένα αρχείο δεν χάθηκε ($(wc -l < files_after.txt) αρχεία)"; fi
  if [ "$seeded" = 1 ]; then
    adb shell cat "$D/files/training.json" > training_after.json
    # Οι παλμοί του δείγματος (3 τιμές): είτε ακόμα μέσα στο training.json είτε μεταφερμένοι στο hr/ci-seed-1.json (#91).
    adb shell cat "$D/files/hr/ci-seed-1.json" > hr_after.json 2> /dev/null || true
    if python3 -I -c '
import json, sys
j = json.load(open("training_after.json"))
assert j.get("hrLimit") == 137, "hrLimit"
s = [s for s in j.get("sessions", []) if s.get("id") == "ci-seed-1"]
assert s, "session"
s = s[0]
if s.get("hr"):
    assert len(s["hr"]) == 3, "hr"
else:
    assert s.get("hrf") == 3, "hrf"
    h = json.load(open("hr_after.json"))
    assert h.get("n") == 3, "hr file"
'; then echo "training.json μετά την αναβάθμιση: διαβάζεται, έχει το δείγμα και τους παλμούς του"; else fail "το training.json μετά την αναβάθμιση δεν έχει το δείγμα ή τους παλμούς του"; fi
  fi
fi
errq_check "Αναβάθμιση" || ok=0
crash_check "Αναβάθμιση" || ok=0

[ "$ok" = 1 ] && echo "Αναβάθμιση: εντάξει" && exit 0
exit 1
