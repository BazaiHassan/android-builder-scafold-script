#!/usr/bin/env bash
# =============================================================================
#  create_android_project.sh
#  Scaffolds an Android project (Kotlin + Jetpack Compose + Version Catalog)
#  Detects tools by reading shell config files (.zshrc, .bashrc, .profile)
#  and $PATH — no network scanning, no binary execution for detection.
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
header()  {
    echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}  $*${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"
}

# ── Prompt helpers ────────────────────────────────────────────────────────────
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

confirm_or_override() {
    # confirm_or_override "Label" "detected_value" VAR_NAME
    local label="$1" detected="$2" var_name="$3"
    if [[ -n "$detected" ]]; then
        echo -e "  ${GREEN}✔ Detected${RESET} ${BOLD}${label}${RESET}: ${CYAN}${detected}${RESET}"
        echo -en "  Press Enter to accept, or type a different path: "
        read -r override
        if [[ -n "$override" ]]; then
            printf -v "$var_name" '%s' "$override"
            success "Overridden → ${override}"
        else
            printf -v "$var_name" '%s' "$detected"
            success "Accepted  → ${detected}"
        fi
    else
        warn "${label} not detected in shell configs or PATH."
        ask_required "  Enter ${label} path manually" "$var_name"
    fi
}

# =============================================================================
# STEP 0 – OS Detection
# =============================================================================
header "Detecting Operating System"

OS_TYPE=""
OS_NAME=""
IS_WSL=false

detect_os() {
    if grep -qi microsoft /proc/version 2>/dev/null || grep -qi wsl /proc/version 2>/dev/null; then
        IS_WSL=true
    fi
    case "$(uname -s)" in
        Linux*)
            OS_TYPE="linux"
            if [[ -f /etc/os-release ]]; then
                source /etc/os-release
                OS_NAME="${PRETTY_NAME:-Linux}"
            else
                OS_NAME="Linux"
            fi
            ;;
        Darwin*)
            OS_TYPE="macos"
            OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null || echo '')"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            OS_TYPE="windows"
            OS_NAME="Windows (Git Bash / MSYS2)"
            ;;
        *)
            OS_TYPE="unknown"
            OS_NAME="Unknown OS"
            ;;
    esac

    echo -e "  ${BOLD}OS Detected :${RESET} $OS_NAME"
    $IS_WSL && echo -e "  ${BOLD}Environment :${RESET} WSL (Windows Subsystem for Linux)"
    echo ""
}

detect_os

# =============================================================================
# STEP 1 – Read shell config files and PATH to detect tool paths
# =============================================================================
header "Reading Shell Config Files for Tool Paths"

# ── Collect config files to read ──────────────────────────────────────────────
CONFIG_FILES=()
case "$OS_TYPE" in
    linux|unknown)
        for f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" \
                  "$HOME/.bash_profile" "$HOME/.zprofile" \
                  "/etc/environment" "/etc/profile"; do
            if [[ -f "$f" ]]; then CONFIG_FILES+=("$f"); fi
        done
        ;;
    macos)
        for f in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" \
                  "$HOME/.bash_profile" "$HOME/.profile"; do
            if [[ -f "$f" ]]; then CONFIG_FILES+=("$f"); fi
        done
        ;;
    windows)
        for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
            if [[ -f "$f" ]]; then CONFIG_FILES+=("$f"); fi
        done
        ;;
esac

