#include "monster_field_solver.h"

#include <cmath>
#include <vector>

namespace godot
{

void
MonsterFieldSolver::_bind_methods()
{
	ClassDB::bind_method(
	  D_METHOD("build", "heights", "blocked", "loaded", "width", "clearance_class", "max_step_height"),
	  &MonsterFieldSolver::build);
}

PackedFloat32Array
MonsterFieldSolver::build(const PackedInt32Array& heights,
						  const PackedByteArray& blocked,
						  const PackedByteArray& loaded,
						  int width,
						  int clearance_class,
						  int max_step_height) const
{
	PackedFloat32Array result;
	if (width < 3 || width > 1025 || width % 2 == 0 || max_step_height < 0 || heights.size() != width * width ||
		blocked.size() != heights.size() || loaded.size() != heights.size() || clearance_class < 0 ||
		clearance_class > 2)
	{
		return result;
	}
	const int cells = width * width;
	result.resize(cells * 3);
	float* out = result.ptrw();
	const int32_t* h = heights.ptr();
	const uint8_t* b = blocked.ptr();
	const uint8_t* l = loaded.ptr();
	for (int i = 0; i < cells; ++i)
	{
		out[i * 3] = -1.0f;
		out[i * 3 + 1] = out[i * 3 + 2] = 0.0f;
	}
	const auto inside = [width](int x, int z) { return x > 0 && z > 0 && x < width - 1 && z < width - 1; };
	const auto walkable = [&](int x, int z, int reference_height)
	{
		if (!inside(x, z))
		{
			return false;
		}
		const int i = z * width + x;
		return !b[i] && l[i] && std::abs(h[i] - reference_height) <= max_step_height;
	};
	const auto step_passable = [&](int x, int z, int tx, int tz)
	{
		const int from = z * width + x;
		const int to = tz * width + tx;
		if (b[to] || !l[to] || std::abs(h[to] - h[from]) > max_step_height)
		{
			return false;
		}
		if (x != tx && z != tz)
		{
			const int s1 = z * width + tx;
			const int s2 = tz * width + x;
			if (b[s1] || b[s2] || !l[s1] || !l[s2] || std::abs(h[s1] - h[from]) > max_step_height ||
				std::abs(h[s2] - h[from]) > max_step_height)
			{
				return false;
			}
		}
		return true;
	};
	const auto clearance = [&](int x, int z, int tx, int tz)
	{
		const int base_height = h[z * width + x];
		if (clearance_class == 2)
		{
			for (int dx = -1; dx <= 1; ++dx)
			{
				for (int dz = -1; dz <= 1; ++dz)
				{
					if (dx == 0 && dz == 0)
					{
						continue;
					}
					const int i = (z + dz) * width + x + dx;
					if (b[i] || !l[i] || (inside(x + dx, z + dz) && std::abs(h[i] - base_height) > max_step_height))
					{
						return false;
					}
				}
			}
		}
		else if (clearance_class == 1)
		{
			const int target_height = h[tz * width + tx];
			if (x != tx && z == tz)
			{
				return (walkable(x, z + 1, base_height) && walkable(tx, tz + 1, target_height)) ||
					   (walkable(x, z - 1, base_height) && walkable(tx, tz - 1, target_height));
			}
			if (x == tx && z != tz)
			{
				return (walkable(x + 1, z, base_height) && walkable(tx + 1, tz, target_height)) ||
					   (walkable(x - 1, z, base_height) && walkable(tx - 1, tz, target_height));
			}
		}
		return true;
	};
	const int gx = width / 2;
	const int gz = gx;
	const int goal = gz * width + gx;
	const int dxs[] = { 1, -1, 0, 0, 1, -1, 1, -1 };
	const int dzs[] = { 0, 0, 1, -1, 1, 1, -1, -1 };
	std::vector<int> queue;
	queue.reserve(cells);
	if (!l[goal])
	{
		return result;
	}
	if (b[goal])
	{
		for (int d = 0; d < 8; ++d)
		{
			const int px = gx + dxs[d];
			const int pz = gz + dzs[d];
			if (!inside(px, pz))
			{
				continue;
			}
			const int p = pz * width + px;
			if (b[p] || !l[p] || std::abs(h[p] - h[goal]) > max_step_height)
			{
				continue;
			}
			if (dxs[d] != 0 && dzs[d] != 0)
			{
				const int s1 = gz * width + px;
				const int s2 = pz * width + gx;
				if (b[s1] || b[s2] || !l[s1] || !l[s2] || std::abs(h[s1] - h[p]) > max_step_height ||
					std::abs(h[s2] - h[p]) > max_step_height || std::abs(h[s1] - h[goal]) > max_step_height ||
					std::abs(h[s2] - h[goal]) > max_step_height)
				{
					continue;
				}
			}
			if (clearance_class > 0 && dxs[d] != 0 && dzs[d] != 0)
			{
				if (clearance_class == 2)
				{
					continue;
				}
			}
			else if (clearance_class > 0)
			{
				const int dx = dxs[d];
				const int dz = dzs[d];
				const int sx = -dz;
				const int sz = dx;
				const bool plus = walkable(px + sx, pz + sz, h[p]) && walkable(px + dx, pz + dz, h[p]) &&
								  walkable(px + dx + sx, pz + dz + sz, h[p]);
				const bool minus = walkable(px - sx, pz - sz, h[p]) && walkable(px + dx, pz + dz, h[p]) &&
								   walkable(px + dx - sx, pz + dz - sz, h[p]);
				if (!(clearance_class == 2 ? plus && minus : plus || minus))
				{
					continue;
				}
			}
			out[p * 3] = 0.0f;
			const float length = std::sqrt(float(dxs[d] * dxs[d] + dzs[d] * dzs[d]));
			out[p * 3 + 1] = -dxs[d] / length;
			out[p * 3 + 2] = -dzs[d] / length;
			queue.push_back(p);
		}
	}
	else
	{
		out[goal * 3] = 0.0f;
		queue.push_back(goal);
	}
	for (size_t head = 0; head < queue.size(); ++head)
	{
		const int current = queue[head];
		const int cx = current % width;
		const int cz = current / width;
		for (int d = 0; d < 8; ++d)
		{
			const int nx = cx + dxs[d];
			const int nz = cz + dzs[d];
			if (!inside(nx, nz))
			{
				continue;
			}
			const int n = nz * width + nx;
			// GDScript arithmetic uses double, with distances stored as float32.
			// Preserve that rounding and deterministic equal-cost tie order.
			const double cost = (dxs[d] != 0 && dzs[d] != 0) ? 1.414 : 1.0;
			const double distance = double(out[current * 3]) + cost;
			if (out[n * 3] >= 0.0f && distance >= out[n * 3])
			{
				continue;
			}
			if (!step_passable(nx, nz, cx, cz) || !clearance(nx, nz, cx, cz))
			{
				continue;
			}
			const bool first_visit = out[n * 3] < 0.0f;
			out[n * 3] = distance;
			const float length = std::sqrt(float(dxs[d] * dxs[d] + dzs[d] * dzs[d]));
			out[n * 3 + 1] = -dxs[d] / length;
			out[n * 3 + 2] = -dzs[d] / length;
			if (first_visit)
			{
				queue.push_back(n);
			}
		}
	}
	return result;
}

} // namespace godot
