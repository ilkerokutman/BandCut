#!/bin/sh
set -eu

FFMPEG_VERSION=8.1.2
LAME_VERSION=3.100
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/bandcut-ffmpeg-build"
OUTPUT="$ROOT/macos/Runner/Resources/ffmpeg"
JOBS="$(sysctl -n hw.ncpu)"

mkdir -p "$WORK/sources" "$OUTPUT"
cd "$WORK/sources"

if [ ! -f "ffmpeg-$FFMPEG_VERSION.tar.xz" ]; then
  curl -fLO "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
fi
if [ ! -f "lame-$LAME_VERSION.tar.gz" ]; then
  curl -fL -o "lame-$LAME_VERSION.tar.gz" "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"
fi

for ARCH in arm64 x86_64; do
  PREFIX="$WORK/install-$ARCH"
  BUILD="$WORK/build-$ARCH"
  rm -rf "$PREFIX" "$BUILD"
  mkdir -p "$PREFIX" "$BUILD/lame" "$BUILD/ffmpeg"

  cd "$WORK/sources"
  tar -xzf "lame-$LAME_VERSION.tar.gz" -C "$BUILD/lame" --strip-components=1
  cd "$BUILD/lame"
  HOST="x86_64-apple-darwin"
  MIN_VERSION=10.15
  if [ "$ARCH" = arm64 ]; then
    HOST="aarch64-apple-darwin"
    MIN_VERSION=11.0
  fi
  CFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_VERSION -O2" \
  LDFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_VERSION" \
  ./configure --prefix="$PREFIX" --host="$HOST" --disable-shared \
    --enable-static --disable-frontend
  make -j"$JOBS"
  make install

  cd "$WORK/sources"
  tar -xJf "ffmpeg-$FFMPEG_VERSION.tar.xz" -C "$BUILD/ffmpeg" \
    --strip-components=1
  cd "$BUILD/ffmpeg"
  PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" ./configure \
    --prefix="$PREFIX" \
    --arch="$ARCH" \
    --target-os=darwin \
    --cc="clang -arch $ARCH" \
    --extra-cflags="-arch $ARCH -mmacosx-version-min=$MIN_VERSION -I$PREFIX/include" \
    --extra-ldflags="-arch $ARCH -mmacosx-version-min=$MIN_VERSION -L$PREFIX/lib" \
    --pkg-config-flags=--static \
    --disable-gpl \
    --disable-nonfree \
    --disable-version3 \
    --disable-autodetect \
    --disable-x86asm \
    --disable-everything \
    --disable-doc \
    --disable-debug \
    --disable-ffplay \
    --disable-ffprobe \
    --disable-network \
    --enable-static \
    --disable-shared \
    --enable-libmp3lame \
    --enable-protocol=file \
    --enable-demuxer=wav \
    --enable-decoder=pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,pcm_f64le \
    --enable-encoder=libmp3lame \
    --enable-muxer=mp3 \
    --enable-filter=aresample
  make -j"$JOBS" ffmpeg
  cp ffmpeg "$WORK/ffmpeg-$ARCH"
done

lipo -create "$WORK/ffmpeg-arm64" "$WORK/ffmpeg-x86_64" \
  -output "$OUTPUT/ffmpeg"
chmod 755 "$OUTPUT/ffmpeg"
"$OUTPUT/ffmpeg" -version
"$OUTPUT/ffmpeg" -hide_banner -encoders | grep libmp3lame
lipo -info "$OUTPUT/ffmpeg"
