#!/bin/bash
# (tilt.root) Builds TILT.ROOT from this source tree on Linux, with the tools an extracted Hookshot AppImage carries
# (clang, Python, the sysroot, FFmpeg, SDL2): the renderer (hookshot_vk.so) from gpu/vk for this PC's CPU, then the game
# from your own copy.
#
#   scripts/linux/tilt-root-build.sh vk                               the renderer alone (needs no game)
#   scripts/linux/tilt-root-build.sh game <game.nup> <out folder> [language]   the renderer, then the game
#
# TILT_ROOT_HOME (default ~/.local/share/tilt-root-build) holds everything this makes and needs, outside the source tree:
#   toolchain/   the AppImage, extracted (Hookshot-<version>-x86_64.AppImage --appimage-extract, squashfs-root renamed)
#   cpm/         Vulkan-Headers, SPIRV-Headers and VulkanMemoryAllocator in CPM's layout (scripts/linux/deps.sh's versions)
#   tree/        a copy of this source tree the build runs in, with the tools' prebuilt helpers beside it
#   vk-work/     the renderer's objects      cache/   the game's objects
# Nothing is written into the source tree, so it stays free of binaries and of anything made from the game.
#
# TILT_ROOT_TARGET=windows builds the Windows game instead (hookshot_vk.dll, hookshot.exe), still on Linux. It needs, in
# TILT_ROOT_HOME as well:
#   mingw/       llvm-mingw's Linux build, unpacked (github.com/mstorsjo/llvm-mingw, llvm-mingw-<date>-ucrt-ubuntu-22.04-x86_64)
#   cpm/ffmpeg/<any name>/{include,lib,bin}   a Windows FFmpeg, shared, with its headers (a win64-lgpl-shared build of
#                the FFmpeg-Builds autobuilds has this layout)
#   sdl-win/     SDL2.dll and SDL3.dll (github.com/libsdl-org: sdl2-compat's and SDL's win32-x64 releases)
# and makes  vk-work-win/  and  cache-win/  beside the Linux build's. The game folder it makes runs on Windows.
set -euo pipefail
SRC=$(cd "$(dirname "$0")/../.." && pwd)
HOME_DIR=${TILT_ROOT_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/tilt-root-build}
TC=$HOME_DIR/toolchain
LIB=$TC/usr/lib/hookshot
PY=$TC/usr/python/bin/python3
TREE=$HOME_DIR/tree
VERSION=${TILT_ROOT_VERSION:-v2.0.14-tiltroot.1}
JOBS=${JOBS:-$(nproc)}
TARGET=${TILT_ROOT_TARGET:-linux}
case $TARGET in
    linux)   SUFFIX=;     VKNAME=hookshot_vk.so ;;
    windows) SUFFIX=-win; VKNAME=hookshot_vk.dll ;;
    *) echo "TILT_ROOT_TARGET is linux or windows, not '$TARGET'."; exit 1 ;;
esac

[ -x "$PY" ] && [ -d "$LIB/emsdk" ] || { echo "No toolchain in $TC: extract a Hookshot AppImage there (see the top of this script)."; exit 1; }
[ -d "$HOME_DIR/cpm/vulkanheaders" ] || { echo "No Vulkan headers in $HOME_DIR/cpm (see scripts/linux/deps.sh, 'the Vulkan back end's headers')."; exit 1; }
if [ "$TARGET" = windows ]; then
    [ -x "$HOME_DIR/mingw/bin/x86_64-w64-mingw32-clang" ] || { echo "No llvm-mingw in $HOME_DIR/mingw (see the top of this script)."; exit 1; }
    ls "$HOME_DIR"/cpm/ffmpeg/*/include/libavcodec/avcodec.h >/dev/null 2>&1 || { echo "No Windows FFmpeg in $HOME_DIR/cpm/ffmpeg (see the top of this script)."; exit 1; }
    [ -f "$HOME_DIR/sdl-win/SDL2.dll" ] && [ -f "$HOME_DIR/sdl-win/SDL3.dll" ] || { echo "No SDL2.dll and SDL3.dll in $HOME_DIR/sdl-win (see the top of this script)."; exit 1; }
fi

# ---- the tree the build runs in: this source, and the helpers the AppImage has built already ----
mkdir -p "$TREE"
rsync -a --delete --exclude .git --exclude work --exclude '*.so' --exclude '*.sha1' --exclude __pycache__ "$SRC/" "$TREE/"
T=$TC/usr/share/hookshot
for f in third_party/a64-kit/lift/liba64emit.so third_party/a64-kit/lift/liba64emit.so.sha1 third_party/zbic/zbic.so; do
    [ -f "$T/$f" ] && cp -u "$T/$f" "$TREE/$f"
done
find "$T/third_party/a64-kit" -name '*.so' -o -name '*.sha1' | while read -r f; do cp -u "$f" "$TREE/${f#"$T"/}"; done
if [ -d "$T/work" ]; then mkdir -p "$TREE/work" && cp -ru "$T/work/." "$TREE/work/"; fi   # (the hot list and the play profile)
printf '%s\n' "$VERSION" > "$TREE/VERSION"
if [ "$TARGET" = windows ]; then   # (the rsync above removes them: the source tree has none)
    cp "$HOME_DIR/sdl-win/SDL2.dll" "$HOME_DIR/sdl-win/SDL3.dll" "$TREE/third_party/sdl2/"
    export RX_TARGET=windows HOOKSHOT_MINGW=$HOME_DIR/mingw
fi

export EMSDK=$LIB/emsdk RX_CPM=$HOME_DIR/cpm

# ---- the renderer (the Linux one for this PC's CPU; the AppImage's is built for any x86-64-v3 one) ----
cd "$TREE"
OOT_WORK=$HOME_DIR/vk-work$SUFFIX RX_VK_ONLY=1 RX_RELEASE=1 HOOKSHOT_VERSION=$VERSION "$PY" -I -B nx2/build.py --standalone --jobs "$JOBS"
VK=$HOME_DIR/vk-work$SUFFIX/sa/build/$VKNAME
[ -f "$VK" ] || { echo "$VKNAME was not built"; exit 1; }
echo "renderer: $VK"
[ "${1:-vk}" = game ] || exit 0

# ---- the game, from your copy ----
NUP=${2:?the game\'s .nup file}
OUT=${3:?the folder to build the game into}
LANGUAGE=${4:-pt-BR}
export HOOKSHOT_VK_PREBUILT=$VK HOOKSHOT_VERSION=$VERSION
if [ "$TARGET" = linux ]; then
    export HOOKSHOT_TOOLS=$TREE HOOKSHOT_SYSROOT=$LIB/sysroot HOOKSHOT_FFMPEG=$LIB/ffmpeg HOOKSHOT_SDL2=$LIB/libSDL2-2.0.so.0
fi
exec "$PY" -I -B nx2/make_game.py --nup "$NUP" --out "$OUT" --language "$LANGUAGE" --work "$HOME_DIR/cache$SUFFIX" \
    --jobs "$JOBS" --log "$HOME_DIR/build$SUFFIX.log"
