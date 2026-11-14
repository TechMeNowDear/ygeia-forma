#!/usr/bin/env python3
"""Προσθήκες στο AndroidManifest.xml που φτιάχνει το «flutter create» (δεν το κρατάμε στο repository).

Για τη σύνδεση με το Oura (απόφαση 2/11, διόρθωση μετά τον έλεγχο):
1. Μικρή οθόνη OuraCallbackActivity για τη διεύθυνση επιστροφής (OAuth redirect), με δύο ακριβείς μορφές:
   - App Link https://ygeia-forma.netlify.app/oura/callback (autoVerify, assetlinks.json στο Netlify),
   - ygeiaforma://oura-callback (custom scheme, εφεδρική).
   Η MainActivity ΔΕΝ αλλάζει (μένει όπως τη φτιάχνει η Flutter: launchMode, επιλογέας αρχείων, άδειες Samsung).
2. <queries> για browser (https), όπως θέλει το Android 11+ για να βλέπει ποιος ανοίγει συνδέσμους.
3. Κανόνες αντιγράφου Google (έλεγχος 4/11, A10): μόνο βάση, ρυθμίσεις, σχέδιο πηγών, νύχτες Oura
   (tools/android/xml → res/xml: data_extraction_rules.xml, backup_rules.xml)· όχι το βοηθητικό αρχείο, όχι tokens.

Τρέχει όσες φορές θέλουμε (δεν προσθέτει δεύτερη φορά). Σταματά με σφάλμα αν δεν βρει ό,τι περιμένει.
Χρήση: python3 tools/android/patch_manifest.py android/app/src/main/AndroidManifest.xml
"""
import os
import re
import shutil
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    s = f.read()

CALLBACK = (
    "\n        <!-- Σύνδεση Oura: επιστροφή από τη σελίδα της Oura (OAuth). Δίνει τον κωδικό στην εφαρμογή και κλείνει. -->\n"
    "        <activity\n"
    '            android:name=".OuraCallbackActivity"\n'
    '            android:exported="true"\n'
    '            android:noHistory="true"\n'
    '            android:excludeFromRecents="true"\n'
    '            android:taskAffinity=""\n'
    '            android:theme="@android:style/Theme.Translucent.NoTitleBar">\n'
    '            <intent-filter android:autoVerify="true">\n'
    '                <action android:name="android.intent.action.VIEW"/>\n'
    '                <category android:name="android.intent.category.DEFAULT"/>\n'
    '                <category android:name="android.intent.category.BROWSABLE"/>\n'
    '                <data android:scheme="https" android:host="ygeia-forma.netlify.app" android:path="/oura/callback"/>\n'
    "            </intent-filter>\n"
    "            <intent-filter>\n"
    '                <action android:name="android.intent.action.VIEW"/>\n'
    '                <category android:name="android.intent.category.DEFAULT"/>\n'
    '                <category android:name="android.intent.category.BROWSABLE"/>\n'
    '                <data android:scheme="ygeiaforma" android:host="oura-callback"/>\n'
    "            </intent-filter>\n"
    "        </activity>"
)
# Widgets αρχικής οθόνης (7/11): τέσσερις παροχείς και η οθόνη ρύθμισης (Flutter, διαδρομή «/widget»).
WIDGETS = "\n        <!-- Widgets αρχικής οθόνης (7/11). Η ρύθμιση ανοίγει όταν μπαίνει widget και με παρατεταμένο πάτημα. -->\n" + (
    "        <activity\n"
    '            android:name=".WidgetConfigActivity"\n'
    '            android:exported="true"\n'
    '            android:taskAffinity=""\n'
    '            android:excludeFromRecents="true"\n'
    '            android:theme="@style/LaunchTheme"\n'
    '            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"\n'
    '            android:hardwareAccelerated="true"\n'
    '            android:windowSoftInputMode="adjustResize">\n'
    '            <meta-data android:name="io.flutter.embedding.android.NormalTheme" android:resource="@style/NormalTheme"/>\n'
    '            <meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>\n'
    "            <intent-filter>\n"
    '                <action android:name="android.appwidget.action.APPWIDGET_CONFIGURE"/>\n'
    "            </intent-filter>\n"
    "        </activity>"
) + "".join(
    "\n        <receiver\n"
    f'            android:name=".{cls}"\n'
    '            android:exported="false"\n'
    f'            android:label="{label}">\n'
    "            <intent-filter>\n"
    '                <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>\n'
    # Έλεγχος 9/11 (D2-05): αλλαγή ώρας ή ζώνης → ξαναζωγράφισμα (εξαιρούνται από τα όρια των σιωπηρών broadcasts).
    + ('                <action android:name="android.intent.action.TIME_SET"/>\n'
       '                <action android:name="android.intent.action.TIMEZONE_CHANGED"/>\n' if cls == "MoveWidget" else "")
    + "            </intent-filter>\n"
    f'            <meta-data android:name="android.appwidget.provider" android:resource="@xml/widget_{res}"/>\n'
    "        </receiver>"
    for cls, label, res in (("SleepWidget", "Ύπνος", "sleep"), ("MoveWidget", "Κίνηση", "move"),
                            ("FoodWidget", "Φαγητό", "food"), ("BodyWidget", "Σώμα", "body"),
                            # 13/11: δύο απλά widgets με γράμματα (QuickWidgets.kt), χωρίς οθόνη ρύθμισης.
                            ("WorkoutWidget", "Προπόνηση σήμερα", "workout"), ("QuickFoodWidget", "Γρήγορο φαγητό", "quickfood"))
)

