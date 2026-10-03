extends RefCounted
class_name BossAttackMark

## A single fixed marker with an independent countdown; no coroutine survives its owner.
var centre: Vector3 = Vector3.ZERO
var born: float = 0.0
var detonate: float = 0.0
var exploded: bool = false
var visual: BossAttackVFX
