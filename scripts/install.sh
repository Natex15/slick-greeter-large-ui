#!/usr/bin/env bash
#
# install.sh - Build and install Slick-Greeter Large UI package for Linux Mint
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PATCH_FILE="${REPO_ROOT}/patches/large-login-ui.patch"
CONFIG_EXAMPLE="${REPO_ROOT}/config/slick-greeter.conf.example"

# Supported versions
SUPPORTED_VERSION="2.2.6+zena"
SUPPORTED_DISTRO="Linuxmint"
SUPPORTED_CODENAME="zena"

# Defaults
BUILD_DIR="${TMPDIR:-/tmp}/slick-greeter-build-${UID}"
CUSTOM_REV_SUFFIX="+custom1"
WALLPAPER_PATH=""
WRITE_CONFIG=false
DRY_RUN=false
ASSUME_YES=false
SKIP_BUILD_DEP=false

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

pass() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

usage() {
    cat <<EOF
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS]

Build and install the custom Large UI package for Slick-Greeter.

${BOLD}Options:${NC}
  --wallpaper <path>       Set or update the greeter background wallpaper in /etc/lightdm/slick-greeter.conf
  --write-config           Write /etc/lightdm/slick-greeter.conf from example template if not present
  --package-rev <suffix>   Custom Debian version suffix (default: +custom1)
  --build-dir <path>       Temporary build directory (default: /tmp/slick-greeter-build-<uid>)
  --skip-build-dep         Skip running apt-get build-dep
  -y, --yes                Run non-interactively, accepting prompts
  -n, --dry-run            Show what steps would be executed without making system changes
  -h, --help               Show this help message

${BOLD}Examples:${NC}
  ./scripts/install.sh
  ./scripts/install.sh --wallpaper /usr/share/backgrounds/linuxmint/custom.png
  ./scripts/install.sh --dry-run
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --wallpaper)
            WALLPAPER_PATH="$2"
            WRITE_CONFIG=true
            shift 2
            ;;
        --write-config)
            WRITE_CONFIG=true
            shift
            ;;
        --package-rev)
            CUSTOM_REV_SUFFIX="$2"
            shift 2
            ;;
        --build-dir)
            BUILD_DIR="$2"
            shift 2
            ;;
        --skip-build-dep)
            SKIP_BUILD_DEP=true
            shift
            ;;
        -y|--yes)
            ASSUME_YES=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD} Slick-Greeter Large UI Installer${NC}"
echo -e "${BOLD}======================================================${NC}"

# Check patch file existence
if [[ ! -f "$PATCH_FILE" ]]; then
    error "Patch file not found at: $PATCH_FILE"
    exit 1
fi

# Step 1: Pre-flight checks (OS and Version)
info "Checking system environment..."

if ! command -v lsb_release >/dev/null 2>&1; then
    error "lsb_release command not found. Please ensure lsb-release is installed."
    exit 1
fi

DISTRO_ID=$(lsb_release -si 2>/dev/null || echo "")
DISTRO_RELEASE=$(lsb_release -sr 2>/dev/null || echo "")
DISTRO_CODENAME=$(lsb_release -sc 2>/dev/null || echo "")

info "Detected OS: $DISTRO_ID $DISTRO_RELEASE ($DISTRO_CODENAME)"

if [[ ! "$DISTRO_ID" =~ ^(Linuxmint|LinuxMint)$ ]]; then
    warn "This installer is tailored for Linux Mint. Detected: $DISTRO_ID"
    if [[ "$ASSUME_YES" != true ]]; then
        read -r -p "Do you want to continue anyway? [y/N] " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            info "Aborting."
            exit 1
        fi
    fi
fi

# Check available/installed slick-greeter version
CURRENT_INSTALLED_VER=$(dpkg-query -W -f='${Version}' slick-greeter 2>/dev/null || echo "none")
info "Currently installed slick-greeter version: $CURRENT_INSTALLED_VER"

# Check candidate version from apt
CANDIDATE_VER=$(apt-cache policy slick-greeter | awk '/Candidate:/ {print $2}')
info "APT candidate version for slick-greeter: $CANDIDATE_VER"

BASE_VER="${CANDIDATE_VER}"
if [[ "$BASE_VER" == "(none)" || -z "$BASE_VER" ]]; then
    if [[ "$CURRENT_INSTALLED_VER" != "none" ]]; then
        BASE_VER="${CURRENT_INSTALLED_VER}"
    fi
fi

# Clean base version (strip previous local custom revisions like +custom1, +local1)
CLEAN_BASE_VER=$(echo "$BASE_VER" | sed -E 's/\+([a-zA-Z0-9_-]+)$//g')

