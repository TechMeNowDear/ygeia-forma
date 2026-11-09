"""Έλεγχος του APK του ρολογιού: να έχει τη δυνατότητα «ygeia_watch» (android_wear_capabilities).

Χωρίς αυτή το κινητό δεν βρίσκει ποτέ την εφαρμογή του ρολογιού (το #85 βγήκε έτσι: τη έσβησε η σμίκρυνση
πόρων). Χρήση: python3 -I tools/check_wear_capability.py <apk>
"""
import sys
import zipfile

apk = sys.argv[1]
data = zipfile.ZipFile(apk).read('resources.arsc')
want = 'ygeia_watch'
if want.encode('utf-8') not in data and want.encode('utf-16-le') not in data:
    print(f'::error title=Ρολόι::Το {apk} δεν έχει τη δυνατότητα «{want}»· το κινητό δεν θα βρει το ρολόι.')
    sys.exit(1)
print(f'{apk}: δυνατότητα «{want}» υπάρχει')
