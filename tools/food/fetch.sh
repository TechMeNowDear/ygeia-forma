#!/usr/bin/env bash
# Κατεβάζει τις ανοιχτές πηγές τροφίμων (τρέχει μόνο στο GitHub Actions).
# CIQUAL (ANSES, Licence Ouverte) και USDA FoodData Central (CC0).
set -u
OUT=food-raw
mkdir -p "$OUT"
log() { echo "$@" | tee -a "$OUT/fetch.log"; }

# --- CIQUAL: Recherche Data Gouv (Dataverse), DOI 10.57745/RDMHWY ---
API="https://entrepot.recherche.data.gouv.fr/api"
DOI="doi:10.57745/RDMHWY"
UA="ygeia-forma-data-fetch/1.0 (personal research)"
if curl -sfL -A "$UA" "$API/datasets/:persistentId/?persistentId=$DOI" -o "$OUT/ciqual-meta.json"; then
  log "ciqual meta ok"
  python3 - "$OUT" <<'PY'
import json,sys,urllib.request,os
out=sys.argv[1]
m=json.load(open(f"{out}/ciqual-meta.json"))
v=m["data"]["latestVersion"]
print("version", v.get("versionNumber"), v.get("versionMinorNumber"), v.get("releaseTime"))
print("license", json.dumps(v.get("license")))
for f in v["files"]:
    df=f["dataFile"]
    print("file", df["id"], df.get("filename"), df.get("contentType"), df.get("filesize"))
PY
  python3 - "$OUT" <<'PY' | while read id name; do
import json,sys
m=json.load(open(sys.argv[1]+"/ciqual-meta.json"))
for f in m["data"]["latestVersion"]["files"]:
    df=f["dataFile"]
    n=df.get("filename","")
    if n.lower().endswith((".xlsx",".xls",".xml",".csv",".zip",".pdf")):
        print(df["id"], n.replace(" ","_"))
PY
    curl -sfL -A "$UA" "$API/access/datafile/$id?format=original" -o "$OUT/ciqual_$name" && log "ciqual file ok $name" || log "ciqual file FAIL $name"
  done
else
  log "ciqual meta FAIL"
  curl -sL -A "$UA" "$API/datasets/:persistentId/?persistentId=$DOI" | head -c 400 >> "$OUT/fetch.log"
fi

# --- USDA FoodData Central: Foundation Foods + SR Legacy (CSV) ---
curl -sfL -A "$UA" "https://fdc.nal.usda.gov/download-datasets" -o "$OUT/usda-downloads.html" || curl -sfL -A "$UA" "https://fdc.nal.usda.gov/download-datasets.html" -o "$OUT/usda-downloads.html" || log "usda page FAIL"
for pat in foundation_food_csv sr_legacy_food_csv; do
  url=$(grep -oE "https?://[^\"' ]*${pat}[^\"' ]*\.zip|/fdc-datasets/[^\"' ]*${pat}[^\"' ]*\.zip" "$OUT/usda-downloads.html" 2>/dev/null | head -1)
  [ -z "$url" ] && { log "usda $pat link not found"; continue; }
  case "$url" in /*) url="https://fdc.nal.usda.gov$url";; esac
  log "usda $pat $url"
  curl -sfL -A "$UA" "$url" -o "$OUT/usda_${pat}.zip" && log "usda ok $pat" || log "usda FAIL $pat"
done
rm -f "$OUT/usda-downloads.html"
ls -la "$OUT" | tee -a "$OUT/fetch.log"
