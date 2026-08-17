#!/bin/bash
# Build script for FLEX dylib injection (modernized)
# Compiles FLEX directly with clang into an injectable dynamic library.
#
# Usage:
#   ./build_dylib.sh [mode] [--sign "Identity"] [--no-sign]
#
# Modes:
#   arm64       iOS device, arm64            (default)
#   arm64e      iOS device, arm64e (A12+)    (optional, needs matching signing)
#
# Environment:
#   MIN_IOS_VERSION   minimum iOS deployment version (default 26.0)
#   FLEX_JOBS         parallel compile jobs      (default: CPU core count)
#
# Examples:
#   ./build_dylib.sh                       # device arm64
#   ./build_dylib.sh arm64e                # device arm64e (A12+)
#   ./build_dylib.sh arm64 --no-sign       # device, skip code signing
#   ./build_dylib.sh arm64 --sign "Apple Development: Jane Doe"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_DIR/Build"
OBJ_ROOT="$BUILD_DIR/Objects"
DYLIB_NAME="FLEX.dylib"
OUTPUT_DYLIB="$BUILD_DIR/$DYLIB_NAME"
ENTITLEMENTS="$PROJECT_DIR/entitlements.plist"

# Defaults (override via environment)
MIN_IOS_VERSION="${MIN_IOS_VERSION:-26.0}"
JOBS="${FLEX_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
JOBS=$(( JOBS < 1 ? 1 : JOBS ))

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [arm64|arm64e] [--sign \"Identity\"] [--no-sign]"
    echo "  MIN_IOS_VERSION env var overrides the deployment target (default 26.0)"
    exit 0
}

# ---------------------------------------------------------------- args

MODE="arm64"
SIGN_IDENTITY=""
NO_SIGN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)      SIGN_IDENTITY="${2:?--sign requires a code signing identity}"; shift 2 ;;
        --no-sign)   NO_SIGN=1; shift ;;
        -h|--help)   usage ;;
        *)           MODE="$1"; shift ;;
    esac
done

case "$MODE" in
    arm64|arm64e)
        TARGET_SDK="iphoneos"
        ARCHS=("$MODE")
        ;;
    *)
        echo -e "${RED}Unknown mode: $MODE${NC}"
        usage
        ;;
esac

echo -e "${GREEN}Building FLEX as injectable dylib${NC} (mode: $MODE, min iOS: $MIN_IOS_VERSION, jobs: $JOBS)"

# ---------------------------------------------------------------- toolchain

if ! command -v xcrun &> /dev/null; then
    echo -e "${RED}Error: xcrun not found. Please install Xcode.${NC}"
    exit 1
fi

CC="$(xcrun --find clang)"

SDK_PATH="$(xcrun --sdk "$TARGET_SDK" --show-sdk-path 2>/dev/null || true)"
if [[ -z "$SDK_PATH" ]]; then
    echo -e "${RED}Error: Could not find the $TARGET_SDK SDK. Install Xcode or run 'sudo xcode-select -s'.${NC}"
    exit 1
fi
echo -e "${BLUE}Using $TARGET_SDK SDK: $SDK_PATH${NC}"

# ---------------------------------------------------------------- sources

echo -e "${BLUE}Collecting source files...${NC}"
SOURCES=()
while IFS= read -r -d '' file; do
    SOURCES+=("$file")
done < <(find "$PROJECT_DIR/Classes" -type f \( -name "*.m" -o -name "*.mm" -o -name "*.c" \) ! -path "*/Headers/*" -print0)

# Make sure the dylib entry point is included
if ! printf '%s\n' "${SOURCES[@]}" | grep -q "FLEXDylibEntry.m"; then
    if [[ -f "$PROJECT_DIR/Classes/FLEXDylibEntry.m" ]]; then
        SOURCES+=("$PROJECT_DIR/Classes/FLEXDylibEntry.m")
        echo -e "${GREEN}Added FLEXDylibEntry.m${NC}"
    else
        echo -e "${RED}Warning: FLEXDylibEntry.m not found — the dylib will not auto-initialize!${NC}"
    fi
fi
echo -e "${GREEN}Found ${#SOURCES[@]} source files${NC}"

# ---------------------------------------------------------------- swift sources

SWIFT_FILES=()
while IFS= read -r -d '' file; do
    SWIFT_FILES+=("$file")
