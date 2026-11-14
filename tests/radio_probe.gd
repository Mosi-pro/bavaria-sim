extends Node
## Prüft, ob jede Funkmeldung eines Fahrzeugs zu dem Einsatz gehört, in dem es sich befindet.
const IL = preload("res://src/incidents/incident_logic.gd")
const Advisor = preload("res://src/dispatch/advisor.gd")
var bad: Array = []
var by_cs := {}
var n := 0
func _ready():
	Sim.new_game({"mode": "frei", "difficulty": "schwer", "seed": 77})
	Sim.running = false
	for id in State.vehicles: by_cs[State.vehicles[id].callsign] = id
	State.radio_added.connect(_on_radio)
	var me = {"name": "Bot", "role": "leitung"}
	var steps := 0
	while State.clock < 3 * 3600.0:
		Sim.step(0.5); steps += 1
		if steps % 4 == 0: Sim.CallGen.real_tick(2.0)
		for cid in State.calls.keys():
			var c = State.calls[cid]
			if c.state == "ringing": Sim.act({"a": "call_take", "id": cid}, me)
			elif c.state == "active" and c.talk > 6.0:
				if c.nuisance != "" or c.truth == "" or State.truths.get(c.truth, {}).get("incident", "") != "":
					Sim.act({"a": "call_end", "id": cid}, me); continue
				var tr = State.truths[c.truth]
				Sim.CallGen._set_loc_level(c, tr, 2)
				var r = Sim.act({"a": "call_create", "id": cid, "form": {"keyword": IL.correct_keyword(tr), "x": c.loc.x, "y": c.loc.y}}, me)
				Sim.act({"a": "call_end", "id": cid}, me)
		for iid in State.incidents.keys():
			var inc = State.incidents[iid]
			if inc.done:
				if inc.close_t > 30: Sim.act({"a": "inc_close", "id": iid}, me)
				continue
			if steps % 40 == 0 or inc.t_alarm < 0:
				var s = Advisor.suggest(inc)
				if s.suggested.size() > 0: Sim.act({"a": "inc_alarm", "id": iid, "vehicles": s.suggested}, me)
		if steps % 20 == 0:
			for vid in State.vehicles:
				if State.vehicles[vid].talk != "": Sim.act({"a": "veh_talk", "id": vid}, me)
	print("Funkmeldungen geprüft: ", n, "   unstimmig: ", bad.size())
	for b in bad.slice(0, 25): print("  ", b)
	get_tree().quit()
func _on_radio(e):
	if e.kind != "funk" and e.kind != "status": return
	if not by_cs.has(e.src): return
	n += 1
	var v = State.vehicles[by_cs[e.src]]
	var cur: String = v.incident if v.incident != "" else v.last_incident
	var text: String = e.text
	if e.inc != "" and cur != e.inc:
		bad.append("%s  %s  meldet zu %s, ist aber bei %s (Zustand %s): %s" % [State.time_str(e.t), e.src, e.inc, cur, v.state, text.substr(0, 90)])
	# Lagemeldung/Ortsangaben müssen zum Einsatz passen, in dem das Fahrzeug steht
	if text.begins_with("Lagemeldung") and State.incidents.has(e.inc):
		var inc = State.incidents[e.inc]
		var tr = State.truths.get(inc.truth, {})
		if not tr.is_empty() and text.find(tr.object) < 0:
			bad.append("%s Lagemeldung passt nicht zur Lage: %s" % [e.src, text.substr(0, 90)])
		if v.state != "onscene":
			bad.append("%s gibt Lagemeldung, ist aber nicht vor Ort (%s)" % [e.src, v.state])
