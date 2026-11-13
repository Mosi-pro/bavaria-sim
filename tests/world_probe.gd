extends Node
func _ready():
	World.ensure_built()
	var cnt = [0,0,0,0,0,0,0,0,0]
	var km = [0.0,0,0,0,0,0,0,0,0]
	for e in World.edge_a.size():
		cnt[World.edge_cls[e]] += 1
		km[World.edge_cls[e]] += World.edge_len[e]/1000.0
	for i in 9: print(World.CLASS_NAMES[i], " ", cnt[i], " ", snapped(km[i],0.1), " km")
	var sig=0; var rb=0
	for f in World.node_flags:
		if f==1: sig+=1
		if f==2: rb+=1
	print("Ampeln ", sig, " Kreisverkehre ", rb, " Namen ", World.names.size(), " AS ", World.junctions.size())
	var t0=Time.get_ticks_msec()
	var a=World.nearest_node(Vector2(-7000,3000)); var b=World.nearest_node(Vector2(6000,-7200))
	var r=World.find_path(a,b,true)
	print("Route ok=", r.ok, " nodes=", r.nodes.size(), " t=", r.time, " d=", r.dist, " ms=", Time.get_ticks_msec()-t0)
	t0=Time.get_ticks_msec(); var tt=World.times_from(a); print("dijkstra ms=", Time.get_ticks_msec()-t0)
	var unreachable=0
	for x in tt:
		if x==INF: unreachable+=1
	print("unreachable ", unreachable)
	print(World.address_at(Vector2(100,300)).text, " | ", World.address_at(Vector2(-4000,-5000)).text)
	get_tree().quit()
