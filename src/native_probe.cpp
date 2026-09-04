#include "native_probe.h"

namespace godot {

void NativeProbe::_bind_methods() {
    ClassDB::bind_method(D_METHOD("is_native_loaded"), &NativeProbe::is_native_loaded);
    ClassDB::bind_method(D_METHOD("get_native_build_version"), &NativeProbe::get_native_build_version);
}

NativeProbe::NativeProbe() {}
NativeProbe::~NativeProbe() {}

bool NativeProbe::is_native_loaded() const {
    return true;
}

String NativeProbe::get_native_build_version() const {
    return "0.1.0-native";
}

} // namespace godot