# Φωνή του ρολογιού από το κινητό (14/11, SayService.kt): ξυπνά ΜΟΝΟ με το μήνυμα «/ygeia/say» του ρολογιού (στην
# άσκηση), για να ακουστεί το «Πρώτο χιλιόμετρο» στα ακουστικά του κινητού, μέσα στη μουσική.
SAY = (
    "\n        <!-- Φωνή του ρολογιού στα ακουστικά του κινητού (14/11). Μόνο με μήνυμα του ρολογιού στην άσκηση. -->\n"
    "        <service\n"
    '            android:name=".SayService"\n'
    '            android:exported="true">\n'
    "            <intent-filter>\n"
    '                <action android:name="com.google.android.gms.wearable.MESSAGE_RECEIVED"/>\n'
    '                <data android:scheme="wear" android:host="*" android:path="/ygeia/say"/>\n'
    "            </intent-filter>\n"
    "        </service>"
)
TTS_QUERY = (
    "\n        <!-- Φωνή (14/11): το Android 11+ θέλει να δηλωθεί ότι ψάχνουμε μηχανή φωνής (TextToSpeech). -->\n"
    "        <intent>\n"
    '            <action android:name="android.intent.action.TTS_SERVICE"/>\n'
    "        </intent>"
)

BROWSER = (
    "\n        <!-- Σύνδεση Oura: άνοιγμα της σελίδας σύνδεσης στον browser. -->\n"
    "        <intent>\n"
    '            <action android:name="android.intent.action.VIEW"/>\n'
    '            <category android:name="android.intent.category.BROWSABLE"/>\n'
    '            <data android:scheme="https"/>\n'
    "        </intent>"
)

if not re.search(r'<activity\b[^>]*android:name="\.MainActivity"', s, re.S):
    sys.exit("Δεν βρέθηκε η MainActivity στο manifest")
