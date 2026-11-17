#!/usr/bin/env python3
"""Erzeugt data/stations.json (fiktive Wachen der Stadt Bavaria).
Die erzeugte JSON-Datei ist die maßgebliche Konfiguration und kann von Hand bearbeitet werden."""
import json, os
S = []
def st(id, nr, name, org, kind, pos, vehicles, slots=None, **kw):
    d = {"id": id, "nr": nr, "name": name, "org": org, "kind": kind, "pos": pos, "vehicles": vehicles,
         "slots": slots or max(len(vehicles) + 1, 3)}
    d.update(kw); S.append(d)

# Berufsfeuerwehr: 10 Feuerwachen. Grobe Anordnung wie in einer bayerischen Großstadt:
# Hauptfeuerwache im Zentrum, je eine Wache im Westen/Südwesten/Süden, Norden (bei der
# Integrierten Leitstelle), Nordosten, Osten, Südosten und am Messegelände.
# Tanklöschfahrzeuge nur an einzelnen Wachen, Feuerwehrkräne an Wache 6 und 9.
st("fw1", 1, "Feuerwache 1 – Altstadt (Hauptfeuerwache)", "fw", "bf", [-220, 330], ["KDOW", "ELW1", "HLF20", "HLF20", "DLK", "RW", "KLAF"], 10)
st("fw2", 2, "Feuerwache 2 – Zentrum Süd", "fw", "bf", [-1300, 2700], ["ELW1", "HLF20", "HLF20", "DLK", "ELW2", "GWA"], 9)
st("fw3", 3, "Feuerwache 3 – Westend", "fw", "bf", [-2950, 480], ["ELW1", "HLF20", "HLF20", "DLK", "GWL", "KLAF"], 9)
st("fw4", 4, "Feuerwache 4 – Zentrum Nord", "fw", "bf", [-700, -2000], ["ELW1", "HLF20", "HLF20", "DLK", "RW"], 8)
st("fw5", 5, "Feuerwache 5 – Ost", "fw", "bf", [2600, 2300], ["ELW1", "HLF20", "HLF20", "DLK", "TLF3000", "GWW", "GWH"], 9)
st("fw6", 6, "Feuerwache 6 – Güterstadt", "fw", "bf", [-5380, -1150], ["ELW1", "HLF20", "HLF20", "DLK", "TLF4000", "RW", "GWG", "FWK"], 10)
st("fw7", 7, "Feuerwache 7 – Nordstadt", "fw", "bf", [-720, -5180], ["ELW1", "HLF20", "HLF20", "DLK", "MTF", "KLAF"], 9)
st("fw8", 8, "Feuerwache 8 – Nordost", "fw", "bf", [3600, -3900], ["ELW1", "HLF20", "HLF20", "DLK"], 7)
st("fw9", 9, "Feuerwache 9 – Industriehafen", "fw", "bf", [5200, 3400], ["ELW1", "HLF20", "HLF20", "DLK", "TLF4000", "GWG", "GWA", "GWW", "GWDEKON", "FWK"], 12)
st("fw10", 10, "Feuerwache 10 – Messe", "fw", "bf", [6900, -2300], ["ELW1", "HLF20", "LF20", "DLK", "TLF4000", "GWL", "KLAF"], 9)
st("fwflug", 11, "Flughafenfeuerwehr Bavaria", "fw", "flughafen", [5450, -7250], ["KDOW", "ELW1", "FLF", "FLF", "FLF", "FLF", "HLF20", "TLF4000", "RW", "TRF", "TRF"], 13)
# Werkfeuerwehr eines (fiktiven) Industriebetriebs – rund um die Uhr besetzt
st("werk1", 40, "Werkfeuerwehr Bavaria Metallwerke", "fw", "werk", [-5050, -2350], ["ELW1", "HLF20", "TLF3000", "TMB", "GWL", "HLL"], 8)
# Freiwillige Feuerwehren
FF = ["MZF", "HLF10", "LF10"]
st("ff21", 21, "FF Seeburg", "fw", "ff", [4700, 5950], FF + ["TLF3000", "GWW"], 6)
st("ff22", 22, "FF Südwest", "fw", "ff", [-4700, 5300], FF + ["DLK"], 6)
st("ff23", 23, "FF Nordost", "fw", "ff", [4550, -4550], FF + ["DLK"], 6)
st("ff24", 24, "FF Stadionviertel", "fw", "ff", [-4250, -5200], FF + ["TLF3000"], 6)
st("ff25", 25, "FF Ostpark", "fw", "ff", [3900, -300], FF, 5)
st("ff26", 26, "FF Universitätsviertel", "fw", "ff", [2350, -2450], ["MZF", "HLF20", "LF10"], 5)
st("ff27", 27, "FF Zentrum Süd", "fw", "ff", [-350, 2400], ["MZF", "HLF20", "LF20", "GWL"], 6)
st("ff28", 28, "FF Waldheim", "fw", "ff", [-7300, 2900], ["MTF", "HLF20", "LF10", "TLF4000"], 6)
st("ff29", 29, "FF Südstadt", "fw", "ff", [900, 5200], FF + ["DLK"], 6)
st("ff30", 30, "FF Flughafen-Nord", "fw", "ff", [5250, -5950], FF, 5)
st("ff31", 31, "FF Oberfeldkirchen", "fw", "ff", [-10900, -8150], ["MTF", "HLF10", "TLF3000"], 4)
st("ff32", 32, "FF Aichering", "fw", "ff", [11100, 3550], ["MTF", "HLF10", "LF10"], 4)
st("ff33", 33, "FF Moosbrunn", "fw", "ff", [-1650, 10450], ["MTF", "HLF10"], 4)
st("ff34", 34, "FF Hohenried", "fw", "ff", [-11300, 6700], ["MTF", "LF10", "TLF3000"], 4)
st("ff35", 35, "FF Kirchstetten", "fw", "ff", [10900, -9400], ["MTF", "HLF10"], 4)
# Rettungsdienst (inkl. Rettungswagen der Berufsfeuerwehr – an den Feuerwachen stationiert, Organisation Rettungsdienst)
def rw(id, nr, name, pos, v, slots=None, kind="rw"): st(id, nr, name, "rd", kind, pos, v, slots)
rw("rwf1", 31, "Rettungswache Feuerwache 1 – Altstadt", [-180, 290], ["RTW", "NEF", "KINEF"], 4)
rw("rwf4", 34, "Rettungswache Feuerwache 4 – Zentrum Nord", [-660, -1960], ["RTW"], 2)
rw("rwf7", 37, "Rettungswache Feuerwache 7 – Nordstadt", [-680, -5140], ["RTW"], 2)
rw("rwf6", 36, "Rettungswache Feuerwache 6 – Güterstadt", [-5340, -1110], ["GRTW"], 2)
rw("rwwerk", 40, "Werksanitätsdienst Bavaria Metallwerke", [-5010, -2310], ["RTW"], 2)
rw("rw1", 1, "Rettungswache 1 – Altstadt", [220, -330], ["RTW", "RTW", "NEF"])
rw("rw2", 2, "Rettungswache 2 – Bahnhofsviertel", [-1500, -560], ["RTW", "RTW", "NEF", "KTW", "SRTW"], 6)
rw("rw3", 3, "Rettungswache 3 – Zentrum Nord", [-350, -2350], ["RTW", "RTW"])
rw("rw4", 4, "Rettungswache 4 – Zentrum Süd", [-200, 2250], ["RTW", "RTW", "NEF"])
rw("rw5", 5, "Rettungswache 5 – Westend", [-3050, -250], ["RTW", "RTW", "KTW"])
rw("rw6", 6, "Rettungswache 6 – Nordstadt", [-250, -4900], ["RTW", "RTW", "NEF"])
rw("rw7", 7, "Rettungswache 7 – Nordost", [4000, -4050], ["RTW", "RTW", "KTW"])
rw("rw8", 8, "Rettungswache 8 – Universitätsklinikum", [2900, -3150], ["RTW", "NEF", "ITW", "NAW"], 5)
rw("rw9", 9, "Rettungswache 9 – Ostpark", [3000, 500], ["RTW", "RTW"])
rw("rw10", 10, "Rettungswache 10 – Industriehafen", [5900, 3100], ["RTW", "RTW"])
rw("rw11", 11, "Rettungswache 11 – Seeburg", [4300, 5600], ["RTW", "RTW", "NEF"])
rw("rw12", 12, "Rettungswache 12 – Südstadt", [900, 5450], ["RTW", "RTW", "KTW"])
rw("rw13", 13, "Rettungswache 13 – Südwest", [-4300, 4850], ["RTW", "RTW", "NEF"])
rw("rw14", 14, "Rettungswache 14 – Waldheim", [-7300, 3550], ["RTW", "RTW"])
rw("rw15", 15, "Rettungswache 15 – Güterstadt", [-5850, -850], ["RTW", "RTW", "NEF", "SRTW"], 5)
rw("rw16", 16, "Rettungswache 16 – Stadionviertel", [-3900, -4950], ["RTW", "RTW", "KTW"])
rw("rw17", 17, "Rettungswache 17 – Messe", [6800, -3600], ["RTW", "RTW", "NEF"])
rw("rw18", 18, "Rettungswache 18 – Flughafen", [5000, -6850], ["RTW", "RTW", "NEF"])
rw("rw19", 19, "Krankentransportzentrale Süd", [-1050, 3250], ["KTW", "KTW", "KTW", "KTW", "KTW"], 7)
rw("rw20", 20, "Führungs- und SEG-Standort Rettungsdienst", [2150, 3650], ["ELRD", "ELRD", "GWSAN", "SEGKTW", "SEGKTW", "SEGKTW", "GRTW"], 9)
rw("rw21", 21, "Rettungswache 21 – Südstadt West", [-1900, 6100], ["RTW", "RTW"])
rw("rw22", 22, "Rettungswache 22 – Nordstadt West", [-2600, -4100], ["RTW", "RTW"])
# Luftrettung (Christoph 1 nur bei Tageslicht, Christoph Bavaria rund um die Uhr inkl. Intensivtransport)
st("rth1", 51, "Luftrettungsstation Klinikum Süd", "rd", "rth", [-250, 6200], ["RTH"], 1, callsign="Christoph 1", flight="day", operator="Luftrettung Bavaria")
st("rth2", 52, "Luftrettungsstation Universitätsklinikum", "rd", "rth", [3000, -3400], ["RTH"], 1, callsign="Christoph Bavaria", flight="24h", operator="Luftrettung Bavaria")
# Polizei
st("pp", 1, "Polizeipräsidium Bavaria", "pol", "pol", [-420, -950], ["POLELW", "FUSTW", "FUSTW", "KRIPO", "KRIPO", "SEK", "DHF", "DHF"], 10)
PI = ["FUSTW", "FUSTW", "FUSTW", "FUSTW"]
st("pi11", 11, "Polizeiinspektion 11 – Altstadt", "pol", "pol", [330, 230], PI + ["FUSTW"], 7)
st("pi12", 12, "Polizeiinspektion 12 – Nordstadt", "pol", "pol", [-520, -4300], PI, 6)
st("pi13", 13, "Polizeiinspektion 13 – Westend", "pol", "pol", [-3250, 950], PI, 6)
st("pi14", 14, "Polizeiinspektion 14 – Südstadt", "pol", "pol", [320, 4250], PI, 6)
st("pi15", 15, "Polizeiinspektion 15 – Ost", "pol", "pol", [3850, 900], PI, 6)
st("pi16", 16, "Polizeiinspektion 16 – Flughafen", "pol", "pol", [5300, -6600], ["FUSTW", "FUSTW", "FUSTW"], 5)
st("pi17", 17, "Polizeiinspektion 17 – Südwest", "pol", "pol", [-4850, 4500], PI, 6)
st("pi18", 18, "Polizeiinspektion 18 – Nordost", "pol", "pol", [4650, -3800], PI, 6)
st("pi19", 19, "Polizeiinspektion 19 – Seeburg/Hafen", "pol", "pol", [5200, 4200], ["FUSTW", "FUSTW", "FUSTW"], 5)
st("vpi", 20, "Verkehrspolizeiinspektion Bavaria", "pol", "pol", [-2100, -6800], ["VERKEHR", "VERKEHR", "VERKEHR", "VERKEHR", "FUSTW", "KRAD", "KRAD"], 9)
st("ehu", 30, "Einsatzhundertschaft Bavaria", "pol", "pol", [-6200, -3600], ["GRUKW", "GRUKW", "GRUKW", "GRUKW", "POLELW"], 8)
# Weitere Organisationen
st("thw1", 1, "THW Ortsverband Bavaria-Mitte", "thw", "thw", [2550, 3350], ["THWMTW", "THWGKW", "THWLKW", "THWPUMPE"], 6)
st("thw2", 2, "THW Ortsverband Bavaria-West", "thw", "thw", [-6500, 450], ["THWMTW", "THWGKW", "THWGKW", "THWLKW"], 6)
st("wr1", 1, "Wasserrettungsstation Seeburger See", "wr", "wr", [5500, 5750], ["WRKFZ", "WRKFZ", "WRTAUCH"], 5)
st("wr2", 2, "Wasserrettung Flusswache Bavar", "wr", "wr", [1250, 1500], ["WRKFZ", "WRTAUCH"], 4)
st("kats1", 1, "Katastrophenschutzzentrum Bavaria", "kats", "kats", [2000, 3900], ["KATSKDOW", "BTKOMBI", "BTKOMBI", "GWBT", "KATSSAN", "KATSSAN", "KATSLKW", "KIT", "KIT"], 11)

