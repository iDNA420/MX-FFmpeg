#!/usr/bin/env bash

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
MX_FF_SRC_DIR="${SCRIPT_DIR}/src"
BUILD_ROOT="${MX_FF_SRC_DIR}/jni"

VERSION=${VERSION:="1.87.0"}
BUILD_NUMBER="2"
MX_FF_SRC_URL="https://github.com/MXVideoPlayer/MX-FFmpeg/archive/refs/heads/main.tar.gz"

die() {
	echo -e "$*" >&2
	exit 1
}
warn() { echo -e "$*" >&2; }
log() { echo -e "$*"; }

execute() {
	log ":==> $*\n"
	"$@" || die "failed to execute $*"
	log ""
}

if [[ ! -d "$NDK" ]]; then
	NDK_BUILD_PATH="$(which ndk-build)"
	if [[ -n "$NDK_BUILD_PATH" ]]; then
		export NDK=$(dirname "$NDK_BUILD_PATH")
		warn "NDK location auto-detected! path: $NDK"
	else
		die "Unable to detect NDK!!"
	fi
fi

clean() {
	[[ -z "$1" ]] && die "invalid usage! please specify output directory"

	if [[ ! -d "$1" ]]; then
		execute mkdir -p "$1"
	else
		execute rm -vrf "$1/"*
	fi
}

build() {
	[[ -z "$1" ]] && die "invalid usage! please specify cpu arch."
	case "${1}" in
	arm64)
		ARCH_NAME="neon64"
		TARGET="${BUILD_ROOT}/libs/arm64-v8a"
		;;
	neon)
		ARCH_NAME="neon"
		TARGET="${BUILD_ROOT}/libs/armeabi-v7a/neon"
		;;
	x86)
		ARCH_NAME="x86"
		TARGET="${BUILD_ROOT}/libs/x86"
		;;
	x86_64)
		ARCH_NAME="x86_64"
		TARGET="${BUILD_ROOT}/libs/x86_64"
		;;
	*)
		die "unknown arch: $1"
		;;
	esac

	LIB_NAME="${TARGET}/libffmpeg.mx.so"
	TARGET_LIB_NAME="${LIB_NAME}.${ARCH_NAME}.${VERSION}"
	TARGET_ARCHIVE_NAME="${OUTPUT_DIR}/${ARCH_NAME}-${VERSION}-build_${BUILD_NUMBER}.zip"
	TARGET_AIO_ARCHIVE_NAME="${OUTPUT_DIR}/aio-${VERSION}-build_${BUILD_NUMBER}.zip"

	if [[ ! -d "$TARGET" ]]; then
		execute mkdir -p "$TARGET"
	else
		execute find "$TARGET" \( -iname "*.so" -or -iname "*.a" \) -not -iname "libmx*.so" -exec rm {} +
	fi

	log "========== building codec for $i =========="
	execute "${PWD}/build-libmp3lame.sh" "$1"
	execute "${PWD}/build-openssl.sh" "$1"
	execute "${PWD}/build-libsmb2.sh" "$1"
	execute "${PWD}/build-libdav1d.sh" "$1"
	execute "${PWD}/build-ffmpeg.sh" "$1"

	if [[ -f "$LIB_NAME" ]]; then
		execute mv "$LIB_NAME" "$TARGET_LIB_NAME"
	else
		die "unable to locate the artifact. check the build logs for more info"
	fi

	if [[ -f "$TARGET_LIB_NAME" ]]; then
		execute zip -qj9 "$TARGET_ARCHIVE_NAME" "$TARGET_LIB_NAME"
		execute zip -qj9 "$TARGET_AIO_ARCHIVE_NAME" "$TARGET_LIB_NAME"
		execute rm -f "$TARGET_LIB_NAME"
	else
		die "no artifact found in the output directory. check the build logs for more info"
	fi
}

build_all() {
	for i in arm64 neon x86 x86_64; do
		build "$i"
	done
}

if [[ -z $GITHUB_ACTIONS ]]; then
	execute curl -#LR "${MX_FF_SRC_URL}" -o "${SCRIPT_DIR}/ffmpeg_src.tar.gz"
	[[ -d "${MX_FF_SRC_DIR}" ]] && execute rm -rfd "${MX_FF_SRC_DIR}"
	execute mkdir -p "${MX_FF_SRC_DIR}"
	execute tar --strip-components=1 -C "${MX_FF_SRC_DIR}" -xzf "${SCRIPT_DIR}/ffmpeg_src.tar.gz"
else
	execute git -C "${MX_FF_SRC_DIR}" clean -ffdx
	execute git -C "${MX_FF_SRC_DIR}" reset --hard HEAD
fi

cd "${BUILD_ROOT}" || die "failed to switch to source directory"

perl -i -pe 's/(FF_FEATURES\+=\$FF_FEATURE_(DEMUXER|DECODER|MISC))/# $1/g' config-ffmpeg.sh
perl -i -pe 's/#\!\/bin\/sh/#\!\/usr\/bin\/env bash/g' ffmpeg/configure # too many shift error may occur when the configure script is called on a posix compliant shell.

if [[ -z "$1" ]]; then
	clean "${OUTPUT_DIR}"
	build_all
else
	case "$1" in
	all)
		clean "${OUTPUT_DIR}"
		build_all
		;;
	clean)
		clean "${OUTPUT_DIR}"
		;;
	*)
		build "$1"
		;;
	esac
fi