if [[ "$CLEAN_BASE_VER" != "$SUPPORTED_VERSION" ]]; then
    echo ""
    error "Unsupported Slick-Greeter version detected: '$CLEAN_BASE_VER'"
    echo -e "${YELLOW}This repository is currently tested and verified for: ${SUPPORTED_VERSION} (${SUPPORTED_DISTRO} ${SUPPORTED_CODENAME})${NC}"
    echo ""
    echo "To add support for your version:"
    echo "  1. Fetch the source for your version: apt source slick-greeter"
    echo "  2. Test applying the patch: patch -p1 --dry-run < patches/large-login-ui.patch"
    echo "  3. If hunks fail, adjust the line offsets or context in patches/large-login-ui.patch"
    echo "  4. Update SUPPORTED_VERSION in scripts/install.sh"
    echo ""
    exit 1
fi

pass "Target Slick-Greeter base version verified: $CLEAN_BASE_VER"

# Step 2: Display Manager checks
info "Checking display manager configuration..."

DM_PATH="/etc/X11/default-display-manager"
if [[ -f "$DM_PATH" ]]; then
    ACTIVE_DM=$(cat "$DM_PATH" 2>/dev/null || true)
    info "Default display manager: $ACTIVE_DM"
    if [[ "$ACTIVE_DM" != *"/lightdm"* && "$ACTIVE_DM" != "lightdm" ]]; then
        warn "Default display manager is set to '$ACTIVE_DM' rather than LightDM."
        warn "Slick-Greeter requires LightDM to function."
    fi
fi

# Step 3: Check build prerequisites & deb-src
info "Checking build tooling and deb-src availability..."

MISSING_TOOLS=()
for tool in dpkg-buildpackage dch patch apt-get; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    warn "Missing required tools: ${MISSING_TOOLS[*]}"
    info "You may need to install: dpkg-dev devscripts build-essential patch"
    if [[ "$DRY_RUN" == true ]]; then
        info "[Dry-Run] Would run: sudo apt-get update && sudo apt-get install -y dpkg-dev devscripts build-essential patch"
    else
        echo "Installing prerequisite tools requires sudo privileges."
        if [[ "$ASSUME_YES" != true ]]; then
            read -r -p "Install missing build tools now? [Y/n] " response
            if [[ "$response" =~ ^[Nn]$ ]]; then
                error "Cannot proceed without required build tools."
                exit 1
            fi
        fi
        sudo apt-get update
        sudo apt-get install -y dpkg-dev devscripts build-essential patch
    fi
fi

# Check if apt source works (deb-src enabled)
if ! grep -rq "^[[:space:]]*deb-src" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    error "No active deb-src repositories found in /etc/apt/sources.list or /etc/apt/sources.list.d/"
    echo "Please enable source repositories (deb-src) in Software Sources or /etc/apt/sources.list.d/official-package-repositories.list and run 'sudo apt update'."
    exit 1
fi

# Step 4: Install build dependencies if needed
if [[ "$SKIP_BUILD_DEP" != true ]]; then
    info "Ensuring package build dependencies are installed..."
    if [[ "$DRY_RUN" == true ]]; then
        info "[Dry-Run] Would run: sudo apt-get build-dep -y slick-greeter"
    else
        info "Running: sudo apt-get build-dep -y slick-greeter"
        sudo apt-get build-dep -y slick-greeter
    fi
fi

# Step 5: Acquire pristine source in build directory
mkdir -p "$BUILD_DIR"
SOURCE_DIR="${BUILD_DIR}/slick-greeter-${CLEAN_BASE_VER}"

info "Preparing source tree in $BUILD_DIR..."

if [[ -d "$SOURCE_DIR" ]]; then
    info "Found existing source directory: $SOURCE_DIR"
else
    info "Downloading pristine source via 'apt source slick-greeter'..."
    if [[ "$DRY_RUN" == true ]]; then
        info "[Dry-Run] Would fetch apt source slick-greeter into $BUILD_DIR"
        mkdir -p "$SOURCE_DIR"
    else
        (cd "$BUILD_DIR" && apt source "slick-greeter=${CLEAN_BASE_VER}")
    fi
fi

# Step 6: Apply patch safely (idempotent check)
if [[ "$DRY_RUN" == true ]]; then
    info "[Dry-Run] Would test and apply $PATCH_FILE to $SOURCE_DIR"
else
    info "Checking patch application status..."
    cd "$SOURCE_DIR"

    # Test if patch applies cleanly
    if patch -p1 --dry-run -s -f < "$PATCH_FILE" >/dev/null 2>&1; then
        info "Applying Large UI patch..."
        patch -p1 < "$PATCH_FILE"
        pass "Patch applied cleanly with zero errors."
    elif patch -R -p1 --dry-run -s -f < "$PATCH_FILE" >/dev/null 2>&1; then
        info "Patch is already applied to source tree. Skipping re-application."
    else
        error "Patch failed to apply cleanly to source in $SOURCE_DIR!"
        echo "Running patch with verbose output for diagnostics:"
        patch -p1 --dry-run < "$PATCH_FILE" || true
        exit 1
    fi
