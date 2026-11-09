#!/usr/bin/env bash
# Υπογραφή των APK (κινητό + ρολόι) με το ΣΤΑΘΕΡΟ κλειδί, έλεγχος 9/11 (V-A-20).
#
# Τρέχει ΜΟΝΟ στο job «sign» του android.yml: ένα καθαρό μηχάνημα όπου δεν τρέχει κανένα χτίσιμο, καμία εξάρτηση
# Gradle/Maven και κανένας έλεγχος. Το κλειδί και ο κωδικός:
# - έρχονται ΜΟΝΟ ως μεταβλητές αυτού του βήματος (YGEIA_KEYSTORE_B64, YGEIA_KEYSTORE_PASSWORD), ποτέ στο $GITHUB_ENV,
# - ο κωδικός δίνεται στο apksigner ως «env:» (όχι στη γραμμή εντολών, δεν φαίνεται στη λίστα διεργασιών),
# - το αρχείο του κλειδιού γράφεται με δικαιώματα μόνο για τον χρήστη και σβήνεται στο τέλος (και σε αποτυχία· το
#   workflow το ξανασβήνει σε βήμα «if: always()»).
# Ποτέ νέο κλειδί: ένα άλλο κλειδί σημαίνει ότι η έκδοση δεν μπαίνει πάνω στην παλιά (η απεγκατάσταση σβήνει τα
# δεδομένα) και ότι το ρολόι δεν μιλά με το κινητό. Γι' αυτό κάθε APK ελέγχεται ότι έχει ΑΚΡΙΒΩΣ το πιστοποιητικό
# YGEIA_CERT_SHA256 (δημόσιο, ίδιο με το site/public/assetlinks.json).
#
# Χρήση: bash tools/ci/sign_apks.sh <apk> [apk…]   (υπογράφονται στη θέση τους)
# Σχήματα όπως ως την #89: μόνο v2 (minSdk 29/30 → χωρίς v1· χωρίς v3/v4, ίδιο αποτέλεσμα με το Gradle).
set -euo pipefail
umask 077

KS_DIR="${RUNNER_TEMP:-/tmp}/ygeia-ks"
cleanup() { rm -rf "$KS_DIR"; }
trap cleanup EXIT

want="${YGEIA_CERT_SHA256:?Λείπει το YGEIA_CERT_SHA256 (το αναμενόμενο αποτύπωμα)}"
want="$(printf '%s' "$want" | tr 'A-F' 'a-f' | tr -d ':')"

if [ -z "${YGEIA_KEYSTORE_B64:-}" ] || [ -z "${YGEIA_KEYSTORE_PASSWORD:-}" ]; then
  echo "::error title=Κλειδί υπογραφής::Δεν βρέθηκε το κλειδί υπογραφής στα Secrets του repository. Η έκδοση δεν υπογράφεται, για να μη φτιαχτεί ποτέ με άλλο κλειδί."
  exit 1
fi

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
bt="$(ls -d "$sdk"/build-tools/* 2>/dev/null | sort -V | tail -1)"
[ -n "$bt" ] && [ -x "$bt/apksigner" ] || { echo "::error title=Υπογραφή::Δεν βρέθηκε το apksigner στο Android SDK του runner"; exit 1; }
APKSIGNER="$bt/apksigner"
echo "apksigner από build-tools $(basename "$bt")"

# 1. Στοίχιση ΠΡΙΝ από την υπογραφή (έλεγχος 9/11, M-1): ασυμπίεστα αρχεία στα 4 byte (αλλιώς το Android 11+ αρνείται την
#    εγκατάσταση) και .so στα 16 KB. Χωρίς κλειδί ακόμα. Το ρολόι έρχεται πλέον «unsigned» από το Gradle· έτσι στοιχίζεται
#    σίγουρα και αυτό. Η υπογραφή v2 ΔΕΝ αλλάζει τη θέση των αρχείων (--alignment-preserved), και το apk_check.py το ελέγχει.
ZIPALIGN="$bt/zipalign"
[ -x "$ZIPALIGN" ] || { echo "::error title=Υπογραφή::Δεν βρέθηκε το zipalign"; exit 1; }
za_help=$("$ZIPALIGN" -h 2>&1 || true)
case "$za_help" in
  *"-P <pagesize_kb>"*) za=(-P 16) ;;
  *) za=(-p) ;;  # παλιό zipalign: 4 KB· ο έλεγχος 16 KB μετά θα σταματήσει τη δημοσίευση
