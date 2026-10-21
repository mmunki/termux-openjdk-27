#!/usr/bin/env bash
# ============================================================================
# package.sh -- turn a built OpenJDK 27 image into Termux .deb packages
#
# The layout follows the official Termux openjdk-25 package exactly:
#
#   data/data/com.termux/files/usr/lib/jvm/java-27-openjdk/   the JDK image
#   data/data/com.termux/files/usr/share/doc/openjdk-27/     empty doc dir
#
# The X11 part of the JDK (the awt_xawt library, the font manager and the
# java.desktop module) is put into a second package, openjdk-27-x, the same
# way the official package splits it.
#
#   package.sh --image <path to images/jdk> --out <output directory>
# ============================================================================
set -euo pipefail

IMAGE=""
OUT=""
VERSION="${VERSION:-27.0.1}"
TERMUX_PREFIX="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
PKG_NAME="${PKG_NAME:-openjdk-27}"
PKG_NAME_X="${PKG_NAME}-x"

while [ $# -gt 0 ]; do
  case "$1" in
    --image)  IMAGE="${2:?--image needs a value}"; shift 2 ;;
    --out)    OUT="${2:?--out needs a value}"; shift 2 ;;
    --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

[ -n "$IMAGE" ] || { echo "error: --image is required" >&2; exit 1; }
[ -n "$OUT" ]   || { echo "error: --out is required" >&2; exit 1; }
[ -d "$IMAGE" ] || { echo "error: no such image: $IMAGE" >&2; exit 1; }

JDK_DIR_NAME="${JDK_DIR_NAME:-java-27-openjdk}"
PREFIX_REL="data/data/com.termux/files/usr"

log() { printf '==> %s\n' "$*" >&2; }

mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# The main package
# ---------------------------------------------------------------------------
STAGE="$WORK/stage"
mkdir -p "$STAGE/$PREFIX_REL/lib/jvm" "$STAGE/$PREFIX_REL/share/doc/$PKG_NAME"
cp -a "$IMAGE" "$STAGE/$PREFIX_REL/lib/jvm/$JDK_DIR_NAME"
JDK="$STAGE/$PREFIX_REL/lib/jvm/$JDK_DIR_NAME"

# The debug information is not shipped, the official package does not ship it
# either.
find "$JDK" -name "*.debuginfo" -delete

