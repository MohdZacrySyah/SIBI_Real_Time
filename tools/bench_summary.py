#!/usr/bin/env python3
"""Ringkas berkas CSV benchmark SIBI menjadi rerata, SD, p95 (sesuai Tabel 3.9).

Pemakaian:
    python tools/bench_summary.py FOLDER_ATAU_BERKAS.csv [...]
Hasil dicetak sebagai tabel dan disimpan ke summary.csv di folder kerja.
"""
import csv, glob, math, os, statistics as st, sys


def pct(v, p):
    v = sorted(v)
    if not v:
        return float('nan')
    k = (len(v) - 1) * p / 100.0
    lo, hi = math.floor(k), math.ceil(k)
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def stats(v):
    if not v:
        return None
    return (len(v), st.fmean(v), st.pstdev(v) if len(v) > 1 else 0.0, pct(v, 95))


def num(row, key):
    s = row.get(key, '')
    return float(s) if s not in ('', None) else None


def load(path):
    with open(path, newline='', encoding='utf8') as f:
        return list(csv.DictReader(f))


def collect(rows, key, cond=lambda r: True):
    out = []
    for r in rows:
        if cond(r):
            x = num(r, key)
            if x is not None:
                out.append(x)
    return out


def summarize(label, rows):
    res = []
    hand = lambda r: r['hand'] == '1'
    is_word = lambda r: 'Kata' in r['engine'] and hand(r)
    is_alpha = lambda r: 'Huruf' in r['engine'] and hand(r)
    items = [
        ('Waktu ekstraksi landmark (ms)', collect(rows, 'landmark_ms', hand)),
        ('Inference time Model 1 per invoke (ms)', collect(rows, 'alpha_invoke_ms', hand)),
        ('Inference time Model 2 per invoke (ms)', collect(rows, 'word_invoke_ms', hand)),
        ('Waktu classify() total (ms)', collect(rows, 'classify_ms', hand)),
        ('Latency end-to-end, hasil huruf (ms)', collect(rows, 'latency_ms', is_alpha)),
        ('Latency end-to-end, hasil kata (ms)', collect(rows, 'latency_ms', is_word)),
    ]
    warm = [r for r in rows if num(r, 'elapsed_ms') is not None and num(r, 'elapsed_ms') >= 2000]
    fps = collect(warm, 'fps', lambda r: num(r, 'fps') and num(r, 'fps') > 0)
    items.append(('FPS pipeline', fps))
    for name, v in items:
        s = stats(v)
        if s:
            res.append((label, name) + s)
    # penurunan FPS: bandingkan awal vs akhir sesi
    if warm:
        t_end = num(warm[-1], 'elapsed_ms')
        span = 60000 if t_end >= 150000 else t_end / 3.0
        first = collect(warm, 'fps', lambda r: num(r, 'elapsed_ms') <= 2000 + span and num(r, 'fps') > 0)
        last = collect(warm, 'fps', lambda r: num(r, 'elapsed_ms') >= t_end - span and num(r, 'fps') > 0)
        if first and last:
            a, b = st.fmean(first), st.fmean(last)
            res.append((label, 'Penurunan FPS awal→akhir (%)', len(first) + len(last), (a - b) / a * 100.0, 0.0, 0.0))
    rss = collect(rows, 'rss_mb')
    if rss:
        res.append((label, 'RSS awal / akhir / maks (MB)', len(rss), rss[0], rss[-1], max(rss)))
    dur = (num(rows[-1], 'elapsed_ms') or 0) / 1000.0
    res.append((label, 'Durasi sesi (detik) / jumlah frame', len(rows), dur, 0.0, 0.0))
    return res


def main(args):
    files = []
    for a in args:
        files += sorted(glob.glob(os.path.join(a, '*.csv'))) if os.path.isdir(a) else [a]
    if not files:
        print(__doc__)
        return 1
    out = []
    merged = {}
    for f in files:
        rows = load(f)
        if not rows:
            continue
        key = f"{rows[0]['platform']} / {rows[0]['mode']}"
        out += summarize(f"{os.path.basename(f)}", rows)
        merged.setdefault(key, []).extend(rows)
    if len(merged) and len(files) > len(merged):
        for key, rows in merged.items():
            out += summarize(f"GABUNGAN {key}", rows)
    print(f"{'Sesi':44} {'Parameter':44} {'N':>7} {'Rerata':>9} {'SD':>9} {'p95':>9}")
    for l, n, N, m, sd, p in out:
        print(f"{l[:44]:44} {n:44} {N:7d} {m:9.2f} {sd:9.2f} {p:9.2f}")
    with open('summary.csv', 'w', newline='', encoding='utf8') as f:
        w = csv.writer(f)
        w.writerow(['sesi', 'parameter', 'N', 'rerata', 'sd', 'p95'])
        for r in out:
            w.writerow(list(r[:3]) + [f'{x:.3f}' for x in r[3:]])
    print('\nTersimpan: summary.csv')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
