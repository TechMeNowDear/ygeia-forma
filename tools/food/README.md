# Δεδομένα τροφίμων

1. `fetch.sh` τρέχει στο GitHub Actions (workflow «Δεδομένα τροφίμων») και ανεβάζει τις ακατέργαστες πηγές στο branch `food-raw`.
2. `ciqual_parse.py` και `usda_parse.py` τις κάνουν `ciqual.json` / `usda.json` (ίδιο σχήμα, ανά 100 g).
3. `greek_list.tsv` είναι η επιμελημένη ελληνική λίστα (πηγή, κωδικός, όνομα, κατηγορία, άλλα ονόματα).
4. `build_list.py` βγάζει το `assets/foods/basic_foods.json` και τυπώνει ό,τι θέλει έλεγχο.

Πηγές: CIQUAL 2025 (ANSES, Licence Ouverte etalab-2.0) · USDA FoodData Central SR Legacy και Foundation (CC0).
