"""Μεταφορά σε Python του lib/food/food_search.dart και του FoodStore.search/find (για έλεγχο πολλών αναζητήσεων
χωρίς Flutter). Χρήση: python3 tools/food/search_port.py «αναζήτηση» …

Κρατιέται ΙΔΙΟ με τη Dart: κάθε αλλαγή στο food_search.dart γίνεται και εδώ (και ανάποδα).
Αρχή κατάταξης (από πάνω προς τα κάτω):
  1. ακριβές ταίριασμα όλης της αναζήτησης με άλλο όνομα ή με την «κεφαλή» του ονόματος (+4)
  2. ταίριασμα λέξεων: πρώτη λέξη ονόματος 10 · άλλη λέξη 8 · άλλο όνομα 9 · αρχή/ρίζα 7/5/4/3 · κατηγορία 6
  3. τροποποιητές: «σημαδεμένες» παραλλαγές (παστό, αλατισμένο, καπνιστό, μαρινάτο, αποξηραμένο φρούτο) −3
     αν η αναζήτηση δεν τις ζητά· ωμό με μαγειρεμένες μορφές +1,2· προτιμήσεις/ιστορικό· μήκος ονόματος
  4. σταθερή σειρά στις ισοπαλίες (η σειρά της λίστας)
Αν δεν βρεθεί τίποτα: διόρθωση ενός γράμματος → χωρίς τις λέξεις που δεν ταιριάζουν πουθενά → χωρίς μία λέξη.
"""
import json, re
ACC = {'ά':'α','έ':'ε','ή':'η','ί':'ι','ό':'ο','ύ':'υ','ώ':'ω','ϊ':'ι','ΐ':'ι','ϋ':'υ','ΰ':'υ','ς':'σ'}
def plain(s): return ''.join(ACC.get(c, c) for c in s.lower())
GRD = {'ου':'u','ει':'i','οι':'i','υι':'i','αι':'e','μπ':'b','ντ':'d','γκ':'g','γγ':'g','τσ':'ts','τζ':'dz','αυ':'av','ευ':'ev'}
GRL = {'α':'a','β':'v','γ':'g','δ':'d','ε':'e','ζ':'z','η':'i','θ':'th','ι':'i','κ':'k','λ':'l','μ':'m','ν':'n','ξ':'ks','ο':'o','π':'p','ρ':'r','σ':'s','τ':'t','υ':'i','φ':'f','χ':'h','ψ':'ps','ω':'o'}
LAD = {'ou':'u','oy':'u','ei':'i','oi':'i','ai':'e','mp':'b','nt':'d','gk':'g','gg':'g','ng':'g','ch':'h','kh':'h','ph':'f','th':'th','ps':'ps','ks':'ks','tz':'dz'}
LAL = {'x':'h','y':'i','w':'o','u':'u','c':'k','q':'k','j':'g'}
def phonetic(s):
    p = plain(s); out = []; i = 0
    while i < len(p):
        two = p[i:i+2] if i+1 < len(p) else ''
        ch = p[i]
        if 0x370 <= ord(ch) <= 0x3FF:
            if i+2 < len(p) and p[i:i+3] == 'νγκ': out.append('g'); i += 3; continue
            if two in ('αυ','ευ'):
                nxt = p[i+2] if i+2 < len(p) else ''
                vl = nxt == '' or nxt in 'θκξπστφχψ' or nxt not in GRL
                out.append(('af' if vl else 'av') if two=='αυ' else ('ef' if vl else 'ev')); i += 2; continue
            if two in GRD: out.append(GRD[two]); i += 2; continue
            out.append(GRL.get(ch, ch)); i += 1
        else:
            if two in LAD: out.append(LAD[two]); i += 2; continue
            out.append(LAL.get(ch, ch)); i += 1
    return re.sub(r'([a-z])\1+', r'\1', ''.join(out))
