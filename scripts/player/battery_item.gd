class_name BatteryItem
extends RefCounted
## Данные одной батарейки в инвентаре.

var charge: float = 0.5


func _init(initial_charge: float = 0.5) -> void:
	charge = clampf(initial_charge, 0.0, 1.0)


func label() -> String:
	return "%d%%" % int(charge * 100.0)


static func weighted_charge(rng: RandomNumberGenerator) -> float:
	var roll := rng.randf()
	if roll < 0.35:
		return rng.randf_range(0.15, 0.35)
	if roll < 0.75:
		return rng.randf_range(0.35, 0.70)
	return rng.randf_range(0.70, 1.0)
