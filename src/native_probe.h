#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

class NativeProbe : public RefCounted {
    GDCLASS(NativeProbe, RefCounted);

protected:
    static void _bind_methods();

public:
    NativeProbe();
    ~NativeProbe();

    bool is_native_loaded() const;
    String get_native_build_version() const;
};

} // namespace godot
