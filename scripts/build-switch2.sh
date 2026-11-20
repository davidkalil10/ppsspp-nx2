#!/usr/bin/env bash
set -euo pipefail

export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
export DEVKITA64="${DEVKITA64:-$DEVKITPRO/devkitA64}"
export PATH="$DEVKITPRO/tools/bin:$DEVKITA64/bin:$DEVKITPRO/portlibs/switch2/bin:$DEVKITPRO/portlibs/switch/bin:$PATH"
export PKG_CONFIG_PATH="$DEVKITPRO/portlibs/switch2/lib/pkgconfig:$DEVKITPRO/portlibs/switch/lib/pkgconfig"

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
DEPS_DIR="$ROOT_DIR/build-switch2-deps"
BUILD_DIR="$ROOT_DIR/build-switch2-release"
DIST_DIR="$ROOT_DIR/dist"
SDL_SOURCE_DIR="$DEPS_DIR/sdl-src"
SDL_BUILD_DIR="$DEPS_DIR/sdl-build"
SDL_PREFIX="$DEPS_DIR/sdl-prefix"
FFMPEG_SOURCE_DIR="$DEPS_DIR/ffmpeg-src"
FFMPEG_BUILD_DIR="$DEPS_DIR/ffmpeg-build"
FFMPEG_PREFIX="$DEPS_DIR/ffmpeg-prefix"

SDL_REPOSITORY="https://github.com/devkitPro/SDL.git"
SDL_REVISION="c329016c0e338ab4397ad930f83330c9fe058348"
SDL_RECIPE_VERSION="switch2-v1"
FFMPEG_REPOSITORY="https://github.com/hrydgard/ppsspp-ffmpeg.git"
FFMPEG_REVISION="1e3b4965632f60b1d85360261d1b9dd45444bc71"
FFMPEG_RECIPE_VERSION="switch2-v1"

SWITCH2_TOOLCHAIN="$DEVKITPRO/libounce/cmake/Switch2.cmake"
OUNCEVK_PREFIX="$DEVKITPRO/portlibs/switch2"
LIBOUNCE_PREFIX="$DEVKITPRO/libounce"

[[ -f "$SWITCH2_TOOLCHAIN" ]] || { echo "Missing Switch2.cmake at $SWITCH2_TOOLCHAIN" >&2; exit 1; }
[[ -f "$OUNCEVK_PREFIX/lib/libvulkan.a" ]] || { echo "Missing OunceVK libvulkan.a at $OUNCEVK_PREFIX/lib" >&2; exit 1; }

JOBS="${JOBS:-$(nproc)}"
SWITCH_RELEASE_VERSION="${PPSSPP_SWITCH_RELEASE_VERSION:-1.1.7}"
mkdir -p "$DEPS_DIR" "$BUILD_DIR" "$DIST_DIR"

SDL_PATCH="$ROOT_DIR/SDL/switch-vulkan-window.patch"
SDL_PATCH_SUM="$(sha256sum "$SDL_PATCH" | cut -d' ' -f1)"
SDL_STAMP="$SDL_RECIPE_VERSION $SDL_REVISION $SDL_PATCH_SUM"
if [[ ! -f "$SDL_PREFIX/.ppsspp-switch2-sdl" ]] || [[ "$(<"$SDL_PREFIX/.ppsspp-switch2-sdl")" != "$SDL_STAMP" ]]; then
  echo "==> Building SDL3 for Nintendo Switch 2 (libounce + OunceVK)..."
  rm -rf "$SDL_SOURCE_DIR" "$SDL_BUILD_DIR" "$SDL_PREFIX"
  git clone --no-checkout "$SDL_REPOSITORY" "$SDL_SOURCE_DIR"
  git -C "$SDL_SOURCE_DIR" checkout --detach "$SDL_REVISION"
  git -C "$SDL_SOURCE_DIR" apply "$SDL_PATCH"
  cmake -S "$SDL_SOURCE_DIR" -B "$SDL_BUILD_DIR" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$SWITCH2_TOOLCHAIN" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$SDL_PREFIX" \
    -DCMAKE_PREFIX_PATH="$OUNCEVK_PREFIX" \
    -DOpenGL_DIR="$OUNCEVK_PREFIX/lib/cmake/OpenGL" \
    -DVulkan_DIR="$OUNCEVK_PREFIX/lib/cmake/Vulkan" \
    -DSDL_SHARED=OFF \
    -DSDL_STATIC=ON \
    -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON \
    -DSDL_TESTS=OFF \
    -DSDL_EXAMPLES=OFF \
    -DSDL_INSTALL=ON \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE=OFF \
    -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG -g0 -mcpu=cortex-a78c+crypto -mtp=soft -ftls-model=local-exec -D__SWITCH__ -D__SWITCH2__ -DSDL_VIDEO_DRIVER_SWITCH=1 -DSDL_AUDIO_DRIVER_SWITCH=1 -DSDL_JOYSTICK_SWITCH=1"
  cmake --build "$SDL_BUILD_DIR" --target install --parallel "$JOBS"
  printf '%s\n' "$SDL_STAMP" > "$SDL_PREFIX/.ppsspp-switch2-sdl"