done < <(find "$PROJECT_DIR/Classes" -type f -name "*.swift" -print0)
if [[ ${#SWIFT_FILES[@]} -gt 0 ]]; then
    echo -e "${BLUE}Found ${#SWIFT_FILES[@]} Swift source files${NC}"
fi

# ---------------------------------------------------------------- flags

COMMON_FLAGS=(
    -isysroot "$SDK_PATH"
    -mios-version-min="$MIN_IOS_VERSION"
    -fobjc-arc
    -fobjc-weak
    -fmodules
    -fPIC
    -O2
    -g
    # FLEX targets old APIs by design; silence the noise for a debug tool
    -Wno-unsupported-availability-guard
    -Wno-unguarded-availability-new
    -Wno-deprecated-declarations
    -Wno-strict-prototypes
    -Wno-nullability-completeness
)

FRAMEWORKS=(
    -framework Foundation
    -framework UIKit
    -framework CoreGraphics
    -framework ImageIO
    -framework QuartzCore
    -framework WebKit
    -framework Security
    -framework SceneKit
    -framework SwiftUI
)

LIBS=(
    -lz
    -lsqlite3
    -lc++
)

INCLUDES=(-I"$SDK_PATH/usr/include")
while IFS= read -r -d '' dir; do
    INCLUDES+=(-I"$dir")
done < <(find "$PROJECT_DIR/Classes" -type d -print0)

# ---------------------------------------------------------------- compile

compile_arch() {
    local arch="$1"
    local sdk="$2"
    local target="$3"
    local objdir="$OBJ_ROOT/$arch"
    local logdir="$objdir/logs"
    local cflags_file="$objdir/cflags.txt"
    local includes_file="$objdir/includes.txt"

    echo -e "${BLUE}Compiling $arch (target: $target)...${NC}"
    rm -rf "$objdir"
    mkdir -p "$logdir"

    printf '%s\n' "${COMMON_FLAGS[@]}" -target "$target" > "$cflags_file"
    printf '%s\n' "${INCLUDES[@]}" > "$includes_file"

    local jobs_file="$objdir/jobs.txt"
    : > "$jobs_file"

    for src in "${SOURCES[@]}"; do
        local rel="${src#$PROJECT_DIR/}"
        local obj="$objdir/${rel%.*}.o"
        local lang="objc"
        [[ "$src" == *.mm ]] && lang="objcxx"
        [[ "$src" == *.c ]] && lang="c"
        mkdir -p "$(dirname "$obj")"
        echo "$src|$obj|$lang" >> "$jobs_file"
    done

    export CC objdir logdir

    if ! xargs -P "$JOBS" -n1 bash -c '
        IFS="|" read -r src obj lang <<< "$1"
        local_flags=()
        while IFS= read -r f; do local_flags+=("$f"); done < "$objdir/cflags.txt"
        local_includes=()
        while IFS= read -r f; do local_includes+=("$f"); done < "$objdir/includes.txt"
        case "$lang" in
            objcxx) lang_flags=(-x objective-c++ -std=gnu++14) ;;
            c)      lang_flags=(-x c) ;;
            *)      lang_flags=(-x objective-c) ;;
        esac
        log="$logdir/$(basename "$src").log"
        if ! "$CC" "${local_flags[@]}" "${lang_flags[@]}" "${local_includes[@]}" \
             -c "$src" -o "$obj" > "$log" 2>&1; then
            echo "  FAILED: $src" >&2
            tail -25 "$log" >&2
            exit 1
        fi
    ' _ < "$jobs_file"; then
        echo -e "${RED}Compilation failed for $arch${NC}"
        return 1
    fi

    # ------------------------------------------------------------ swift compile
    if [[ ${#SWIFT_FILES[@]} -gt 0 ]]; then
        echo -e "${BLUE}Compiling Swift for $arch...${NC}"
        local swift_obj="$objdir/SwiftUI.o"
        local swift_log="$logdir/swift.log"
        local bridging_header="$PROJECT_DIR/Classes/SwiftUI/FLEX-Bridging-Header.h"
        if ! xcrun swiftc \
            -target "$target" \
            -sdk "$sdk" \
            -module-name FLEX \
            -import-objc-header "$bridging_header" \
            -emit-object \
            -o "$swift_obj" \
            "${SWIFT_FILES[@]}" > "$swift_log" 2>&1; then
            echo "  FAILED: Swift compilation" >&2
            tail -40 "$swift_log" >&2
            return 1
        fi
    fi

    local obj_count
    obj_count="$(find "$objdir" -name '*.o' | wc -l | tr -d ' ')"
    echo -e "${GREEN}Compiled $obj_count object files for $arch${NC}"
    return 0
}

echo -e "${BLUE}Cleaning previous builds...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$OBJ_ROOT"

PER_ARCH_DYLIB=()
for arch in "${ARCHS[@]}"; do
    target="$arch-apple-ios$MIN_IOS_VERSION"
    if ! compile_arch "$arch" "$SDK_PATH" "$target"; then
        exit 1
    fi
    PER_ARCH_DYLIB+=("$BUILD_DIR/FLEX-$arch.dylib")
done

# ---------------------------------------------------------------- link

for arch in "${ARCHS[@]}"; do
    target="$arch-apple-ios$MIN_IOS_VERSION"
    echo -e "${BLUE}Linking $arch dylib...${NC}"
    OBJECT_FILES=()
    while IFS= read -r f; do OBJECT_FILES+=("$f"); done < <(find "$OBJ_ROOT/$arch" -name '*.o' | sort)
    # Link through the swiftc driver so the Swift runtime is linked correctly
    # (the dylib contains SwiftUI code compiled from the Classes/SwiftUI sources).
    xcrun swiftc \
        -target "$target" \
        -sdk "$SDK_PATH" \
        -emit-library \
        -module-name FLEX \
        -Xlinker -install_name -Xlinker "@rpath/$DYLIB_NAME" \
        -Xlinker -compatibility_version -Xlinker 1.0 \
        -Xlinker -current_version -Xlinker 1.0 \
        -Xlinker -dead_strip \
        "${OBJECT_FILES[@]}" \
        "${FRAMEWORKS[@]}" \
        "${LIBS[@]}" \
        -o "$BUILD_DIR/FLEX-$arch.dylib"
done

# ---------------------------------------------------------------- lipo

if [[ "${#PER_ARCH_DYLIB[@]}" -gt 1 ]]; then
    echo -e "${BLUE}Creating universal dylib with lipo...${NC}"
    lipo -create "${PER_ARCH_DYLIB[@]}" -output "$OUTPUT_DYLIB"
else
    cp "${PER_ARCH_DYLIB[0]}" "$OUTPUT_DYLIB"
fi

if [[ ! -f "$OUTPUT_DYLIB" ]]; then
    echo -e "${RED}Error: Failed to create dylib${NC}"
    exit 1
fi

# ---------------------------------------------------------------- codesign

if [[ "$NO_SIGN" != "1" ]]; then
    if command -v codesign &> /dev/null; then
        IDENTITY="$SIGN_IDENTITY"
        if [[ -z "$IDENTITY" ]] && command -v security &> /dev/null; then
            IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
                | grep "Apple Development" | head -1 \
                | sed 's/.*"\(.*\)".*/\1/' || true)
        fi

        if [[ -n "$IDENTITY" ]]; then
            echo -e "${BLUE}Code signing with: $IDENTITY${NC}"
            if [[ -f "$ENTITLEMENTS" ]]; then
                codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$OUTPUT_DYLIB" \
                    || echo -e "${YELLOW}Warning: Code signing failed, but the dylib was created.${NC}"
            else
                codesign --force --sign "$IDENTITY" "$OUTPUT_DYLIB" \
                    || echo -e "${YELLOW}Warning: Code signing failed, but the dylib was created.${NC}"
            fi
        else
            echo -e "${YELLOW}No Apple Development certificate found — dylib left unsigned.${NC}"
            echo -e "${YELLOW}  Sign manually: codesign --force --sign \"Apple Development: Your Name\" --entitlements $ENTITLEMENTS \"$OUTPUT_DYLIB\"${NC}"
        fi
    fi
else
    echo -e "${YELLOW}Skipping code signing (--no-sign)${NC}"
fi

# ---------------------------------------------------------------- done

echo ""
echo -e "${GREEN}=========================================="
echo "Build Complete!"
echo "==========================================${NC}"
echo ""
echo -e "Dylib location: ${GREEN}$OUTPUT_DYLIB${NC}"
echo -e "Size: $(du -h "$OUTPUT_DYLIB" | cut -f1)"
echo -e "Slices: $(lipo -info "$OUTPUT_DYLIB" | sed 's/^[^:]*: //')"
echo ""
echo -e "To inject with Frida:"
echo -e "  ${YELLOW}frida -U -f com.example.app -l \"$OUTPUT_DYLIB\"${NC}"
echo -e "  Hold three fingers for 0.5s to toggle FLEX."
echo ""
