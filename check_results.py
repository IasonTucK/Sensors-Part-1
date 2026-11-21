#!/usr/bin/python
# -*- coding: utf-8 -*-
# Έλεγχος αποτελεσμάτων: python check_results.py log.txt
# Διαβάζει το log της προσομοίωσης, ξαναϋπολογίζει σε κάθε εποχή το ερώτημα από τις μετρήσεις όλων των κόμβων
# του δέντρου (κανάλι "Measurements") και το συγκρίνει με ό,τι τύπωσε η ρίζα (κανάλι "Results").
# Τυπώνει επίσης πόσα μηνύματα συνάθροισης και πόσα bytes στάλθηκαν (κανάλι "Messages").
from __future__ import print_function
import re, sys

log = open(sys.argv[1] if len(sys.argv) > 1 else "log.txt").read().splitlines()

meas = {}      # epoch -> {node: measurement}
results = {}   # epoch -> (query, value)
msgs = {}      # epoch -> [bytes, ...]
query_name = {"1": "SUM", "2": "AVG", "3": "VARIANCE", "4": "MAX"}
query = epoch_sec = None

for line in log:
    m = re.search(r"ROOT: queryType= (\d+) .*epochSec= (\d+)", line)
    if m:
        query, epoch_sec = query_name[m.group(1)], int(m.group(2))
    m = re.search(r"epoch= (\d+) node= (\d+) depth= \d+ parent= \d+ measurement= (\d+)", line)
    if m:
        meas.setdefault(int(m.group(1)), {})[int(m.group(2))] = int(m.group(3))
    m = re.search(r"EPOCH (\d+) : (SUM|AVG|VARIANCE|MAX) = ([\d.]+)", line)
    if m:
        results[int(m.group(1))] = (m.group(2), float(m.group(3)))
    m = re.search(r"epoch= (\d+) node= \d+ to= \d+ bytes= (\d+)", line)
    if m:
        msgs.setdefault(int(m.group(1)), []).append(int(m.group(2)))

def expected(q, values):
    n = float(len(values))
    if q == "SUM":
        return float(sum(values))
    if q == "AVG":
        return sum(values) / n
    if q == "VARIANCE":
        mean = sum(values) / n
        return sum(v * v for v in values) / n - mean * mean
    return float(max(values))

print("Query: %s, epoch: %s s" % (query, epoch_sec))
print("%-6s %-6s %-12s %-12s %-6s %-9s %-6s" % ("Epoch", "Nodes", "Expected", "Root", "OK", "AggMsgs", "Bytes"))
ok_count = 0
for e in sorted(results):
    q, got = results[e]
    vals = list(meas.get(e, {}).values())
    exp = expected(q, vals) if vals else float("nan")
    ok = abs(exp - got) < 0.01
    ok_count += ok
    print("%-6d %-6d %-12.2f %-12.2f %-6s %-9d %-6d" % (e, len(vals), exp, got, "yes" if ok else "NO",
                                                      len(msgs.get(e, [])), sum(msgs.get(e, []))))
print("Correct epochs: %d / %d" % (ok_count, len(results)))
