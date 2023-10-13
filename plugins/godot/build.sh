GODOT_VERSION="4.1"
GODOT_BIN="${GODOT_BIN:-godot}"

SCRIPT_DIR="$(dirname "$0")"

mkdir -p $SCRIPT_DIR/thirdparty/godot
pushd $SCRIPT_DIR/thirdparty/godot
# generate json and headers
$GODOT_BIN --dump-extension-api --dump-gdextension-interface --headless
popd

# build godot-cpp (c++ bindings) dependency
pushd $SCRIPT_DIR/godot-cpp
scons platform=linux -j8 custom_api_file=../thirdparty/godot/extension_api.json bits=64
popd

scons platform=linux

