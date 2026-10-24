"""USDA FoodData Central (CC0): SR Legacy + Foundation Foods → usda.json (ίδιο σχήμα με ciqual.json).
Τιμές ανά 100 g. Αλάτι = νάτριο × 2,5 / 1000 (κανόνας ΕΕ 1169/2011)."""
import csv, json, sys, os

base = sys.argv[1]
out = sys.argv[2]
NUT = {
    1008: "kcal", 1062: "kj", 1003: "protein", 1005: "carbs", 2000: "sugars", 1009: "starch",
    1079: "fiber", 1004: "fat", 1258: "satFat", 1292: "monoFat", 1293: "polyFat",
    1404: "ala", 1278: "epa", 1272: "dha", 1093: "sodium", 1051: "water", 1018: "alcohol",
    1253: "cholesterol", 1087: "calcium", 1089: "iron", 1090: "magnesium", 1091: "phosphorus",
    1092: "potassium", 1095: "zinc", 1103: "selenium", 1100: "iodine", 1098: "copper", 1101: "manganese",
    1106: "vitA", 1114: "vitD", 1109: "vitE", 1185: "vitK1", 1162: "vitC", 1165: "vitB1", 1166: "vitB2",
    1167: "vitB3", 1170: "vitB5", 1175: "vitB6", 1178: "vitB12", 1177: "folate",
}
ATWATER = (2047, 2048)  # Foundation: ενέργεια Atwater (γενική / ειδική) όταν λείπει το 1008

foods = {}
for ds in sorted(os.listdir(base)):
    d = os.path.join(base, ds)
    if not os.path.isdir(d):
        continue
    kind = "foundation" if "foundation" in ds else "sr_legacy"
    cats = {}
    with open(os.path.join(d, "food_category.csv"), encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            cats[r["id"]] = r["description"]
    with open(os.path.join(d, "food.csv"), encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r.get("data_type") not in ("sr_legacy_food", "foundation_food"):
                continue
            fid = int(r["fdc_id"])
            foods[fid] = {"code": fid, "en": r["description"], "dataset": kind,
                          "group": cats.get(r.get("food_category_id", ""), ""), "n": {}, "_atw": {}}
    with open(os.path.join(d, "food_nutrient.csv"), encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            fid = int(r["fdc_id"])
            if fid not in foods or not r.get("amount"):
                continue
            nid = int(r["nutrient_id"])
            amt = float(r["amount"])
            if nid in NUT:
                foods[fid]["n"][NUT[nid]] = amt
            elif nid in ATWATER:
                foods[fid]["_atw"][nid] = amt

for f in foods.values():
    n = f["n"]
    if "kcal" not in n:
        for k in (2048, 2047):
            if k in f["_atw"]:
                n["kcal"] = f["_atw"][k]
                f["energyFrom"] = "atwater"
                break
    if "sodium" in n:
        n["salt"] = round(n["sodium"] * 2.5 / 1000, 3)
    del f["_atw"]

json.dump(sorted(foods.values(), key=lambda f: f["code"]), open(out, "w"), ensure_ascii=False)
print(len(foods), "foods")
