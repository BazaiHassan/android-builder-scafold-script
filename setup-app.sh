#!/usr/bin/env bash
# =============================================================================
#  create_android_project.sh
#  Scaffolds an Android project (Kotlin + Jetpack Compose + Version Catalog)
#  without Android Studio.  Tested on Fedora.
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; }

# ── Helper: prompt with default ───────────────────────────────────────────────
ask() {
    local prompt="$1" default="$2" var_name="$3"
    local input
    echo -en "${BOLD}${prompt}${RESET} [${YELLOW}${default}${RESET}]: "
    read -r input
    printf -v "$var_name" '%s' "${input:-$default}"
}

ask_required() {
    local prompt="$1" var_name="$2"
    local input
    while true; do
        echo -en "${BOLD}${prompt}${RESET}: "
        read -r input
        if [[ -n "$input" ]]; then
            printf -v "$var_name" '%s' "$input"
            break
        fi
        warn "This field is required."
    done
}

# ─────────────────────────────────────────────────────────────────────────────
header "Android Project Scaffolder  (Kotlin · Compose · Version Catalog)"
# ─────────────────────────────────────────────────────────────────────────────

# ══ STEP 1 – Collect Gradle wrapper location ══════════════════════════════════
echo ""
info "Provide the path to your local Gradle installation or the gradle binary."
info "Example: /opt/gradle/gradle-8.7/bin/gradle  OR  just press Enter to"
info "generate a Gradle Wrapper that downloads Gradle automatically."
echo -en "${BOLD}Gradle binary path (leave empty = use wrapper)${RESET}: "
read -r GRADLE_BIN_INPUT

USE_WRAPPER=false
GRADLE_BIN=""
if [[ -z "$GRADLE_BIN_INPUT" ]]; then
    USE_WRAPPER=true
    info "Will generate a Gradle Wrapper (gradlew)."
else
    GRADLE_BIN="${GRADLE_BIN_INPUT/#\~/$HOME}"   # expand ~
    [[ -x "$GRADLE_BIN" ]] || die "Gradle binary not found or not executable: $GRADLE_BIN"
    success "Gradle found: $GRADLE_BIN"
fi

# ══ STEP 2 – Environment checks ═══════════════════════════════════════════════
header "Checking Environment"

check_java() {
    if command -v java &>/dev/null; then
        JAVA_VER=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        success "Java found: $JAVA_VER"
        JAVA_MAJOR=${JAVA_VER%%.*}
        [[ "$JAVA_MAJOR" -ge 17 ]] 2>/dev/null || \
            warn "Java 17+ is recommended for modern Android development (found $JAVA_VER)."
    else
        die "Java (JDK) not found.  Install with: sudo dnf install java-17-openjdk-devel"
    fi
}

check_android_sdk() {
    # Prefer ANDROID_HOME, then ANDROID_SDK_ROOT
    if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
        warn "ANDROID_HOME / ANDROID_SDK_ROOT is not set."
        echo -en "${BOLD}Enter Android SDK path${RESET}: "
        read -r SDK_INPUT
        SDK_PATH="${SDK_INPUT/#\~/$HOME}"
    else
        SDK_PATH="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
        success "Android SDK env var found: $SDK_PATH"
    fi

    [[ -d "$SDK_PATH" ]] || die "SDK directory not found: $SDK_PATH"
    [[ -d "$SDK_PATH/platforms" ]] || die "No 'platforms' directory in SDK – is the SDK installed correctly?"
    success "Android SDK directory OK: $SDK_PATH"
    ANDROID_SDK_PATH="$SDK_PATH"
}

check_adb() {
    if command -v adb &>/dev/null; then
        success "adb found: $(adb version | head -1)"
    else
        warn "adb not found.  Add \$ANDROID_HOME/platform-tools to PATH if you need device deployment."
    fi
}

check_ktlint_optional() {
    if command -v ktlint &>/dev/null; then
        success "ktlint found (optional linter)."
    else
        info "ktlint not found – skipping (optional)."
    fi
}

check_java
check_android_sdk
check_adb
check_ktlint_optional

# Detect highest installed compileSdk
LATEST_PLATFORM=$(ls "$ANDROID_SDK_PATH/platforms" 2>/dev/null | grep '^android-' | \
    sort -t- -k2 -n | tail -1 | sed 's/android-//')
