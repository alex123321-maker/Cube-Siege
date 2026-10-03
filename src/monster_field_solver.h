#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot
{

// Pure batch computation. No nodes, world ownership, target selection, or physics.
class MonsterFieldSolver : public RefCounted
{
	GDCLASS(MonsterFieldSolver, RefCounted);

protected:
	static void _bind_methods();

public:
	// Inputs include a one-cell border. Output triples: distance, direction X/Z.
	PackedFloat32Array build(const PackedInt32Array& heights,
							 const PackedByteArray& blocked,
							 const PackedByteArray& loaded,
							 int width,
							 int clearance_class,
							 int max_step_height) const;
};

} // namespace godot
