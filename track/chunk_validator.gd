class_name ChunkValidator
extends RefCounted
## Validates chunk metadata against its authored geometry. Used by the editor plugin,
## the catalogue at load time and the test suite.

const HAZARD_TYPES := ["scatter", "slalom", "picket", "slider", "riser"]


static func validate(info: ChunkInfo, file_id: String = "") -> PackedStringArray:
	var errors := PackedStringArray()
	if info == null:
		errors.append("%s: missing ChunkInfo" % file_id)
		return errors
	var name := String(info.id)
	if name.is_empty():
		errors.append("%s: empty id" % file_id)
	if not file_id.is_empty() and file_id != name:
		errors.append("%s: id '%s' does not match the file name" % [file_id, name])
	if not TrackGeometry.is_profile(info.entry_profile):
		errors.append("%s: unknown entry_profile '%s'" % [name, info.entry_profile])
	if not TrackGeometry.is_profile(info.exit_profile):
		errors.append("%s: unknown exit_profile '%s'" % [name, info.exit_profile])
	if info.sections.is_empty():
		errors.append("%s: no sections" % name)
		return errors
	if info.difficulty < 1 or info.difficulty > 10:
		errors.append("%s: difficulty must be 1-10" % name)
	if info.weight <= 0.0:
		errors.append("%s: weight must be > 0" % name)
	if info.min_speed > info.max_speed:
		errors.append("%s: min_speed > max_speed" % name)

	for si in info.sections.size():
		var sec = info.sections[si]
		if not (sec is Dictionary):
			errors.append("%s: section %d is not a Dictionary" % [name, si])
			continue
		if float(sec.get("len", 0.0)) <= 0.0:
			errors.append("%s: section %d has no positive len" % [name, si])
		if sec.has("profile") and not TrackGeometry.is_profile(StringName(sec["profile"])):
			errors.append("%s: section %d unknown profile '%s'" % [name, si, sec["profile"]])
	if not errors.is_empty():
		return errors

	var total := TrackGeometry.sections_length(info)
	if absf(total - info.length) > 0.001:
		errors.append("%s: length %.3f does not match sections (%.3f)" % [name, info.length, total])
	if absf(fposmod(total, TrackGeometry.GRID_CELL)) > 0.001:
		errors.append("%s: length %.3f is not a multiple of %.1f m" % [name, total, TrackGeometry.GRID_CELL])

	var data := TrackGeometry.build_samples(info)
	# Join profile: exit cross-section, pitch and bank must match the standard join.
	if StringName(data["end_profile"]) != info.exit_profile:
		errors.append("%s: geometry ends in '%s' but exit_profile is '%s'"
			% [name, data["end_profile"], info.exit_profile])
	if absf(float(data["end_pitch_extra"])) > 0.0001:
		errors.append("%s: exit pitch is not the base pitch" % name)
	if absf(float(data["end_bank"])) > 0.0001:
		errors.append("%s: exit bank is not zero" % name)
	var first: Dictionary = info.sections[0]
	var last: Dictionary = info.sections[info.sections.size() - 1]
	if not bool(first.get("floor", true)) or first.has("hole") or bool(first.get("launch", false)):
		errors.append("%s: entry section must have a plain floor" % name)
	if not bool(last.get("floor", true)) or last.has("hole") or bool(last.get("launch", false)):
		errors.append("%s: exit section must have a plain floor" % name)
	if float(first.get("drop", 0.0)) != 0.0 or float(last.get("drop", 0.0)) != 0.0:
		errors.append("%s: entry/exit sections must not drop" % name)
	if info.adapter and info.entry_profile == info.exit_profile:
		errors.append("%s: adapter must change profile" % name)
	if not info.adapter and info.entry_profile != info.exit_profile:
		errors.append("%s: only adapters may change profile" % name)

	for slot in info.hazard_slots:
		if not (slot is Dictionary) or not HAZARD_TYPES.has(String(slot.get("type", ""))):
			errors.append("%s: bad hazard slot %s" % [name, slot])
			continue
		var positions: Array = []
		if slot.has("at"):
			positions = slot["at"]
		else:
			positions = [slot.get("from", -1.0), slot.get("to", -1.0)]
		for a in positions:
			if float(a) < 2.0 or float(a) > total - 2.0:
				errors.append("%s: hazard position %s outside the chunk" % [name, a])
	if info.is_breather() == false and info.has_tag(&"breather"):
		errors.append("%s: breather chunks must not have hazards" % name)
	return errors
