extends GutTest

func test_native_probe_available_in_classdb() -> void:
	assert_true(ClassDB.class_exists("NativeProbe"), "NativeProbe must be registered in ClassDB by GDExtension")

func test_native_probe_instance_methods() -> void:
	if not ClassDB.class_exists("NativeProbe"):
		return
	
	var probe: Object = ClassDB.instantiate("NativeProbe")
	assert_not_null(probe, "NativeProbe should be instantiable")
	assert_true(probe.call("is_native_loaded"), "is_native_loaded must return true")
	assert_eq(probe.call("get_native_build_version"), "0.1.0-native")
