#!/bin/bash
set -x

# See https://github.com/karl-zylinski/odin-raylib-web for more examples on how
# to do a web build, including how to embed assets into it.

git clone https://github.com/emscripten-core/emsdk.git
./emsdk/emsdk install latest
./emsdk/emsdk activate latest

EMSCRIPTEN_SDK_DIR="emsdk"
OUT_DIR="game_web"

mkdir -p $OUT_DIR

export EMSDK_QUIET=1
# shellcheck disable=SC1091
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"

if ! odin-linux-amd64-nightly+2025-03-05/odin build source/main_web -target:freestanding_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -vet -strict-style -o:speed -out:$OUT_DIR/gamegame; then
  exit 1
fi

ODIN_PATH=$(odin-linux-amd64-nightly+2025-03-05/odin root)

cp $ODIN_PATH/core/sys/wasm/js/odin.js $OUT_DIR

files="$OUT_DIR/gamegame.wasm.o ${ODIN_PATH}/vendor/raylib/wasm/libraylib.a ${ODIN_PATH}/vendor/raylib/wasm/libraygui.a"
flags="-sUSE_GLFW=3 -sWASM_BIGINT -sWARN_ON_UNDEFINED_SYMBOLS=0 -sASSERTIONS --shell-file source/main_web/index_template.html --preload-file assets"

# shellcheck disable=SC2086
# Add `-g` to `emcc` call to enable debug symbols (works in chrome).
emcc -g -o $OUT_DIR/index.html $files $flags && rm $OUT_DIR/gamegame.wasm.o
# emcc -o $OUT_DIR/index.html $files $flags

echo "Web build created in ${OUT_DIR}"
