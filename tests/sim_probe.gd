extends Node
## Automatischer Durchlauf: ein "Bot" nimmt Notrufe an, legt Einsätze mit dem
## richtigen Stichwort an und alarmiert den Vorschlag. Prüft die gesamte Kette.
const IL = preload("res://src/incidents/incident_logic.gd")
const Advisor = preload("res://src/dispatch/advisor.gd")
func _ready():
	Sim.new_game({"mode": "frei", "difficulty": "schwer", "seed": 4711})
	Sim.running = false
	var me = {"name": "Bot", "role": "leitung"}
	var t0 = Time.get_ticks_msec()
	var steps = 0
	var maxc = 0
	var hours = 0.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hours="): hours = float(a.substr(8))
	var tb = 0
	while State.clock < hours * 3600.0:
		var q0 = Time.get_ticks_usec()
		Sim.step(0.5); steps += 1
		tb += Time.get_ticks_usec() - q0
		if steps % 4 == 0:
			Sim.CallGen.real_tick(2.0)
		for cid in State.calls.keys():
			var c = State.calls[cid]
			if c.state == "ringing":
				Sim.act({"a": "call_take", "id": cid}, me)
			elif c.state == "active" and c.talk > 8.0:
				if c.loc_level < 2:
					Sim.act({"a": "call_ask", "id": cid, "q": "q_wo"}, me)
					if c.talk < 20.0: continue
				if c.nuisance != "":
					Sim.act({"a": "call_end", "id": cid}, me); continue
				var tr = State.truths.get(c.truth, {})
				if tr.is_empty() or tr.incident != "":
					Sim.act({"a": "call_end", "id": cid}, me); continue
				var kw = IL.correct_keyword(tr)
				var r = Sim.act({"a": "call_create", "id": cid, "form": {"keyword": kw, "x": c.loc.x, "y": c.loc.y, "address": c.loc.text, "radius": c.loc.r}}, me)
				assert(r.ok)
				Sim.act({"a": "call_end", "id": cid}, me)
		for iid in State.incidents.keys():
			var inc = State.incidents[iid]
			if inc.done:
				if inc.close_t > 60: Sim.act({"a": "inc_close", "id": iid}, me)
				continue
			if steps % 60 == 0 or (inc.t_alarm < 0 and steps % 10 == 0):
				var s = Advisor.suggest(inc)
				if s.suggested.size() > 0:
					Sim.act({"a": "inc_alarm", "id": iid, "vehicles": s.suggested}, me)
		for vid in State.vehicles:
			if State.vehicles[vid].talk != "":
				Sim.act({"a": "veh_talk", "id": vid}, me)
		maxc = max(maxc, State.incidents.size())
	print("step time total ms ", tb / 1000)
	print("sim in ", Time.get_ticks_msec() - t0, " ms, steps ", steps)
	print("stats ", State.meta.stats)
	print("offene Einsätze ", State.incidents.size(), " max ", maxc, " archiv ", State.archive.size(), " truths ", State.truths.size(), " calls ", State.calls.size())
	var by = {}
	for v in State.vehicles.values(): by[v.state] = by.get(v.state, 0) + 1
	print("Fahrzeugzustände ", by)
	var sc = {}
	for a in State.archive: sc[a.keyword] = sc.get(a.keyword, []) + [a.score]
	print(sc)
	for iid in State.incidents:
		var inc = State.incidents[iid]
		print(" offen: ", inc.nr, " ", inc.keyword, " ", inc.status, " need ", inc.need, " have ", inc.have, " pat ", inc.pat, " prog ", snapped(inc.progress, 0.01), " age ", int(State.clock - inc.t_created))
	for e in State.radio.slice(-25): print(State.time_str(e.t), " [", e.kind, "] ", e.src, ": ", e.text, " (", e.status, ")")
	get_tree().quit()
