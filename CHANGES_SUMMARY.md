# FLEX Dylib Injection - Changes Summary

## Overview

FLEX has been successfully modified to support injection as a dynamic library (dylib) for debugging iOS apps on **non-jailbroken devices**. When injected, FLEX automatically initializes and displays its debugging interface without requiring any code changes to the target app.

## Files Created

### 1. `Classes/FLEXDylibEntry.m`
- **Purpose**: Entry point that auto-initializes FLEX when the dylib is loaded
- **Key Features**:
  - Uses `__attribute__((constructor))` to run automatically on dylib load
  - Ensures initialization happens on the main thread
  - Waits 0.5 seconds for app initialization before showing FLEX
  - Includes error handling and logging

### 2. `DYLIB_INJECTION.md`
- **Purpose**: Comprehensive guide for building and injecting FLEX
- **Contents**:
  - Step-by-step build instructions
  - Xcode project configuration
  - Code signing requirements
  - Injection methods (Frida, etc.)
  - Troubleshooting guide

### 3. `QUICKSTART_DYLIB.md`
- **Purpose**: Quick reference for experienced users
- **Contents**: Condensed build and injection steps

### 4. `build_dylib.sh`
- **Purpose**: Helper script with build instructions
- **Features**: Color-coded output, step-by-step guidance

### 5. `entitlements.plist`
- **Purpose**: Code signing entitlements template
- **Contents**: Required entitlements for dylib injection on non-jailbroken devices

## How It Works

1. **Dylib Load**: When the dylib is injected into an app, the constructor function `FLEXDylibInit()` runs automatically
2. **Thread Safety**: The constructor checks if it's on the main thread; if not, it dispatches to the main queue
3. **Delayed Initialization**: Waits 0.5 seconds to allow the app to fully initialize
4. **Auto-Show**: Calls `[[FLEXManager sharedManager] showExplorer]` to display FLEX automatically
5. **Error Handling**: Wraps initialization in try-catch to prevent crashes

## Compatibility

### ✅ Works On
- Non-jailbroken iOS devices (with Developer Mode)
- iOS 26.0 and later (device only)
- All FLEX features (except some advanced system log hooks)

### ⚠️ Limitations
- Requires proper code signing with Apple Developer certificate
- Requires Developer Mode enabled (iOS 16+)
- Some apps may detect and prevent dylib injection
- System log hooks that require Substrate won't work (but won't crash)

### 🔒 Security Notes
- The existing Substrate dependency in `FLEXSystemLogViewController.m` is optional
- It gracefully falls back if Substrate is not available
- No jailbreak-specific code was added; only non-jailbreak compatible code

## Modernisation (2026)

### Build script (`build_dylib.sh`)
- **Device-only builds**: `./build_dylib.sh` (default) and `./build_dylib.sh arm64e` target `iphoneos`; simulator slices were removed since FLEX is injected on device
- **arm64e support**: `./build_dylib.sh arm64e` builds a slice for A12+ devices that run arm64e
- **Explicit target triples** (`arm64-apple-ios26.0`) instead of relying on arch/SDK inference
- **Parallel compilation**: source files compile across all CPU cores (`FLEX_JOBS` to override) — ~176 files no longer compile serially
- **Modern defaults**: minimum iOS bumped to **26.0** (`MIN_IOS_VERSION` env override), warning flags tuned for current clang (`-Wno-unguarded-availability-new`, `-Wno-nullability-completeness`), `-dead_strip` at link time
- **Flexible signing**: `--sign "Identity"`, `--no-sign`, or automatic `Apple Development` certificate discovery
- **Robust builds**: object files mirror the source tree (no basename collisions), per-file compile logs, reliable error reporting (the old `PIPESTATUS`/`grep` pipe trick is gone)

### Entry point (`Classes/FLEXDylibEntry.m`)
- Initialization wrapped in `dispatch_once`, so loading the dylib twice can never double-swizzle `UIApplication`
- Block-based `NSTimer` API (iOS 10+) instead of target/selector timers
- Works unchanged with scene-based (iOS 13+) apps — all touches still flow through `-[UIApplication sendEvent:]`

### FLEX core compatibility
- Replaced all direct `UIApplication.sharedApplication.keyWindow` access (deprecated since iOS 13, returns nil in multi-scene apps) with the scene-aware `FLEXUtility.appKeyWindow` in: `FLEXTableViewController`, `FLEXExplorerViewController`, `FLEXWindowManagerController`, `FLEXManager+Extensibility`, `FLEXColor`

