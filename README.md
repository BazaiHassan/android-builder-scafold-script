# setup-app.sh

A Bash script that scaffolds a production-ready Android project from scratch — no Android Studio required. Designed for **Fedora Linux**, using **Kotlin**, **Jetpack Compose**, and a **Gradle Version Catalog** (TOML).

---

## Requirements

Make sure the following are installed and accessible before running the script.

| Tool | Required | Notes |
|---|---|---|
| JDK 17+ | ✅ Yes | `sudo dnf install java-17-openjdk-devel` |
| Android SDK | ✅ Yes | Set `ANDROID_HOME` or `ANDROID_SDK_ROOT` env var |
| Gradle binary | ⚠️ Optional | Pass the path, or let the script generate a wrapper |
| `adb` | ⚠️ Optional | Needed only for device deployment |
| `ktlint` | ⚠️ Optional | Detected if installed; used for linting |
| `curl` or `wget` | ⚠️ Optional | Needed to auto-download `gradle-wrapper.jar` |

The script checks all of the above automatically and will error or warn accordingly.

---

## Usage

```bash
chmod +x setup-app.sh
./setup-app.sh
```

The script is fully interactive — it will prompt you for everything it needs.

---

## Step-by-step walkthrough

### Step 1 — Gradle binary

```
Gradle binary path (leave empty = use wrapper):
```

You have two options:

**Option A — provide your local Gradle binary** (recommended if Gradle is already installed):

```
/opt/gradle/gradle-8.13/bin/gradle
```

The script will validate the path is executable, then generate a thin `./gradlew` wrapper inside your project that delegates to your binary.

**Option B — leave it empty** to auto-generate a full Gradle Wrapper. The script will create `gradlew`, `gradle-wrapper.properties`, and attempt to download `gradle-wrapper.jar` via `curl` or `wget`.

---

### Step 2 — Environment checks

The script automatically checks:

- **Java** — detects version, warns if below 17
- **Android SDK** — reads `ANDROID_HOME` / `ANDROID_SDK_ROOT`, or prompts you to enter the path; validates that `platforms/` exists
- **Highest installed SDK platform** — auto-detected from `$ANDROID_SDK/platforms/`, used as the default for `compileSdk`
- **adb** — warns (non-fatal) if missing
- **ktlint** — detected if installed; skipped if not

---

### Step 3 — Project configuration prompts

All prompts have defaults (shown in yellow). Press Enter to accept a default or type your own value.

| Prompt | Default | Required |
|---|---|---|
| Application name | — | ✅ Yes |
| Package name | `com.example.myapp` | No |
| Project directory name | derived from app name | No |
| Output parent directory | `~/Projects` | No |
| Minimum SDK version | `26` | No |
| Compile / Target SDK | highest installed platform | No |
| Kotlin version | `2.0.21` | No |
| Compose BOM version | `2024.12.01` | No |
| AGP version | `8.7.3` | No |
| Gradle wrapper version | `8.11.1` | No (only if using wrapper) |
| App version name | `1.0.0` | No |
| App version code | `1` | No |

> **Gradle wrapper version** is only used when you leave the Gradle binary path empty (Option B above). It must match the Gradle version you want the wrapper to download — e.g. `8.13`.

After confirming, the script shows the full output path and asks for a final confirmation before writing anything to disk.

---

### Step 4 — Optional initial build

At the end, the script offers to run `assembleDebug` immediately:

```
Attempt an initial Gradle sync / build now? [y/N]:
```

If it fails, the script prints common fixes to check.

---

## Generated project structure

```
<your-project>/
├── app/
│   ├── src/
│   │   ├── main/
│   │   │   ├── kotlin/<package>/ 
│   │   │   │   ├── MainActivity.kt
│   │   │   │   ├── screens/
│   │   │   │   │   └── HomeScreen.kt
│   │   │   │   └── ui/theme/
│   │   │   │       ├── Theme.kt
│   │   │   │       └── Type.kt
│   │   │   ├── res/
│   │   │   │   ├── values/
│   │   │   │   │   ├── strings.xml
│   │   │   │   │   └── themes.xml
│   │   │   │   ├── drawable/
│   │   │   │   └── mipmap-*/
│   │   │   └── AndroidManifest.xml
│   │   ├── test/kotlin/<package>/
│   │   └── androidTest/kotlin/<package>/
│   ├── build.gradle.kts
│   └── proguard-rules.pro
├── gradle/
│   ├── libs.versions.toml          ← Version Catalog
│   └── wrapper/                    ← only if using wrapper mode
│       ├── gradle-wrapper.jar
│       └── gradle-wrapper.properties
├── build.gradle.kts                ← root (plugins only)
├── settings.gradle.kts
├── gradle.properties
├── gradlew
├── gradlew.bat
├── local.properties                ← sdk.dir auto-filled
└── .gitignore
```

