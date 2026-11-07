#!/usr/bin/env bash
# Στιγμιότυπα της οθόνης ρύθμισης widget στο emulator (7/11): ανοίγει τη WidgetConfigActivity ως προεπισκόπηση
# (χωρίς widget, με «ygeia_kind») για κάθε είδος και μέγεθος, και κρατά μια εικόνα της οθόνης. Η εικόνα του widget
# μέσα σε αυτήν είναι ο ίδιος ο ζωγράφος της αρχικής οθόνης (WidgetRenderer.kt), με παράδειγμα τιμών.
set -u
PKG=gr.ygeiaforma.ygeia_forma
ACT="$PKG/.WidgetConfigActivity"
mkdir -p widget_shots
ok=1
for spec in "sleep 92 300" "move 180 400" "food 180 190" "body 370 190"; do
  set -- $spec
  # Κάθε εντολή με όριο χρόνου: ένα κόλλημα του emulator δεν σταματά όλο τον έλεγχο.
  timeout 20 adb shell am force-stop "$PKG"; sleep 1
  timeout 40 adb shell am start -n "$ACT" --es ygeia_kind "$1" --ei ygeia_w "$2" --ei ygeia_h "$3" > /dev/null
  sleep 12
  timeout 30 adb exec-out screencap -p > "widget_shots/$1_$2x$3.png" || ok=0
  pid=$(timeout 15 adb shell pidof "$PKG" | tr -d '\r')
  [ -z "$pid" ] && { echo "$1 $2x$3: η οθόνη ρύθμισης έκλεισε"; ok=0; }
done
timeout 30 adb logcat -b crash -d > widget_crash.log 2>&1 || true
if grep -q "Process: $PKG\|>>> $PKG <<<" widget_crash.log; then
  echo "Κρασάρισμα στην οθόνη ρύθμισης widget:"; grep -A30 "Process: $PKG\|>>> $PKG <<<" widget_crash.log | head -40; ok=0
fi
[ "$ok" = 1 ] && echo "Widgets: εντάξει" && exit 0
exit 1
