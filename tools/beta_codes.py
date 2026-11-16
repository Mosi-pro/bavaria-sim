#!/usr/bin/env python3
"""Erzeugt neue Beta-Zugangscodes.

  python3 tools/beta_codes.py 20 ausgabe.txt      # 20 neue Codes erzeugen
  python3 tools/beta_codes.py --sperren 7         # Code von Tester 7 sperren

Ins Repository (data/beta/zugang.json) kommen nur gesalzene SHA-256-Prüfwerte.
Die Codes selbst stehen ausschließlich in der Ausgabedatei – diese NICHT ins Repository
einchecken, sondern sicher aufbewahren und jedem Tester seinen eigenen Code geben.
Änderungen werden mit dem nächsten Build der Beta-Version wirksam."""
import hashlib, json, os, secrets, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LIST = os.path.join(ROOT, "data", "beta", "zugang.json")
ALPHA = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # ohne 0/O und 1/I

def load():
    if os.path.exists(LIST):
        return json.load(open(LIST, encoding="utf-8"))
    return {"_comment": "Beta-Zugang: nur gesalzene SHA-256-Prüfwerte (salt:CODE). Erzeugt mit tools/beta_codes.py.",
            "salt": secrets.token_hex(16), "codes": {}}

def save(d):
    os.makedirs(os.path.dirname(LIST), exist_ok=True)
    with open(LIST, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
        f.write("\n")

def main():
    d = load()
    if len(sys.argv) >= 3 and sys.argv[1] == "--sperren":
        nr = sys.argv[2]
        if d["codes"].pop(nr, None) is None:
            sys.exit("Tester %s nicht gefunden." % nr)
        save(d)
        print("Code von Tester %s gesperrt (wirksam mit dem nächsten Beta-Build)." % nr)
        return
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    n, out = int(sys.argv[1]), sys.argv[2]
    start = max([int(k) for k in d["codes"]] + [0]) + 1
    lines = ["Beta-Zugangscodes LEITSTELLE 112 – vertraulich, nicht ins Repository!",
             "Jeder Tester bekommt genau einen Code. Sperren: python3 tools/beta_codes.py --sperren <Nr>", ""]
    for nr in range(start, start + n):
        raw = "".join(secrets.choice(ALPHA) for _ in range(12))
        d["codes"][str(nr)] = hashlib.sha256(("%s:%s" % (d["salt"], raw)).encode()).hexdigest()
        lines.append("Tester %3d:  LB-%s-%s-%s" % (nr, raw[:4], raw[4:8], raw[8:]))
    save(d)
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("%d Codes erzeugt (Tester %d–%d) → %s" % (n, start, start + n - 1, out))

if __name__ == "__main__":
    main()
