#!/usr/bin/env bash
# ============================================================================
# build.sh -- build OpenJDK 27 for Termux (Android aarch64)
#
# The build is a cross build: the JDK is compiled on a Linux host with the
# Android NDK for the aarch64-linux-android target.  The result is packaged
# into Termux .deb packages by package.sh.
#
#   ./build.sh                 # build everything and package it
#   ./build.sh --skip-build    # only package an existing build
#
# What it needs:
#   - the Android NDK (30.0.16248370 is the one the official Termux
#     openjdk-25 package was built with)
#   - the JDK 27 GA boot JDK (downloaded by the script)
#   - network access
# ============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-/tmp/termux-openjdk-27}"
NDK="${NDK:-/usr/local/lib/android/sdk/ndk/30.0.16248370}"
API="${API:-24}"
TARGET="aarch64-linux-android${API}"
VERSION="${VERSION:-27.0.1}"
TERMUX_PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
JDK_DIR_NAME="java-27-openjdk"
PREFIX="$WORK/prefix"
DL="$WORK/dl"
SRC="$WORK/src"
BUILD="$WORK/build"
TERMUX_REPO_URL="https://packages.termux.dev/apt/termux-main/pool/main"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

SKIP_BUILD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1; shift ;;
    --work) WORK="${2:?--work needs a value}"; shift 2 ;;
    -h|--help) sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
export CC="$TOOLCHAIN/bin/${TARGET}-clang"
export CXX="$TOOLCHAIN/bin/${TARGET}-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export NM="$TOOLCHAIN/bin/llvm-nm"
export OBJCOPY="$TOOLCHAIN/bin/llvm-objcopy"
export OBJDUMP="$TOOLCHAIN/bin/llvm-objdump"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
export CXXFILT="$TOOLCHAIN/bin/llvm-cxxfilt"

mkdir -p "$WORK" "$DL" "$SRC" "$BUILD" "$PREFIX"

download() {
  local url="$1" file="$2"
  if [ -f "$DL/$file" ]; then
    return 0
  fi
  log "download $file"
  curl -sSL --max-time 1800 -o "$DL/$file" "$url"
}

# ---------------------------------------------------------------------------
# 1. the sources
# ---------------------------------------------------------------------------
download "https://github.com/openjdk/jdk27u/archive/refs/tags/jdk-${VERSION}-ga.tar.gz" "jdk-${VERSION}-ga.tar.gz"

# The boot JDK has to be the same major version as the JDK that is built.
BOOT_JDK="$WORK/bootjdk"
if [ ! -x "$BOOT_JDK/bin/java" ]; then
  log "download the boot JDK"
  BOOT_URL="https://download.java.net/java/GA/jdk${VERSION}/cb858dd9ef0246e1847750bdb65252fe/9/GPL/openjdk-${VERSION}_linux-x64_bin.tar.gz"
  download "$BOOT_URL" "openjdk-${VERSION}_linux-x64_bin.tar.gz"
  mkdir -p "$BOOT_JDK"
  tar xzf "$DL/openjdk-${VERSION}_linux-x64_bin.tar.gz" -C "$BOOT_JDK" --strip-components=1
fi

# The headers of the libraries the JDK links against.  They are taken from
# the upstream sources, the shared libraries themselves come from the Termux
# packages so that the sonames match the ones on the device.
download "https://www.x.org/releases/individual/proto/xorgproto-2026.1.tar.gz" "xorgproto-2026.1.tar.gz"
download "https://www.x.org/releases/individual/lib/libX11-1.8.14.tar.gz" "libX11-1.8.14.tar.gz"
download "https://www.x.org/releases/individual/lib/libXext-1.3.7.tar.gz" "libXext-1.3.7.tar.gz"
download "https://www.x.org/releases/individual/lib/libXi-1.8.4.tar.gz" "libXi-1.8.4.tar.gz"
download "https://www.x.org/releases/individual/lib/libXrender-0.9.13.tar.gz" "libXrender-0.9.13.tar.gz"
download "https://www.x.org/releases/individual/lib/libXrandr-1.5.5.tar.gz" "libXrandr-1.5.5.tar.gz"
download "https://www.x.org/releases/individual/lib/libXtst-1.2.6.tar.gz" "libXtst-1.2.6.tar.gz"
download "https://www.x.org/releases/individual/lib/libXt-1.3.1.tar.gz" "libXt-1.3.1.tar.gz"
download "https://github.com/OpenPrinting/cups/releases/download/v2.4.20/cups-2.4.20-source.tar.gz" "cups-2.4.20-source.tar.gz"
download "https://github.com/alsa-project/alsa-lib/archive/refs/tags/v1.2.16.1.tar.gz" "alsa-lib-1.2.16.1.tar.gz"
download "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/2.18.3/fontconfig-2.18.3.tar.gz" "fontconfig-2.18.3.tar.gz"

