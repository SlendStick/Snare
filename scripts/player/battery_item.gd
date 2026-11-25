extends RefCounted
class_name BatteryItem

var charge: float = 100.0 # 0..100

func _init(c: float = 100.0) -> void:
	charge = clampf(c, 0.0, 100.0)

static func random_charge(rng: RandomNumberGenerator) -> float:
	# Weighted: more mid/low, some fresh
	var roll := rng.randf()
	if roll < 0.2:
		return rng.randf_range(15.0, 35.0)
	elif roll < 0.5:
		return rng.randf_range(35.0, 65.0)
	elif roll < 0.8:
		return rng.randf_range(65.0, 90.0)
	else:
		return rng.randf_range(90.0, 100.0)
