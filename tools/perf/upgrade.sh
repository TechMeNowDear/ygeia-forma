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
# 3β. (έλεγχος 13/11, S12-10) Πρόσθετο δείγμα για όσα δεν σπέρνονταν ποτέ: ρυθμίσεις με «Τα στοιχεία μου», στόχους, ζώνη
#    και μέση (prefs.json), δύο καταχωρίσεις στο ημερολόγιο φαγητού (χθες) και μία μέρα ιστορικού. Η παλιά ανοίγει ξανά,
#    για να τα διαβάσει και να τα ξαναγράψει όπως στο κινητό.
# 4. «adb install -r» της νέας ΧΩΡΙΣ απεγκατάσταση.
# 5. Η νέα πρέπει: να ανοίγει (πρώτη οθόνη, όχι μονόχρωμη), να δείχνει «137 bpm» και ΟΧΙ «Δεν διαβάστηκαν οι
#    προπονήσεις», να κρατά όλα τα αρχεία της παλιάς, το training.json να διαβάζεται και να έχει ακόμα το δείγμα, και
#    να μην υπάρχει κανένα σφάλμα Dart/Kotlin στην ουρά ή κρασάρισμα. Και το πρόσθετο δείγμα (3β): οι ρυθμίσεις, το
#    ημερολόγιο φαγητού και η μέρα ιστορικού ΤΙΜΗ ΠΡΟΣ ΤΙΜΗ όπως ήταν πριν (νέα πρόσθετα κλειδιά επιτρέπονται), και ο
#    στόχος θερμίδων του δείγματος στην οθόνη της Διατροφής (αν τον έδειχνε και η παλιά). Πριν, ο έλεγχος «κανένα
#    αρχείο δεν χάθηκε» σύγκρινε μόνο ΟΝΟΜΑΤΑ αρχείων: μια έκδοση που δεν διάβαζε πια τους στόχους περνούσε πράσινη.
set -u
. "$(dirname "$0")/ui.sh"
OLD="$1"
NEW="$2"
D="/data/data/$PKG"
ok=1
fail() { echo "ΑΠΟΤΥΧΙΑ: $*"; ok=0; }
labels() { tr '>' '\n' < ui.xml 2> /dev/null | grep -o 'text="[^"]*"\|content-desc="[^"]*"' | grep -v '=""' | head -25 | tr '\n' ' '; echo; }
food_mine() { # Το προϊόν-δείγμα στα «δικά μου» (παλιά: Διατροφή › Τα δικά μου· από τα σχέδια 9/11: «+ Φαγητό» › Δικά μου)
  ui_tap "Διατροφή" || { echo "  (δεν βρέθηκε «Διατροφή»)"; return 1; }
  sleep 3
  if ui_tap "Τα δικά μου"; then
    sleep 3
    # Η καρτέλα δείχνει μια κάρτα «Τα προϊόντα μου · N προϊόν»· η λίστα ανοίγει με πάτημα.
    ui_tap "Τα προϊόντα μου" || { echo "  (δεν βρέθηκε η κάρτα «Τα προϊόντα μου»: $(labels))"; return 1; }
    sleep 3
    ui_find_scroll "Προϊόν δοκιμής αναβάθμισης" 4 && { adb shell input keyevent KEYCODE_BACK; sleep 2; return 0; }
  else
    # Νέα διάταξη: η Διατροφή χωρίς υπο-καρτέλες· τα δικά μου είναι στο «+ Φαγητό» (ενότητα «Δικά μου»).
    ui_tap "Φαγητό" || { echo "  (δεν βρέθηκε το «Φαγητό»: $(labels))"; return 1; }
    sleep 3
    # Το πληκτρολόγιο της αναζήτησης ανοίγει μόνο του: κλείνει (μόνο αν φαίνεται), για να φαίνεται η λίστα.
    if adb shell dumpsys input_method | tr -d '\r' | grep -q 'mInputShown=true'; then adb shell input keyevent KEYCODE_BACK; sleep 1; fi
    if ui_find_scroll "Προϊόν δοκιμής αναβάθμισης" 4; then
      adb shell input keyevent KEYCODE_BACK; sleep 2
      return 0
    fi
  fi
  echo "  (στην οθόνη: $(labels))"
  return 1
}

