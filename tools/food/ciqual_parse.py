"""CIQUAL 2025 (ANSES, Licence Ouverte etalab-2.0) → ciqual.json.

Τιμές ανά 100 g. Κανόνες για τιμές που δεν είναι απλοί αριθμοί:
  "-"      → λείπει (δεν μετρήθηκε)       → δεν γράφεται
  "traces" → ίχνη                         → {"tr": true}  (μετράει ως 0)
  "< x"    → μικρότερο από x              → {"lt": x}     (μετράει ως 0, δείχνεται «<x»)
"""
import json, sys, xml.etree.ElementTree as ET

src = sys.argv[1]
out = sys.argv[2]

KEYS = {
    328: "kcal", 327: "kj", 25003: "protein", 31000: "carbs", 32000: "sugars", 33110: "starch",
    34100: "fiber", 34000: "polyols", 40000: "fat", 40302: "satFat", 40303: "monoFat", 40304: "polyFat",
    41833: "ala", 42053: "epa", 42263: "dha", 10004: "salt", 10110: "sodium", 400: "water",
    60000: "alcohol", 75100: "cholesterol",
    10200: "calcium", 10260: "iron", 10120: "magnesium", 10150: "phosphorus", 10190: "potassium",
    10300: "zinc", 10340: "selenium", 10530: "iodine", 10290: "copper", 10251: "manganese",
    51104: "vitA", 52100: "vitD", 53100: "vitE", 54101: "vitK1", 55100: "vitC", 56100: "vitB1",
    56200: "vitB2", 56310: "vitB3", 56400: "vitB5", 56500: "vitB6", 56600: "vitB12", 56700: "folate",
}

def num(s):
    return float(s.replace(",", ".").strip())

def parse_value(s):
    s = (s or "").strip()
    if not s or s == "-":
        return None
    low = s.lower()
    if low.startswith("trace"):
        return {"tr": True}
    if s.startswith("<"):
        return {"lt": num(s[1:])}
    return num(s)

def text(el, tag):
    v = el.findtext(tag)
    return v.strip() if v else ""

groups = {}
for g in ET.parse(f"{src}/ciqual_alim_grp_2025_11_03.xml").getroot():
    groups[text(g, "alim_ssgrp_code")] = (text(g, "alim_grp_nom_eng"), text(g, "alim_ssgrp_nom_eng"))

foods = {}
for a in ET.parse(f"{src}/ciqual_alim_2025_11_03.xml").getroot():
    code = int(text(a, "alim_code"))
    sg = text(a, "alim_ssgrp_code")
    foods[code] = {
        "code": code,
        "fr": text(a, "alim_nom_fr"),
        "en": text(a, "alim_nom_eng"),
        "group": groups.get(sg, ("", ""))[0],
        "subgroup": groups.get(sg, ("", ""))[1],
        "n": {},
    }

for _, el in ET.iterparse(f"{src}/ciqual_compo_2025_11_03.xml"):
    if el.tag != "COMPO":
        continue
    c = int(text(el, "const_code"))
    if c in KEYS:
        code = int(text(el, "alim_code"))
        v = parse_value(el.findtext("teneur"))
        if code in foods and v is not None:
            foods[code]["n"][KEYS[c]] = v
    el.clear()

json.dump(sorted(foods.values(), key=lambda f: f["code"]), open(out, "w"), ensure_ascii=False)
print(len(foods), "foods")