if [[ -z "$LATEST_PLATFORM" ]]; then
    warn "No SDK platform found in $ANDROID_SDK_PATH/platforms."
    LATEST_PLATFORM="35"
fi
info "Highest installed SDK platform detected: $LATEST_PLATFORM"

# ══ STEP 3 – Project metadata ═════════════════════════════════════════════════
header "Project Configuration"

ask_required "Application name (e.g. My Awesome App)" APP_NAME
ask          "Package name" "com.example.myapp" PACKAGE_NAME
ask          "Project directory name" "$(echo "$APP_NAME" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')" PROJECT_DIR_NAME
ask          "Output parent directory" "$HOME/Projects" OUTPUT_PARENT
ask          "Minimum SDK version" "26" MIN_SDK
ask          "Compile / Target SDK version" "$LATEST_PLATFORM" COMPILE_SDK
ask          "Kotlin version" "2.1.21" KOTLIN_VERSION
ask          "Compose BOM version" "2025.05.00" COMPOSE_BOM_VERSION
ask          "AGP (Android Gradle Plugin) version" "8.9.2" AGP_VERSION
ask          "Gradle wrapper version (used only if no binary supplied)" "8.13" GRADLE_WRAPPER_VERSION
ask          "App version name" "1.0.0" VERSION_NAME
ask          "App version code" "1" VERSION_CODE

# ── Compatibility table ───────────────────────────────────────────────────────
echo ""
header "Compatibility Check"

# ── Version number helpers ────────────────────────────────────────────────────
# Convert "X.Y.Z" → integer XXYYZZ  (e.g. 2.1.21 → 20121, 8.13.0 → 81300)
ver_num() {
    local maj min pat
    maj=$(echo "$1" | cut -d. -f1)
    min=$(echo "$1" | cut -d. -f2)
    pat=$(echo "$1" | cut -d. -f3)
    pat=${pat:-0}
    echo $(( maj * 10000 + min * 100 + pat ))
}

AGP_NUM=$(ver_num "$AGP_VERSION")
KT_NUM=$(ver_num "$KOTLIN_VERSION")

# Gradle binary version (if supplied)
if [[ -n "$GRADLE_BIN" ]]; then
    GRADLE_USED_VER=$("$GRADLE_BIN" --version 2>/dev/null | awk '/^Gradle / {print $2}')
else
    GRADLE_USED_VER="$GRADLE_WRAPPER_VERSION"
fi
GRADLE_NUM=$(ver_num "${GRADLE_USED_VER:-0}")

# Java major already in JAVA_MAJOR from check_java()

# ── Check each pair and store result/note ─────────────────────────────────────
# Each row: check_name | left_val | right_val | status | note
# status: OK | WARN | FAIL

ROWS=()

# ── 1. Java ↔ AGP ────────────────────────────────────────────────────────────
# AGP 8.x requires JDK 17+
row_java_agp_status="OK"
row_java_agp_note="JDK ${JAVA_VER} satisfies AGP ${AGP_VERSION}"
if [[ -n "${JAVA_MAJOR:-}" && "$JAVA_MAJOR" -lt 17 ]]; then
    row_java_agp_status="FAIL"
    row_java_agp_note="AGP 8.x requires JDK 17+. Found JDK $JAVA_VER"
fi
ROWS+=("Java ↔ AGP|JDK $JAVA_VER|AGP $AGP_VERSION|$row_java_agp_status|$row_java_agp_note")

# ── 2. Java ↔ Gradle ─────────────────────────────────────────────────────────
# Gradle 8.x requires JDK 8+ to run; JDK 17 is recommended
row_java_gradle_status="OK"
row_java_gradle_note="JDK ${JAVA_VER} runs Gradle ${GRADLE_USED_VER}"
if [[ -n "${JAVA_MAJOR:-}" && "$JAVA_MAJOR" -lt 8 ]]; then
    row_java_gradle_status="FAIL"
    row_java_gradle_note="Gradle requires at least JDK 8. Found JDK $JAVA_VER"
elif [[ -n "${JAVA_MAJOR:-}" && "$JAVA_MAJOR" -lt 17 ]]; then
    row_java_gradle_status="WARN"
    row_java_gradle_note="JDK 17+ recommended for Gradle 8.x (found $JAVA_VER)"
fi
ROWS+=("Java ↔ Gradle|JDK $JAVA_VER|Gradle $GRADLE_USED_VER|$row_java_gradle_status|$row_java_gradle_note")

