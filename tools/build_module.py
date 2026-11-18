"""Build an SKTools Profession DB module from CMaNGOS classic-db (loot/skinning/recipes)
and QuestieDB Forever (spawns already in Forever map coordinates, vendors).

usage: build_module.py <profession> <output Data.lua>
"""
import pickle, re, collections, sys, math

SRC = '/home/claude/src'
PROF = {
    'leatherworking': dict(name='Leatherworking', skill=165, recipeSub=1, icon=133611, extra={2934},
        cats=['Leather', 'Hides', 'Scales', 'Elemental', 'Other reagents', 'Vendor supplies', 'Patterns']),
    'tailoring': dict(name='Tailoring', skill=197, recipeSub=2, icon=136249, extra={2589},  # + Linen Cloth (Bolt of Linen is taught automatically)
        cats=['Cloth', 'Leather & hides', 'Elemental', 'Other reagents', 'Vendor supplies', 'Patterns']),
}
KEY = sys.argv[1]; P = PROF[KEY]
OUT = sys.argv[2]
MIN_CHANCE = 0.5          # drops below this % are left out of the data
CLUSTER = 1.2             # merge spawn points closer than this (map %)

cols, rows = pickle.load(open(f'{SRC}/tables.pkl', 'rb'))
QN, QI, QO = pickle.load(open(f'{SRC}/questie.pkl', 'rb'))

ic = cols['item_template']; ITEM = {r[0]: dict(zip(ic, r)) for r in rows['item_template']}
c2, r2 = pickle.load(open(f'{SRC}/s2.pkl', 'rb'))
SPELL = {r[0]: dict(zip(c2['spell_template'], r)) for r in r2['spell_template']}
def learned(sp):
    s_ = SPELL.get(sp)
    if not s_: return None
    return s_['EffectTriggerSpell1'] if s_['Effect1'] == 36 else sp
craft = set()
for t in ('npc_trainer', 'npc_trainer_template'):
    for r in r2[t]:
        d = dict(zip(c2[t], r))
        if d['reqskill'] == P['skill']:
            craft.add(learned(d['spell']))
patterns = {}
for i, d in ITEM.items():
    if d['class'] == 9 and d['subclass'] == P['recipeSub']:
        patterns[i] = d
        for k in ('spellid_1', 'spellid_2'):
            sp = d.get(k)
            if sp in SPELL and SPELL[sp]['Effect1'] == 36:
                craft.add(SPELL[sp]['EffectTriggerSpell1'])
reag, crafted = {}, set()
for sp in craft:
    s_ = SPELL.get(sp)
    if not s_: continue
    if s_['EffectItemType1']: crafted.add(s_['EffectItemType1'])
    for k in range(1, 9):
        it = s_['Reagent%d' % k]
        if it: reag.setdefault(it, set()).add(sp)
cc = cols['creature_template']; CRE = {r[0]: dict(zip(cc, r)) for r in rows['creature_template']}

def table(name):
    t = collections.defaultdict(list)
    for r in rows[name]:
        t[r[0]].append(r)
    return t
SKIN, LOOT, REF = table('skinning_loot_template'), table('creature_loot_template'), table('reference_loot_template')

def chances(entries, depth=0):
    """item -> % chance for one loot template, resolving groups and references."""
    out = collections.defaultdict(float)
    groups = collections.defaultdict(list)
    for e in entries:
        groups[e[3]].append(e)
    for gid, es in groups.items():
        if gid == 0:
            for _, item, ch, _, mc, *_ in es:
                ch = abs(ch)
                if mc < 0:
                    if depth < 4:
                        for it, c in chances(REF.get(-mc, []), depth + 1).items():
                            out[it] += ch / 100 * c
                else:
                    out[item] += ch
        else:
            explicit = sum(abs(e[2]) for e in es if e[2] != 0)
            zeros = [e for e in es if e[2] == 0]
            share = max(0.0, 100 - explicit) / len(zeros) if zeros else 0
            for _, item, ch, _, mc, *_ in es:
                ch = abs(ch) if ch != 0 else share
                if mc < 0:
                    if depth < 4:
                        for it, c in chances(REF.get(-mc, []), depth + 1).items():
                            out[it] += ch / 100 * c
                else:
                    out[item] += ch
    return out