---

## Generated files overview

### `gradle/libs.versions.toml`

The single source of truth for all dependency versions. Includes:

- AGP, Kotlin, Compose BOM
- AndroidX core, lifecycle, activity, navigation
- Compose UI, Material3
- JUnit, Espresso, Compose test libraries

### `app/build.gradle.kts`

Fully configured for Compose with:

- `buildFeatures { compose = true }`
- `compileOptions` and `kotlinOptions` targeting Java 17
- `isMinifyEnabled = true` for release builds with ProGuard
- All dependencies wired through the version catalog

### `gradle.properties`

Performance-optimized defaults:

```properties
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configuration-cache=true
org.gradle.jvmargs=-Xmx2048m
android.enableJetifier=false
kotlin.code.style=official
```

### `MainActivity.kt`

Edge-to-edge enabled, sets `AppTheme`, launches `HomeScreen`.

### `ui/theme/Theme.kt`

Material3 dynamic color theme with light/dark support. Falls back to static schemes on API < 31.

### `screens/HomeScreen.kt`

A minimal `Scaffold` with a `TopAppBar` — ready to be replaced with your own screens.

---

## Command Reference

A complete reference of commands you'll use throughout the Android development lifecycle.

---

### Gradle — Build

```bash
# Build debug APK
./gradlew assembleDebug

# Build release APK (minified + ProGuard)
./gradlew assembleRelease

# Build both debug and release
./gradlew assemble

# Build Android App Bundle (.aab) for Play Store
./gradlew bundleRelease
./gradlew bundleDebug

# Build and install debug APK on connected device/emulator
./gradlew installDebug

# Build and install release APK on connected device/emulator
./gradlew installRelease

# Uninstall from connected device
./gradlew uninstallDebug
./gradlew uninstallRelease
./gradlew uninstallAll

# Clean all build outputs
./gradlew clean

# Clean then build (useful when cache causes issues)
./gradlew clean assembleDebug
```

### Gradle — Testing

```bash
# Run unit tests (no device needed)
./gradlew test

# Run unit tests for a specific build variant
./gradlew testDebugUnitTest
./gradlew testReleaseUnitTest

# Run instrumented tests on connected device/emulator
./gradlew connectedAndroidTest

# Run instrumented tests for a specific variant
./gradlew connectedDebugAndroidTest

# Generate test coverage report
./gradlew createDebugCoverageReport
```

### Gradle — Code quality

```bash
# Run Android Lint
./gradlew lint

# Run Lint for a specific variant
./gradlew lintDebug
./gradlew lintRelease

# Lint + fix auto-correctable issues (if ktlint Gradle plugin is added)
./gradlew ktlintFormat
./gradlew ktlintCheck
```

### Gradle — Dependencies & project info

```bash
# Print full dependency tree
./gradlew dependencies

# Dependency tree for a specific configuration
./gradlew dependencies --configuration releaseRuntimeClasspath

# Check for outdated dependencies (requires versions plugin)
./gradlew dependencyUpdates

# List all available tasks
./gradlew tasks

# List tasks including sub-tasks
./gradlew tasks --all

# Print project properties
./gradlew properties

# Show the build environment (Java version, Gradle version, etc.)
./gradlew --version
./gradlew buildEnvironment
```

### Gradle — Performance & daemon

```bash
# Run with build scan (uploads report to scans.gradle.com)
./gradlew assembleDebug --scan

# Run with detailed profiling info
./gradlew assembleDebug --profile

# Run without using the Gradle daemon (useful for CI)
./gradlew assembleDebug --no-daemon

# Stop all running Gradle daemons
./gradlew --stop

# Show status of Gradle daemons
./gradlew --status

# Run with extra info logging
./gradlew assembleDebug --info

# Run with debug-level logging
./gradlew assembleDebug --debug

# Dry-run (shows what tasks would run, without executing)
./gradlew assembleDebug --dry-run

# Refresh all dependency caches
./gradlew assembleDebug --refresh-dependencies

# Skip configuration cache (useful when debugging cache issues)
./gradlew assembleDebug --no-configuration-cache
```

### Gradle — Wrapper management

```bash
# Update the wrapper to a specific Gradle version
./gradlew wrapper --gradle-version=8.13

# Verify wrapper checksum (security)
./gradlew wrapper --gradle-version=8.13 --distribution-type=bin

# Show current Gradle version used by the wrapper
./gradlew --version
```

---

### ADB — Device management