fi

# Determine target version string
TARGET_VERSION="${CLEAN_BASE_VER}${CUSTOM_REV_SUFFIX}"
if [[ "$CURRENT_INSTALLED_VER" == "$TARGET_VERSION" ]]; then
    # Auto-increment revision if the exact version is already installed
    TARGET_VERSION="${CLEAN_BASE_VER}+custom2"
fi

info "Target package version: $TARGET_VERSION"

# Step 7: Update changelog & Build Debian package
if [[ "$DRY_RUN" == true ]]; then
    info "[Dry-Run] Would update changelog to $TARGET_VERSION and run dpkg-buildpackage -us -uc -b"
else
    info "Updating debian/changelog..."
    cd "$SOURCE_DIR"
    DEBEMAIL="noreply@local" DEBFULLNAME="Custom Build" \
        dch -b -v "${TARGET_VERSION}" --force-distribution -D "${DISTRO_CODENAME}" "Custom large login UI"

    info "Building package with dpkg-buildpackage (binary only)..."
    dpkg-buildpackage -us -uc -b

    pass "Package built successfully!"
fi

# Step 8: Deterministically locate the generated .deb
DEB_FILE="${BUILD_DIR}/slick-greeter_${TARGET_VERSION}_amd64.deb"
if [[ ! -f "$DEB_FILE" && "$DRY_RUN" != true ]]; then
    # Search in parent directory of SOURCE_DIR
    FOUND_DEBS=($(find "$BUILD_DIR" -maxdepth 1 -name "slick-greeter_${TARGET_VERSION}_*.deb"))
    if [[ ${#FOUND_DEBS[@]} -gt 0 ]]; then
        DEB_FILE="${FOUND_DEBS[0]}"
    else
        error "Could not locate built package for version $TARGET_VERSION in $BUILD_DIR"
        exit 1
    fi
fi

# Step 9: Install package
info "Installing package..."
if [[ "$DRY_RUN" == true ]]; then
    info "[Dry-Run] Would install $DEB_FILE via 'sudo dpkg -i $DEB_FILE'"
else
    info "Installing: $DEB_FILE"
    sudo dpkg -i "$DEB_FILE"
    pass "Package installed successfully."
fi

# Step 10: LightDM Configuration Safety
CONF_TARGET="/etc/lightdm/slick-greeter.conf"

if [[ -n "$WALLPAPER_PATH" ]]; then
    if [[ ! -f "$WALLPAPER_PATH" ]]; then
        warn "Specified wallpaper path does not exist on disk: $WALLPAPER_PATH"
    fi
    info "Configuring Slick-Greeter wallpaper to: $WALLPAPER_PATH"
    if [[ "$DRY_RUN" == true ]]; then
        info "[Dry-Run] Would update background in $CONF_TARGET"
    else
        if [[ ! -f "$CONF_TARGET" ]]; then
            sudo cp "$CONFIG_EXAMPLE" "$CONF_TARGET"
        fi
        sudo sed -i -E "s|^#?[[:space:]]*background=.*|background=${WALLPAPER_PATH}|g" "$CONF_TARGET"
        pass "Updated wallpaper in $CONF_TARGET"
    fi
elif [[ "$WRITE_CONFIG" == true ]]; then
    if [[ -f "$CONF_TARGET" ]]; then
        info "Preserving existing $CONF_TARGET"
    else
        info "Writing example configuration to $CONF_TARGET..."
        if [[ "$DRY_RUN" == true ]]; then
            info "[Dry-Run] Would copy $CONFIG_EXAMPLE to $CONF_TARGET"
        else
            sudo cp "$CONFIG_EXAMPLE" "$CONF_TARGET"
            pass "Wrote default configuration to $CONF_TARGET"
        fi
    fi
else
    if [[ -f "$CONF_TARGET" ]]; then
        info "Preserved existing configuration at $CONF_TARGET"
    else
        info "No $CONF_TARGET present; using distro default settings. (Reference template available at config/slick-greeter.conf.example)"
    fi
fi

# Step 11: Final verification
echo ""
info "Running post-installation verification..."
if [[ "$DRY_RUN" != true ]]; then
    "${SCRIPT_DIR}/verify.sh"
else
    info "[Dry-Run] Would run verify.sh"
fi

echo ""
echo -e "${GREEN}${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD} Slick-Greeter Large UI installation complete!${NC}"
echo -e "${GREEN}${BOLD}======================================================${NC}"
echo "To test the greeter without rebooting, you can run:"
echo "    slick-greeter --test-mode"
echo "Or lock/logout to view the login screen."