# ── 3. AGP ↔ Gradle ──────────────────────────────────────────────────────────
# AGP 8.x requires Gradle 8.0+; AGP 8.9+ works best with Gradle 8.11+
row_agp_gradle_status="OK"
row_agp_gradle_note="AGP ${AGP_VERSION} and Gradle ${GRADLE_USED_VER} are compatible"
if [[ $GRADLE_NUM -lt 80000 ]]; then
    row_agp_gradle_status="FAIL"
    row_agp_gradle_note="AGP $AGP_VERSION requires Gradle 8.0+. Found $GRADLE_USED_VER"
elif [[ $AGP_NUM -ge 80900 && $GRADLE_NUM -lt 81100 ]]; then
    row_agp_gradle_status="WARN"
    row_agp_gradle_note="AGP $AGP_VERSION works best with Gradle 8.11+. Found $GRADLE_USED_VER"
fi
ROWS+=("AGP ↔ Gradle|AGP $AGP_VERSION|Gradle $GRADLE_USED_VER|$row_agp_gradle_status|$row_agp_gradle_note")

# ── 4. AGP ↔ Kotlin ──────────────────────────────────────────────────────────
row_agp_kotlin_status="OK"
row_agp_kotlin_note="AGP ${AGP_VERSION} and Kotlin ${KOTLIN_VERSION} are compatible"
if [[ $AGP_NUM -ge 81000 && $KT_NUM -lt 20100 ]]; then
    row_agp_kotlin_status="FAIL"
    row_agp_kotlin_note="AGP $AGP_VERSION requires Kotlin 2.1+. Found $KOTLIN_VERSION"
elif [[ $AGP_NUM -ge 81300 && $KT_NUM -lt 20300 ]]; then
    row_agp_kotlin_status="WARN"
    row_agp_kotlin_note="AGP $AGP_VERSION supports Kotlin 2.3+. Found $KOTLIN_VERSION (works, can upgrade)"
fi
ROWS+=("AGP ↔ Kotlin|AGP $AGP_VERSION|Kotlin $KOTLIN_VERSION|$row_agp_kotlin_status|$row_agp_kotlin_note")

# ── 5. Kotlin ↔ Gradle ───────────────────────────────────────────────────────
row_kt_gradle_status="OK"
row_kt_gradle_note="Kotlin ${KOTLIN_VERSION} and Gradle ${GRADLE_USED_VER} are compatible"
if [[ $KT_NUM -ge 20000 && $GRADLE_NUM -lt 76000 ]]; then
    row_kt_gradle_status="FAIL"
    row_kt_gradle_note="Kotlin 2.x requires Gradle 7.6.3+. Found $GRADLE_USED_VER"
elif [[ $KT_NUM -ge 20300 && $GRADLE_NUM -lt 80700 ]]; then
    row_kt_gradle_status="WARN"
    row_kt_gradle_note="Kotlin $KOTLIN_VERSION works best with Gradle 8.7+. Found $GRADLE_USED_VER"
fi
ROWS+=("Kotlin ↔ Gradle|Kotlin $KOTLIN_VERSION|Gradle $GRADLE_USED_VER|$row_kt_gradle_status|$row_kt_gradle_note")

# ── 6. compileSdk ↔ AGP ──────────────────────────────────────────────────────
row_sdk_agp_status="OK"
row_sdk_agp_note="compileSdk $COMPILE_SDK is supported by AGP $AGP_VERSION"
if [[ $COMPILE_SDK -lt 34 && $AGP_NUM -ge 81000 ]]; then
    row_sdk_agp_status="WARN"
    row_sdk_agp_note="AGP $AGP_VERSION recommends compileSdk 34+. Found $COMPILE_SDK"
fi
ROWS+=("compileSdk ↔ AGP|compileSdk $COMPILE_SDK|AGP $AGP_VERSION|$row_sdk_agp_status|$row_sdk_agp_note")

# ── 7. minSdk ↔ compileSdk ───────────────────────────────────────────────────
row_minsdk_status="OK"
row_minsdk_note="minSdk $MIN_SDK ≤ compileSdk $COMPILE_SDK"
if [[ $MIN_SDK -gt $COMPILE_SDK ]]; then
    row_minsdk_status="FAIL"
    row_minsdk_note="minSdk ($MIN_SDK) cannot be greater than compileSdk ($COMPILE_SDK)"