if [[ ${#CONFIG_FILES[@]} -eq 0 ]]; then
    warn "No shell config files found. Will rely on PATH only."
else
    echo -e "  ${BOLD}Config files scanned:${RESET}"
    for f in "${CONFIG_FILES[@]}"; do echo -e "    ${CYAN}$f${RESET}"; done
    echo ""
fi

# ── Extract a variable's value from config files ───────────────────────────────
# Usage: extract_var VAR_NAME
# Looks for: export VAR_NAME=/some/path  or  VAR_NAME=/some/path
extract_var() {
    local var="$1"
    local val=""
    for f in "${CONFIG_FILES[@]}"; do
        # Match: export VAR=/path or VAR=/path (with or without quotes, ignoring comments)
        local found
        found=$(grep -E "^\s*(export\s+)?${var}[[:space:]]*=" "$f" 2>/dev/null \
            | grep -v '^\s*#' \
            | tail -1 \
            | sed -E "s/.*${var}[[:space:]]*=[[:space:]]*//" \
            | sed "s/['\"]//g" \
            | sed 's/#.*//' \
            | sed 's/[[:space:]]*$//' \
            | sed "s|~|$HOME|g")
        if [[ -n "$found" ]]; then
            val="$found"
        fi
    done
    echo "$val"
}

# ── Search PATH for a binary and return the parent installation root ───────────
# e.g.  /usr/lib/jvm/java-21-openjdk/bin/java  →  /usr/lib/jvm/java-21-openjdk
find_in_path() {
    local binary="$1"
    local bin_path
    bin_path=$(command -v "$binary" 2>/dev/null || echo "")
    echo "$bin_path"
}

# ── Resolve symlinks to real path ──────────────────────────────────────────────
real_path() {
    local p="$1"
    if command -v realpath &>/dev/null; then
        realpath "$p" 2>/dev/null || echo "$p"
    elif command -v readlink &>/dev/null; then
        readlink -f "$p" 2>/dev/null || echo "$p"
    else
        echo "$p"
    fi
}

# =============================================================================
# Detect JAVA_HOME
# =============================================================================
echo ""
info "Detecting Java / JDK …"

JAVA_HOME_DETECTED=""

# 1. From config files
_from_config=$(extract_var "JAVA_HOME")
if [[ -n "$_from_config" ]]; then
    _from_config="${_from_config%/bin}"
    if [[ -d "$_from_config" ]]; then JAVA_HOME_DETECTED="$_from_config"; fi
fi

# 2. From current environment
if [[ -z "$JAVA_HOME_DETECTED" && -n "${JAVA_HOME:-}" && -d "$JAVA_HOME" ]]; then
    JAVA_HOME_DETECTED="$JAVA_HOME"
fi

# 3. From 'java' on PATH — walk symlinks to find the JDK root
if [[ -z "$JAVA_HOME_DETECTED" ]]; then
    _java_bin=$(find_in_path java)
    if [[ -n "$_java_bin" ]]; then
        _real=$(real_path "$_java_bin")
        # Strip /bin/java suffix to get JAVA_HOME
        _home="${_real%/bin/java}"
        if [[ -d "$_home" ]]; then JAVA_HOME_DETECTED="$_home"; fi
    fi
fi

# 4. Common well-known locations (read directory names, no execution)
if [[ -z "$JAVA_HOME_DETECTED" ]]; then
    for candidate in \
        /usr/lib/jvm/java-21-openjdk \
        /usr/lib/jvm/java-21-openjdk-amd64 \
        /usr/lib/jvm/java-17-openjdk \
        /usr/lib/jvm/java-17-openjdk-amd64 \
        /usr/local/lib/jvm/java-21 \
        /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home \
        /opt/homebrew/opt/openjdk@21 \
        "C:/Program Files/Java/jdk-21" \
        "C:/Program Files/Eclipse Adoptium/jdk-21"; do
        if [[ -d "$candidate/bin" ]]; then
            JAVA_HOME_DETECTED="$candidate"
            break
        fi
    done
fi

# Read version from release file (no execution needed)
JAVA_VERSION_DETECTED=""
if [[ -n "$JAVA_HOME_DETECTED" && -f "$JAVA_HOME_DETECTED/release" ]]; then
    JAVA_VERSION_DETECTED=$(grep '^JAVA_VERSION=' "$JAVA_HOME_DETECTED/release" \
        | sed 's/JAVA_VERSION=//' | tr -d '"')
fi

if [[ -n "$JAVA_VERSION_DETECTED" ]]; then
    echo -e "  ${BOLD}Java version (from release file):${RESET} ${CYAN}${JAVA_VERSION_DETECTED}${RESET}"
fi

# =============================================================================
# Detect ANDROID_HOME / ANDROID_SDK_ROOT
# =============================================================================
echo ""
info "Detecting Android SDK …"

ANDROID_SDK_DETECTED=""

# 1. From config files
for _var in ANDROID_HOME ANDROID_SDK_ROOT; do
    _v=$(extract_var "$_var")
    if [[ -n "$_v" && -d "$_v/platforms" ]]; then
        ANDROID_SDK_DETECTED="$_v"
        break
    fi
done

# 2. From current environment
if [[ -z "$ANDROID_SDK_DETECTED" ]]; then
    for _var in ANDROID_HOME ANDROID_SDK_ROOT; do
        _v="${!_var:-}"
        if [[ -n "$_v" && -d "$_v/platforms" ]]; then
            ANDROID_SDK_DETECTED="$_v"
            break
        fi
    done
fi

# 3. Common default locations
if [[ -z "$ANDROID_SDK_DETECTED" ]]; then
    for candidate in \
        "$HOME/Android/Sdk" \
        "$HOME/android-sdk" \
        "$HOME/Library/Android/sdk" \
        "/opt/android-sdk" \
        "/usr/local/share/android-sdk" \
        "C:/Users/$USER/AppData/Local/Android/Sdk" \
        "C:/Android/sdk"; do
        candidate="${candidate/#\~/$HOME}"
        if [[ -d "$candidate/platforms" ]]; then
            ANDROID_SDK_DETECTED="$candidate"
            break
        fi
    done
fi

# =============================================================================
# Detect Gradle binary
# =============================================================================
echo ""
info "Detecting Gradle …"

GRADLE_BIN_DETECTED=""
GRADLE_VERSION_DETECTED=""

# 1. From config files (GRADLE_HOME)
_gradle_home=$(extract_var "GRADLE_HOME")
if [[ -n "$_gradle_home" ]]; then
    _gradle_home="${_gradle_home%/bin}"
    _candidate="$_gradle_home/bin/gradle"
    if [[ -x "$_candidate" ]]; then GRADLE_BIN_DETECTED="$_candidate"; fi
fi

# 2. From PATH
if [[ -z "$GRADLE_BIN_DETECTED" ]]; then
    _gradle_bin=$(find_in_path gradle)
    if [[ -n "$_gradle_bin" ]]; then
        GRADLE_BIN_DETECTED="$_gradle_bin"
    fi
fi

# 3. Common install dirs — version read from directory name only, no execution
if [[ -z "$GRADLE_BIN_DETECTED" ]]; then
    for dir_pattern in \
        /opt/gradle/gradle-*/bin \
        /usr/local/gradle/gradle-*/bin \
        /opt/homebrew/Cellar/gradle/*/bin \
        "C:/tools/gradle/gradle-*/bin"; do
        for candidate_dir in $dir_pattern; do
            [[ -x "$candidate_dir/gradle" ]] || continue
            GRADLE_BIN_DETECTED="$candidate_dir/gradle"
            break 2
        done
    done
fi

# Read Gradle version from directory name (e.g. gradle-8.13)
if [[ -n "$GRADLE_BIN_DETECTED" ]]; then
    GRADLE_VERSION_DETECTED=$(echo "$GRADLE_BIN_DETECTED" \
        | grep -oP 'gradle-\K[0-9]+\.[0-9]+(\.[0-9]+)?' || echo "")
    echo -e "  ${BOLD}Gradle binary :${RESET} ${CYAN}${GRADLE_BIN_DETECTED}${RESET}"
    if [[ -n "$GRADLE_VERSION_DETECTED" ]]; then
        echo -e "  ${BOLD}Gradle version:${RESET} ${CYAN}${GRADLE_VERSION_DETECTED}${RESET}"
    fi
fi

# =============================================================================
# STEP 2 – Confirm or override detected paths
# =============================================================================
header "Confirm Detected Paths"

echo ""
confirm_or_override "JAVA_HOME" "$JAVA_HOME_DETECTED" JAVA_HOME
echo ""
confirm_or_override "Android SDK" "$ANDROID_SDK_DETECTED" ANDROID_SDK_PATH
echo ""
confirm_or_override "Gradle binary" "$GRADLE_BIN_DETECTED" GRADLE_BIN

# Derive JAVA_HOME export variable
export JAVA_HOME

# Read highest installed SDK platform (no network, just directory listing)
LATEST_PLATFORM="35"
if [[ -n "$ANDROID_SDK_PATH" && -d "$ANDROID_SDK_PATH/platforms" ]]; then
    _detected=$(ls "$ANDROID_SDK_PATH/platforms" 2>/dev/null \
        | grep '^android-' | sort -t- -k2 -n | tail -1 | sed 's/android-//')
    if [[ -n "$_detected" ]]; then LATEST_PLATFORM="$_detected"; fi
    info "Highest installed SDK platform detected: android-${LATEST_PLATFORM}"
fi

# =============================================================================
# STEP 3 – Project metadata
# =============================================================================
header "Project Configuration"

ask_required "Application name (e.g. My Awesome App)" APP_NAME
ask          "Package name" "com.example.myapp" PACKAGE_NAME
ask          "Project directory name" \
             "$(echo "$APP_NAME" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')" \
             PROJECT_DIR_NAME
ask          "Output parent directory" "$HOME/Projects" OUTPUT_PARENT
ask          "Minimum SDK version" "26" MIN_SDK
ask          "Compile / Target SDK version" "$LATEST_PLATFORM" COMPILE_SDK
ask          "Kotlin version" "2.1.21" KOTLIN_VERSION
ask          "Compose BOM version" "2025.05.00" COMPOSE_BOM_VERSION

echo ""
info "AGP = Android Gradle Plugin  (format: X.Y.Z  e.g. 8.10.0)"
ask  "AGP version" "8.10.0" AGP_VERSION

# Validate formats
echo "$AGP_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || die "AGP version must be X.Y.Z (e.g. 8.10.0). Got: '$AGP_VERSION'"
echo "$KOTLIN_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || die "Kotlin version must be X.Y.Z (e.g. 2.1.21). Got: '$KOTLIN_VERSION'"

ask  "Gradle wrapper version (for gradle-wrapper.properties)" \
     "${GRADLE_VERSION_DETECTED:-8.13}" GRADLE_WRAPPER_VERSION
ask  "App version name" "1.0.0" VERSION_NAME
ask  "App version code" "1"     VERSION_CODE

# =============================================================================
# STEP 4 – Repository / Mirror Configuration
# =============================================================================
header "Repository & Mirror Configuration"

EXTRA_MAVEN_URLS=()
EXTRA_MAVEN_NAMES=()

echo ""
info "You can add extra Maven repositories (internal Nexus, Myket mirror, etc.)."
info "These are injected into pluginManagement and dependencyResolutionManagement."
echo ""

while true; do
    echo -en "${BOLD}Add a Maven repository? [y/N] or paste URL directly${RESET}: "
    read -r _add_maven

    # If the user typed a URL directly at the y/N prompt, use it
    if [[ "$_add_maven" == http* || "$_add_maven" == https* ]]; then
        _maven_url="$_add_maven"
    elif [[ "${_add_maven,,}" == "y" ]]; then
        echo -en "  ${BOLD}Repository URL${RESET}: "
        read -r _maven_url
        if [[ -z "$_maven_url" ]]; then
            warn "URL cannot be empty. Skipping."
            continue
        fi
    else
        # anything else (n, N, empty) → stop asking
        break
    fi

    echo -en "  ${BOLD}Repository name${RESET} [${YELLOW}custom${RESET}]: "
    read -r _maven_name
    _maven_name="${_maven_name:-custom}"

    EXTRA_MAVEN_URLS+=("${_maven_url%/}")
    EXTRA_MAVEN_NAMES+=("$_maven_name")
    success "Added: $_maven_name → ${_maven_url%/}"
done

# =============================================================================
# STEP 5 – Compatibility check
# =============================================================================
header "Compatibility Check"

# ver_num: convert "X.Y.Z" → integer for numeric comparison
# wrapped in || true so set -e never triggers on the echo $(( )) line
ver_num() {
    local ver="${1:-0.0.0}"
    local maj min pat
    maj=$(echo "$ver" | cut -d. -f1)
    min=$(echo "$ver" | cut -d. -f2)
    pat=$(echo "$ver" | cut -d. -f3)
    maj=${maj:-0}; min=${min:-0}; pat=${pat:-0}
    echo $(( maj * 10000 + min * 100 + pat )) || true
}

AGP_NUM=$(ver_num "$AGP_VERSION")       || AGP_NUM=0
KT_NUM=$(ver_num "$KOTLIN_VERSION")     || KT_NUM=0
GW_NUM=$(ver_num "$GRADLE_WRAPPER_VERSION") || GW_NUM=0

# Read Java major from JAVA_HOME/release — grep returns 1 if not found, guard with || true
JAVA_MAJOR="0"
if [[ -n "${JAVA_HOME:-}" && -f "$JAVA_HOME/release" ]]; then
    _jver=$(grep '^JAVA_VERSION=' "$JAVA_HOME/release" 2>/dev/null || true)
    _jver=$(echo "$_jver" | tr -d '"' | cut -d= -f2)
    _jver="${_jver:-0}"
    JAVA_MAJOR="${_jver%%.*}"
    # Java 1.8 style → extract second segment
    if [[ "$JAVA_MAJOR" == "1" ]]; then
        JAVA_MAJOR=$(echo "$_jver" | cut -d. -f2) || JAVA_MAJOR=8
    fi
fi
JAVA_MAJOR="${JAVA_MAJOR:-0}"

ROWS=()
HAS_FAIL=false
HAS_WARN=false

# add_row: store row and set flags — use if/else, never bare [[ ]] with &&
# because [[ ... ]] returning 1 (false) would trigger set -e
add_row() {
    ROWS+=("$1|$2|$3|$4|$5")
    if [[ "$4" == "FAIL" ]]; then HAS_FAIL=true; fi
    if [[ "$4" == "WARN" ]]; then HAS_WARN=true; fi
}

# Java ↔ AGP
if [[ -n "$JAVA_MAJOR" && "$JAVA_MAJOR" -gt 0 && "$JAVA_MAJOR" -lt 17 ]]; then
    add_row "Java ↔ AGP" "JDK $JAVA_MAJOR" "AGP $AGP_VERSION" FAIL \
        "AGP 8.x requires JDK 17+. Found JDK $JAVA_MAJOR"
else
    add_row "Java ↔ AGP" "JDK ${JAVA_MAJOR}" "AGP $AGP_VERSION" OK \
        "JDK ${JAVA_MAJOR} satisfies AGP $AGP_VERSION"
fi

# AGP ↔ Gradle
if [[ "$GW_NUM" -lt 80000 ]]; then
    add_row "AGP ↔ Gradle" "AGP $AGP_VERSION" "Gradle $GRADLE_WRAPPER_VERSION" FAIL \
        "AGP $AGP_VERSION requires Gradle 8.0+"
elif [[ "$AGP_NUM" -ge 80900 && "$GW_NUM" -lt 81100 ]]; then
    add_row "AGP ↔ Gradle" "AGP $AGP_VERSION" "Gradle $GRADLE_WRAPPER_VERSION" WARN \
        "AGP $AGP_VERSION works best with Gradle 8.11+"
else
    add_row "AGP ↔ Gradle" "AGP $AGP_VERSION" "Gradle $GRADLE_WRAPPER_VERSION" OK \
        "Compatible"
fi

# AGP ↔ Kotlin
if [[ "$AGP_NUM" -ge 81000 && "$KT_NUM" -lt 20100 ]]; then
    add_row "AGP ↔ Kotlin" "AGP $AGP_VERSION" "Kotlin $KOTLIN_VERSION" FAIL \
        "AGP $AGP_VERSION requires Kotlin 2.1+"
else
    add_row "AGP ↔ Kotlin" "AGP $AGP_VERSION" "Kotlin $KOTLIN_VERSION" OK \
        "Compatible"
fi

# minSdk ↔ compileSdk
if [[ "$MIN_SDK" -gt "$COMPILE_SDK" ]]; then
    add_row "minSdk ↔ compileSdk" "minSdk $MIN_SDK" "compileSdk $COMPILE_SDK" FAIL \
        "minSdk cannot exceed compileSdk"
else
    add_row "minSdk ↔ compileSdk" "minSdk $MIN_SDK" "compileSdk $COMPILE_SDK" OK \
        "OK"
fi

# ── Print compatibility table ─────────────────────────────────────────────────
COL1=22; COL2=18; COL3=22; COL4=6; COL5=44
TOTAL=$(( COL1 + COL2 + COL3 + COL4 + COL5 + 16 ))
DIVIDER=$(printf '─%.0s' $(seq 1 $TOTAL))

# pad: truncate+left-pad a string to exactly N chars — || true guards printf exit
pad() { printf "%-${1}s" "${2:0:$1}" || true; }

echo ""
echo -e "  ${BOLD}┌${DIVIDER}┐${RESET}"
printf "  ${BOLD}│ %-${COL1}s │ %-${COL2}s │ %-${COL3}s │ %-${COL4}s │ %-${COL5}s │${RESET}\n" \
    "Check" "Value A" "Value B" "Status" "Note"
echo -e "  ${BOLD}├${DIVIDER}┤${RESET}"

for row in "${ROWS[@]}"; do
    IFS='|' read -r c1 c2 c3 c4 c5 <<< "$row"
    # Truncate note if too long
    if [[ "${#c5}" -gt "$COL5" ]]; then c5="${c5:0:$((COL5-1))}…"; fi
    case "$c4" in
        OK)   ICON="${GREEN}OK    ${RESET}" ;;
        WARN) ICON="${YELLOW}WARN  ${RESET}" ;;
        FAIL) ICON="${RED}FAIL  ${RESET}" ;;
        *)    ICON="??    " ;;
    esac
    # Use echo -e to honour colour escapes; build the line with subshells
    echo -e "  │ $(pad $COL1 "$c1") │ $(pad $COL2 "$c2") │ $(pad $COL3 "$c3") │ ${ICON}│ $(pad $COL5 "$c5") │"
