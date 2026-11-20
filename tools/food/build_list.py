"""Ελληνική λίστα (greek_list.tsv) + CIQUAL + USDA → assets/foods/basic_foods.json.

Κανόνες ακρίβειας:
- Οι αριθμοί έρχονται ΜΟΝΟ από την πηγή (ανά 100 g). Κανένας αριθμός από AI.
- Αν λείπουν οι θερμίδες, υπολογίζονται από τα μακροθρεπτικά με τους συντελεστές του Κανονισμού ΕΕ 1169/2011
  (πρωτεΐνη 4, υδατάνθρακες 4, λίπος 9, φυτικές ίνες 2, αλκοόλ 7, πολυόλες 2,4) και το τρόφιμο σημειώνεται "energyCalc".
- Έλεγχος λογικής: θερμίδες πηγής vs υπολογισμένες από τα μακρο. Απόκλιση >15% (και >20 kcal) → λίστα για έλεγχο.
- Αλάτι = νάτριο × 2,5 / 1000 όταν υπάρχει νάτριο (ορισμός ΕΕ), ώστε όλες οι πηγές να συμφωνούν· και «<x» όταν το νάτριο είναι «<x».
- Το id είναι σταθερό: πηγή+κωδικός, ή η 6η στήλη όταν ο ίδιος κωδικός ξαναχρησιμοποιείται.
"""
import json, sys

listfile, ciqual, usda, out = sys.argv[1:5]
C = {f["code"]: f for f in json.load(open(ciqual))}
U = {f["code"]: f for f in json.load(open(usda))}

def val(x):
    if x is None: return None
    if isinstance(x, dict): return 0.0
    return float(x)

def calc_kcal(n):
    p, c, f = val(n.get("protein")), val(n.get("carbs")), val(n.get("fat"))
    if p is None or c is None or f is None: return None
    fib = val(n.get("fiber")) or 0.0
    alc = val(n.get("alcohol")) or 0.0
    pol = val(n.get("polyols")) or 0.0
    # Στη CIQUAL οι υδατάνθρακες περιέχουν ήδη τις πολυόλες.
    return 4*p + 4*max(0.0, c - pol) + 9*f + 2*fib + 7*alc + 2.4*pol

# Έλεγχος 17/11 (επιστημονικός, κατηγορία 2): εδώ το νάτριο της CIQUAL δεν στέκει με το δικό της αλάτι, που στηρίζεται
# σε νεότερα ή περισσότερα δεδομένα. Ηλιόσποροι αλατισμένοι: νάτριο 2.000 mg (= 5 g αλάτι, το πάνω άκρο του εύρους
# 0,25–5) έναντι αλατιού 2,63 g (USDA 169: 1,64 g)· γαύρος μαρινάτος: 7,68 έναντι 4,15 g (και τα δύο υπολογισμένα)·
# γκρυγιέρ: νάτριο του 2004 (0,8 g) έναντι αλατιού 1,3 g (2015· USDA: 1,79 g).
CIQUAL_SALT = {15045, 26700, 12114}
# Ελέγχθηκαν και μένει το νάτριο × 2,5: μαϊντανός (νάτριο 51,5 mg· USDA 56 mg = 0,14 g αλάτι· το αλάτι 0,59 g της CIQUAL δεν στέκει).
SODIUM_OK = {11014}

