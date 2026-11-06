"""Summarise an observe.sh log: stale episodes per app/source, and flip -> converge timings."""
import re, sys
from collections import defaultdict

log, events = sys.argv[1], sys.argv[2]
blocks = []
cur = None
for line in open(log):
    line = line.rstrip('\n')
    m = re.match(r'^(\d\d):(\d\d):(\d\d) disabled=(\S*)', line)
    if m:
        h, mi, s, flag = m.groups()
        cur = {'t': int(h) * 3600 + int(mi) * 60 + int(s), 'ts': line[:8], 'flag': flag}
        blocks.append(cur)
        continue
    if cur is None:
        continue
    m = re.match(r'^\s+(REAL|TREE|ASET|CLICK):\s*(.*)$', line)
    if m:
        k, v = m.groups()
        v = v.strip()
        if k == 'CLICK':
            cur[k] = dict(x.split('=') for x in v.split() if '=' in x)
        else:
            cur[k] = [] if v == '-' else v.split()

def ts(t):
    return f'{t//3600:02d}:{t%3600//60:02d}:{t%60:02d}'

# stale episodes: name in TREE/ASET but not REAL (deleting counts as real), per source
open_ep = {}
episodes = []
for b in blocks:
    real = {n.replace('(deleting)', '') for n in b.get('REAL', [])}
    now = set()
    for src in ('TREE', 'ASET'):
        for n in b.get(src, []):
            if n not in real:
                now.add((src, n))
    for key in now:
        open_ep.setdefault(key, [b['t'], b['t']])
        open_ep[key][1] = b['t']
    for key in list(open_ep):
        if key not in now:
            st, en = open_ep.pop(key)
            episodes.append((key[0], key[1], st, en, False))
for key, (st, en) in open_ep.items():
    episodes.append((key[0], key[1], st, en, True))

# 404 clicks on apps that exist and are NOT being deleted (the worst case)
bad_click = []
for b in blocks:
    live = {n for n in b.get('REAL', []) if '(deleting)' not in n}
    for n, c in b.get('CLICK', {}).items():
        if c != '200' and n in live:
            bad_click.append((b['ts'], n, c))

print(f'samples: {len(blocks)}  ({blocks[0]["ts"]} -> {blocks[-1]["ts"]}), avg interval '
      f'{(blocks[-1]["t"]-blocks[0]["t"])/max(1,len(blocks)-1):.1f}s')
print('\nevents:')
print(open(events).read().rstrip())

print('\nflip convergence (first sample where REAL/TREE/ASET all match the flag):')
evs = [(l[:8], l[9:].strip()) for l in open(events) if l.strip()]
for et, what in evs:
    if what not in ('flip true', 'flip false'):
        continue
    t0 = int(et[:2]) * 3600 + int(et[3:5]) * 60 + int(et[6:8])
    want = 0 if what == 'flip true' else 26
    hit = {}
    for b in blocks:
        if b['t'] < t0:
            continue
        for src in ('REAL', 'TREE', 'ASET'):
            ok = len([n for n in b.get(src, []) if '(deleting)' not in n]) == want
            if ok and src not in hit:
                hit[src] = b['t'] - t0
        if len(hit) == 3:
            break
    print(f'  {et} {what:10s} -> ' + ', '.join(f'{s} {hit.get(s, "never")}s' for s in ('REAL', 'TREE', 'ASET')))

print(f'\nstale episodes (visible in TREE/ASET, no Application): {len(episodes)}')
by = defaultdict(list)
for src, n, st, en, op in episodes:
    by[src].append(en - st)
for src, d in by.items():
    print(f'  {src}: {len(d)} episodes, longest {max(d)}s (+ up to one sample interval)')
longest = sorted(episodes, key=lambda e: e[3] - e[2], reverse=True)[:10]
print('  longest:')
for src, n, st, en, op in longest:
    print(f'    {src} {n:40s} {ts(st)} -> {ts(en)}  {en-st}s{"  STILL OPEN at end" if op else ""}')
still = [e for e in episodes if e[4]]
print(f'\nstill stale at end of run: {len(still)}')
for src, n, st, en, op in still:
    print(f'    {src} {n} since {ts(st)}')
print(f'\nnon-200 clicks on live (not deleting) apps: {len(bad_click)}')
for x in bad_click[:10]:
    print('   ', *x)
