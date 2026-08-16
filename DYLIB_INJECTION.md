# FLEX Dylib Injection Guide

This guide explains how to build and inject FLEX as a dynamic library into iOS apps without requiring a jailbreak.

## Overview

FLEX has been modified to support injection as a dylib. When injected, FLEX automatically initializes and shows its debugging interface, allowing you to debug any app on non-jailbroken devices (with proper code signing).

## Requirements

- macOS with Xcode installed
- iOS device with Developer Mode enabled (iOS 16+)
- Apple Developer account (for code signing)
- Injection tool (Frida recommended)

## Building the Dylib

### Option 0: Using the build script (Recommended)

The repo ships a modernized build script that compiles all of `Classes/` directly with clang, in parallel:

```bash
./build_dylib.sh              # arm64 iOS device (default, min iOS 13.0)
./build_dylib.sh arm64e       # arm64e device slice (A12+)
./build_dylib.sh simulator    # universal simulator dylib (arm64 + x86_64)
./build_dylib.sh --no-sign    # skip code signing (sign later, e.g. in CI)
```

- Output: `Build/FLEX.dylib` (universal for simulator builds via `lipo`)
- Deployment target defaults to iOS 13.0; override with `MIN_IOS_VERSION=15.0 ./build_dylib.sh`
- Code signing uses an `Apple Development` certificate automatically, or pass `--sign "Identity"`
- Set `FLEX_JOBS` to control parallelism (defaults to CPU core count)

### Option 1: Using Xcode

1. Open `FLEX.xcodeproj` in Xcode

2. Create a new target:
   - Go to **File > New > Target**
   - Select **Framework** under iOS
   - Name it `FLEXDylib`
   - Click **Finish**

3. Configure the target:
   - Select the `FLEXDylib` target
   - Go to **Build Settings**
   - Set **Mach-O Type** to `Dynamic Library`
   - Set **Installation Directory** to `@rpath`
   - Set **Code Signing Identity** to your Apple Development certificate
   - Add `-fobjc-arc` to **Other C Flags** if needed

4. Add source files:
   - Right-click on the `FLEXDylib` target
   - Select **Add Files to "FLEX"...**
   - Navigate to `Classes/` folder
   - Select all files and folders
   - Make sure **"Copy items if needed"** is unchecked
   - Make sure **"Create groups"** is selected
   - Make sure **"Add to targets: FLEXDylib"** is checked
   - Click **Add**

5. Add the entry point:
   - Add `Classes/FLEXDylibEntry.m` to the target (should already be in the project)

6. Build:
   ```bash
   xcodebuild -project FLEX.xcodeproj \
              -target FLEXDylib \
              -configuration Release \
              -arch arm64 \
              -sdk iphoneos \
              CODE_SIGN_IDENTITY="Apple Development" \
              DEVELOPMENT_TEAM="YOUR_TEAM_ID"
   ```

7. The dylib will be at:
   ```
   Build/Release-iphoneos/FLEXDylib.framework/FLEXDylib
   ```

### Option 2: Using Makefile (Advanced)

A Makefile can be created for automated building. See `Makefile.dylib` (if provided).

## Injection Methods

### Method 1: Using Frida (Recommended)

1. Install Frida:
   ```bash
   pip install frida-tools
   ```

2. Install Frida on your iOS device:
   - For non-jailbroken devices, you need to use Frida's injection server
   - See Frida documentation for device setup

3. Inject FLEX:
   ```bash
   frida -U -f com.example.app -l Build/FLEX.dylib
   ```

### Method 2: Using Other Injection Tools

Various tools support dylib injection on non-jailbroken devices:
- **Sideloadly** (with modifications)
- **AltStore** (with custom dylib support)
- Custom injection tools

**Note:** All injection methods require:
- Developer certificate code signing
- Device with Developer Mode enabled
- Proper entitlements

## Code Signing

The dylib must be properly code signed to work on non-jailbroken devices:

```bash
codesign --force --sign "Apple Development: Your Name" \
         --entitlements entitlements.plist \
         FLEXDylib.framework/FLEXDylib
```

Create `entitlements.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
```

## How It Works

When the dylib is loaded:

1. The `__attribute__((constructor))` function `FLEXDylibInit()` runs automatically
2. It ensures initialization happens on the main thread
3. After a short delay (0.5 seconds) to let the app initialize, it calls `[FLEXManager sharedManager] showExplorer]`
4. FLEX's debugging interface appears automatically

## Troubleshooting

### Dylib doesn't load
- Check code signing
- Verify entitlements
- Ensure Developer Mode is enabled on device

### FLEX doesn't appear
- Check device logs for errors
- Verify the dylib was actually injected
- Try manually calling `[[FLEXManager sharedManager] showExplorer]` in your injection script

### App crashes
- Some apps have anti-debugging measures
- Try injecting at different points in the app lifecycle
- Check for conflicts with other injected libraries

## Limitations

1. **Code Signing Required**: The dylib must be signed with a valid developer certificate
2. **Developer Mode**: iOS 16+ requires Developer Mode to be enabled
3. **App Restrictions**: Some apps detect and prevent dylib injection
4. **System Log**: Some system log features may be limited on non-jailbroken devices (Substrate hooks won't work)

## Legal Notice

Only use this tool on apps you own or have explicit permission to debug. Unauthorized modification of apps may violate terms of service and applicable laws.

## Support

For issues specific to dylib injection, please check:
- FLEX main repository: https://github.com/FLEXTool/FLEX
- Frida documentation: https://frida.re/docs/