fi

FFMPEG_STAMP="$FFMPEG_RECIPE_VERSION $FFMPEG_REVISION"
if [[ ! -f "$FFMPEG_PREFIX/.ppsspp-switch2-ffmpeg" ]] || [[ "$(<"$FFMPEG_PREFIX/.ppsspp-switch2-ffmpeg")" != "$FFMPEG_STAMP" ]]; then
  echo "==> Building FFmpeg for Nintendo Switch 2 (libounce)..."
  rm -rf "$FFMPEG_SOURCE_DIR" "$FFMPEG_BUILD_DIR" "$FFMPEG_PREFIX"
  mkdir -p "$FFMPEG_SOURCE_DIR" "$FFMPEG_BUILD_DIR" "$FFMPEG_PREFIX"
  FFMPEG_GIT_DIR="$DEPS_DIR/ffmpeg-git"
  if [[ ! -d "$FFMPEG_GIT_DIR" ]]; then
    git init --bare "$FFMPEG_GIT_DIR"
  fi
  if ! git --git-dir="$FFMPEG_GIT_DIR" cat-file -e "$FFMPEG_REVISION^{commit}" 2>/dev/null; then
    git --git-dir="$FFMPEG_GIT_DIR" fetch --depth 1 "$FFMPEG_REPOSITORY" "$FFMPEG_REVISION"
  fi
  git --git-dir="$FFMPEG_GIT_DIR" archive "$FFMPEG_REVISION" | tar -xf - -C "$FFMPEG_SOURCE_DIR"
  (
    cd "$FFMPEG_BUILD_DIR"
    "$FFMPEG_SOURCE_DIR/configure" \
      --prefix="$FFMPEG_PREFIX" \
      --disable-debug \
      --enable-cross-compile \
      --arch=aarch64 \
      --cross-prefix=aarch64-none-elf- \
      --ar=aarch64-none-elf-gcc-ar \
      --nm=aarch64-none-elf-gcc-nm \
      --ranlib=aarch64-none-elf-gcc-ranlib \
      --target-os=horizon \
      --extra-cflags="-D__SWITCH__ -D__SWITCH2__ -D_GNU_SOURCE -O3 -DNDEBUG -g0 -I$OUNCEVK_PREFIX/include -I$LIBOUNCE_PREFIX/include -mcpu=cortex-a78c+crypto -mtp=soft -fPIE -pie -ffunction-sections -fdata-sections -ftls-model=local-exec" \
      --extra-cxxflags="-D__SWITCH__ -D__SWITCH2__ -D_GNU_SOURCE -O3 -DNDEBUG -g0 -I$OUNCEVK_PREFIX/include -I$LIBOUNCE_PREFIX/include -mcpu=cortex-a78c+crypto -mtp=soft -fPIE -pie -ffunction-sections -fdata-sections -ftls-model=local-exec" \
      --extra-ldflags="-g0 -fPIE -pie -Wl,--build-id=none -L$OUNCEVK_PREFIX/lib -L$LIBOUNCE_PREFIX/lib" \
      --disable-shared \
      --enable-static \
      --disable-iconv \
      --disable-runtime-cpudetect \
      --disable-everything \
      --enable-zlib \
      --disable-filters \
      --disable-programs \
      --disable-network \
      --disable-avfilter \
      --disable-postproc \
      --disable-encoders \
      --disable-protocols \
      --disable-hwaccels \
      --disable-doc \
      --enable-decoder=h264 \
      --enable-decoder=mpeg4 \
      --enable-decoder=mpeg2video \
      --enable-decoder=mjpeg \
      --enable-decoder=mjpegb \
      --enable-decoder=aac \
      --enable-decoder=aac_latm \
      --enable-decoder=atrac3 \
      --enable-decoder=atrac3p \
      --enable-decoder=mp3 \
      --enable-decoder=pcm_s16le \
      --enable-decoder=pcm_s8 \
      --enable-encoder=huffyuv \
      --enable-encoder=ffv1 \
      --enable-encoder=mjpeg \
      --enable-encoder=pcm_s16le \
      --enable-demuxer=h264 \
      --enable-demuxer=m4v \
      --enable-demuxer=mpegvideo \
      --enable-demuxer=mpegps \
      --enable-demuxer=mp3 \
      --enable-demuxer=avi \
      --enable-demuxer=aac \
      --enable-demuxer=pmp \
      --enable-demuxer=oma \
      --enable-demuxer=pcm_s16le \
      --enable-demuxer=pcm_s8 \
      --enable-demuxer=wav \
      --enable-muxer=avi \
      --enable-parser=h264 \
      --enable-parser=mpeg4video \
      --enable-parser=mpegaudio \
      --enable-parser=mpegvideo \
      --enable-parser=aac \
      --enable-parser=aac_latm
    make -j"$JOBS"
    make install
  )
  printf '%s\n' "$FFMPEG_STAMP" > "$FFMPEG_PREFIX/.ppsspp-switch2-ffmpeg"