if ! errq_root; then
  echo "::warning title=Αναβάθμιση::Χωρίς root στον emulator: η δοκιμή αναβάθμισης γίνεται χωρίς δείγμα δεδομένων"
fi

# 1. Παλιά έκδοση, καθαρή.
adb uninstall "$PKG" > /dev/null 2>&1 || true
apk_install "$OLD" || { cat install.log; echo "Η εγκατάσταση της παλιάς έκδοσης απέτυχε"; exit 2; }
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

# 3β. Πρόσθετο δείγμα (συνθετικό): ρυθμίσεις, ημερολόγιο φαγητού, ιστορικό. Μπαίνει ΜΕΤΑ τους παραπάνω ελέγχους της
#     παλιάς, ώστε εκείνοι να τρέχουν όπως πάντα. Οι καταχωρίσεις φαγητού μπαίνουν στη χθεσινή μέρα (η σημερινή οθόνη της
#     Διατροφής μένει όπως ήταν για τους ελέγχους με το «Φαγητό»).
# check_more: το πρόσθετο δείγμα όπως είναι ΤΩΡΑ στο κινητό. 0 = κάθε τιμή του υπάρχει και είναι ίδια.
check_more() {
  adb shell "cat $D/files/prefs.json" 2> /dev/null | tr -d '\r' > prefs_now.json
  adb shell "sqlite3 $DB < /data/local/tmp/seed_check.sql" 2> /dev/null | tr -d '\r' > db_now.txt
  python3 -I -c '
import json, sys
exp = json.load(open("seed_expect.json", encoding="utf-8"))
def within(a, b):
    # Κάθε τιμή του a υπάρχει ίδια στο b· το b μπορεί να έχει ΚΑΙ νέα κλειδιά (οι αλλαγές μορφής είναι μόνο πρόσθετες).
    if isinstance(a, dict):
        return isinstance(b, dict) and all(k in b and within(v, b[k]) for k, v in a.items())
    if isinstance(a, list):
        return isinstance(b, list) and len(a) == len(b) and all(within(x, y) for x, y in zip(a, b))
    return isinstance(a, bool) == isinstance(b, bool) and a == b
bad = []
try:
    now = json.load(open("prefs_now.json", encoding="utf-8"))
except Exception:
    now = None
for k, v in exp["prefs"].items():
    if not (isinstance(now, dict) and within(v, now.get(k))):
        bad.append("prefs.json: " + k)
try:
    lines = [l for l in open("db_now.txt", encoding="utf-8").read().splitlines() if l.strip()]
    food = [json.loads(l) for l in lines if not l.startswith("DAY")]
    day = [json.loads(l[3:]) for l in lines if l.startswith("DAY")]
except Exception:
    food, day = [], []
if not within(exp["food"], food):
    bad.append("ημερολόγιο φαγητού (food_log)")
if not (len(day) == 1 and within(exp["hist"], day[0])):
    bad.append("ιστορικό (days)")
if bad:
    print("  δεν είναι όπως μπήκαν: " + ", ".join(bad))
    sys.exit(1)
'
}
goal_ui() { ui_tap "Διατροφή" && sleep 3 && ui_find_scroll "στόχος 2.250" 3; }

more_seeded=0
goal_ui_old=0
if errq_root && [ -n "$(adb shell 'command -v sqlite3' | tr -d '\r')" ] && [ "$(adb shell "test -f $DB && echo y" | tr -d '\r')" = y ]; then
  adb shell am force-stop "$PKG"
  d0=$(adb shell date +%F | tr -d '\r')
  ms=$(( $(adb shell date +%s | tr -d '\r') * 1000 ))
  adb shell "cat $D/files/prefs.json" 2> /dev/null | tr -d '\r' > prefs_old.json
  if python3 -I -c '
import datetime, json, sys
d0 = datetime.date.fromisoformat(sys.argv[1])
ms = int(sys.argv[2])
day = lambda n: (d0 - datetime.timedelta(days=n)).isoformat()
# Ό,τι έγραψε ήδη η παλιά έκδοση στις ρυθμίσεις μένει· προστίθενται τα κλειδιά του δείγματος.
try:
    prefs = json.load(open("prefs_old.json", encoding="utf-8"))
    if not isinstance(prefs, dict):
        prefs = {}
