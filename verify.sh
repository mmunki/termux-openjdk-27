#!/usr/bin/env bash
# ============================================================================
# verify.sh -- run the built JDK under qemu with the Android runtime
#
# The binaries are aarch64 Android binaries, they are run with
# qemu-aarch64-static and the linker and the C library of an Android system
# image.  The system image is the one of the Android SDK.
# ============================================================================
set -uo pipefail

JDK="${1:?usage: verify.sh <path to the jdk image>}"
QEMU="${QEMU:-qemu-aarch64-static}"
SYSIMG="${SYSIMG:-/usr/local/lib/android/sdk/system-images/android-24/default/arm64-v8a/system.img}"
ROOT="${ROOT:-/tmp/opencode/work/android-root}"
PREFIX_LIB="${PREFIX_LIB:-/tmp/opencode/work/prefix/lib}"

if [ ! -x "$ROOT/system/bin/linker64" ]; then
  echo "the Android runtime is not extracted, run:"
  echo "  debugfs -R 'dump /bin/linker64 $ROOT/system/bin/linker64' $SYSIMG"
  exit 1
fi

run() {
  echo "### $*"
  "$QEMU" -L "$ROOT" \
    -E "LD_LIBRARY_PATH=$JDK/lib:$JDK/lib/server:$PREFIX_LIB" \
    -E "JAVA_HOME=$JDK" \
    -E "PATH=$JDK/bin" \
    -E "TMPDIR=/tmp" \
    "$@"
  echo "--- exit: $?"
}

run "$JDK/bin/java" -version
run "$JDK/bin/java" --list-modules
run "$JDK/bin/java" -XshowSettings:properties -version

cat > /tmp/Hello.java <<'EOF'
public class Hello {
    public static void main(String[] args) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 5; i++) {
            sb.append("line ").append(i).append('\n');
        }
        System.out.print(sb);
        System.out.println("java.version=" + System.getProperty("java.version"));
        System.out.println("java.home=" + System.getProperty("java.home"));
        System.out.println("os=" + System.getProperty("os.name") + " " + System.getProperty("os.arch"));
        System.out.println("modules=" + Runtime.getRuntime().availableProcessors());
    }
}
EOF

run "$JDK/bin/javac" -d /tmp /tmp/Hello.java
run "$JDK/bin/java" -cp /tmp Hello
run "$JDK/bin/jar" --version
run "$JDK/bin/jlink" --version
run "$JDK/bin/jshell" --version