done

echo -e "  ${BOLD}└${DIVIDER}┘${RESET}"
echo ""

# ── Evaluate results — use if/else, never bare boolean && with set -e ─────────
if $HAS_FAIL; then
    die "Fix the FAIL items above before continuing."
fi

if $HAS_WARN; then
    warn "Some checks show warnings."
    echo -en "Continue anyway? [y/N]: "
    read -r _wc
    if [[ "${_wc,,}" != "y" ]]; then
        die "Aborted by user."
    fi
else
    success "All compatibility checks passed."
fi

# =============================================================================
# STEP 6 – Confirm & scaffold
# =============================================================================
PACKAGE_PATH="${PACKAGE_NAME//.//}"
OUTPUT_PARENT="${OUTPUT_PARENT/#\~/$HOME}"
PROJECT_ROOT="$OUTPUT_PARENT/$PROJECT_DIR_NAME"

header "Summary"
echo ""
echo -e "  ${BOLD}OS           :${RESET} $OS_NAME"
echo -e "  ${BOLD}JAVA_HOME    :${RESET} $JAVA_HOME"
echo -e "  ${BOLD}Android SDK  :${RESET} ${ANDROID_SDK_PATH:-<not set>}"
echo -e "  ${BOLD}Gradle bin   :${RESET} $GRADLE_BIN"
echo -e "  ${BOLD}App name     :${RESET} $APP_NAME"
echo -e "  ${BOLD}Package      :${RESET} $PACKAGE_NAME"
echo -e "  ${BOLD}Output path  :${RESET} $PROJECT_ROOT"
echo -e "  ${BOLD}minSdk       :${RESET} $MIN_SDK"
echo -e "  ${BOLD}compileSdk   :${RESET} $COMPILE_SDK"
echo -e "  ${BOLD}Kotlin       :${RESET} $KOTLIN_VERSION"
echo -e "  ${BOLD}Compose BOM  :${RESET} $COMPOSE_BOM_VERSION"
echo -e "  ${BOLD}AGP          :${RESET} $AGP_VERSION"
echo -e "  ${BOLD}Gradle wrap  :${RESET} $GRADLE_WRAPPER_VERSION"
echo ""
echo -en "Create project? [Y/n]: "
read -r CONFIRM
if [[ "${CONFIRM,,}" == "n" ]]; then die "Aborted."; fi

