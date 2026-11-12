class_name TrackGeometry
extends RefCounted
## Pure geometry for chunks: centreline sampling, cross-section profiles, mesh and
## collision construction. Has no scene-tree dependency so tests can use it directly.

const BASE_PITCH_DEG := -18.0
const PROFILE_POINTS := 33
const SAMPLE_STEP := 1.0
## Grid cell size along the track. Chunk lengths must be a multiple of it so the grid
## lines continue seamlessly across joins.
const GRID_CELL := 2.0
const PROFILES: Array[StringName] = [&"flat_wide", &"flat_narrow", &"halfpipe", &"tube"]

const _CACHES := [&"gradient_profiles", &"gradient_samples", &"gradient_meshes"]


## Caches live in Engine metadata rather than static vars so they can be released
## cleanly at shutdown and work without a scene tree.
static func _cache(cache_name: StringName) -> Dictionary:
	if not Engine.has_meta(cache_name):
		Engine.set_meta(cache_name, {})
	return Engine.get_meta(cache_name)


static func clear_caches() -> void:
	for c in _CACHES:
		if Engine.has_meta(c):
			Engine.remove_meta(c)


static func is_profile(profile: StringName) -> bool:
	return PROFILES.has(profile)


## Cross-section points ordered from the left top edge, across the floor, to the right
## top edge. All profiles have the same point count so they can morph into each other.
static func profile_points(profile: StringName) -> PackedVector2Array:
	var cache := _cache(&"gradient_profiles")
	if cache.has(profile):
		return cache[profile]
	var pts := PackedVector2Array()
	var n := PROFILE_POINTS
	match profile:
		&"flat_wide", &"flat_narrow":
			var w := 8.0 if profile == &"flat_wide" else 4.0
			for k in n:
				pts.append(Vector2(lerpf(-w * 0.5, w * 0.5, float(k) / (n - 1)), 0.0))
		&"halfpipe":
			var r := 3.0
			var floor_w := 4.0
			var arc := PI * 0.5 * r
			var total := arc * 2.0 + floor_w
			for k in n:
				var s := total * float(k) / (n - 1)
				if s <= arc:
					var a := PI + s / r
					pts.append(Vector2(-floor_w * 0.5, r) + Vector2(cos(a), sin(a)) * r)
				elif s <= arc + floor_w:
					pts.append(Vector2(-floor_w * 0.5 + (s - arc), 0.0))
				else:
					var a := PI * 1.5 + (s - arc - floor_w) / r
					pts.append(Vector2(floor_w * 0.5, r) + Vector2(cos(a), sin(a)) * r)
		&"tube":
			var r := 3.5
			for k in n:
				var a := PI * 0.5 + TAU * float(k) / (n - 1)
				pts.append(Vector2(0.0, r) + Vector2(cos(a), sin(a)) * r)
			pts[n - 1] = pts[0]
		_:
			push_error("Unknown profile %s" % profile)
			return profile_points(&"flat_wide")
	# Snap to a fixed precision so both chunks at a join compute identical values.
	for k in n:
		pts[k] = Vector2(snappedf(pts[k].x, 1e-5), snappedf(pts[k].y, 1e-5))
	cache[profile] = pts
	return pts


static func morph(a: StringName, b: StringName, t: float) -> PackedVector2Array:
	if a == b or t <= 0.0:
		return profile_points(a)
	if t >= 1.0:
		return profile_points(b)
	var pa := profile_points(a)
	var pb := profile_points(b)
	var out := PackedVector2Array()
	out.resize(pa.size())
	for k in pa.size():
		out[k] = pa[k].lerp(pb[k], t)
	return out


## Width of the rideable floor (points lower than 0.6 m) of a cross-section.
static func floor_width(cs: PackedVector2Array) -> float:
	var lo := INF
	var hi := -INF
	for p in cs:
		if p.y < 0.6:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
	return maxf(hi - lo, 1.0)


