#!/usr/bin/env bash
# Emulator Android 14 (google_apis, x86_64) για τους ελέγχους ανοίγματος και αναβάθμισης (check.yml, android.yml).
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
IMG="system-images;android-34;google_apis;x86_64"
export ANDROID_AVD_HOME="$HOME/.android/avd"
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"

case "${1:-}" in
start)
  mkdir -p "$ANDROID_AVD_HOME"
  yes | "$BIN/sdkmanager" --licenses > /dev/null 2>&1 || true
  # Το κατέβασμα αποτυγχάνει πού και πού (δίκτυο): έως 3 φορές.
  for i in 1 2 3; do
    "$BIN/sdkmanager" "emulator" "platform-tools" "$IMG" > sdk.log 2>&1 && break
    echo "sdkmanager: ξαναδοκιμή $i"; sleep $((i * 15))
  done
  echo no | "$BIN/avdmanager" create avd -n smoke -k "$IMG" -d pixel_6 --force > /dev/null 2>&1 || \
    echo no | "$BIN/avdmanager" create avd -n smoke -k "$IMG" --force > /dev/null
  nohup "$SDK/emulator/emulator" -avd smoke -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim \
    -no-snapshot -camera-back none -camera-front none -memory 4096 > emu.log 2>&1 &
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
  adb shell settings put global window_animation_scale 0
  adb shell settings put global transition_animation_scale 0
  adb shell settings put global animator_duration_scale 0
  adb shell cmd connectivity airplane-mode enable > /dev/null 2>&1 || true
  echo "Emulator έτοιμος · Android $(adb shell getprop ro.build.version.release | tr -d '\r') · root: $(adb shell id -u | tr -d '\r' | sed 's/^0$/ναι/;s/^[1-9].*/όχι/') · πτήση: $(adb shell settings get global airplane_mode_on | tr -d '\r')"
  sleep 10
  ;;
*)
  echo "Χρήση: $0 start|wait"; exit 2
  ;;
esac
