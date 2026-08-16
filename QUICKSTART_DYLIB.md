# Quick Start: FLEX Dylib Injection

## What Was Changed

FLEX has been modified to support injection as a dynamic library (dylib) for debugging apps on non-jailbroken iOS devices.

### Key Files Added/Modified

1. **`Classes/FLEXDylibEntry.m`** - Entry point that auto-initializes FLEX when the dylib is loaded (idempotent, gesture-based toggle)
2. **`DYLIB_INJECTION.md`** - Comprehensive guide for building and injecting
3. **`build_dylib.sh`** - Modern build script (arm64 / arm64e device slices, parallel compilation)
4. **`entitlements.plist`** - Code signing entitlements template

## Quick Build Steps

### Automated Build (Recommended)

Simply run the build script:

```bash
./build_dylib.sh
```

This will:
- Automatically find all source files
- Compile them in parallel using clang
- Link into a dylib
- Code sign (if a certificate is available, or pass `--sign "Identity"`)
- Output: `Build/FLEX.dylib`

**For iOS Device (arm64, default):**
```bash
./build_dylib.sh arm64
```

**For iOS Device on A12+ (arm64e, optional):**
```bash
./build_dylib.sh arm64e
```

**Signing options:**
```bash
./build_dylib.sh arm64 --sign "Apple Development: Your Name"   # explicit identity
./build_dylib.sh arm64 --no-sign                                # skip signing
```

**Other options:**
```bash
MIN_IOS_VERSION=26.0 ./build_dylib.sh    # raise minimum iOS version (default 26.0)
FLEX_JOBS=8 ./build_dylib.sh             # control parallel compile jobs
```

### Manual Xcode Build (Alternative)

If you prefer using Xcode:

1. **Open Xcode project:**
   ```bash
   open FLEX.xcodeproj
   ```

2. **Create Framework target:**
   - File > New > Target > Framework
   - Name: `FLEXDylib`

3. **Configure target:**
   - Mach-O Type: `Dynamic Library`
   - Installation Directory: `@rpath`
   - Add all files from `Classes/` folder

4. **Build:**
   ```bash
   xcodebuild -project FLEX.xcodeproj \
              -target FLEXDylib \
              -configuration Release \
              -arch arm64 \
              -sdk iphoneos \
              CODE_SIGN_IDENTITY="Apple Development" \
              DEVELOPMENT_TEAM="YOUR_TEAM_ID"
   ```

### Inject with Frida

```bash
frida -U -f com.example.app -l Build/FLEX.dylib
```

## How It Works

When the dylib is injected:
- The `__attribute__((constructor))` function runs automatically
- FLEX initializes on the main thread (guarded so it can never run twice)
- Holding **three fingers for 0.5 seconds** toggles the FLEX explorer
- No manual code changes needed in the target app

## Requirements

- ✅ macOS with Xcode (any recent version; iOS SDK required)
- ✅ iOS device with Developer Mode enabled (iOS 16+)
- ✅ Apple Developer account (for signing; unsigned dylibs can be signed later)
- ✅ Frida or similar injection tool
- ✅ Proper code signing

## Notes

- The Substrate dependency in SystemLog is optional and won't break on non-jailbroken devices
- All FLEX features work except some advanced system log hooks that require Substrate
- The dylib must be properly code signed to work on non-jailbroken devices
- The build script defaults to a minimum iOS of 26.0 (`MIN_IOS_VERSION` to override)

## Troubleshooting

**FLEX doesn't appear:**
- Check device logs: `idevicesyslog | grep FLEX`
- Verify dylib was injected successfully
- Ensure app has proper entitlements
- Remember it's a **3-finger hold**, not auto-show

**Build errors:**
- Make sure all source files are added to the FLEXDylib target
- Verify FLEXDylibEntry.m is included
- Check code signing settings

For detailed information, see `DYLIB_INJECTION.md`.