H = [
 {"id": "kh_mitte", "name": "Klinikum Bavaria Mitte", "pos": [-620, 1150], "level": 3, "beds": 1200},
 {"id": "kh_uni", "name": "Universitätsklinikum Bavaria", "pos": [2950, -3350], "level": 3, "beds": 1600},
 {"id": "kh_nord", "name": "Klinikum Nord", "pos": [-1500, -6000], "level": 2, "beds": 650},
 {"id": "kh_sued", "name": "Klinikum Süd", "pos": [-300, 6250], "level": 2, "beds": 700},
 {"id": "kh_ost", "name": "Klinikum Ost", "pos": [4350, 1350], "level": 2, "beds": 520},
 {"id": "kh_west", "name": "Kinder- und Frauenklinik Westend", "pos": [-3550, -550], "level": 1, "beds": 310},
 {"id": "kh_unfall", "name": "Unfallklinik Güterstadt", "pos": [-4700, -2450], "level": 2, "beds": 420},
 {"id": "kh_seeburg", "name": "Kreisklinik Seeburg", "pos": [3650, 6600], "level": 1, "beds": 260},
 {"id": "kh_waldheim", "name": "Waldklinik Waldheim", "pos": [-6700, 4000], "level": 1, "beds": 220},
]
out = {"_comment": "Fiktive Standorte. kind: bf=Berufsfeuerwehr, ff=Freiwillige Feuerwehr, rw=Rettungswache, pol=Polizei. pos in Metern (x Ost, y Süd).",
       "stations": S, "hospitals": H}
p = os.path.join(os.path.dirname(__file__), "..", "data", "stations.json")
with open(p, "w", encoding="utf-8") as f:
    f.write("{\n \"_comment\": %s,\n \"stations\": [\n" % json.dumps(out["_comment"], ensure_ascii=False))
    f.write(",\n".join("  " + json.dumps(s, ensure_ascii=False) for s in S))
    f.write("\n ],\n \"hospitals\": [\n")
    f.write(",\n".join("  " + json.dumps(h, ensure_ascii=False) for h in H))
    f.write("\n ]\n}\n")
print(len(S), "Wachen,", sum(len(s["vehicles"]) for s in S), "Fahrzeuge")