# =============================================================================
# STEP 7 – Directory tree
# =============================================================================
header "Creating Directory Structure"

mkdir -p "$PROJECT_ROOT/gradle"
mkdir -p "$PROJECT_ROOT/app/src/main/kotlin/$PACKAGE_PATH/ui/theme"
mkdir -p "$PROJECT_ROOT/app/src/main/kotlin/$PACKAGE_PATH/screens"
mkdir -p "$PROJECT_ROOT/app/src/main/res/values"
mkdir -p "$PROJECT_ROOT/app/src/main/res/drawable"
mkdir -p "$PROJECT_ROOT/app/src/main/res/mipmap-hdpi"
mkdir -p "$PROJECT_ROOT/app/src/main/res/mipmap-mdpi"
mkdir -p "$PROJECT_ROOT/app/src/main/res/mipmap-xhdpi"
mkdir -p "$PROJECT_ROOT/app/src/main/res/mipmap-xxhdpi"
mkdir -p "$PROJECT_ROOT/app/src/main/res/mipmap-xxxhdpi"
mkdir -p "$PROJECT_ROOT/app/src/androidTest/kotlin/$PACKAGE_PATH"
mkdir -p "$PROJECT_ROOT/app/src/test/kotlin/$PACKAGE_PATH"

success "Directory tree created."