STOP = {'ton','tin','tis','tu','to','ta','ti','me','se','ke','i','o','apo','gia','sto','sti','stin','ston','stis','stus','sta','ena','enas','mia'}
def allwords(s): return [w for w in re.split(r'[^a-z0-9α-ω%]+', s) if w]
def words(s): return [w for w in allwords(s) if w not in STOP]
# Γενική σε -ου/-ιού («κοτόπουλου», «πορτοκαλιού») και -εως («αλέσεως»).
END = ['eos','es','as','os','is','us','iu','on','a','e','i','o','u','s']
SAME = {'vrast':'vrasmen', 'aspr':'lefk', 'galakt':'gal', 'kreat':'kre', 'furn':'psit', 'shar':'psit'}
def pluralstem(w):
    if re.search(r'[^a-z]', w): return None
    for e in ('ies','ia'):
        if w.endswith(e) and len(w)-len(e) >= 4: return w[:-len(e)]
    return None
def stem(w, same=True):
    if len(w) < 4 or re.search(r'[^a-z]', w): return w
    for e in END:
        if w.endswith(e) and len(w)-len(e) >= 3:
            b = w[:-len(e)]; return SAME.get(b, b) if same else b
    return w
NEG = 'horis'
# Ομόηχες ρίζες με άλλο νόημα: «τσίπουρο» (ποτό) ≠ «τσιπούρα» (ψάρι).
HOMONYMS = [{'tsipuro', 'tsipuru'}]
def homonym(a, b):
    for g in HOMONYMS:
        if (a in g) != (b in g): return True
    return False
# Λέξεις που περιγράφουν κομμάτι/μορφή, όχι το τρόφιμο: δεν χρειάζεται να ταιριάξουν («φιλέτο σολομού» → σολομός).
OPTIONAL = {phonetic(w) for w in ['φιλέτο','φιλέτα','φιλετάκι','φιλετάκια','κομμάτι','κομμάτια','μερίδα','σπιτικό','σπιτικός','σπιτική','σπιτικά']}
# Παραλλαγές με πολύ περισσότερο αλάτι ή ζάχαρη ανά 100 g: πάνε κάτω από το απλό τρόφιμο, αν δεν τις ζητήσεις.
MARKED = {stem(phonetic(w)) for w in ['παστός','αλατισμένος','αλίπαστος','καπνιστός','μαρινάτος']}
MARKED_CAT = {'Αποξηραμένα φρούτα': [phonetic(w) for w in ['ξερά', 'αποξηραμένα']]}
MARKED_PENALTY = 3.0
EXACT_BONUS = 4.0
# Κατηγορίες: «ψάρι» φέρνει τα ψάρια, «κρέας» το κρέας κ.λπ. (χαμηλός βαθμός, κάτω από κάθε λέξη ονόματος).
CAT_TERMS = {
    'Κρέας': ['κρέας', 'κρέατα'], 'Πουλερικά': ['πουλερικά', 'πουλερικό', 'κρέας'], 'Αλλαντικά': ['αλλαντικά', 'αλλαντικό'],
    'Ψάρια': ['ψάρι', 'ψάρια'], 'Θαλασσινά': ['θαλασσινά', 'θαλασσινό'],
    'Γαλακτοκομικά': ['γαλακτοκομικά', 'γαλακτοκομικό'], 'Τυριά': ['τυρί', 'τυριά'], 'Αυγά': ['αυγό', 'αυγά'],
    'Όσπρια': ['όσπρια', 'όσπριο'], 'Λαχανικά': ['λαχανικά', 'λαχανικό', 'ζαρζαβατικά'], 'Πατάτες': ['πατάτα', 'πατάτες'],
    'Φρούτα': ['φρούτο', 'φρούτα'], 'Αποξηραμένα φρούτα': ['αποξηραμένα φρούτα', 'ξερά φρούτα', 'αποξηραμένα'],
    'Ξηροί καρποί': ['ξηροί καρποί', 'ξηρός καρπός', 'ξηροκάρπια'], 'Σπόροι': ['σπόροι', 'σπόρος'],
    'Δημητριακά': ['δημητριακά'], 'Ζυμαρικά': ['ζυμαρικά'], 'Γλυκά': ['γλυκά', 'γλυκό'],
    'Ροφήματα': ['ροφήματα', 'ρόφημα', 'ποτά', 'ποτό'], 'Σάλτσες': ['σάλτσες', 'σάλτσα'],
    'Καρυκεύματα': ['καρυκεύματα', 'μπαχαρικά'], 'Έτοιμα φαγητά': ['έτοιμο φαγητό', 'έτοιμα φαγητά'],
    'Συμπληρώματα': ['συμπληρώματα', 'συμπλήρωμα'],
}
CAT_SCORE = 6.0
# Λέξεις τρόπου μαγειρέματος: αν χρειαστεί να αγνοηθούν, οι μαγειρεμένες μορφές μπαίνουν πρώτες.
COOKING = {stem(phonetic(w)) for w in ['ψητό','βραστό','βρασμένο','σχάρας','φούρνου','τηγανητό','μαγειρεμένο','ατμού','στιφάδο','κοκκινιστό','πανέ']}
PREFERRED = {'C19033':0.5,'C2013':0.5,'C36017':0.5,'C7000':0.5,'C9104':0.5,'C36018':0.5,'C39500':0.5,'C12066':1.5,
             'U170903':0.5,'C26024':0.5}