# The shared libraries, taken from the Termux packages.
TERMUX_DEBS=(
  "libx/libx11/libx11_1.8.14_aarch64.deb"
  "libx/libxext/libxext_1.3.7_aarch64.deb"
  "libx/libxi/libxi_1.8.4_aarch64.deb"
  "libx/libxrender/libxrender_0.9.13_aarch64.deb"
  "libx/libxrandr/libxrandr_1.5.5_aarch64.deb"
  "libx/libxrender/libxrender_0.9.13_aarch64.deb"
  "libx/libxtst/libxtst_1.2.6_aarch64.deb"
  "libx/libxt/libxt_1.3.1-1_aarch64.deb"
  "libx/libxau/libxau_1.0.12-2_aarch64.deb"
  "libx/libxdmcp/libxdmcp_1.1.5-2_aarch64.deb"
  "c/cups/cups_2.4.20_aarch64.deb"
  "a/alsa-lib/alsa-lib_1.2.16.1_aarch64.deb"
)
for deb in "${TERMUX_DEBS[@]}"; do
  download "$TERMUX_REPO_URL/$deb" "$(basename "$deb")"
done

# ---------------------------------------------------------------------------
# 2. the target libraries and headers
# ---------------------------------------------------------------------------
if [ ! -f "$PREFIX/include/X11/Xlib.h" ]; then
  log "unpack the headers"
  mkdir -p "$SRC/headers"
  for t in xorgproto-2026.1 libX11-1.8.14 libXext-1.3.7 libXi-1.8.4 libXrender-0.9.13 \
           libXrandr-1.5.5 libXtst-1.2.6 libXt-1.3.1 cups-2.4.20-source alsa-lib-1.2.16.1 \
           fontconfig-2.18.3; do
    tar xzf "$DL/$t.tar.gz" -C "$SRC/headers" --strip-components=1 2>/dev/null || true
  done
  # the gitlab and github archives use the version as the directory name
  for d in "$SRC/headers"/*; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in
      fontconfig-2.18.3) mv "$d" "$SRC/headers/fontconfig" ;;
      cups-2.4.20-source) mv "$d" "$SRC/headers/cups" ;;
    esac
  done

  mkdir -p "$PREFIX/include/X11/extensions" "$PREFIX/include/cups" "$PREFIX/include/alsa" "$PREFIX/include/fontconfig"
  cp "$SRC/headers/xorgproto-2026.1/include/X11/"*.h "$PREFIX/include/X11/"
  cp "$SRC/headers/xorgproto-2026.1/include/X11/extensions/"*.h "$PREFIX/include/X11/extensions/"
  cp "$SRC/headers/libX11-1.8.14/include/X11/"*.h "$PREFIX/include/X11/"
  cp "$SRC/headers/libXext-1.3.7/include/X11/extensions/"*.h "$PREFIX/include/X11/extensions/"
  cp "$SRC/headers/libXi-1.8.4/include/X11/extensions/"*.h "$PREFIX/include/X11/extensions/"
  cp "$SRC/headers/libXrender-0.9.13/include/X11/extensions/"*.h "$PREFIX/include/X11/extensions/"
  cp "$SRC/headers/libXrandr-1.5.5/include/X11/extensions/"*.h "$PREFIX/include/X11/extensions/"
  cp "$SRC/headers/libXtst-1.2.6/include/X11/extensions/"*.h "$PREFIX/include/X11/extensions/"
  cp "$SRC/headers/libXt-1.3.1/include/X11/"*.h "$PREFIX/include/X11/"
  cp "$SRC/headers/cups/cups/"*.h "$PREFIX/include/cups/" 2>/dev/null || true
  cp "$SRC/headers/alsa-lib-1.2.16.1/include/"*.h "$PREFIX/include/alsa/"
  # alsa-lib builds asoundlib.h out of two files
  cat "$SRC/headers/alsa-lib-1.2.16.1/include/asoundlib-head.h" \
      "$SRC/headers/alsa-lib-1.2.16.1/include/asoundlib-tail.h" > "$PREFIX/include/alsa/asoundlib.h"
  # fontconfig.h is generated by the fontconfig build, the version numbers
  # are the only thing that changes in it
  sed -e 's/@CACHE_VERSION@/12/' -e 's/@CACHE_SNAP_VERSION@/0/' \
      -e 's/@NEXT_CACHE_VERSION@/0/' -e 's/@CACHE_MIN_COMPAT_VERSION@/9/' \
      "$SRC/headers/fontconfig/fontconfig/fontconfig.h.in" > "$PREFIX/include/fontconfig/fontconfig.h"
  cp "$SRC/headers/fontconfig/fontconfig/fcfreetype.h" "$SRC/headers/fontconfig/fontconfig/fcfontations.h" \
     "$PREFIX/include/fontconfig/"
fi

if [ ! -f "$PREFIX/lib/libX11.so" ]; then
  log "unpack the Termux libraries"
  mkdir -p "$SRC/debs"
  for deb in "${TERMUX_DEBS[@]}"; do
    name="$(basename "$deb")"
    [ -f "$DL/$name" ] || continue
    dpkg-deb -x "$DL/$name" "$SRC/debs"
  done
  cp -a "$SRC/debs/data/data/com.termux/files/usr/lib/"*.so* "$PREFIX/lib/"
fi

# libandroid-spawn: the posix_spawn() implementation for Android, the same
# source the Termux libandroid-spawn package is built from.
if [ ! -f "$PREFIX/lib/libandroid-spawn.so" ]; then
  log "build libandroid-spawn"
  mkdir -p "$BUILD/libandroid-spawn"
  cp "$REPO_DIR/deps/libandroid-spawn/posix_spawn."* "$BUILD/libandroid-spawn/"
  (
    cd "$BUILD/libandroid-spawn"
    "$CXX" -O2 -fPIC -D__ANDROID__=1 -D__TERMUX__=1 -I. -c posix_spawn.cpp -o posix_spawn.o
    "$CXX" -shared -static-libstdc++ posix_spawn.o -o libandroid-spawn.so
    "$AR" rcu libandroid-spawn.a posix_spawn.o
    install -Dm600 libandroid-spawn.so "$PREFIX/lib/libandroid-spawn.so"
    install -Dm600 libandroid-spawn.a "$PREFIX/lib/libandroid-spawn.a"
    install -Dm600 posix_spawn.h "$PREFIX/include/spawn.h"
  )
fi

# ---------------------------------------------------------------------------
# 3. the patched JDK sources
# ---------------------------------------------------------------------------
JDK_SRC="$SRC/jdk-$VERSION"
if [ ! -d "$JDK_SRC" ]; then
  log "unpack the JDK sources"
  mkdir -p "$JDK_SRC"
  tar xzf "$DL/jdk-${VERSION}-ga.tar.gz" -C "$JDK_SRC" --strip-components=1
fi

if [ ! -f "$JDK_SRC/.termux-patched" ]; then
  log "apply the patches"
  cd "$JDK_SRC"
  for patch in "$REPO_DIR"/patches/*.patch "$REPO_DIR"/patches/tmpdir-path-length.diff; do
    [ -f "$patch" ] || continue
    # the Termux prefix is patched into the sources
    sed -e "s|@TERMUX_PREFIX@|$TERMUX_PREFIX|g" \
        -e "s|@TERMUX_TMPDIR_PATH_LENGTH@|$(( ${#TERMUX_PREFIX} + 4 ))|g" \
        "$patch" | patch -p1 --forward --batch
  done
  # the patches that do not apply to this JDK version are applied by hand
  # afterwards, see patches/README.md
  touch .termux-patched
fi

# ---------------------------------------------------------------------------
# 4. configure
# ---------------------------------------------------------------------------
if [ ! -f "$JDK_SRC/build/linux-aarch64-server-release/spec.gmk" ]; then
  log "configure"
  cd "$JDK_SRC"
  bash ./configure \
    --with-boot-jdk="$BOOT_JDK" \
    --openjdk-target="$TARGET" \
    --with-toolchain-type=clang \
    --with-jvm-variants=server \
    --with-debug-level=release \
    --with-version-pre="" \
    --with-version-opt="" \
    --with-vendor-name="Termux" \
    --with-fontconfig-include="$PREFIX/include" \
    --with-freetype=bundled \
    --with-libjpeg=bundled \
    --with-libpng=bundled \
    --with-lcms=bundled \
    --with-giflib=bundled \
    --with-zlib=bundled \
    --with-cups="$PREFIX" \
    --with-x="$PREFIX" \
    --with-alsa="$PREFIX" \
    --disable-warnings-as-errors \
    --with-extra-cflags="-O2 -fPIC -I$PREFIX/include -D__ANDROID__=1 -D__TERMUX__=1 -DLE_STANDALONE" \
    --with-extra-cxxflags="-O2 -fPIC -I$PREFIX/include -D__ANDROID__=1 -D__TERMUX__=1 -DLE_STANDALONE" \
    --with-extra-ldflags="-L$PREFIX/lib -Wl,-rpath,$TERMUX_PREFIX/lib -Wl,-rpath,$TERMUX_PREFIX/lib/jvm/$JDK_DIR_NAME/lib -Wl,--enable-new-dtags -Wl,--as-needed -landroid-shmem -landroid-spawn" \
    --with-jobs="$(nproc)" \
    CC="$CC" CXX="$CXX" AR="$AR" NM="$NM" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" \
    STRIP="$STRIP" CXXFILT="$CXXFILT" \
    BUILD_CC="$TOOLCHAIN/bin/clang" BUILD_CXX="$TOOLCHAIN/bin/clang++" \
    BUILD_NM="$NM" BUILD_AR="$AR" BUILD_OBJCOPY="$OBJCOPY" BUILD_STRIP="$STRIP"
fi

# ---------------------------------------------------------------------------
# 5. build
# ---------------------------------------------------------------------------
if [ "$SKIP_BUILD" = 0 ]; then
  log "build the JDK"
  cd "$JDK_SRC/build/linux-aarch64-server-release"
  make images
fi

# ---------------------------------------------------------------------------
# 6. package
# ---------------------------------------------------------------------------
log "package"
VERSION="$VERSION" "$REPO_DIR/package.sh" \
  --image "$JDK_SRC/build/linux-aarch64-server-release/images/jdk" \
  --out "$WORK/packages"