# =============================================================================
# STEP 8 – libs.versions.toml
# =============================================================================
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
junit                 = "4.13.2"
junitExt              = "1.2.1"
espressoCore          = "3.6.1"

[libraries]
androidx-core-ktx               = { group = "androidx.core",            name = "core-ktx",                version.ref = "coreKtx" }
androidx-lifecycle-runtime-ktx  = { group = "androidx.lifecycle",       name = "lifecycle-runtime-ktx",   version.ref = "lifecycleRuntimeKtx" }
androidx-activity-compose       = { group = "androidx.activity",        name = "activity-compose",         version.ref = "activityCompose" }
androidx-navigation-compose     = { group = "androidx.navigation",      name = "navigation-compose",       version.ref = "navigationCompose" }
androidx-compose-bom            = { group = "androidx.compose",         name = "compose-bom",              version.ref = "composeBom" }
androidx-compose-ui             = { group = "androidx.compose.ui",      name = "ui" }
androidx-compose-ui-graphics    = { group = "androidx.compose.ui",      name = "ui-graphics" }
androidx-compose-ui-tooling     = { group = "androidx.compose.ui",      name = "ui-tooling" }
androidx-compose-ui-tooling-preview = { group = "androidx.compose.ui", name = "ui-tooling-preview" }
androidx-compose-material3      = { group = "androidx.compose.material3", name = "material3" }
junit                           = { group = "junit",                    name = "junit",                    version.ref = "junit" }
androidx-junit-ext              = { group = "androidx.test.ext",        name = "junit",                    version.ref = "junitExt" }
androidx-espresso-core          = { group = "androidx.test.espresso",   name = "espresso-core",            version.ref = "espressoCore" }
androidx-compose-ui-test-junit4   = { group = "androidx.compose.ui",   name = "ui-test-junit4" }
androidx-compose-ui-test-manifest = { group = "androidx.compose.ui",   name = "ui-test-manifest" }