```bash
# List all connected devices and emulators
adb devices

# List with full device info
adb devices -l

# Target a specific device (use when multiple are connected)
adb -s <device-serial> <command>

# Restart the ADB server (fixes connection issues)
adb kill-server
adb start-server

# Connect to a device over Wi-Fi (Android 11+)
adb pair <ip>:<pairing-port>       # pair first
adb connect <ip>:<port>            # then connect

# Disconnect a Wi-Fi device
adb disconnect <ip>:<port>
```

### ADB — App management

```bash
# Install an APK
adb install app/build/outputs/apk/debug/app-debug.apk

# Install and replace existing app
adb install -r app/build/outputs/apk/debug/app-debug.apk

# Install allowing version downgrade
adb install -d app/build/outputs/apk/debug/app-debug.apk

# Install to specific device
adb -s <device-serial> install app-debug.apk

# Uninstall an app by package name
adb uninstall com.example.myapp

# Keep data and cache when uninstalling
adb uninstall -k com.example.myapp

# List all installed packages
adb shell pm list packages

# List only third-party (user-installed) packages
adb shell pm list packages -3

# Clear app data and cache (without uninstalling)
adb shell pm clear com.example.myapp
```

### ADB — Launch & activity

```bash
# Launch an app by package and activity name
adb shell am start -n com.example.myapp/.MainActivity

# Force-stop an app
adb shell am force-stop com.example.myapp

# Send a broadcast intent
adb shell am broadcast -a android.intent.action.BOOT_COMPLETED

# Simulate a deep link
adb shell am start -W -a android.intent.action.VIEW \
  -d "myapp://home" com.example.myapp
```

### ADB — Logcat (logs)

```bash
# Stream all logs
adb logcat

# Filter logs by tag
adb logcat -s MyTag

# Filter by package name (Android 7+)
adb logcat --pid=$(adb shell pidof -s com.example.myapp)

# Filter by log level: V D I W E F
adb logcat *:E              # errors only
adb logcat *:W              # warnings and above

# Filter by tag and level
adb logcat MyTag:D *:S

# Clear the log buffer
adb logcat -c

# Save logs to a file
adb logcat -d > logcat.txt

# Show logs with timestamps
adb logcat -v time

# Show logs in a readable long format
adb logcat -v long
```

### ADB — File management

```bash
# Copy file from PC to device
adb push local_file.txt /sdcard/

# Copy file from device to PC
adb pull /sdcard/file.txt ./

# Copy the debug APK to the device's Downloads
adb push app/build/outputs/apk/debug/app-debug.apk /sdcard/Download/

# List files on device
adb shell ls /sdcard/

# Open a shell on the device
adb shell

# Run a single shell command on device
adb shell cat /proc/version
```

### ADB — Device info & settings

```bash
# Get device Android version
adb shell getprop ro.build.version.release

# Get device API level
adb shell getprop ro.build.version.sdk

# Get device model
adb shell getprop ro.product.model

# Get all properties
adb shell getprop

# Take a screenshot and save to PC
adb shell screencap /sdcard/screen.png
adb pull /sdcard/screen.png ./

# Record screen (stops with Ctrl+C)
adb shell screenrecord /sdcard/demo.mp4
adb pull /sdcard/demo.mp4 ./

# Simulate input — tap at coordinates
adb shell input tap 500 800

# Simulate input — swipe (x1 y1 x2 y2 duration_ms)
adb shell input swipe 300 800 300 200 300

# Simulate key press (e.g. Back = 4, Home = 3, Menu = 82)
adb shell input keyevent 4

# Type text into focused field
adb shell input text "hello"

# Show current battery status
adb shell dumpsys battery

# Simulate low battery
adb shell dumpsys battery set level 5

# Reset battery simulation
adb shell dumpsys battery reset

# Show memory usage for your app
adb shell dumpsys meminfo com.example.myapp

# Show activity manager info (current activities, tasks)
adb shell dumpsys activity
```

### ADB — Network

```bash
# Forward a port from PC to device
adb forward tcp:8080 tcp:8080

# Reverse-forward a port from device to PC (useful for local APIs)
adb reverse tcp:8080 tcp:8080

# Remove all port forwards
adb forward --remove-all
adb reverse --remove-all
```

---

### sdkmanager — SDK packages

`sdkmanager` lives at `$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager`.

```bash
# List all installed packages
sdkmanager --list_installed

# List all available packages
sdkmanager --list

# Install a specific SDK platform
sdkmanager "platforms;android-35"
sdkmanager "platforms;android-34"

# Install build tools
sdkmanager "build-tools;35.0.1"

# Install platform tools (adb, fastboot)
sdkmanager "platform-tools"

# Install command-line tools
sdkmanager "cmdline-tools;latest"

# Install emulator
sdkmanager "emulator"

# Install a system image for the emulator
sdkmanager "system-images;android-35;google_apis;x86_64"

# Update all installed packages
sdkmanager --update

# Accept all licenses
sdkmanager --licenses
```