fi
ROWS+=("minSdk ↔ compileSdk|minSdk $MIN_SDK|compileSdk $COMPILE_SDK|$row_minsdk_status|$row_minsdk_note")

# ── Render the table ──────────────────────────────────────────────────────────
COL1=22   # Check
COL2=18   # Left value
COL3=18   # Right value
COL4=7    # Status
COL5=46   # Note

pad() { printf "%-${1}s" "$2"; }   # left-pad a string to width $1

DIVIDER=$(printf '─%.0s' $(seq 1 $(( COL1 + COL2 + COL3 + COL4 + COL5 + 14 )) ))

status_col() {
    case "$1" in
        OK)   echo -e "${GREEN}  ✔ OK ${RESET}" ;;
        WARN) echo -e "${YELLOW} ⚠ WARN${RESET}" ;;
        FAIL) echo -e "${RED}  ✖ FAIL${RESET}" ;;
        *)    echo "  ?     " ;;
    esac
}

echo ""
echo -e "  ${BOLD}┌${DIVIDER}┐${RESET}"
printf "  ${BOLD}│ %-${COL1}s │ %-${COL2}s │ %-${COL3}s │ %-${COL4}s │ %-${COL5}s │${RESET}\n" \
    "Check" "Your Value A" "Your Value B" "Status" "Note"
echo -e "  ${BOLD}├${DIVIDER}┤${RESET}"

HAS_FAIL=false
HAS_WARN=false

for row in "${ROWS[@]}"; do
    IFS='|' read -r c1 c2 c3 c4 c5 <<< "$row"
    # Truncate note if too long
    if [[ ${#c5} -gt $COL5 ]]; then c5="${c5:0:$(( COL5 - 1 ))}…"; fi
    # Pick colour for the row background hint via status icon
    case "$c4" in
        OK)   SICON="${GREEN}✔ OK  ${RESET}" ;;
        WARN) SICON="${YELLOW}⚠ WARN${RESET}"; HAS_WARN=true ;;
        FAIL) SICON="${RED}✖ FAIL${RESET}"; HAS_FAIL=true ;;
        *)    SICON="?     " ;;
    esac
    printf "  │ $(pad $COL1 "$c1") │ $(pad $COL2 "$c2") │ $(pad $COL3 "$c3") │ %b │ $(pad $COL5 "$c5") │\n" \
        "$SICON"
done

echo -e "  ${BOLD}└${DIVIDER}┘${RESET}"
echo ""

# ── Abort on FAIL, continue on WARN ──────────────────────────────────────────
if $HAS_FAIL; then
    die "One or more compatibility checks FAILED. Fix the issues above before continuing."
fi
if $HAS_WARN; then
    warn "Some checks show warnings. You can continue but consider reviewing them."
    echo -en "Continue anyway? [y/N]: "
    read -r WARN_CONFIRM
    [[ "${WARN_CONFIRM,,}" != "y" ]] && die "Aborted by user."
else
    success "All compatibility checks passed."
fi

# Derive package path
PACKAGE_PATH="${PACKAGE_NAME//.//}"

# Resolve full project path
OUTPUT_PARENT="${OUTPUT_PARENT/#\~/$HOME}"
PROJECT_ROOT="$OUTPUT_PARENT/$PROJECT_DIR_NAME"

echo ""
info "Project will be created at: ${BOLD}$PROJECT_ROOT${RESET}"
echo ""
echo -e "  ${BOLD}Summary:${RESET}"
echo -e "  App Name     : $APP_NAME"
echo -e "  Package      : $PACKAGE_NAME"
echo -e "  Path         : $PROJECT_ROOT"
echo -e "  SDK          : minSdk=$MIN_SDK  compileSdk=$COMPILE_SDK"
echo -e "  Kotlin       : $KOTLIN_VERSION"
echo -e "  Compose BOM  : $COMPOSE_BOM_VERSION"
echo -e "  AGP          : $AGP_VERSION"
echo -e "  Gradle       : ${GRADLE_BIN:-wrapper v$GRADLE_WRAPPER_VERSION}"
echo ""
echo -en "Continue? [Y/n]: "
read -r CONFIRM
[[ "${CONFIRM,,}" == "n" ]] && die "Aborted by user."

# ══ STEP 4 – Create directory tree ════════════════════════════════════════════
header "Creating Directory Structure"

