#!/usr/bin/env python3
"""Erzeugt docs/EINSATZLISTE.md aus data/incident_types.json und data/vehicle_types.json.
Aufruf: python3 tools/gen_einsatzliste.py"""
import json, os
root = os.path.join(os.path.dirname(__file__), "..")
d = json.load(open(os.path.join(root, "data/incident_types.json"), encoding="utf-8"))
ver = "?"
for line in open(os.path.join(root, "project.godot"), encoding="utf-8"):
    if line.startswith("config/version="):
        ver = line.split('"')[1]
cats, kws, types = dict(d["categories"]), d["keywords"], d["types"]
cats.setdefault("vu", {"name": "Verkehrsunfall", "desc": "Unfälle auf Straße und Autobahn (Stichwörter THL 2–5, RD)"})
for t in types.values():
    cats.setdefault(t.get("cat"), {"name": t.get("cat"), "desc": ""})
total = sum(float(t.get("weight", 1)) for t in types.values())

CAPS = {"loeschen": "Löschfahrzeug", "drehleiter": "Drehleiter", "rettungswagen": "RTW",
        "notarzt": "Notarzt", "polizei": "Polizei", "rth": "Hubschrauber"}

def caps(r):
    return ", ".join(f"{v}× {CAPS.get(k, k)}" for k, v in r.items()) if r else "–"

out = [f"# Einsatzliste – LEITSTELLE 112 (Version {ver})", "",
       "Alle Einsätze, die im Spiel vorkommen können. Die Häufigkeit ist der Anteil an allen",
       "zufälligen Notrufen (gerundet). Jede Einsatzart hat Varianten: Was der Anrufer meldet",
       "und was die erste Einheit vor Ort vorfindet, kann sich unterscheiden.", "",
       f"**{len(types)} Einsatzarten** in {len([c for c in cats if any(t.get('cat') == c for t in types.values())])} Kategorien, "
       f"{sum(len(t.get('variants', [])) for t in types.values())} Varianten, {len(kws)} Stichwörter.", ""]
for cid, c in cats.items():
    ts = [(k, t) for k, t in types.items() if t.get("cat") == cid]
    if not ts:
        continue
    ts.sort(key=lambda x: (-float(x[1].get("weight", 1))))
    out += [f"## {c['name']}", "", f"_{c.get('desc', '')}_", "",
            "| Einsatz | Stichwort | Häufigkeit | Mögliche Lagen vor Ort |", "|---|---|---|---|"]
    for k, t in ts:
        pct = 100 * float(t.get("weight", 1)) / total
        WN = {"starkregen": "Starkregen", "sturm": "Sturm", "regen": "Regen", "schnee": "Schnee", "nebel": "Nebel", "klar": "Trockenheit"}
        if float(t.get("weight", 1)) <= 0:
            freq = "nur in Szenarien"
        else:
            freq = f"{pct:.1f} %" if pct >= 0.1 else "sehr selten"
        if t.get("weather"):
            freq += " (häufiger bei " + ", ".join(WN.get(w, w) for w in t["weather"]) + ")"
        vs = []
        for v in t.get("variants", []):
            s = v.get("name", "")
            if v.get("keyword") and v["keyword"] != t.get("keyword"):
                s += f" (→ {v['keyword']})"
            vs.append(s)
        out.append(f"| {t['name']} | {t.get('keyword', '')} | {freq} | {'; '.join(vs) or '–'} |")
    out.append("")
out += ["## Stichwörter (Alarmierungsbekanntmachung)", "",
        "| Stichwort | Bedeutung | Mindestanforderung | Typische Schlagworte |", "|---|---|---|---|"]
for k, v in kws.items():
    out.append(f"| {k} | {v.get('name', '')} | {v.get('min', '–')} | {v.get('schlagworte', '–')} |")
out.append("")
open(os.path.join(root, "docs/EINSATZLISTE.md"), "w", encoding="utf-8").write("\n".join(out))
print("docs/EINSATZLISTE.md geschrieben:", len(types), "Einsatzarten")