fi

echo "==> Configuring PPSSPP for Nintendo Switch 2..."
cmake -S "$ROOT_DIR" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$SWITCH2_TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$OUNCEVK_PREFIX;$SDL_PREFIX" \
  -DOpenGL_DIR="$OUNCEVK_PREFIX/lib/cmake/OpenGL" \
  -DVulkan_DIR="$OUNCEVK_PREFIX/lib/cmake/Vulkan" \
  -DSDL3_DIR="$SDL_PREFIX/lib/cmake/SDL3" \
  -DFFMPEG_DIR="$FFMPEG_PREFIX" \
  -DPPSSPP_SWITCH_RELEASE_VERSION="$SWITCH_RELEASE_VERSION" \
  -DUSE_LIBNX=ON \
  -DNINTENDO_SWITCH2=ON \
  -DSWITCH_ENABLE_LTO=OFF \
  -DUSE_FFMPEG=ON \
  -DUSE_SYSTEM_FFMPEG=OFF \
  -DBUILD_BUNDLED_FFMPEG=OFF \
  -DUSE_DISCORD=OFF \
  -DUSE_MINIUPNPC=OFF \
  -DHEADLESS=OFF \
  -DUNITTEST=OFF \
  -DATLAS_TOOL=OFF

echo "==> Building PPSSPP-switch2.nro..."
cmake --build "$BUILD_DIR" --target PPSSPP_NRO --parallel "$JOBS"
cmake -E copy_if_different "$BUILD_DIR/PPSSPP-switch2.nro" "$DIST_DIR/PPSSPP-switch2.nro"

echo "==> Verifying Switch 2 NRO package (OUN0 + kaiHEN JIT + zero Switch 1 libs)..."
python3 "$ROOT_DIR/Tools/verify_switch2_package.py" \
  "$DIST_DIR/PPSSPP-switch2.nro" \
  --link-map "$BUILD_DIR/PPSSPP-switch2.map"

sha256sum "$DIST_DIR/PPSSPP-switch2.nro"