## Width of the flat part of the floor (where obstacles can stand).
static func flat_width(cs: PackedVector2Array) -> float:
	var lo := INF
	var hi := -INF
	for p in cs:
		if p.y < 0.05:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
	return maxf(hi - lo, 2.0)


static func smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func smooth_deriv(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 6.0 * t * (1.0 - t)


static func sample_basis(heading: float, pitch_deg: float, bank_deg: float) -> Basis:
	return (Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
		* Basis(Vector3.BACK, deg_to_rad(bank_deg)))


## Total length of the authored sections.
static func sections_length(info: ChunkInfo) -> float:
	var total := 0.0
	for sec in info.sections:
		total += float((sec as Dictionary).get("len", 0.0))
	return total


## Samples the centreline every ~1 m. Returned arrays are indexed by sample; per-interval
## data (floor, hole, launch, section) is stored at the index of the interval's END sample.
static func get_samples(info: ChunkInfo) -> Dictionary:
	var cache := _cache(&"gradient_samples")
	if cache.has(info.id):
		return cache[info.id]
	var data := build_samples(info)
	cache[info.id] = data
	return data


static func build_samples(info: ChunkInfo) -> Dictionary:
	var pos := PackedVector3Array()
	var bases: Array[Basis] = []
	var dist := PackedFloat32Array()
	var curv := PackedFloat32Array()
	var cross: Array[PackedVector2Array] = []
	var floor_on := PackedByteArray()
	var launch := PackedByteArray()
	var section := PackedInt32Array()
	var holes: Array[Vector2] = []

	var heading := 0.0
	var pitch_extra := 0.0
	var bank := 0.0
	var profile: StringName = info.entry_profile
	var p := Vector3.ZERO
	var d := 0.0

	pos.append(p)
	bases.append(sample_basis(heading, BASE_PITCH_DEG + pitch_extra, bank))
	dist.append(0.0)
	curv.append(0.0)
	cross.append(profile_points(profile))
	floor_on.append(1)
	launch.append(0)
	section.append(0)
	holes.append(Vector2.ZERO)

	for si in info.sections.size():
		var sec: Dictionary = info.sections[si]
		var length := float(sec.get("len", 0.0))
		if length <= 0.0:
			continue
		var steps := maxi(1, ceili(length / SAMPLE_STEP - 0.001))
		var ds := length / steps
		var yaw := deg_to_rad(float(sec.get("yaw", 0.0)))
		var pitch_to := float(sec.get("pitch", pitch_extra))
		var bank_to := float(sec.get("bank", bank))
		var prof_to := StringName(sec.get("profile", profile))
		var drop := float(sec.get("drop", 0.0))
		var has_floor := bool(sec.get("floor", true))
		var is_launch := bool(sec.get("launch", false))
		var hole := Vector2.ZERO
		if sec.has("hole"):
			var h: Array = sec["hole"]
			hole = Vector2(float(h[0]), float(h[1]))
		var h0 := heading
		var pe0 := pitch_extra
		var b0 := bank
		var prof0 := profile
		for k in range(1, steps + 1):
			var t1 := float(k) / steps
			var tm := (float(k) - 0.5) / steps
			var hm := h0 - yaw * smooth(tm)
			var pm := deg_to_rad(BASE_PITCH_DEG + lerpf(pe0, pitch_to, smooth(tm)))
			var dir := Basis(Vector3.UP, hm) * Vector3(0.0, sin(pm), -cos(pm))
			p += dir * ds
			p.y -= drop / steps
			d += ds
			heading = h0 - yaw * smooth(t1)
			pitch_extra = lerpf(pe0, pitch_to, smooth(t1))
			bank = lerpf(b0, bank_to, smooth(t1))
			pos.append(p)
			bases.append(sample_basis(heading, BASE_PITCH_DEG + pitch_extra, bank))
			dist.append(d)
			# Signed curvature in rad/m, positive = turning right.
			curv.append(yaw * smooth_deriv(t1) / length)
			cross.append(morph(prof0, prof_to, smooth(t1)))
			floor_on.append(1 if has_floor else 0)
			launch.append(1 if is_launch else 0)
			section.append(si)
			holes.append(hole)
		profile = prof_to

	return {
		"pos": pos,
		"basis": bases,
		"dist": dist,
		"curv": curv,
		"cross": cross,
		"floor": floor_on,
		"launch": launch,
		"section": section,
		"hole": holes,
		"length": d,
		"end_heading": heading,
		"end_pitch_extra": pitch_extra,
		"end_bank": bank,
		"end_profile": profile,
		"exit": Transform3D(Basis(Vector3.UP, heading), p),
	}


## Index of the last sample whose distance is <= offset (binary search).
static func sample_index(data: Dictionary, offset: float) -> int:
	var dist: PackedFloat32Array = data["dist"]
	var lo := 0
	var hi := dist.size() - 1
	if offset <= dist[0]:
		return 0
	if offset >= dist[hi]:
		return hi - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if dist[mid] <= offset:
			lo = mid
		else:
			hi = mid
	return lo


## Local-space frame (origin on the centreline floor, basis = right/up/back) at an offset.
## Offsets outside the chunk are extrapolated along the end tangents.
static func frame_at(data: Dictionary, offset: float) -> Transform3D:
	var pos: PackedVector3Array = data["pos"]
	var bases: Array[Basis] = data["basis"]
	var dist: PackedFloat32Array = data["dist"]
	var last := pos.size() - 1
	if offset <= 0.0:
		var b0 := bases[0]
		return Transform3D(b0, pos[0] - b0.z * offset)
	if offset >= dist[last]:
		var bl := bases[last]
		return Transform3D(bl, pos[last] - bl.z * (offset - dist[last]))
	var i := sample_index(data, offset)
	var seg := dist[i + 1] - dist[i]
	var t := (offset - dist[i]) / seg if seg > 0.0 else 0.0
	var q := bases[i].get_rotation_quaternion().slerp(bases[i + 1].get_rotation_quaternion(), t)
	return Transform3D(Basis(q), pos[i].lerp(pos[i + 1], t))


static func curvature_at(data: Dictionary, offset: float) -> float:
	var curv: PackedFloat32Array = data["curv"]
	var dist: PackedFloat32Array = data["dist"]
	if offset <= 0.0 or offset >= dist[dist.size() - 1]:
		return 0.0
	var i := sample_index(data, offset)
	var seg := dist[i + 1] - dist[i]
	var t := (offset - dist[i]) / seg if seg > 0.0 else 0.0
	return lerpf(curv[i], curv[i + 1], t)


## Projects a local point onto the centreline polyline. Searches around `hint` first.
## Returns Vector2(offset, sample_index).
static func locate(data: Dictionary, local: Vector3, hint: int) -> Vector2:
	var pos: PackedVector3Array = data["pos"]
	var dist: PackedFloat32Array = data["dist"]
	var n := pos.size()
	var lo := 0
	var hi := n - 2
	if hint >= 0:
		lo = clampi(hint - 6, 0, n - 2)
		hi = clampi(hint + 12, 0, n - 2)
	var best_d := INF
	var best_off := 0.0
	var best_i := lo
	for i in range(lo, hi + 1):
		var a := pos[i]
		var ab := pos[i + 1] - a
		var l2 := ab.length_squared()
		var t := clampf((local - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		var q := a + ab * t
		var dd := q.distance_squared_to(local)
		if dd < best_d:
			best_d = dd
			best_i = i
			best_off = lerpf(dist[i], dist[i + 1], t)
	# Extrapolate past either end so callers can tell they left the chunk.
	if best_i == 0:
		var b0: Basis = data["basis"][0]
		var before := (local - pos[0]).dot(-b0.z)
		if before < 0.0:
			best_off = before
	elif best_i == n - 2:
		var bl: Basis = data["basis"][n - 1]
		var after := (local - pos[n - 1]).dot(-bl.z)
		if after > 0.0:
			best_off = dist[n - 1] + after
	return Vector2(best_off, best_i)


## Lowest local Y of the cross-section around an offset (for the kill plane).
static func floor_min_y(data: Dictionary, offset: float) -> float:
	var t := frame_at(data, offset)
	var i := clampi(sample_index(data, offset), 0, (data["pos"] as PackedVector3Array).size() - 1)
	var cs: PackedVector2Array = data["cross"][i]
	var lo := INF
	for p in cs:
		lo = minf(lo, (t.origin + t.basis.x * p.x + t.basis.y * p.y).y)
	return lo


## Builds (and caches per chunk id) the render mesh and merged collision faces.
## Within a chunk every quad shares exact vertices with its neighbours (indexed mesh);
## across chunks the join cross-section is computed from the same snapped profile.
static func get_mesh(info: ChunkInfo) -> Dictionary:
	var cache := _cache(&"gradient_meshes")
	if cache.has(info.id):
		return cache[info.id]
	var data := get_samples(info)
	var pos: PackedVector3Array = data["pos"]
	var bases: Array[Basis] = data["basis"]
	var dist: PackedFloat32Array = data["dist"]
	var cross: Array[PackedVector2Array] = data["cross"]
	var floor_on: PackedByteArray = data["floor"]
	var holes: Array[Vector2] = data["hole"]
	var n := pos.size()
	var m := PROFILE_POINTS

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	verts.resize(n * m)
	normals.resize(n * m)
	uvs.resize(n * m)
	uv2s.resize(n * m)
	for i in n:
		var b := bases[i]
		var cs := cross[i]
		var u := 0.0
		for j in m:
			var idx := i * m + j
			verts[idx] = pos[i] + b.x * cs[j].x + b.y * cs[j].y
			if j > 0:
				u += cs[j].distance_to(cs[j - 1])
			var jp := mini(j + 1, m - 1)
			var jm := maxi(j - 1, 0)
			var lat := cs[jp] - cs[jm]
			var tangent := (b.x * lat.x + b.y * lat.y).normalized()
			normals[idx] = tangent.cross(-b.z).normalized()
			uvs[idx] = Vector2(u, dist[i])
			uv2s[idx] = Vector2(float(j) / (m - 1), 0.0)

	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	for i in range(1, n):
		if floor_on[i] == 0:
			continue
		var hole := holes[i]
		for j in m - 1:
			if hole != Vector2.ZERO:
				var ca := cross[i][j]
				var cb := cross[i][j + 1]
				var mid_x := (ca.x + cb.x) * 0.5
				if mid_x > hole.x and mid_x < hole.y and maxf(ca.y, cb.y) < 1.0:
					continue
			var a := (i - 1) * m + j
			var bb := (i - 1) * m + j + 1
			var c := i * m + j
			var dd := i * m + j + 1
			# Godot treats clockwise winding (seen from the front) as the front face.
			for tri in [[a, c, bb], [bb, c, dd]]:
				for v in tri:
					indices.append(v)
					faces.append(verts[v])

	var mesh := ArrayMesh.new()
	if indices.size() > 0:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var result := {"mesh": mesh, "shape": shape, "faces": faces, "verts": verts}
	cache[info.id] = result
	return result


## World-space vertices of the first or last cross-section (used by seam tests).
static func end_cross_section(info: ChunkInfo, at_exit: bool) -> PackedVector3Array:
	var data := get_samples(info)
	var pos: PackedVector3Array = data["pos"]
	var i := pos.size() - 1 if at_exit else 0
	var b: Basis = data["basis"][i]
	var cs: PackedVector2Array = data["cross"][i]
	var out := PackedVector3Array()
	for p in cs:
		out.append(pos[i] + b.x * p.x + b.y * p.y)
	return out
