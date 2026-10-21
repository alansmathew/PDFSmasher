#!/bin/bash
# Builds a self-contained, universal `qpdf` command-line tool that PDF Smasher bundles for
# lossless optimization (recompressing streams, packing objects into object streams).
#
# qpdf is Apache-2.0 and libjpeg-turbo is BSD/IJG licensed; both may be redistributed
# in a free app as long as their license texts ship with it (copied to Resources/ThirdParty).
#
# Requires: cmake (brew install cmake)

set -euo pipefail
cd "$(dirname "$0")/.."

QPDF_VERSION="${QPDF_VERSION:-12.4.2}"
JPEG_VERSION="${JPEG_VERSION:-3.2.0}"
export MACOSX_DEPLOYMENT_TARGET=14.0

ROOT="$PWD"
DEPS="$ROOT/.deps"
PREFIX="$DEPS/prefix"
mkdir -p "$DEPS" "$ROOT/Resources/bin" "$ROOT/Resources/ThirdParty"

fetch() {
    local url="$1" dir="$2"
    if [[ ! -d "$DEPS/$dir" ]]; then
        echo "▸ Downloading $url"
        curl -fsSL "$url" | tar -xz -C "$DEPS"
    fi
}

fetch "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$JPEG_VERSION/libjpeg-turbo-$JPEG_VERSION.tar.gz" "libjpeg-turbo-$JPEG_VERSION"
fetch "https://github.com/qpdf/qpdf/releases/download/v$QPDF_VERSION/qpdf-$QPDF_VERSION.tar.gz" "qpdf-$QPDF_VERSION"

JOBS="$(sysctl -n hw.ncpu)"
BINARIES=()
for ARCH in arm64 x86_64; do
    ARCH_PREFIX="$PREFIX-$ARCH"

    echo "▸ Building libjpeg-turbo $JPEG_VERSION ($ARCH)"
    cmake -S "$DEPS/libjpeg-turbo-$JPEG_VERSION" -B "$DEPS/build-jpeg-$ARCH" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_SYSTEM_PROCESSOR="$ARCH" -DCMAKE_INSTALL_PREFIX="$ARCH_PREFIX" \
        -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_SIMD=OFF -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF \
        -DWITH_TESTS=OFF > /dev/null
    cmake --build "$DEPS/build-jpeg-$ARCH" --config Release -j "$JOBS" > /dev/null
    cmake --install "$DEPS/build-jpeg-$ARCH" > /dev/null

    echo "▸ Building qpdf $QPDF_VERSION ($ARCH)"
    cmake -S "$DEPS/qpdf-$QPDF_VERSION" -B "$DEPS/build-qpdf-$ARCH" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
        -DREQUIRE_CRYPTO_NATIVE=ON -DUSE_IMPLICIT_CRYPTO=OFF \
        -DBUILD_DOC=OFF -DINSTALL_EXAMPLES=OFF -DINSTALL_MANUAL=OFF -DINSTALL_PKGCONFIG=OFF -DINSTALL_CMAKE_PACKAGE=OFF \
        -DLIBJPEG_H_PATH="$ARCH_PREFIX/include" -DLIBJPEG_LIB_PATH="$ARCH_PREFIX/lib/libjpeg.a" > /dev/null
    cmake --build "$DEPS/build-qpdf-$ARCH" --config Release --target qpdf -j "$JOBS" > /dev/null
    BINARIES+=("$DEPS/build-qpdf-$ARCH/qpdf/qpdf")
done

lipo -create "${BINARIES[@]}" -output "$ROOT/Resources/bin/qpdf"
strip -x "$ROOT/Resources/bin/qpdf"
cp "$DEPS/qpdf-$QPDF_VERSION/LICENSE.txt" "$ROOT/Resources/ThirdParty/qpdf-LICENSE.txt"
cp "$DEPS/qpdf-$QPDF_VERSION/NOTICE.md" "$ROOT/Resources/ThirdParty/qpdf-NOTICE.md" 2>/dev/null || true
cp "$DEPS/libjpeg-turbo-$JPEG_VERSION/LICENSE.md" "$ROOT/Resources/ThirdParty/libjpeg-turbo-LICENSE.md"

echo "✓ Resources/bin/qpdf ($(lipo -archs "$ROOT/Resources/bin/qpdf"))"
otool -L "$ROOT/Resources/bin/qpdf" | tail -n +2
