import json,re,sys
C=json.load(open(sys.argv[1])); U=json.load(open(sys.argv[2]))
for line in open(sys.argv[3]):
    line=line.strip()
    if not line or line.startswith('#'): print(line); continue
    src,pat=line.split('|',1)
    db=C if src=='C' else U
    r=re.compile(pat,re.I)
    m=[x for x in db if r.search(x['en'])]
    print(f"[{src}] {pat} ({len(m)})")
    for x in m[:int(sys.argv[4]) if len(sys.argv)>4 else 6]: print(f"   {x['code']} {x['en'][:95]} | {x['n'].get('kcal')}")