foods, problems, seen = [], [], set()
for line in open(listfile, encoding="utf-8"):
    if not line.strip() or line.startswith("#"): continue
    parts = line.rstrip("\n").split("\t")
    src, code, name, cat = parts[0], int(parts[1]), parts[2], parts[3]
    aliases = [a.strip() for a in (parts[4] if len(parts) > 4 else "").split(",") if a.strip()]
    db = C if src == "C" else U
    if code not in db:
        problems.append(f"ΔΕΝ ΥΠΑΡΧΕΙ {src}{code} {name}"); continue
    s = db[code]
    n = dict(s["n"])
    fid = parts[5].strip() if len(parts) > 5 and parts[5].strip() else f"{src}{code}"
    if fid in seen:
        problems.append(f"ΔΙΠΛΟ ID {fid} {name}: βάλε σταθερό id στην 6η στήλη"); continue
    seen.add(fid)
    if s.get("carbsInclFiber"):
        problems.append(f"ΧΩΡΙΣ ΦΥΤΙΚΕΣ ΙΝΕΣ (υδατάνθρακες USDA με ίνες) {fid} {name}")
    sod = n.get("sodium")
    if isinstance(sod, (int, float)):
        n["salt"] = round(sod * 2.5 / 1000, 3)
    elif isinstance(sod, dict) and "lt" in sod:
        # Νάτριο «<x» mg → αλάτι «<x×2,5/1000» g. Η τιμή αλατιού της CIQUAL εκεί είναι μερικές φορές λάθος
        # (γκρέιπφρουτ, κόκκινο κρασί: «<2 g»· έλεγχος διατροφής M3, 4/11).
        n["salt"] = {"lt": round(sod["lt"] * 2.5 / 1000, 4)}
    # Έλεγχος 17/11: όπου η CIQUAL δίνει δικό της αλάτι πολύ διαφορετικό από νάτριο × 2,5, το λέει για έλεγχο. Στα
    # [CIQUAL_SALT] κρατιέται το αλάτι της CIQUAL (το νάτριο είναι από παλιά ή υπολογισμένη πηγή).
    cs = s["n"].get("salt") if src == "C" else None
    if isinstance(cs, (int, float)) and isinstance(n.get("salt"), (int, float)):
        if code in CIQUAL_SALT:
            n["salt"] = cs
        elif code not in SODIUM_OK and abs(cs - n["salt"]) > 0.2 and abs(cs - n["salt"]) > 0.25 * max(cs, n["salt"]):
            problems.append(f"ΑΛΑΤΙ (έλεγξε) {fid} {name}: CIQUAL {cs:g} g, νάτριο × 2,5 = {n['salt']:g} g")
    entry = {
        "id": fid,
        "name": name, "cat": cat, "aliases": aliases,
        "source": "CIQUAL 2025" if src == "C" else ("USDA Foundation" if s.get("dataset") == "foundation" else "USDA SR Legacy"),
        "sourceCode": code, "sourceName": s["en"], "n": n,
    }
    ck = calc_kcal(n)
    if "kcal" not in n or n["kcal"] is None or isinstance(n["kcal"], dict):
        if ck is None:
            problems.append(f"ΧΩΡΙΣ ΘΕΡΜΙΔΕΣ ΚΑΙ ΜΑΚΡΟ {entry['id']} {name}"); continue
        n["kcal"] = round(ck, 1); entry["energyCalc"] = True
    elif ck is not None:
        k = float(n["kcal"])
        if abs(k - ck) > 20 and abs(k - ck) / max(k, 1) > 0.15:
            problems.append(f"ΑΠΟΚΛΙΣΗ {entry['id']} {name}: πηγή {k:.0f} kcal, από μακρο {ck:.0f}")
    for key in ("protein", "carbs", "fat"):
        if key not in n: problems.append(f"ΛΕΙΠΕΙ {key} {entry['id']} {name}")
    # Round9 (R9-A2-1): το μέρος δεν γίνεται μεγαλύτερο από το όλον (σάκχαρα ⊂ υδατάνθρακες, κορεσμένα ⊂ λιπαρά). Πριν
    # κανένας έλεγχος δεν το έπιανε και το «Κανένα πρόβλημα» περνούσε με σάκχαρα 7,9 g σε υδατάνθρακες 7,3 g. Μόνο με
    # αριθμούς: «ίχνη» ή «<x» δεν είναι αριθμός της πηγής (CIQUAL αβοκάντο: υδατάνθρακες «ίχνη», σάκχαρα 0,4 g).
    for part, whole in (("sugars", "carbs"), ("satFat", "fat")):
        pv, wv = n.get(part), n.get(whole)
        if isinstance(pv, (int, float)) and isinstance(wv, (int, float)) and pv > wv + 0.05:
            problems.append(f"ΜΕΡΟΣ > ΟΛΟΝ {entry['id']} {name}: {part} {pv:g} > {whole} {wv:g}")
    foods.append(entry)

# Ζευγάρια ωμό → μαγειρεμένο
pairs_file = listfile.replace("greek_list.tsv", "raw_cooked.tsv")
byid = {f["id"]: f for f in foods}
for line in open(pairs_file, encoding="utf-8"):
    if not line.strip() or line.startswith("#"): continue
    raw, cooked, label = line.rstrip("\n").split("\t")[:3]
    if raw == "-":
        # Έλεγχος 17/11: μόνο μαγειρεμένο (καμία ωμή μορφή στη βάση): ζυγίζεται μετά το μαγείρεμα.
        if cooked not in byid:
            problems.append(f"ΜΟΝΟ ΜΑΓΕΙΡΕΜΕΝΟ ΧΩΡΙΣ ΤΡΟΦΙΜΟ {cooked}"); continue
        byid[cooked]["cookedLabel"] = label
        continue
    if raw not in byid or cooked not in byid:
        problems.append(f"ΖΕΥΓΑΡΙ ΧΩΡΙΣ ΤΡΟΦΙΜΟ {raw} → {cooked}"); continue
    byid[raw].setdefault("cooked", []).append({"id": cooked, "label": label})
    byid[cooked]["rawId"] = raw
    byid[cooked]["cookedLabel"] = label

json.dump({"version": 1, "sources": {
    "CIQUAL 2025": "ANSES, Table de composition nutritionnelle des aliments Ciqual 2025, doi:10.57745/RDMHWY — Licence Ouverte (etalab-2.0)",
    "USDA SR Legacy": "U.S. Department of Agriculture, FoodData Central, SR Legacy (2018) — public domain (CC0)",
    "USDA Foundation": "U.S. Department of Agriculture, FoodData Central, Foundation Foods (2026-04) — public domain (CC0)"},
    "foods": foods}, open(out, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print(len(foods), "τρόφιμα")
print("\n".join(problems) or "Κανένα πρόβλημα")