[plugins]
android-application  = { id = "com.android.application",             version.ref = "agp" }
kotlin-android       = { id = "org.jetbrains.kotlin.android",        version.ref = "kotlin" }
kotlin-compose       = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
TOML

success "libs.versions.toml written."

# =============================================================================
# STEP 9 – Build files
# =============================================================================
header "Writing build files"

# Root build.gradle.kts
cat > "$PROJECT_ROOT/build.gradle.kts" <<'KTS'
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android)      apply false
    alias(libs.plugins.kotlin.compose)      apply false
}
KTS

# Build extra maven blocks
_pm_extra=""
_dm_extra=""
for i in "${!EXTRA_MAVEN_URLS[@]}"; do
    _u="${EXTRA_MAVEN_URLS[$i]}"
    _n="${EXTRA_MAVEN_NAMES[$i]}"
    _pm_extra+="        maven { name = \"${_n}\"; url = uri(\"${_u}\") }\n"
    _dm_extra+="        maven { name = \"${_n}\"; url = uri(\"${_u}\") }\n"
done

# settings.gradle.kts
{
cat <<KTS
pluginManagement {
    repositories {
KTS
printf '%b' "$_pm_extra"
cat <<KTS
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
KTS
printf '%b' "$_dm_extra"
cat <<KTS
        google()
        mavenCentral()
    }
}

rootProject.name = "$APP_NAME"
include(":app")
KTS
} > "$PROJECT_ROOT/settings.gradle.kts"

