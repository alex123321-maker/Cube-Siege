extends Resource
class_name CharacterGait

## Authored rigid-leg key poses, in body-facing space. All clips share one phase.
@export var rotations: PackedVector3Array = PackedVector3Array()
@export var lifts: PackedFloat32Array = PackedFloat32Array()

func sample_rotation(phase: float) -> Vector3:
	if rotations.is_empty():
		return Vector3.ZERO
	var cursor: float = fposmod(phase, 1.0) * rotations.size()
	var index: int = int(cursor)
	return rotations[index].lerp(rotations[(index + 1) % rotations.size()], cursor - index)

func sample_lift(phase: float) -> float:
	if lifts.is_empty():
		return 0.0
	var cursor: float = fposmod(phase, 1.0) * lifts.size()
	var index: int = int(cursor)
	return lerpf(lifts[index], lifts[(index + 1) % lifts.size()], cursor - index)