# The man pages are shipped gzipped.
if [ -d "$JDK/man/man1" ]; then
  for page in "$JDK"/man/man1/*.1; do
    [ -f "$page" ] || continue
    gzip -f "$page"
  done
fi

# JAVA_HOME for the shell.
mkdir -p "$JDK/etc/profile.d"
echo "export JAVA_HOME=$TERMUX_PREFIX/lib/jvm/$JDK_DIR_NAME/" > "$JDK/etc/profile.d/java.sh"

# The source archive is a package of its own, exactly like the official one.
mkdir -p "$WORK/stage-source/$PREFIX_REL/lib/jvm/$JDK_DIR_NAME/lib"
cp -a "$JDK/lib/src.zip" "$WORK/stage-source/$PREFIX_REL/lib/jvm/$JDK_DIR_NAME/lib/" 2>/dev/null || true
rm -f "$JDK/lib/src.zip"

# ---------------------------------------------------------------------------
# The X11 package: everything that needs the X11 libraries
# ---------------------------------------------------------------------------
STAGE_X="$WORK/stage-x"
mkdir -p "$STAGE_X/$PREFIX_REL/lib/jvm/$JDK_DIR_NAME"
X_FILES="lib/libawt_xawt.so lib/libfontmanager.so lib/libjawt.so lib/libsplashscreen.so jmods/java.desktop.jmod include/jawt.h include/linux/jawt_md.h"
for f in $X_FILES; do
  [ -e "$JDK/$f" ] || continue
  mkdir -p "$STAGE_X/$PREFIX_REL/lib/jvm/$JDK_DIR_NAME/$(dirname "$f")"
  cp -a "$JDK/$f" "$STAGE_X/$PREFIX_REL/lib/jvm/$JDK_DIR_NAME/$f"
  rm -f "$JDK/$f"
done

# ---------------------------------------------------------------------------
# The control file
# ---------------------------------------------------------------------------
installed_size() {
  du -sk "$1" | cut -f1
}

write_control() {
  local stage="$1" name="$2" depends="$3" recommends="$4" suggests="$5" desc="$6"
  mkdir -p "$stage/DEBIAN"
  {
    echo "Package: $name"
    echo "Architecture: aarch64"
    echo "Installed-Size: $(installed_size "$stage")"
    echo "Maintainer: @termux"
    echo "Version: $VERSION"
    echo "Homepage: https://openjdk.java.net"
    [ -n "$depends" ] && echo "Depends: $depends"
    [ -n "$recommends" ] && echo "Recommends: $recommends"
    [ -n "$suggests" ] && echo "Suggests: $suggests"
    echo "Description: $desc"
  } > "$stage/DEBIAN/control"
}

# The dependencies are the Termux packages that provide the shared libraries
# the JDK links against.
DEPENDS="libandroid-spawn, libiconv, alsa-lib"
RECOMMENDS="ca-certificates-java, $PKG_NAME_X, resolv-conf"
SUGGESTS="cups"

write_control "$STAGE" "$PKG_NAME" "$DEPENDS" "$RECOMMENDS" "$SUGGESTS" \
  "Java development kit and runtime"

write_control "$STAGE_X" "$PKG_NAME_X" \
  "libandroid-shmem, libx11, libxext, libxi, libxrender, libxtst, freetype" "" "" \
  "Portion of $PKG_NAME requiring X11 functionality"

# The source package.
STAGE_SOURCE="$WORK/stage-source"
if [ -d "$STAGE_SOURCE/$PREFIX_REL/lib/jvm/$JDK_DIR_NAME/lib" ]; then
  write_control "$STAGE_SOURCE" "$PKG_NAME-source" "" "" "" \
    "Source files for $PKG_NAME"
fi

# ---------------------------------------------------------------------------
# The alternatives, the same way the official package does it
# ---------------------------------------------------------------------------
make_alternatives() {
  local stage="$1"
  local binaries manpages
  binaries="$(find "$stage/$PREFIX_REL/lib/jvm/$JDK_DIR_NAME/bin" -executable -type f 2>/dev/null | xargs -I{} basename "{}" | sort | xargs echo)"
  manpages="$(find "$stage/$PREFIX_REL/lib/jvm/$JDK_DIR_NAME/man/man1" -name "*.1.gz" 2>/dev/null | xargs -I{} basename "{}" | sort | xargs echo)"

  {
    echo "#!/data/data/com.termux/files/usr/bin/sh"
    echo "# Automatically added by termux_step_create_alternatives"
    echo "if [ \"\$1\" = 'configure' ] || [ \"\$1\" = 'abort-upgrade' ] || [ \"\$1\" = 'abort-deconfigure' ] || [ \"\$1\" = 'abort-remove' ]; then"
    echo "  if [ -x \"/data/data/com.termux/files/usr/bin/update-alternatives\" ]; then"
    echo "    update-alternatives \\"
    echo "      --install \"/data/data/com.termux/files/usr/bin/java\" \"java\" \"/data/data/com.termux/files/usr/lib/jvm/$JDK_DIR_NAME/bin/java\" 50 \\"
    for b in $binaries; do
      [ "$b" = "java" ] && continue
      echo "      --slave \"/data/data/com.termux/files/usr/bin/$b\" \"$b\" \"/data/data/com.termux/files/usr/lib/jvm/$JDK_DIR_NAME/bin/$b\" \\"
    done
    echo "      --slave \"/data/data/com.termux/files/usr/etc/profile.d/java.sh\" \"java-profile\" \"/data/data/com.termux/files/usr/lib/jvm/$JDK_DIR_NAME/etc/profile.d/java.sh\" \\"
    for m in $manpages; do
      echo "      --slave \"/data/data/com.termux/files/usr/share/man/man1/$m\" \"$m\" \"/data/data/com.termux/files/usr/lib/jvm/$JDK_DIR_NAME/man/man1/$m\" \\"
    done
    echo "      ;"
    echo "  fi"
    echo "fi"
    echo "# End automatically added section"
  } > "$stage/DEBIAN/postinst"

  {
    echo "#!/data/data/com.termux/files/usr/bin/sh"
    echo "# Automatically added by termux_step_create_alternatives"
    echo "if [ \"\$1\" = 'remove' ] || [ \"\$1\" != 'upgrade' ]; then"
    echo "  if [ -x \"/data/data/com.termux/files/usr/bin/update-alternatives\" ]; then"
    echo "    update-alternatives --remove \"java\" \"/data/data/com.termux/files/usr/lib/jvm/$JDK_DIR_NAME/bin/java\""
    echo "  fi"
    echo "fi"
    echo "# End automatically added section"
  } > "$stage/DEBIAN/prerm"

  chmod 755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/prerm"
}

make_alternatives "$STAGE"

# ---------------------------------------------------------------------------
# Build the packages
# ---------------------------------------------------------------------------
# The Termux prefix is private, the official packages use the same
# permissions.
chmod -R u+rwX,go-rwx "$STAGE/$PREFIX_REL" "$STAGE_X/$PREFIX_REL" 2>/dev/null || true

build_deb() {
  local stage="$1" name="$2"
  local deb="$OUT/${name}_${VERSION}_aarch64.deb"
  rm -f "$deb"
  dpkg-deb --build --root-owner-group "$stage" "$deb" > /dev/null
  log "built $(basename "$deb") ($(stat -c %s "$deb") bytes)"
  echo "$deb"
}

build_deb "$STAGE" "$PKG_NAME"
build_deb "$STAGE_X" "$PKG_NAME_X"
if [ -d "$STAGE_SOURCE/$PREFIX_REL/lib/jvm/$JDK_DIR_NAME/lib" ]; then
  build_deb "$STAGE_SOURCE" "$PKG_NAME-source"
fi
