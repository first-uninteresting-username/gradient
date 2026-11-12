class_name Autopilot
extends RefCounted
## Simple centre-seeking steering used by the acceptance tests and the attract demo.


static func centre_seeking(ball: Ball, frame: TrackFrame) -> float:
	if frame == null:
		return 0.0
	var rel := ball.global_position - frame.transform.origin
	var offset := rel.dot(frame.transform.basis.x)
	var lat_v := ball.linear_velocity.dot(frame.transform.basis.x)
	return clampf(-(offset * 1.2 + lat_v * 0.3), -1.0, 1.0)


## Demo bot for the attract mode and --autoplay: picks the lateral position that stays
## clear of the hazards (and floor holes) it will reach soon, predicting where moving
## hazards will be on arrival. Good, not perfect: it still crashes now and then.
static func dodger(ball: Ball, frame: TrackFrame) -> float:
	if frame == null or ball.generator == null:
		return 0.0
	var gen := ball.generator
	var origin := frame.transform.origin
	var right := frame.transform.basis.x
	var up := frame.transform.basis.y
	var my_x := (ball.global_position - origin).dot(right)
	var lat_v := ball.linear_velocity.dot(right)
	var speed := maxf(frame.target_speed, 1.0)
	var look := maxf(30.0, speed * 1.1)
	var chunk := gen.get_chunk(frame.chunk_index)
	if chunk == null:
		return 0.0
	var half := TrackGeometry.flat_width(chunk.data["cross"][TrackGeometry.sample_index(chunk.data, frame.offset)]) * 0.5
	half = maxf(half - 0.55, 0.3)
	# [x_min, x_max, distance_ahead]
	var blocked: Array = []
	for idx in [frame.chunk_index, frame.chunk_index + 1, frame.chunk_index + 2]:
		var c := gen.get_chunk(idx)
		if c == null:
			continue
		for body in c.hazard_bodies:
			var hz := body as Node3D
			var along: float = body.get("along_distance")
			var ahead := along - frame.progress
			if ahead < -1.5 or ahead > look:
				continue
			var size: Vector3 = body.get("size")
			var local := hz.transform
			if body is MovingHazard:
				local = (body as MovingHazard).predicted_pose(maxf(ahead, 0.0) / speed, frame.progress, speed)
				var rise := (local.origin - (body as MovingHazard).base_transform.origin).dot(local.basis.y)
				if rise + size.y < -0.05:
					continue  # A riser that will be below the floor on arrival.
			var hx := (c.global_transform * local.origin - origin).dot(right)
			blocked.append([hx - size.x * 0.5 - 0.75, hx + size.x * 0.5 + 0.75, ahead])
		# Holes in the floor (tube with a hole).
		var holes: Array[Vector2] = c.data["hole"]
		var dist: PackedFloat32Array = c.data["dist"]
		for i in holes.size():
			if holes[i] == Vector2.ZERO:
				continue
			var ahead := c.start_distance + dist[i] - frame.progress
			if ahead > -1.0 and ahead < look:
				blocked.append([holes[i].x - 0.7, holes[i].y + 0.7, ahead])
	var best_x := 0.0
	var best_score := INF
	var x := -half
	while x <= half + 0.001:
		var score := absf(x - my_x) * 0.6 + absf(x) * 0.15
		for b in blocked:
			if x > float(b[0]) and x < float(b[1]):
				score += 1000.0 / (maxf(float(b[2]), 0.0) + 4.0)
		if score < best_score:
			best_score = score
			best_x = x
		x += 0.25
	return clampf((best_x - my_x) * 1.6 - lat_v * 0.22, -1.0, 1.0)