# ---------------------------------------------------------------- zones
def lua_table(path, var):
    s = open(path, encoding='utf-8').read()
    m = re.search(re.escape(var) + r' = \[\[return \{(.*?)\}\]\]', s, re.S)
    return {int(a): int(b) for a, b in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', m.group(1))}
ZD = f'{SRC}/db/support/Forever/Zones/'
AREA2MAP = lua_table(ZD + 'areaIdToUiMapId.lua', 'ZoneDB.private.areaIdToUiMapId')
OVR = lua_table(ZD + 'areaIdToUiMapId.lua', 'ZoneDB.private.areaIdToUiMapIdOverride')
DUNGEON = {}
for m in re.finditer(r'\[(\d+)\] = \{"([^"]+)",(\{[^}]*\}|nil),(\d+),\{\{(\d+), ([\d.]+), ([\d.]+)\}', open(ZD + 'dungeons.lua').read()):
    aid, name, alts, parent, pz, x, y = m.groups()
    entry = (name, int(pz), float(x), float(y))
    DUNGEON[int(aid)] = entry
    if alts != 'nil':
        for a in re.findall(r'\d+', alts):
            DUNGEON[int(a)] = entry

ZONENAME = {}
for line in open(ZD + 'areaIdToUiMapId.lua'):
    m = re.match(r'\s*\[(\d+)\] = (\d+), -- (.*)', line)
    if m and '->' not in m.group(3):
        ZONENAME[int(m.group(2))] = m.group(3).strip()

def cluster(points):
    out = []
    for x, y in points:
        for c in out:
            if math.hypot(c[0] / c[2] - x, c[1] / c[2] - y) < CLUSTER:
                c[0] += x; c[1] += y; c[2] += 1
                break
        else:
            out.append([x, y, 1])
    return [(round(a / n, 1), round(b / n, 1)) for a, b, n in out]

def spawns(npc):
    """{uiMapID: [(x,y),...]}, dungeon names it lives in"""
    q = QN.get(npc)
    res, dungeons = collections.defaultdict(list), set()
    if not q or not q.get(7):
        return res, dungeons
    for area, pts in q[7].items():
        pts = [(p[1], p[2]) for p in pts.values()] if pts else []
        if area in DUNGEON:
            name, pz, x, y = DUNGEON[area]
            dungeons.add(name)
            m = AREA2MAP.get(pz)
            if m: res[m].append((x, y))
            continue
        m = AREA2MAP.get(area) or OVR.get(area)
        if not m:
            continue
        res[m].extend((x, y) for x, y in pts if 0 <= x <= 100 and 0 <= y <= 100)
    return {m: cluster(p) for m, p in res.items() if p}, dungeons

# ---------------------------------------------------------------- items
PATTERNS = {i for i in patterns if not ITEM[i]['name'].startswith('Deprecated')}
MATS = {i for i in reag if (i not in crafted or ITEM[i]['class'] == 7) and i in ITEM} | P['extra']
items = {}
def category(i):
    n = ITEM[i]['name']
    if i in PATTERNS: return 'Patterns'
    if KEY == 'tailoring':
        if re.search(r'Cloth|Linen|Wool|Silk|Mageweave|Runecloth|Felcloth|Mooncloth|Bolt|Thread|Yarn', n, re.I) \
                and not re.search(r'Coarse|Fine|Heavy Silken|Rune Thread', n): return 'Cloth'
        if re.search(r'Leather|Hide|Pelt|Skin|Scale|Fur', n, re.I): return 'Leather & hides'
    else:
        if re.search(r'Leather|Scraps', n, re.I): return 'Leather'
        if re.search(r'Hide|Pelt|Skin', n, re.I): return 'Hides'
        if re.search(r'Scale|Chitin|Carapace', n, re.I): return 'Scales'
    if re.search(r'Elemental|Core of|Essence|Heart of|Globe|Breath|Living|Fiery|Lava|Frozen', n): return 'Elemental'
    return 'Other reagents'

sources = collections.defaultdict(list)   # item -> [(npc, kind, chance)]
for npc, c in CRE.items():
    if npc not in QN:
        continue
    if c['SkinningLootId']:
        for it, ch in chances(SKIN.get(c['SkinningLootId'], [])).items():
            if (it in MATS or it in PATTERNS) and ch >= MIN_CHANCE:
                sources[it].append((npc, 'S', ch))
    if c['LootId']:
        for it, ch in chances(LOOT.get(c['LootId'], [])).items():
            if (it in MATS or it in PATTERNS) and ch >= MIN_CHANCE:
                sources[it].append((npc, 'D', ch))
for it in MATS | PATTERNS:
    q = QI.get(it) or {}
    for v in (q.get(14) or {}).values():
        if v in QN:
            sources[it].append((v, 'V', 0))

mobs = {}
for it, src in sources.items():
    for npc, kind, ch in src:
        if npc not in mobs:
            sp, dg = spawns(npc)
            q = QN[npc]
            mobs[npc] = dict(name=q[1], lmin=q[4] or 0, lmax=q[5] or 0, rank=q[6] or 0,
                             sub=q.get(14), fr=q.get(13), spawns=sp, dungeons=sorted(dg))
# drop sources with no map position at all
for it in list(sources):
    sources[it] = sorted([s for s in sources[it] if mobs[s[0]]['spawns']], key=lambda s: (s[1] == 'V', -s[2]))
    if not sources[it]:
        del sources[it]
WORLD = {i for i in PATTERNS if i not in sources}
for i in WORLD:
    sources[i] = []
def category2(i):
    c = category(i)
    if c != 'Patterns' and sources[i] and all(s[1] == 'V' for s in sources[i]):
        return 'Vendor supplies'
    return c

used = {s[0] for src in sources.values() for s in src}
def lstr(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

with open(OUT, 'w') as f:
    f.write('-- SKToolsProfessionDB %s data. GENERATED by tools/build_module.py, do not edit by hand.\n' % P['name'])
    f.write('-- Loot, skinning and recipe data: CMaNGOS classic-db (GPLv3).\n')
    f.write('-- Spawns (Forever map coordinates) and vendors: QuestieDB Forever (GPLv3).\n')
    f.write('-- Chances are vanilla 1.12 values; Forever may differ.\n\n')
    f.write('local SKToolsProfessionDB = SKToolsProfessionDB\nif not SKToolsProfessionDB then return end\n\n')
    f.write('local items = {\n')
    n_items = 0
    for it in sorted(sources, key=lambda i: (category2(i), ITEM[i]['RequiredSkillRank'] if i in PATTERNS else 0, ITEM[i]['name'])):
        d = ITEM[it]
        src = ','.join('{%d,"%s",%s}' % (n, k, ('%.1f' % c).rstrip('0').rstrip('.') or '0') for n, k, c in sources[it])
        skill = d['RequiredSkillRank'] if it in PATTERNS else 0
        f.write('  [%d]={n=%s,c=%s,q=%d,%s%ssrc={%s}},\n' % (it, lstr(d['name']), lstr(category2(it)), d['Quality'],
                ('sk=%d,' % skill) if skill else '', 'w=true,' if it in WORLD else '', src))
        n_items += 1
    f.write('}\n\nlocal mobs = {\n')
    n_pts = 0
    for npc in sorted(used):
        m = mobs[npc]
        sp = ','.join('[%d]={%s}' % (mp, ','.join('%g,%g' % p for p in pts)) for mp, pts in sorted(m['spawns'].items()))
        n_pts += sum(len(p) for p in m['spawns'].values())
        extra = ''
        if m['rank']: extra += 'r=%d,' % m['rank']
        if m['sub']: extra += 't=%s,' % lstr(m['sub'])
        if m['fr']: extra += 'f="%s",' % m['fr']
        if m['dungeons']: extra += 'dg=%s,' % lstr(', '.join(m['dungeons']))
        f.write('  [%d]={n=%s,l={%d,%d},%ssp={%s}},\n' % (npc, lstr(m['name']), m['lmin'], m['lmax'], extra, sp))
    f.write('}\n\nlocal zones = {\n')
    for mp in sorted({mp for npc in used for mp in mobs[npc]['spawns']}):
        f.write('  [%d]=%s,\n' % (mp, lstr(ZONENAME.get(mp, 'Map %d' % mp))))
    f.write('}\n\n')
    f.write('SKToolsProfessionDB:RegisterModule("%s", {\n  name = "%s",\n  icon = %d,\n' % (KEY, P['name'], P['icon']) +
            '  categories = {%s},\n' % ','.join('"%s"' % c for c in P['cats']) +
            '  items = items, mobs = mobs, zones = zones,\n})\n')
print(KEY, 'recipes', len(craft), 'items', n_items, 'mobs', len(used), 'pins', n_pts, 'world', len(WORLD), 'missing', sorted(ITEM[i]['name'] for i in (MATS | PATTERNS) - set(sources)))
