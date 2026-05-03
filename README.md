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

## Gradle commands

```bash
# Build debug APK
./gradlew assembleDebug

# Build and install on connected device/emulator
./gradlew installDebug

# Build release APK (minified)
./gradlew assembleRelease

# Run unit tests
./gradlew test

# Run instrumented tests (device/emulator required)
./gradlew connectedAndroidTest

# Lint checks
./gradlew lint

# Check dependency tree
./gradlew dependencies

# Clean build outputs
./gradlew clean
```

---

## Environment variables

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
