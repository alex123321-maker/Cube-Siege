extends RefCounted
class_name ContinuousDamageCadence

## Exposure, not physics-frame count, determines continuous damage doses.
## First contact is immediate; further doses occur per .1s of actual exposure.
## Exit/end flushes the remainder. No future damage is borrowed for a short touch.
const INTERVAL: float = 0.1
var _pending: float = 0.0
var _in_contact: bool = false

func sample(exposure_seconds: float) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	if exposure_seconds <= 0.0000001:
		var residual: float = end_contact()
		if residual > 0.0000001:
			result.append(residual)
		return result
	var exposure: float = exposure_seconds
	if not _in_contact:
		_in_contact = true
		var first: float = minf(INTERVAL, exposure)
		result.append(first)
		exposure -= first
	_pending += exposure
	while _pending >= INTERVAL - 0.0000001:
		result.append(minf(INTERVAL, _pending))
		_pending = maxf(0.0, _pending - INTERVAL)
	return result

func end_contact() -> float:
	var residual: float = _pending
	cancel()
	return residual

func cancel() -> void:
	_pending = 0.0
	_in_contact = false