def osa1(a, b):
    """Απόσταση ≤ 1 (αντικατάσταση, προσθήκη, αφαίρεση ή αντιμετάθεση δύο διπλανών γραμμάτων)."""
    if a == b: return True
    la, lb = len(a), len(b)
    if abs(la - lb) > 1: return False
    if la == lb:
        d = [k for k in range(la) if a[k] != b[k]]
        if len(d) == 1: return True
        return len(d) == 2 and d[1] == d[0]+1 and a[d[0]] == b[d[1]] and a[d[1]] == b[d[0]]
    s, l = (a, b) if la < lb else (b, a)
    k = 0
    while k < len(s) and s[k] == l[k]: k += 1
    return s[k:] == l[k+1:]

INGR_CAP = 2.0
def ingredient_flags(name):
    """Για κάθε λέξη του ονόματος: αν είναι συστατικό μετά από «με» («Πουρές πατάτας (με γάλα και βούτυρο)»)."""
    out = []
    for seg in re.split(r'[(),]', phonetic(name)):
        after = False
        for t in allwords(seg):
            if t == 'me': after = True; continue
            if t in STOP: continue
            out.append(after)
    return out

def head_words(name):
    h = re.split(r'[(,]', name, maxsplit=1)[0]
    return words(phonetic(h))

