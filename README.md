# termux-openjdk-27

OpenJDK 27 built for **Termux** (Android, `aarch64`), packaged as Termux
`.deb` packages.

The build is a real upstream OpenJDK build: the sources of the OpenJDK 27.0.1
GA release are compiled with the Android NDK for the `aarch64-linux-android`
target, with the Android patches of the Termux package applied.  Nothing of
the JDK is replaced by a wrapper or a stub.

The packages have the same layout, the same paths and the same alternatives
as the official Termux `openjdk-25` package, so they are a drop in
replacement for it.

## Packages

| Package | Content |
| --- | --- |
| `openjdk-27_27.0.1_aarch64.deb` | the JDK, without the X11 parts |
| `openjdk-27-x_27.0.1_aarch64.deb` | the part of the JDK that needs X11 (`java.desktop`, `libawt_xawt`, the font manager) |
| `openjdk-27-source_27.0.1_aarch64.deb` | `src.zip` |

The split is the same one the official package uses: the main package has no
`java.desktop` module, the `-x` package adds it.

## Download

The packages are published as a GitHub release:

- https://github.com/mmunki/termux-openjdk-27/releases/tag/v27.0.1

```bash
gh release download v27.0.1 --repo mmunki/termux-openjdk-27 \
  --pattern 'openjdk-27_27.0.1_aarch64.deb'
```

## Installation

```bash
apt install ./openjdk-27_27.0.1_aarch64.deb
```

The X11 part is optional and needs the X11 libraries of Termux:

```bash
apt install ./openjdk-27-x_27.0.1_aarch64.deb
```

After the installation `java`, `javac`, `jar` and the other tools are in
`$PREFIX/bin`, and `JAVA_HOME` is set by
`$PREFIX/lib/jvm/java-27-openjdk/etc/profile.d/java.sh`.

## Build

```bash
./build.sh
```

The script downloads the sources, applies the patches, configures the JDK for
`aarch64-linux-android`, builds it and writes the packages into
`$WORK/packages` (`/tmp/termux-openjdk-27` by default).

What it needs:

* the Android NDK, `30.0.16248370` by default (the same NDK the official
  Termux `openjdk-25` package was built with)
* `curl`, `dpkg-deb`, `patch`, `tar`
* network access

Environment variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `WORK` | `/tmp/termux-openjdk-27` | the scratch directory of the build |
| `NDK` | `/usr/local/lib/android/sdk/ndk/30.0.16248370` | the Android NDK |
| `API` | `24` | the Android API level to build for |
| `VERSION` | `27.0.1` | the OpenJDK version to build |

## The patches

`patches/` holds the patch series.  The first 35 patches are the ones of the
Termux `openjdk-25` package, they apply to the JDK 27 sources with a few
offsets:

* `0013` is not applied, it only touches the x86 code
* `0027` is not applied, it only touches the arm (32 bit) code
* `0032` is not applied, the JDK 27 sources do not have the problem it solves
* `0036` (iconv) is not applied, bionic has `iconv` in libc

The last two patches are the ports of the hunks that do not apply to the
JDK 27 sources, plus the fix for the `noexcept` exception specifications
that bionic does not use:

* `0036-openjdk-27-port-android-fixes.patch`
* `0037-android-bionic-noexcept.patch`

## Licenses

The patches of the Termux package are under the GPL-2.0, the OpenJDK sources
are under the GPL-2.0 with the Classpath exception.  `deps/libandroid-spawn`
is the `posix_spawn` implementation of the Termux `libandroid-spawn`
package, BSD 2-clause.