esac
help=$("$APKSIGNER" sign --help 2>&1 || true)
extra=()
case "$help" in *--alignment-preserved*) extra+=(--alignment-preserved true) ;; esac
echo "zipalign ${za[*]} 4 · apksigner ${extra[*]:-(στοίχιση του apksigner)}"
for apk in "$@"; do
  test -f "$apk" || { echo "::error title=Υπογραφή::Λείπει το $apk"; exit 1; }
  "$ZIPALIGN" -f "${za[@]}" 4 "$apk" "$apk.aligned" > /dev/null || { echo "::error title=Υπογραφή::Το zipalign απέτυχε για το $apk"; exit 1; }
  mv "$apk.aligned" "$apk"
done

mkdir -p "$KS_DIR"
printf '%s' "$YGEIA_KEYSTORE_B64" | base64 -d > "$KS_DIR/release.jks"
unset YGEIA_KEYSTORE_B64

for apk in "$@"; do
  out="$KS_DIR/out.apk"
  if ! "$APKSIGNER" sign \
      --ks "$KS_DIR/release.jks" --ks-key-alias ygeia \
      --ks-pass env:YGEIA_KEYSTORE_PASSWORD --key-pass env:YGEIA_KEYSTORE_PASSWORD \
      --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled false --v4-signing-enabled false \
      ${extra[@]+"${extra[@]}"} --out "$out" "$apk" > "$KS_DIR/sign.log" 2>&1; then
    # Το log του apksigner δεν έχει τον κωδικό· δείχνουμε μόνο τις πρώτες γραμμές.
    echo "::error title=Υπογραφή::Το apksigner απέτυχε για το $apk (λάθος κωδικός ή κλειδί;): $(head -3 "$KS_DIR/sign.log" | tr '\n' ' ')"
    exit 1
  fi
  mv "$out" "$apk"
done

# Το κλειδί δεν χρειάζεται πια: σβήνεται ΠΡΙΝ από τους ελέγχους.
cleanup
unset YGEIA_KEYSTORE_PASSWORD

dir="$(dirname "$0")"
for apk in "$@"; do
  log="$(mktemp)"
  "$APKSIGNER" verify --print-certs -v "$apk" > "$log" 2>&1 || { cat "$log"; echo "::error title=Υπογραφή::Η επαλήθευση του $apk απέτυχε"; exit 1; }
  python3 -I "$dir/apk_check.py" "$want" "$log" "$apk"
  rm -f "$log"
  # Package και versionCode (ΑΠΑΡΑΒΑΤΟ: το applicationId δεν αλλάζει· ο αριθμός από το όνομα: κινητό N, ρολόι 1000000+N).
  badging=$("$bt/aapt2" dump badging "$apk" 2> /dev/null || true)
  line=$(printf '%s\n' "$badging" | sed -n '1p')
  case "$line" in *"name='gr.ygeiaforma.ygeia_forma'"*) ;; *) echo "::error title=Υπογραφή::Λάθος package στο $apk: $line"; exit 1 ;; esac
  base=$(basename "$apk")
  case "$base" in
    ygeia-forma-watch-*.apk) n=${base#ygeia-forma-watch-}; n=${n%.apk}; vc=$((1000000 + n)) ;;
    ygeia-forma-*.apk) n=${base#ygeia-forma-}; n=${n%.apk}; vc=$n ;;
    *) vc="" ;;
  esac
  if [ -n "$vc" ]; then
    case "$line" in *"versionCode='$vc'"*) echo "$base: package gr.ygeiaforma.ygeia_forma · versionCode $vc" ;;
      *) echo "::error title=Υπογραφή::$base: περιμέναμε versionCode $vc: $line"; exit 1 ;; esac
  fi
  echo "::notice title=Υπογραφή::$(basename "$apk") · SHA-256 APK $(sha256sum "$apk" | cut -c1-16)… · πιστοποιητικό ${want:0:12}…"
done

# App Link της Oura: το assetlinks.json πρέπει να έχει το ίδιο αποτύπωμα (ανεβαίνει με το Netlify).
for f in site/public/.well-known/assetlinks.json site/public/assetlinks.json; do
  if [ -f "$f" ] && ! tr -d ':' < "$f" | tr 'A-F' 'a-f' | grep -q "$want"; then
    echo "::warning title=assetlinks.json::Το $f δεν έχει το αποτύπωμα του κλειδιού υπογραφής. Η επιστροφή από την Oura θα περνά από τη σελίδα αντί για App Link ώσπου να διορθωθεί."
  fi
done
