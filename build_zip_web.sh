SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

pushd "$SCRIPT_DIR" > /dev/null || exit 1

# Ensure popd runs on exit (success or failure)
trap 'popd > /dev/null' EXIT

rm -rf build/web/*; ./build_web.sh && zip -r build/web/web-game.zip build/web/*