### avdmanager — Emulator management

`avdmanager` lives at `$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager`.

```bash
# List available device definitions
avdmanager list device

# List existing AVDs
avdmanager list avd

# Create a new AVD
avdmanager create avd \
  --name "Pixel_8_API_35" \
  --package "system-images;android-35;google_apis;x86_64" \
  --device "pixel_8"

# Delete an AVD
avdmanager delete avd --name "Pixel_8_API_35"

# Start an emulator by AVD name
$ANDROID_HOME/emulator/emulator -avd Pixel_8_API_35

# Start emulator in the background (no window, for CI)
$ANDROID_HOME/emulator/emulator -avd Pixel_8_API_35 -no-window -no-audio &
```

---

### ktlint — Linting & formatting

```bash
# Check all Kotlin files in the current directory (recursively)
ktlint

# Check specific files or patterns
ktlint "src/**/*.kt"

# Auto-fix style violations
ktlint --format
ktlint -F "src/**/*.kt"

# Check and exclude test files
ktlint "src/**/*.kt" "!src/**/*Test.kt"

# Print violations grouped by file
ktlint --reporter=plain?group_by_file

# Output a Checkstyle XML report
ktlint --reporter=plain --reporter=checkstyle,output=ktlint-report.xml

# Install a git pre-commit hook (runs ktlint before every commit)
ktlint --install-git-pre-commit-hook

# Remove the git pre-commit hook
ktlint --remove-git-pre-commit-hook

# Print ktlint version
ktlint --version
```

---

### keytool — Signing & keystore

Required to sign release builds for the Play Store.

```bash
# Generate a new release keystore
keytool -genkey -v \
  -keystore release.keystore \
  -alias my-key-alias \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000

# View keystore contents
keytool -list -v -keystore release.keystore

# Get the SHA-1 fingerprint (needed for Firebase, Google Maps, etc.)
keytool -list -v \
  -keystore release.keystore \
  -alias my-key-alias \
  | grep SHA1

# Get the SHA-256 fingerprint
keytool -list -v \
  -keystore release.keystore \
  -alias my-key-alias \
  | grep SHA256

# Get the debug keystore SHA-1 (for development APIs)
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey \
  -storepass android \
  -keypass android \
  | grep SHA1
```

To use the keystore for release builds, add to `app/build.gradle.kts`:

```kotlin
android {
    signingConfigs {
        create("release") {
            storeFile     = file("release.keystore")
            storePassword = System.getenv("STORE_PASSWORD")
            keyAlias      = "my-key-alias"
            keyPassword   = System.getenv("KEY_PASSWORD")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

---

## Environment variables

| Variable | Description |


| Variable | Description |
|---|---|
| `ANDROID_HOME` | Path to the Android SDK (preferred) |
| `ANDROID_SDK_ROOT` | Fallback if `ANDROID_HOME` is not set |
| `JAVA_HOME` | Must point to JDK 17+ for Gradle daemon |

Set them in `~/.bashrc` or `~/.zshrc`:

```bash
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/platform-tools
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
```

---

## Common issues

**Java not found**
```bash
sudo dnf install java-17-openjdk-devel
```

**`ANDROID_HOME` not set**

Export it in your shell profile (see above) and restart your terminal, or enter the path manually when the script prompts you.

**`gradle-wrapper.jar` download failed**

Copy it manually from an existing Android project, or from the [Gradle GitHub releases](https://github.com/gradle/gradle/releases):

```bash
cp /path/to/other/project/gradle/wrapper/gradle-wrapper.jar \
   <your-project>/gradle/wrapper/
```

**Build fails with "SDK platform not found"**

Install the required platform via `sdkmanager`:

```bash
$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "platforms;android-35"
```

**`ktlint` not found (warning only)**

This is non-fatal. See the [ktlint installation guide](https://pinterest.github.io/ktlint/latest/install/cli/) or install via:

```bash
curl -sSLO https://github.com/pinterest/ktlint/releases/latest/download/ktlint
chmod +x ktlint && sudo mv ktlint /usr/local/bin/
```

---

## Notes

- The script uses `set -euo pipefail` — it exits immediately on any unhandled error.
- `local.properties` is auto-filled with your SDK path and is excluded from `.gitignore` (as is standard for Android projects).
- The `gradlew` script is always created — either as a thin wrapper around your binary, or as a full Gradle Wrapper depending on your choice in Step 1.
- Tilde (`~`) expansion is handled for all path inputs.