before_main = re.search(r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>', s, re.S).group(0)

# Έλεγχος 9/11 (E3-08, D2-06, Sentry YGEIA-FORMA-3): κανένα URI που φτάνει στη MainActivity (από άλλη εφαρμογή,
# συντόμευση, ειδοποίηση) δεν γίνεται διαδρομή της Flutter. Τα widgets ανοίγουν με extra και κανάλι, η Oura από τη
# δική της οθόνη: η εφαρμογή δεν χρησιμοποιεί deep links της Flutter. Μπαίνει ΜΕΣΑ στη MainActivity (η ετικέτα της
# μένει ίδια) και στη WidgetConfigActivity (εκεί η διαδρομή «/widget» έρχεται από τον κώδικα, getInitialRoute).
DEEPLINK = '\n            <meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>'
main_at = s.index(before_main)
if "flutter_deeplinking_enabled" not in s[main_at:s.index("</activity>", main_at)]:
    s = s.replace(before_main, before_main + DEEPLINK, 1)

# Προπόνηση (8/11): δόνηση στο τέλος του διαλείμματος και ειδοποίηση με αντίστροφη μέτρηση.
for perm in ("android.permission.VIBRATE", "android.permission.POST_NOTIFICATIONS"):
    if f'android:name="{perm}"' not in s:
        s = s.replace("<application", f'<uses-permission android:name="{perm}"/>\n    <application', 1)

if ".OuraCallbackActivity" not in s:
    if "</application>" not in s:
        sys.exit("Δεν βρέθηκε το τέλος του application")
    s = s.replace("</application>", CALLBACK.lstrip("\n") + "\n    </application>", 1)

if ".WidgetConfigActivity" not in s:
    s = s.replace("</application>", WIDGETS.lstrip("\n") + "\n    </application>", 1)

if ".SayService" not in s:
    s = s.replace("</application>", SAY.lstrip("\n") + "\n    </application>", 1)

if "<!-- Σύνδεση Oura: άνοιγμα" not in s:
    if "<queries>" in s:
        s = s.replace("<queries>", "<queries>" + BROWSER, 1)
    else:
        s = s.replace("</manifest>", "    <queries>" + BROWSER + "\n    </queries>\n</manifest>", 1)

if "android.intent.action.TTS_SERVICE" not in s:
    s = s.replace("<queries>", "<queries>" + TTS_QUERY, 1)

# Τα αρχεία των κανόνων (το res/ το φτιάχνει το «flutter create» και δεν το κρατάμε στο repository).
xml_src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xml")
xml_dst = os.path.join(os.path.dirname(os.path.abspath(path)), "res", "xml")
os.makedirs(xml_dst, exist_ok=True)
for name in ("data_extraction_rules.xml", "backup_rules.xml", "widget_sleep.xml", "widget_move.xml", "widget_food.xml",
             "widget_body.xml", "widget_workout.xml", "widget_quickfood.xml"):
    shutil.copyfile(os.path.join(xml_src, name), os.path.join(xml_dst, name))
# Διατάξεις των widgets (ημέρας και νύχτας).
for folder in ("layout", "layout-night"):
    dst = os.path.join(os.path.dirname(os.path.abspath(path)), "res", folder)
    os.makedirs(dst, exist_ok=True)
    shutil.copyfile(os.path.join(os.path.dirname(os.path.abspath(__file__)), folder, "home_widget.xml"),
                    os.path.join(dst, "home_widget.xml"))

# Τα δύο απλά widgets (13/11): διατάξεις, σχήματα, χρώματα ημέρας και νύχτας. Δικά τους ονόματα αρχείων (quick_*, qw_*),
# ώστε να μη γράφουν ποτέ πάνω σε αρχείο που φτιάχνει το «flutter create».
here = os.path.dirname(os.path.abspath(__file__))
res = os.path.join(os.path.dirname(os.path.abspath(path)), "res")
# Round 1 (f9 · U7-17 ε): και οι προεπισκοπήσεις των τεσσάρων widgets με εικόνα (qw_preview_*).
for folder, names in (("layout", ("quick_workout_widget.xml", "quick_food_widget.xml", "qw_preview_sleep.xml",
                                  "qw_preview_move.xml", "qw_preview_food.xml", "qw_preview_body.xml")),
                      ("drawable", ("qw_bg.xml", "qw_button_food.xml", "qw_button_plain.xml", "qw_preview_bg.xml")),
                      ("values", ("quick_widgets.xml",)), ("values-night", ("quick_widgets.xml",))):
    os.makedirs(os.path.join(res, folder), exist_ok=True)
    for name in names:
        if folder.startswith("values") and os.path.exists(os.path.join(res, folder, name)) and \
                open(os.path.join(res, folder, name), encoding="utf-8").read() != open(os.path.join(here, folder, name), encoding="utf-8").read():
            sys.exit("Υπάρχει ήδη άλλο " + folder + "/" + name)
        shutil.copyfile(os.path.join(here, folder, name), os.path.join(res, folder, name))

BACKUP = ('android:allowBackup="true"', 'android:fullBackupContent="@xml/backup_rules"',
          'android:dataExtractionRules="@xml/data_extraction_rules"')
app_tag = re.search(r"<application\b[^>]*>", s, re.S)
if not app_tag:
    sys.exit("Δεν βρέθηκε το application")
tag = app_tag.group(0)
if "android:fullBackupContent" in tag or "android:dataExtractionRules" in tag or "android:allowBackup" in tag:
    if not all(a in tag for a in BACKUP):
        sys.exit("Το application έχει ήδη άλλους κανόνες αντιγράφου")
else:
    s = s.replace(tag, tag.replace("<application", "<application\n        " + "\n        ".join(BACKUP), 1), 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(s)

# Έλεγχος: όλα στη θέση τους, και η MainActivity ακριβώς όπως ήταν.
after_main = re.search(r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>', s, re.S).group(0)
if after_main != before_main:
    sys.exit("Η MainActivity άλλαξε· δεν έπρεπε")
main_at = s.index(after_main)
if 'android:name="flutter_deeplinking_enabled" android:value="false"' not in s[main_at:s.index("</activity>", main_at)]:
    sys.exit("Λείπει το flutter_deeplinking_enabled=false στη MainActivity")
if s.count('android:name="flutter_deeplinking_enabled" android:value="false"') != 2:
    sys.exit("Το flutter_deeplinking_enabled=false πρέπει να είναι σε MainActivity και WidgetConfigActivity")
for needle in ('android:name=".OuraCallbackActivity"', 'android:scheme="ygeiaforma"', 'android:host="oura-callback"',
               'android:host="ygeia-forma.netlify.app"', 'android:path="/oura/callback"', 'android:autoVerify="true"',
               "<!-- Σύνδεση Oura: άνοιγμα", 'android:name=".WidgetConfigActivity"', 'android:name=".SleepWidget"',
               'android:name=".MoveWidget"', 'android:name=".FoodWidget"', 'android:name=".BodyWidget"',
               'android:name=".WorkoutWidget"', 'android:name=".QuickFoodWidget"', "@xml/widget_workout",
               "@xml/widget_quickfood",
               "android.appwidget.action.APPWIDGET_CONFIGURE", "android.permission.VIBRATE",
               "android.permission.POST_NOTIFICATIONS") + BACKUP:
    if needle not in s:
        sys.exit("Λείπει μετά την αλλαγή: " + needle)
if s.count('android:scheme="ygeiaforma"') != 1:
    sys.exit("Η επιστροφή ygeiaforma:// δηλώθηκε δύο φορές")
if s.count('android:host="ygeia-forma.netlify.app"') != 1:
    sys.exit("Το App Link δηλώθηκε δύο φορές")
print("Manifest: OuraCallbackActivity (https App Link + ygeiaforma://oura-callback), queries https, κανόνες αντιγράφου· "
      "MainActivity χωρίς αλλαγή")
