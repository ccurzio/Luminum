#!/usr/bin/env bash
#
# Luminum Client (macOS) build script
# by Christopher R. Curzio (ccurzio@luminum.net)
#
# Builds the client in release mode and stages the binary in dist/ for
# install.sh:
#
#   dist/LuminumClient
#
# Usage: bash build.sh [--arch <arch>]
#
#   --arch arm64       build for Apple Silicon (aarch64-apple-darwin)
#   --arch x86_64      build for Intel (x86_64-apple-darwin)
#   --arch universal   build both and lipo them into a universal binary
#   (default)          build for the host architecture
#
# Requires the Xcode command line tools (clang) for the ring dependency.
#
set -eu

ARCH=""
while [ $# -gt 0 ]; do
	case "$1" in
		--arch) ARCH="${2:?--arch requires a value}"; shift 2 ;;
		-h|--help)
			cat <<'USAGE'
Usage: bash build.sh [--arch <arch>]

  --arch arm64|x86_64|universal   target architecture (default: host)
USAGE
			exit 0 ;;
		*) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
	esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

DIST="$SCRIPT_DIR/dist"
mkdir -p "$DIST"

build_arch() {
	# $1 = rust target triple (empty = host)
	local target="$1"
	if [ -n "$target" ]; then
		cargo build --release --target "$target"
		cp "target/$target/release/LuminumClient" "$DIST/LuminumClient-$2"
	else
		cargo build --release
		cp target/release/LuminumClient "$DIST/LuminumClient-$2"
	fi
}

case "$ARCH" in
	""|native)
		build_arch "" "$(uname -m)"
		cp "$DIST/LuminumClient-$(uname -m)" "$DIST/LuminumClient"
		rm -f "$DIST/LuminumClient-$(uname -m)"
		;;
	arm64)
		build_arch aarch64-apple-darwin arm64
		cp "$DIST/LuminumClient-arm64" "$DIST/LuminumClient"
		rm -f "$DIST/LuminumClient-arm64"
		;;
	x86_64)
		build_arch x86_64-apple-darwin x86_64
		cp "$DIST/LuminumClient-x86_64" "$DIST/LuminumClient"
		rm -f "$DIST/LuminumClient-x86_64"
		;;
	universal)
		build_arch aarch64-apple-darwin arm64
		build_arch x86_64-apple-darwin x86_64
		lipo -create "$DIST/LuminumClient-arm64" "$DIST/LuminumClient-x86_64" -output "$DIST/LuminumClient"
		rm -f "$DIST/LuminumClient-arm64" "$DIST/LuminumClient-x86_64"
		;;
	*)
		echo "ERROR: unknown arch: $ARCH (use arm64, x86_64, or universal)" >&2
		exit 1
		;;
esac

echo
echo "Built: $DIST/LuminumClient"
lipo -info "$DIST/LuminumClient" 2>/dev/null || file "$DIST/LuminumClient"
