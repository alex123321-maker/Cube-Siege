#!/usr/bin/env python
import os
import sys

# Call godot-cpp SConstruct to get the configured build environment
env = SConscript("godot-cpp/SConstruct")

# Add our own include directory
env.Append(CPPPATH=["src"])

# Gather our C++ sources
sources = Glob("src/*.cpp")

# Configure target library path
lib_name = "bin/libcube_siege{}{}".format(env["suffix"], env["SHLIBSUFFIX"])
library = env.SharedLibrary(lib_name, source=sources)

Default(library)
