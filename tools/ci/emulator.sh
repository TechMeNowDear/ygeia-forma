#!/usr/bin/env bash
# Emulator Android 14 (google_apis, x86_64) για τους ελέγχους ανοίγματος και αναβάθμισης (check.yml, android.yml).
# Με EMU_API=37: Android 17, όπου ισχύουν οι αλλαγές του targetSdk 37 (fix-sdk37· το Fold 8 τρέχει Android 17).
#
#   bash tools/ci/emulator.sh start   # κατέβασμα + εκκίνηση στο παρασκήνιο (ο emulator ξεκινά όσο χτίζεται το APK)
#   bash tools/ci/emulator.sh wait    # περιμένει να ανοίξει, root, χωρίς κινούμενα σχέδια, ΧΩΡΙΣ δίκτυο
#
# Χωρίς δίκτυο (λειτουργία πτήσης): ο έλεγχος δεν στέλνει τίποτα στο Sentry, στην Oura ή στο Open Food Facts, και ό,τι
# σφάλμα γίνει μένει στην ουρά της εφαρμογής (files/errq), όπου το βλέπει ο έλεγχος (tools/perf/smoke.sh).
# Root (adb root, υπάρχει στις εικόνες google_apis): για να διαβάζεται η ουρά σφαλμάτων και να μπαίνει δείγμα δεδομένων.
set -u
SDK="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
BIN="$SDK/cmdline-tools/latest/bin"
API="${EMU_API:-34}"
# Από το Android 16 QPR οι εικόνες έχουν και δευτερεύοντα αριθμό (π.χ. android-37.0)· δοκιμάζονται και οι δύο μορφές.
case "$API" in
  34) CANDIDATES="system-images;android-34;google_apis;x86_64" ;;
  *) CANDIDATES="system-images;android-$API.0;google_apis;x86_64 system-images;android-$API;google_apis;x86_64" ;;
esac
IMG="${CANDIDATES%% *}"
export ANDROID_AVD_HOME="$HOME/.android/avd"
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"

case "${1:-}" in
start)
  mkdir -p "$ANDROID_AVD_HOME"
  yes | "$BIN/sdkmanager" --licenses > /dev/null 2>&1 || true
  # Το κατέβασμα αποτυγχάνει πού και πού (δίκτυο): έως 3 φορές.
  for i in 1 2 3; do
    got=""
    for c in $CANDIDATES; do
      "$BIN/sdkmanager" "emulator" "platform-tools" "$c" > sdk.log 2>&1 && [ -d "$SDK/$(echo "$c" | tr ';' '/')" ] && got="$c" && break
    done
    [ -n "$got" ] && IMG="$got" && break
    echo "sdkmanager: ξαναδοκιμή $i"; sleep $((i * 15))
  done
  echo "Εικόνα emulator: $IMG"
  echo no | "$BIN/avdmanager" create avd -n smoke -k "$IMG" -d pixel_6 --force > /dev/null 2>&1 || \
    echo no | "$BIN/avdmanager" create avd -n smoke -k "$IMG" --force > /dev/null
  # Η εικόνα του Android 17 έχει μικρό χώρο δεδομένων («not enough space» στην εγκατάσταση, 10/11): 6 GB όπως ένα
  # κανονικό κινητό. Το Android 14 μένει ακριβώς όπως ήταν.
  if [ "$API" != 34 ]; then
    cfg="$ANDROID_AVD_HOME/smoke.avd/config.ini"
    sed -i '/^disk.dataPartition.size/d' "$cfg" 2> /dev/null || true
    echo "disk.dataPartition.size=6G" >> "$cfg"
    PART="-partition-size 6144"
  else
    PART=""
  fi
  nohup "$SDK/emulator/emulator" -avd smoke -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim \
    -no-snapshot -camera-back none -camera-front none -memory 4096 $PART > emu.log 2>&1 &
  echo "Ο emulator ξεκινά στο παρασκήνιο (pid $!)"
  ;;
wait)
  if ! timeout 600 adb wait-for-device; then
    echo "Ο emulator δεν εμφανίστηκε"; tail -30 emu.log 2>/dev/null; exit 1
  fi
  for _ in $(seq 1 120); do
    [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
    sleep 5
  done
  [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ] || { echo "Ο emulator δεν ολοκλήρωσε την εκκίνηση"; exit 1; }
  adb root > /dev/null 2>&1 || true
  sleep 3
  timeout 120 adb wait-for-device
  for _ in $(seq 1 30); do
    [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
    sleep 2
  done
  # boot_completed=1 δεν σημαίνει πάντα ότι τρέχει ο διαχειριστής πακέτων (Android 17, 10/11: «Can't find service:
  # package» στην εγκατάσταση). Περιμένουμε να απαντά, έως 3 λεπτά.
  for _ in $(seq 1 90); do
    adb shell pm path android 2> /dev/null | grep -q '^package:' && break
    sleep 2
  done
  adb shell pm path android 2> /dev/null | grep -q '^package:' || { echo "Ο διαχειριστής πακέτων δεν απαντά"; exit 1; }
  adb shell settings put global window_animation_scale 0
  adb shell settings put global transition_animation_scale 0
  adb shell settings put global animator_duration_scale 0
  adb shell cmd connectivity airplane-mode enable > /dev/null 2>&1 || true
  echo "Emulator έτοιμος · Android $(adb shell getprop ro.build.version.release | tr -d '\r') · root: $(adb shell id -u | tr -d '\r' | sed 's/^0$/ναι/;s/^[1-9].*/όχι/') · πτήση: $(adb shell settings get global airplane_mode_on | tr -d '\r')"
  echo "Χώρος δεδομένων: $(adb shell df -h /data 2> /dev/null | tail -1 | tr -s ' ' | cut -d' ' -f2,4 | tr -d '\r')"
  sleep 10
  ;;
*)
  echo "Χρήση: $0 start|wait"; exit 2
  ;;
esac