### Packaging & CI
- `Package.swift` modernized: swift-tools-version 5.9, minimum iOS 26
- Added `.github/workflows/build-dylib.yml` — macOS GitHub Actions build producing the device dylib (`FLEX-device.dylib`) artifact
- Removed dead `.travis.yml` (referenced a workspace that doesn't exist; Travis CI is retired)
- All deployment targets raised to **iOS 26.0**: `FLEX.xcodeproj` (framework + tests), `FLEX.podspec`, `Package.swift`, and the Example projects

## Next Steps

To use this:

1. **Build the dylib** (see `DYLIB_INJECTION.md` or `QUICKSTART_DYLIB.md`)
2. **Code sign** the dylib with your Apple Developer certificate
3. **Inject** using Frida or another injection tool
4. **Debug** - hold three fingers for 0.5s to toggle FLEX!

## Testing

The dylib entry point has been created and should work when:
- Properly built as a dynamic library
- Code signed correctly
- Injected into an app using Frida or similar tool

To test:
1. Build the dylib following the instructions
2. Inject into a test app
3. Verify FLEX appears automatically
4. Test all FLEX features to ensure compatibility

## Technical Details

- **Constructor Priority**: Uses default constructor priority (runs after all +load methods)
- **Thread Safety**: Properly handles both main thread and background thread injection
- **Error Handling**: Catches exceptions to prevent app crashes
- **Logging**: Logs success/failure for debugging injection issues

## Modernisation

- **SF Symbols everywhere** - all emoji UI icons replaced with native SF Symbols, and the legacy bundled PNG toolbar/bar/content icons swapped for SF Symbols (crisp at any scale, adaptive to the system tint)
  - Every globals-menu row now shows a themed SF Symbol icon
  - Database table sort arrows use `arrow.up` / `arrow.down` symbol images
  - The FLEX home screen uses a custom title view with a wrench symbol
- **Quick Actions** - new section at the top of the FLEX menu for on-the-go debugging:
  - Simulate Memory Warning (triggers the private `_performMemoryWarning`)
  - Toggle Idle Timer (prevent/allow screen auto-lock, with state feedback)
  - Suspend App (backgrounds the app immediately)
  - Copy Bundle ID and Copy App Version + build to the pasteboard
- **System log** - the System Log now decodes entries through LoggingSupport's
  `OSActivityEvent` wrapper instead of reading the legacy activity-stream
  structs directly, which fixes host-app crashes on modern iOS and avoids the
  `<compose failure [corrupt log]>` marker
  - FLEX's own messages and system UI noise (scrolling, layout, focus,
    keyboard, and other screen-interaction chatter) are filtered out by
    default, keeping the stream readable; both filters can be toggled in the
    log's settings
- **Instance picker** - method-calling arguments now have an "Instance" mode
  that scans the heap and lists live instances of the argument class and its
  subclasses, so you can pass real objects without digging through the debugger
  - The picker now surfaces well-known singletons and app objects (app,
    delegate, key window, root view controller, notification center, defaults,
    file manager, screen, device, bundle, pasteboard, process info, URL cache)
    above the heap scan, with a search field to narrow both lists
  - Object-typed arguments default straight to the instance picker, so the
    available options are visible immediately
  - Live instances are now grouped by concrete class with per-group counts,
    the target class is surfaced first, and known singletons are retained for
    the lifetime of the picker (no dangling window/root-view-controller refs)
- **Value pools for `SEL` arguments** - when calling a method or editing a
  selector-typed property, a "Choose" button now lists every selector available
  on the target (instance or class methods, including inherited ones) in a
  searchable picker, instead of requiring free-text entry
- **Value pools for plain `NSString` arguments** - method calls that take a
  string now also offer a searchable "Choose" pool built from KVC key paths on
  the target and the app's user-defaults keys up front, then lazily extends
  itself by scanning the heap (live `NSString` instances) and the Objective-C
  runtime (class and protocol names) — no hardcoded value list
  - String-typed **properties and ivars** get the same searchable "Choose"
    pool in the field editor, so editing a string field is just as easy as
    passing a string to a method
- **Picker navigation fix** - the "Choose" (string/selector) and
  "Choose instance"/"Change instance" buttons now resolve the host navigation
  controller by walking the view's responder chain (`nearestViewControllerForView:`)
  instead of probing the private `_viewDelegate` ivar, which returned nil for
  these input views and made the buttons silently do nothing when tapped
- **Plain `id` instance picking** - object arguments typed as plain `id` (no
  class hint) now offer the instance picker over the whole heap, grouped by
  class with per-class limits so a few hot classes can't crowd out the rest;
  `Class`-typed (`#`) arguments stay excluded since class objects are not
  guaranteed to be heap allocations
- **Modern pickers** - the selector, string, and instance pickers now use the
  iOS 26 inset-grouped list style so they match the rest of the modernized UI
- **Liquid Glass design (iOS 26)** - the explorer toolbar is now a floating
  glass pill (`UIGlassEffect`) with continuous-corner highlights and a
  matching glass caption under the selected-view description; navigation and
  toolbars use the frosted `systemChromeMaterial` appearance with no hairline,
  matching the modern system look

## Notes

- This modification does not break existing FLEX functionality
- The dylib entry point is only active when built as a dylib
- Regular FLEX integration (CocoaPods, manual, etc.) is unaffected
- All existing FLEX features work when injected as a dylib