mkdir -p "$PROJECT_ROOT"/{app/src/{main/{kotlin/"$PACKAGE_PATH"/{ui/theme,screens},res/{values,drawable,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi}},androidTest/kotlin/"$PACKAGE_PATH",test/kotlin/"$PACKAGE_PATH"},gradle}

success "Directories created."

# ══ STEP 5 – libs.versions.toml (Version Catalog) ════════════════════════════
header "Writing gradle/libs.versions.toml"

cat > "$PROJECT_ROOT/gradle/libs.versions.toml" <<TOML
[versions]
agp                   = "$AGP_VERSION"
kotlin                = "$KOTLIN_VERSION"
composeBom            = "$COMPOSE_BOM_VERSION"
coreKtx               = "1.15.0"
lifecycleRuntimeKtx   = "2.8.7"
activityCompose       = "1.9.3"
navigationCompose     = "2.8.5"
hiltAndroid           = "2.52"
junit                 = "4.13.2"
junitExt              = "1.2.1"
espressoCore          = "3.6.1"

[libraries]
# Core
androidx-core-ktx               = { group = "androidx.core",       name = "core-ktx",                version.ref = "coreKtx" }
androidx-lifecycle-runtime-ktx  = { group = "androidx.lifecycle",  name = "lifecycle-runtime-ktx",   version.ref = "lifecycleRuntimeKtx" }
androidx-activity-compose       = { group = "androidx.activity",   name = "activity-compose",         version.ref = "activityCompose" }
androidx-navigation-compose     = { group = "androidx.navigation", name = "navigation-compose",       version.ref = "navigationCompose" }

# Compose BOM
androidx-compose-bom            = { group = "androidx.compose",    name = "compose-bom",              version.ref = "composeBom" }
androidx-compose-ui             = { group = "androidx.compose.ui", name = "ui" }
androidx-compose-ui-graphics    = { group = "androidx.compose.ui", name = "ui-graphics" }
androidx-compose-ui-tooling     = { group = "androidx.compose.ui", name = "ui-tooling" }
androidx-compose-ui-tooling-preview = { group = "androidx.compose.ui", name = "ui-tooling-preview" }
androidx-compose-material3      = { group = "androidx.compose.material3", name = "material3" }

# Test
junit                           = { group = "junit",               name = "junit",                    version.ref = "junit" }
androidx-junit-ext              = { group = "androidx.test.ext",   name = "junit",                    version.ref = "junitExt" }
androidx-espresso-core          = { group = "androidx.test.espresso", name = "espresso-core",         version.ref = "espressoCore" }
androidx-compose-ui-test-junit4 = { group = "androidx.compose.ui", name = "ui-test-junit4" }
androidx-compose-ui-test-manifest = { group = "androidx.compose.ui", name = "ui-test-manifest" }

[plugins]
android-application  = { id = "com.android.application",         version.ref = "agp" }
kotlin-android       = { id = "org.jetbrains.kotlin.android",    version.ref = "kotlin" }
kotlin-compose       = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
TOML

success "libs.versions.toml written."

# ══ STEP 6 – Root build.gradle.kts ═══════════════════════════════════════════
header "Writing root build.gradle.kts"

cat > "$PROJECT_ROOT/build.gradle.kts" <<'KTS'
// Top-level build file – configuration shared across sub-projects/modules.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android)      apply false
    alias(libs.plugins.kotlin.compose)      apply false
}
KTS

success "Root build.gradle.kts written."

# ══ STEP 7 – settings.gradle.kts ═════════════════════════════════════════════
header "Writing settings.gradle.kts"

cat > "$PROJECT_ROOT/settings.gradle.kts" <<KTS
pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\\\.android.*")
                includeGroupByRegex("com\\\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "$APP_NAME"
include(":app")
KTS

success "settings.gradle.kts written."

# ══ STEP 8 – app/build.gradle.kts ════════════════════════════════════════════
header "Writing app/build.gradle.kts"

cat > "$PROJECT_ROOT/app/build.gradle.kts" <<KTS
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace   = "$PACKAGE_NAME"
    compileSdk  = $COMPILE_SDK

    defaultConfig {
        applicationId = "$PACKAGE_NAME"
        minSdk        = $MIN_SDK
        targetSdk     = $COMPILE_SDK
        versionCode   = $VERSION_CODE
        versionName   = "$VERSION_NAME"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)

    // Tests
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit.ext)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)

    // Debug
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
KTS

success "app/build.gradle.kts written."