# app/build.gradle.kts
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

    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" } }
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

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit.ext)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)

    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
KTS

success "Build files written."

# =============================================================================
# STEP 10 – AndroidManifest + Kotlin sources
# =============================================================================
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

header "Writing Kotlin source files"
SRC="$PROJECT_ROOT/app/src/main/kotlin/$PACKAGE_PATH"

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

private val DarkColorScheme  = darkColorScheme()
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

    MaterialTheme(colorScheme = colorScheme, content = content)
}
KT

cat > "$SRC/ui/theme/Type.kt" <<KT
package $PACKAGE_NAME.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val Typography = Typography(
    bodyLarge = TextStyle(
        fontFamily    = FontFamily.Default,
        fontWeight    = FontWeight.Normal,
        fontSize      = 16.sp,
        lineHeight    = 24.sp,
        letterSpacing = 0.5.sp
    )
)
KT

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
        topBar = { TopAppBar(title = { Text("$APP_NAME") }) }
    ) { innerPadding ->
        Column(
            modifier            = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(16.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
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

# =============================================================================
# STEP 11 – Resources & misc files
# =============================================================================
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

cat > "$PROJECT_ROOT/app/proguard-rules.pro" <<PRO
-keep class $PACKAGE_NAME.** { *; }
PRO

cat > "$PROJECT_ROOT/.gitignore" <<GIT
.gradle/
build/
**/build/
!gradle/wrapper/gradle-wrapper.jar
local.properties
*.iml
.idea/
*.DS_Store
/captures
.externalNativeBuild/
.cxx/
*.apk
*.aab
GIT

# local.properties
cat > "$PROJECT_ROOT/local.properties" <<PROP
sdk.dir=${ANDROID_SDK_PATH:-}
PROP

# gradle.properties
cat > "$PROJECT_ROOT/gradle.properties" <<PROP
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configuration-cache=true
android.useAndroidX=true
android.enableJetifier=false
kotlin.code.style=official
PROP

if [[ -n "${JAVA_HOME:-}" ]]; then
    echo "org.gradle.java.home=$JAVA_HOME" >> "$PROJECT_ROOT/gradle.properties"
fi

success "Resource and config files written."

# =============================================================================
# STEP 12 – Gradle wrapper setup (using local binary, no download)
# =============================================================================
header "Setting up Gradle Wrapper"

mkdir -p "$PROJECT_ROOT/gradle/wrapper"

# gradle-wrapper.properties — points to the local binary distribution
_dist_url="https://services.gradle.org/distributions/gradle-${GRADLE_WRAPPER_VERSION}-bin.zip"
_dist_url_escaped="${_dist_url//:/'\\:'}"

cat > "$PROJECT_ROOT/gradle/wrapper/gradle-wrapper.properties" <<PROPS
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=${_dist_url_escaped}
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
PROPS

# gradlew — thin wrapper that delegates to the local Gradle binary directly
cat > "$PROJECT_ROOT/gradlew" <<GRADLEW
#!/usr/bin/env bash
# Thin wrapper — delegates to your local Gradle installation.
# Generated by create_android_project.sh
exec "${GRADLE_BIN}" "\$@"
GRADLEW
chmod +x "$PROJECT_ROOT/gradlew"

success "gradlew written (delegates to $GRADLE_BIN)."
info "No gradle-wrapper.jar needed — your local binary is used directly."

# =============================================================================
# STEP 13 – Optional initial build
# =============================================================================
header "Initial Build"

echo -en "Attempt an initial build now? [y/N]: "
read -r BUILD_NOW
if [[ "${BUILD_NOW,,}" == "y" ]]; then
    info "Running: $PROJECT_ROOT/gradlew assembleDebug"
    cd "$PROJECT_ROOT"
    export JAVA_HOME
    if ./gradlew assembleDebug; then
        success "Build succeeded! APK → app/build/outputs/apk/debug/"
    else
        warn "Build failed. Common fixes:"
        warn "  • Check JAVA_HOME: $JAVA_HOME"
        warn "  • Check Android SDK: ${ANDROID_SDK_PATH:-<not set>}"
        warn "  • Ensure compileSdk platform is installed: android-${COMPILE_SDK}"
        warn "  • Run: ./gradlew dependencies  to diagnose dependency issues"
    fi
fi

# =============================================================================
# DONE
# =============================================================================
header "Project Ready! 🎉"
echo ""
echo -e "  ${BOLD}Location   :${RESET} $PROJECT_ROOT"
echo -e "  ${BOLD}Package    :${RESET} $PACKAGE_NAME"
echo -e "  ${BOLD}JAVA_HOME  :${RESET} $JAVA_HOME"
echo -e "  ${BOLD}Gradle bin :${RESET} $GRADLE_BIN"
echo ""
echo -e "  ${CYAN}Quick commands:${RESET}"
echo -e "  cd $PROJECT_ROOT"
echo -e "  ./gradlew assembleDebug          # build APK"
echo -e "  ./gradlew installDebug           # build & deploy to device"
echo -e "  ./gradlew test                   # unit tests"
echo -e "  ./gradlew connectedAndroidTest   # instrumented tests"
echo -e "  ./gradlew lint                   # lint"
echo ""
success "Happy coding!"