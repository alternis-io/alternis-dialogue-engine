GODOT_VERSION="4.1"
GODOT_BIN="${GODOT_BIN:-godot}"

SCRIPT_DIR="$(dirname "$0")"

mkdir -p $SCRIPT_DIR/thirdparty/godot
pushd $SCRIPT_DIR/thirdparty/godot
# generate json and headers
$GODOT_BIN --dump-extension-api --dump-gd-extension-interface --headless
popd