# ══ STEP 9 – AndroidManifest.xml ═════════════════════════════════════════════
header "Writing AndroidManifest.xml"

cat > "$PROJECT_ROOT/app/src/main/AndroidManifest.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="$APP_NAME"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.App">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:label="$APP_NAME"
            android:theme="@style/Theme.App">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

    </application>

</manifest>
XML

success "AndroidManifest.xml written."

# ══ STEP 10 – Kotlin source files ════════════════════════════════════════════
header "Writing Kotlin source files"

SRC="$PROJECT_ROOT/app/src/main/kotlin/$PACKAGE_PATH"

# MainActivity.kt
cat > "$SRC/MainActivity.kt" <<KT
package $PACKAGE_NAME

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import $PACKAGE_NAME.ui.theme.AppTheme
import $PACKAGE_NAME.screens.HomeScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AppTheme {
                HomeScreen()
            }
        }
    }
}
KT

# ui/theme/Theme.kt
cat > "$SRC/ui/theme/Theme.kt" <<KT
package $PACKAGE_NAME.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val DarkColorScheme = darkColorScheme()
private val LightColorScheme = lightColorScheme()

@Composable
fun AppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else      -> LightColorScheme
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = colorScheme.primary.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        content     = content
    )
}
KT

# ui/theme/Type.kt
cat > "$SRC/ui/theme/Type.kt" <<KT
package $PACKAGE_NAME.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val Typography = Typography(
    bodyLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize   = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.5.sp
    )
)
KT