except Exception:
    prefs = {}
# Χωρίς έτος γέννησης στα «στοιχεία μου»: με ηλικία η Άσκηση θα έδειχνε ζώνη περπατήματος, και για 40 ετών το πάνω όριό
# της είναι 137 bpm, ίδιο με το όριο του δείγματος («137 bpm»): ο έλεγχος του ορίου θα περνούσε και χωρίς το όριο.
seed = {
    "me": {"sex": "m", "h": 175, "wds": [1, 3, 5], "wad": 1, "wd": 1},
    "goals": {"v": 1, "aim": "lose", "rate": 0.005, "pal": 1.5, "doc": True, "since": day(10), "kg": 80, "age": 40,
              "h": 175, "m": True, "nuts": 30, "bran": 40, "leg": 3, "fish": 2, "kcal": 2250},
    "zone": {"up": True, "down": False},
    "waist": [{"d": day(8), "v": [92.5, 92.0]}],
}
prefs.update(seed)
json.dump(prefs, open("seed_prefs.json", "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
food = {"id": "ci-seed-meal", "name": "Γεύμα δοκιμής αναβάθμισης", "cat": "", "source": "Ετικέτα",
        "n": {"kcal": 150, "protein": 10, "carbs": 15, "fat": 5}}
rows = [{"id": "ci-seed-log-%d" % i, "day": day(1), "meal": meal, "food": food, "grams": grams,
         "time": ms - 86400000 + i * 60000}
        for i, (meal, grams) in enumerate([("lunch", 200), ("dinner", 150)], 1)]
hist = {"steps": 7654}
q = lambda t: chr(39) + t.replace(chr(39), chr(39) * 2) + chr(39)
enc = lambda o: json.dumps(o, ensure_ascii=False, separators=(",", ":"))
with open("seed_more.sql", "w", encoding="utf-8") as f:
    for r in rows:
        f.write("INSERT OR REPLACE INTO food_log(id, day, json, updated) VALUES(%s, %s, %s, %d);\n" % (q(r["id"]), q(r["day"]), q(enc(r)), ms))
    f.write("INSERT OR REPLACE INTO days(date, json, updated) VALUES(%s, %s, %d);\n" % (q(day(40)), q(enc(hist)), ms))
with open("seed_check.sql", "w", encoding="utf-8") as f:
    f.write("SELECT json FROM food_log WHERE id LIKE %s ORDER BY id;\n" % q("ci-seed-log-%"))
    f.write("SELECT %s || json FROM days WHERE date = %s;\n" % (q("DAY"), q(day(40))))
json.dump({"prefs": seed, "food": rows, "hist": hist}, open("seed_expect.json", "w", encoding="utf-8"), ensure_ascii=False)
' "$d0" "$ms"; then
    uid=$(adb shell stat -c %u "$D" | tr -d '\r')
    adb push seed_prefs.json /data/local/tmp/seed_prefs.json > /dev/null
    adb push seed_more.sql /data/local/tmp/seed_more.sql > /dev/null
    adb push seed_check.sql /data/local/tmp/seed_check.sql > /dev/null
    if adb shell "cp /data/local/tmp/seed_prefs.json $D/files/prefs.json && chown $uid:$uid $D/files/prefs.json && chmod 600 $D/files/prefs.json && restorecon $D/files/prefs.json" \
      && adb shell "sqlite3 $DB < /data/local/tmp/seed_more.sql && chown -R $uid:$uid $D/databases && restorecon -R $D/databases"; then
      more_seeded=1
    fi
    adb shell rm -f /data/local/tmp/seed_prefs.json /data/local/tmp/seed_more.sql
  fi
  if [ "$more_seeded" = 1 ]; then
    # Η παλιά ανοίγει με το πρόσθετο δείγμα (το διαβάζει, ίσως ξαναγράφει τις ρυθμίσεις), όπως στο κινητό πριν από την αναβάθμιση.
    launch
    ui_wait "Σήμερα" 60 > /dev/null || true
    # Ο στόχος του δείγματος στην οθόνη: απαιτείται από τη νέα ΜΟΝΟ αν τον δείχνει και η παλιά (ίδιος έλεγχος, ίδια οθόνη).
    if goal_ui; then goal_ui_old=1; echo "Παλιά έκδοση: δείχνει τον στόχο του δείγματος (στόχος 2.250)"; else echo "Παλιά έκδοση: δεν φάνηκε «στόχος 2.250» στη Διατροφή· στη νέα ελέγχονται μόνο τα αρχεία"; fi
    sleep 3
    adb shell am force-stop "$PKG"
    if check_more; then
      echo "Παλιά έκδοση: κρατά το πρόσθετο δείγμα (ρυθμίσεις, ημερολόγιο φαγητού, ιστορικό)"
    else
      # Το δείγμα δεν έμεινε όπως μπήκε ήδη στην ΠΑΛΙΑ έκδοση: δεν είναι σφάλμα της νέας. Δεν συγκρίνεται (να φανεί).
      more_seeded=0
      echo "::warning title=Αναβάθμιση::Η παλιά έκδοση δεν κράτησε το πρόσθετο δείγμα όπως μπήκε· ενημέρωσε το 3β του tools/perf/upgrade.sh"
    fi
  else
    echo "::warning title=Αναβάθμιση::Δεν μπήκε το πρόσθετο δείγμα (ρυθμίσεις, ημερολόγιο φαγητού, ιστορικό)· ελέγχονται μόνο προπονήσεις και προϊόν"
  fi
fi

# Τι αρχεία έχει η παλιά (ονόματα μόνο).
list_files() { adb shell "cd $D && find files databases shared_prefs no_backup -type f 2>/dev/null | grep -v '^files/errq/'" | tr -d '\r' | LC_ALL=C sort; }
if errq_root; then list_files > files_before.txt; echo "Αρχεία της παλιάς: $(wc -l < files_before.txt)"; fi
errq_clear
adb logcat -c || true
adb logcat -b crash -c || true

# 4. Η νέα ΠΑΝΩ στην παλιά.
if ! apk_install -r "$NEW"; then
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
# Πρόσθετο δείγμα (3β): η νέα έκδοση ΔΙΑΒΑΖΕΙ τους αποθηκευμένους στόχους (τους δείχνει), όπως η παλιά. Δύο προσπάθειες.
if [ "$more_seeded" = 1 ] && [ "$goal_ui_old" = 1 ]; then
  if goal_ui || goal_ui; then
    echo "Νέα έκδοση: δείχνει τον στόχο θερμίδων της παλιάς (στόχος 2.250)"
  else
    fail "η νέα έκδοση δεν δείχνει τον στόχο θερμίδων που είχε η παλιά («στόχος 2.250» στη Διατροφή)"; echo "  (στην οθόνη: $(labels))"
  fi
  shot "upgrade_new_goals" > /dev/null || true
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
if [ "$more_seeded" = 1 ]; then
  if check_more; then
    echo "Νέα έκδοση: ρυθμίσεις (στοιχεία, στόχοι, ζώνη, μέση), ημερολόγιο φαγητού και ιστορικό του δείγματος όπως ήταν"
  else
    fail "μετά την αναβάθμιση άλλαξαν ή χάθηκαν δεδομένα του δείγματος (ρυθμίσεις, ημερολόγιο φαγητού ή ιστορικό)"
  fi
fi
adb shell rm -f /data/local/tmp/seed_check.sql > /dev/null 2>&1 || true
errq_check "Αναβάθμιση" || ok=0
crash_check "Αναβάθμιση" || ok=0

# Τι δοκιμάστηκε πράγματι (η γραμμή φαίνεται στη σημείωση του workflow): ένα «εντάξει» χωρίς δείγμα δεν λέει τίποτα.
[ "$ok" = 1 ] && echo "Αναβάθμιση: εντάξει (δείγμα: προπονήσεις $seeded · προϊόν $food_seeded · ρυθμίσεις, ημερολόγιο, ιστορικό $more_seeded · στόχος στην οθόνη $goal_ui_old)" && exit 0
exit 1