class Index:
    def __init__(self, foods):
        self.foods = foods
        self.name = [words(phonetic(f['name'])) for f in foods]
        self.alias = []
        for f in foods:
            ph = [ws for a in f.get('aliases', []) for ws in [words(phonetic(str(a)))] if ws]
            ph += [[w] for w in words(phonetic(f.get('brand') or ''))]
            self.alias.append(ph)
        self.nstem = [[stem(w) for w in ws] for ws in self.name]
        self.ingr = [ingredient_flags(f['name']) for f in foods]
        for i in range(len(foods)): assert len(self.ingr[i]) == len(self.name[i]), foods[i]['name']
        self.astem = [[[stem(w) for w in ws] for ws in phs] for phs in self.alias]
        self.head = [head_words(f['name']) for f in foods]
        # Για το «ακριβές ταίριασμα όλης της αναζήτησης»: ρίζες ΧΩΡΙΣ τα συνώνυμα (φούρνου ≠ ψητό εδώ).
        self.headbase = [[stem(w, False) for w in ws] for ws in self.head]
        self.abase = [[[stem(w, False) for w in ws] for ws in phs] for phs in self.alias]
        self.cat = [[words(phonetic(t)) for t in CAT_TERMS.get(f.get('cat', ''), [])] for f in foods]
        self.catstem = [[[stem(w) for w in ws] for ws in phs] for phs in self.cat]
        self.marked = []
        for i, f in enumerate(foods):
            m = [w for w in self.nstem[i] if w in MARKED]
            m += [stem(w) for w in MARKED_CAT.get(f.get('cat', ''), [])]
            self.marked.append(set(m))
        vocab = {}
        for f in foods:
            for src in [f['name']] + [str(a) for a in f.get('aliases', [])]:
                for raw in re.split(r'[^0-9A-Za-zΑ-Ωα-ωάέήίόύώϊϋΐΰΆΈΉΊΌΎΏς%]+', src.lower()):
                    if not raw: continue
                    ws = words(phonetic(raw))
                    if len(ws) == 1 and len(ws[0]) >= 6: vocab.setdefault(ws[0], raw)
        self.vocab = vocab

    # ---------- δημόσιο ----------
    def search(self, query, boost=PREFERRED, limit=60):
        return self.find(query, boost, limit)[0]

    def find(self, query, boost=PREFERRED, limit=60):
        """(τρόφιμα, αγνοήθηκαν, διορθώθηκαν{λάθος: σωστό}). self.dropped_food = FoodSearchResult.droppedFood της Dart."""
        self.dropped_food = False
        r = self._with_variants(query, boost, limit)
        if r: return r, [], {}
        q = words(phonetic(query)) or allwords(phonetic(query))
        if not q: return [], [], {}
        typed = {}
        for raw in re.split(r'[^0-9A-Za-zΑ-Ωα-ωάέήίόύώϊϋΐΰΆΈΉΊΌΎΏς%]+', query.lower()):
            for w in allwords(phonetic(raw)): typed.setdefault(w, raw)
        self._typed = typed
        neg = NEG in q
        # 1. Ένα λάθος γράμμα σε λέξη 6+ γραμμάτων που δεν ταιριάζει πουθενά («κοτόπολο», «γιαουτρι»).
        fixed = {}
        q2 = list(q)
        for k, w in enumerate(q):
            # Λέξη που υπάρχει ήδη στα ονόματα (π.χ. μέσα σε φράση) δεν είναι λάθος γράμμα («καλαμάκι» ≠ «καλαμάρι»).
            if len(w) >= 6 and w not in self.vocab and not self._matches_any(w, neg):
                best = None
                for v in sorted(self.vocab):
                    if v != w and v[0] == w[0] and osa1(w, v): best = v; break
                if best is not None:
                    q2[k] = best; fixed[self._typed.get(w, w)] = self.vocab[best]
        if fixed:
            r, _ = self._search(' '.join(q2), boost, limit, phon=True)
            if r: return r, [], fixed
        # 2. Χωρίς τις λέξεις που δεν ταιριάζουν σε κανένα τρόφιμο («μέλι θυμαρίσιο» → μέλι).
        keep = [w for w in q2 if self._matches_any(w, neg)]
        dropped = [w for w in q2 if not self._matches_any(w, neg)]
        if keep and dropped:
            r, _ = self._search(' '.join(keep), boost, limit, phon=True, cooked_first=any(stem(w) in COOKING for w in dropped))
            if r:
                self.dropped_food = q2[0] in dropped
                return r, [self._show(w) for w in dropped], fixed
        # 3. Κάθε λέξη ταιριάζει κάπου, αλλά όχι όλες μαζί: χωρίς μία λέξη (κρατά το καλύτερο ταίριασμα).
        if len(keep) >= 2:
            best = None
            # Ποτέ χωρίς την ΠΡΩΤΗ λέξη (το ίδιο το τρόφιμο): «σοκολάτα χωρίς ζάχαρη» δεν γίνεται «μούσλι χωρίς ζάχαρη».
            for k in range(1, len(keep)):
                rest = keep[:k] + keep[k+1:]
                r, top = self._search(' '.join(rest), boost, limit, phon=True, cooked_first=stem(keep[k]) in COOKING)
                if r and (best is None or top > best[1]): best = (r, top, keep[k])
            if best:
                self.dropped_food = True
                return best[0], [self._show(w) for w in dropped] + [self._show(best[2])], fixed
            # 3β. Μόνο η πρώτη λέξη (το τρόφιμο), χωρίς τους προσδιορισμούς.
            r, _ = self._search(keep[0], boost, limit, phon=True)
            if r:
                self.dropped_food = True
                return r, [self._show(w) for w in dropped] + [self._show(w) for w in keep[1:]], fixed
        return [], [], {}

    # ---------- εσωτερικά ----------
    def _show(self, w):
        return self._typed.get(w) or self.vocab.get(w, w)

    def _matches_any(self, w, neg_query):
        for i in range(len(self.foods)):
            if self._word_score(i, w, stem(w), pluralstem(w), None, None, neg_query) > 0: return True
        return False

    def _with_variants(self, query, boost, limit):
        r, top = self._search(query, boost, limit)
        if (r and top >= 5.0) or re.search(r'[Ͱ-Ͽἀ-῿]', query): return r
        lower = query.lower(); best = r; bestTop = top if r else float('-inf')
        chain = re.sub(r'([ae])[uy](?=[b-df-hj-np-tv-z])', r'\1v', lower)
        vs = []
        for v in [lower.replace('x','ks'), lower.replace('h','i'), lower.replace('x','ks').replace('h','i'),
                  lower.replace('au','av').replace('eu','ev'), re.sub(r'\byi?', 'gi', lower),
                  lower.replace('ev','ef').replace('av','af'), lower.replace('ef','ev').replace('af','av'),
                  chain, chain.replace('ev','ef').replace('av','af')]:
            if v not in vs: vs.append(v)
        for v in vs:
            if v == lower: continue
            alt, at = self._search(v, boost, limit)
            if alt and at > bestTop: best, bestTop = alt, at
        return best

    def _word_score(self, i, w, ws, wp, phrases, catphr, neg_query):
        # phrases/catphr = None: μόνο τα μονολεκτικά άλλα ονόματα και κατηγορίες (για «ταιριάζει κάπου;»)
        best = 0.0
        N = self.name[i]
        for k, nw in enumerate(N):
            first = k == 0; s = 0.0
            if nw == w: s = 10 if first else 8
            elif homonym(w, nw): s = 0
            elif nw.startswith(w): s = 7 if first else 5
            elif len(ws) >= 3 and self.nstem[i][k] == ws: s = 7 if first else 5
            elif wp is not None and self.nstem[i][k] == wp: s = 4 if first else 3
            elif len(w) >= 5 and w in nw: s = 2
            # Λέξη μετά το «χωρίς» στο όνομα: ταιριάζει (λίγο) μόνο αν και η αναζήτηση λέει «χωρίς» («αυγό σε λάδι» ≠
            # «αυγό χωρίς λάδι»).
            if s > 0 and k > 0 and N[k-1] == NEG: s = 1 if neg_query else 0
            if s > INGR_CAP and self.ingr[i][k]: s = INGR_CAP
            best = max(best, s)
        al = range(len(self.alias[i])) if phrases is None else phrases
        for a in al:
            if phrases is None and len(self.alias[i][a]) > 1: continue
            for k, aw in enumerate(self.alias[i][a]):
                if aw == w: s = 9.0
                elif homonym(w, aw): s = 0.0
                elif aw.startswith(w): s = 4.0
                elif len(ws) >= 3 and self.astem[i][a][k] == ws: s = 3.0
                elif wp is not None and self.astem[i][a][k] == wp: s = 2.0
                else: s = 0.0
                best = max(best, s)
        if best == 0:
            cs = [c for c in range(len(self.cat[i])) if len(self.cat[i][c]) == 1] if catphr is None else catphr
            for c in cs:
                cw = self.cat[i][c]
                for k, x in enumerate(cw):
                    if x == w or (len(ws) >= 3 and self.catstem[i][c][k] == ws): best = max(best, CAT_SCORE)
        return best

    def _search(self, query, boost, limit, phon=False, cooked_first=False):
        p = query if phon else phonetic(query)
        q = words(p)
        if not q: q = allwords(p)
        if not q: return [], 0.0
        qs = [stem(w) for w in q]
        qb = [stem(w, False) for w in q]
        def pin(ws, sts):
            for k in range(len(ws)):
                if not any(ws[k] == q[j] or ws[k].startswith(q[j]) or (len(qs[j]) >= 3 and sts[k] == qs[j]) for j in range(len(q))): return False
            return True
        def same_set(ws, sts):
            # όλη η αναζήτηση = αυτή η φράση (ίδιες λέξεις ή ρίζες, με οποιαδήποτε σειρά)
            if len(ws) != len(q): return False
            used = set()
            for j in range(len(q)):
                hit = next((k for k in range(len(ws)) if k not in used and (ws[k] == q[j] or (len(qb[j]) >= 3 and sts[k] == qb[j]))), None)
                if hit is None: return False
                used.add(hit)
            return True
        required = [w for w in q if w not in OPTIONAL] or q
        neg = NEG in q
        scored = []; top = float('-inf')
        for i, f in enumerate(self.foods):
            score = 0.0; ok = True; counted = 0
            phr = [a for a in range(len(self.alias[i])) if len(self.alias[i][a]) == 1 or pin(self.alias[i][a], self.astem[i][a])]
            cph = [c for c in range(len(self.cat[i])) if len(self.cat[i][c]) == 1 or pin(self.cat[i][c], self.catstem[i][c])]
            for w in q:
                best = self._word_score(i, w, stem(w), pluralstem(w), phr, cph, neg)
                if best == 0:
                    if w in required: ok = False; break
                    continue
                score += best; counted += 1
            if not ok: continue
            wavg = score / max(1, counted)
            if wavg > top: top = wavg
            if wavg > 2.0: score += boost.get(f['id'], 0)
            exact = any(same_set(self.alias[i][a], self.abase[i][a]) for a in range(len(self.alias[i]))) or \
                    same_set(self.head[i], self.headbase[i])
            if exact: score += EXACT_BONUS
            if self.marked[i] and not any(stem(w) in self.marked[i] or any(m.startswith(w) for m in self.marked[i] if len(w) >= 3) for w in q):
                score -= MARKED_PENALTY
            if f.get('source') in ('Open Food Facts', 'Ετικέτα'): score += 1.5
            if f.get('cooked'): score += 1.2
            if cooked_first and f.get('rawId'): score += 2.5
            score -= len(f['name']) / 60
            scored.append((score, i))
        if len(q) == 1 and len(q[0]) >= 5 and top <= 2: return [], top
        scored.sort(key=lambda t: (-t[0], t[1]))
        self.last_scored = scored
        return [self.foods[s[1]] for s in scored[:limit]], top

import os
ASSET = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'foods', 'basic_foods.json')

def load(path=ASSET):
    return json.load(open(path, encoding='utf-8'))['foods']

if __name__ == '__main__':
    import sys
    ix = Index(load())
    for q in sys.argv[1:]:
        foods, ign, fix = ix.find(q)
        print(f'«{q}»' + (f' (χωρίς: {ign})' if ign else '') + (f' (διόρθωση: {fix})' if fix else ''))
        for f in foods[:5]:
            print('   ', f['id'], f['name'], f['n'].get('kcal'))