# screens/HomeScreen.kt
cat > "$SRC/screens/HomeScreen.kt" <<KT
package $PACKAGE_NAME.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun HomeScreen() {
    Scaffold(
        topBar = {
            TopAppBar(title = { Text("$APP_NAME") })
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(16.dp),
            verticalArrangement   = Arrangement.Center,
            horizontalAlignment   = Alignment.CenterHorizontally
        ) {
            Text(
                text  = "Hello, Compose! 🚀",
                style = MaterialTheme.typography.headlineMedium
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text  = "Edit screens/HomeScreen.kt to get started.",
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}
KT

success "Kotlin sources written."

# ══ STEP 11 – res/values ═════════════════════════════════════════════════════
cat > "$PROJECT_ROOT/app/src/main/res/values/strings.xml" <<XML
<resources>
    <string name="app_name">$APP_NAME</string>
</resources>
XML

cat > "$PROJECT_ROOT/app/src/main/res/values/themes.xml" <<XML
<resources>
    <style name="Theme.App" parent="android:Theme.Material.Light.NoActionBar" />
</resources>
XML

success "Resource files written."

# ══ STEP 12 – proguard-rules.pro ═════════════════════════════════════════════
cat > "$PROJECT_ROOT/app/proguard-rules.pro" <<PRO
# Add project-specific ProGuard rules here.
# By default, the flags in this file are applied to the release build.
-keep class $PACKAGE_NAME.** { *; }
PRO

# ══ STEP 13 – .gitignore ═════════════════════════════════════════════════════
cat > "$PROJECT_ROOT/.gitignore" <<GIT
# Gradle
.gradle/
build/
**/build/
!gradle/wrapper/gradle-wrapper.jar

# Local config
local.properties
*.iml
.idea/
*.DS_Store

# Android
/captures
.externalNativeBuild/
.cxx/
*.apk
*.aab
GIT

# ══ STEP 14 – local.properties ═══════════════════════════════════════════════
cat > "$PROJECT_ROOT/local.properties" <<PROP
sdk.dir=$ANDROID_SDK_PATH
PROP

success "local.properties written."

# ══ STEP 15 – Gradle wrapper (optional) ══════════════════════════════════════
if $USE_WRAPPER; then
    header "Setting up Gradle Wrapper"
    mkdir -p "$PROJECT_ROOT/gradle/wrapper"

    cat > "$PROJECT_ROOT/gradle/wrapper/gradle-wrapper.properties" <<PROPS
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-${GRADLE_WRAPPER_VERSION}-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
PROPS

    # Minimal gradlew shell script
    cat > "$PROJECT_ROOT/gradlew" <<'GRADLEW'
#!/bin/sh
# Gradle wrapper startup script for *nix

APP_HOME="$(cd "$(dirname "$0")" && pwd -P)"
CLASSPATH="$APP_HOME/gradle/wrapper/gradle-wrapper.jar"
JAVA_OPTS="${JAVA_OPTS:-}"
exec "$JAVA_HOME/bin/java" $JAVA_OPTS -classpath "$CLASSPATH" \
    org.gradle.wrapper.GradleWrapperMain "$@"
GRADLEW
    chmod +x "$PROJECT_ROOT/gradlew"

    # Download the actual gradle-wrapper.jar
    WRAPPER_JAR_URL="https://raw.githubusercontent.com/gradle/gradle/v${GRADLE_WRAPPER_VERSION}/gradle/wrapper/gradle-wrapper.jar"
    JAR_DEST="$PROJECT_ROOT/gradle/wrapper/gradle-wrapper.jar"
    info "Downloading gradle-wrapper.jar …"
    if command -v curl &>/dev/null; then
        curl -fsSL "$WRAPPER_JAR_URL" -o "$JAR_DEST" 2>/dev/null && \
            success "gradle-wrapper.jar downloaded." || \
            warn "Could not download gradle-wrapper.jar.  Copy it manually."
    elif command -v wget &>/dev/null; then
        wget -q "$WRAPPER_JAR_URL" -O "$JAR_DEST" && \
            success "gradle-wrapper.jar downloaded." || \
            warn "Could not download gradle-wrapper.jar.  Copy it manually."
    else
        warn "Neither curl nor wget found.  Copy gradle-wrapper.jar manually to: $JAR_DEST"
    fi

    cat > "$PROJECT_ROOT/gradlew.bat" <<'BAT'
@rem Gradle wrapper for Windows (optional)
@if "%DEBUG%"=="" @echo off
@rem This file is intentionally minimal; run from Linux/macOS with gradlew
BAT

    GRADLE_CMD="$PROJECT_ROOT/gradlew"
else
    header "Using provided Gradle binary"
    # Create a thin wrapper script inside the project for convenience
    cat > "$PROJECT_ROOT/gradlew" <<GRADLEW
#!/bin/sh
exec "$GRADLE_BIN" "\$@"
GRADLEW
    chmod +x "$PROJECT_ROOT/gradlew"
    GRADLE_CMD="$PROJECT_ROOT/gradlew"
    success "Thin wrapper pointing to $GRADLE_BIN created."
fi

# ══ STEP 16 – gradle.properties ══════════════════════════════════════════════
cat > "$PROJECT_ROOT/gradle.properties" <<PROPS
# Project-wide Gradle settings
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configuration-cache=true

android.useAndroidX=true
android.enableJetifier=false
kotlin.code.style=official
PROPS

success "gradle.properties written."

# ══ STEP 17 – Try to build ════════════════════════════════════════════════════
header "Initial Build"
echo -en "Attempt an initial Gradle sync / build now? [y/N]: "
read -r BUILD_NOW
if [[ "${BUILD_NOW,,}" == "y" ]]; then
    info "Running: $GRADLE_CMD assembleDebug"
    cd "$PROJECT_ROOT"
    if "$GRADLE_CMD" assembleDebug; then
        success "Build succeeded!  APK is in app/build/outputs/apk/debug/"
    else
        warn "Build failed.  Check the output above.  Common fixes:"
        warn "  • Ensure JAVA_HOME points to JDK 17"
        warn "  • Run: $GRADLE_CMD dependencies  to diagnose dependency issues"
        warn "  • Check $ANDROID_SDK_PATH/platforms/android-$COMPILE_SDK exists"
    fi
fi

# ══ DONE ══════════════════════════════════════════════════════════════════════
header "Project Ready!"
echo ""
echo -e "  ${BOLD}Location :${RESET} $PROJECT_ROOT"
echo -e "  ${BOLD}Package  :${RESET} $PACKAGE_NAME"
echo -e "  ${BOLD}SDK      :${RESET} minSdk=$MIN_SDK  compileSdk=$COMPILE_SDK"
echo -e "  ${BOLD}Kotlin   :${RESET} $KOTLIN_VERSION"
echo ""
echo -e "  ${CYAN}Quick commands:${RESET}"
echo -e "  cd $PROJECT_ROOT"
echo -e "  ./gradlew assembleDebug          # build APK"
echo -e "  ./gradlew installDebug           # build & install on connected device"
echo -e "  ./gradlew test                   # unit tests"
echo -e "  ./gradlew connectedAndroidTest   # instrumented tests"
echo -e "  ./gradlew lint                   # lint checks"
echo ""
success "Happy coding! 🎉"