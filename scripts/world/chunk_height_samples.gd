extends RefCounted

## Exact integer-coordinate samples for one terrain chunk and its cardinal halo.
## Owned by a single load operation; never retained by the streamed world.
const CHUNK_SIZE: int = 16
const WIDTH: int = CHUNK_SIZE + 2
const SAMPLE_COUNT: int = WIDTH * WIDTH

var origin_x: int
var origin_z: int
var continuous_heights: PackedFloat64Array = PackedFloat64Array()
var voxel_heights: PackedInt32Array = PackedInt32Array()

func _init(cx: int, cz: int, world_seed: int) -> void:
	origin_x = cx * CHUNK_SIZE - 1
	origin_z = cz * CHUNK_SIZE - 1
	continuous_heights.resize(SAMPLE_COUNT)
	voxel_heights.resize(SAMPLE_COUNT)
	for z in range(WIDTH):
		for x in range(WIDTH):
			var index: int = z * WIDTH + x
			var height: float = BiomeSystem.sample_height(float(origin_x + x), float(origin_z + z), world_seed)
			continuous_heights[index] = height
			# Same conversion as BiomeSystem.get_voxel_height, including negative heights.
			voxel_heights[index] = int(roundf(height))

func get_voxel_height(wx: int, wz: int) -> int:
	return voxel_heights[(wz - origin_z) * WIDTH + wx - origin_x]

func get_continuous_height(wx: int, wz: int) -> float:
	return continuous_heights[(wz - origin_z) * WIDTH + wx - origin_x]
