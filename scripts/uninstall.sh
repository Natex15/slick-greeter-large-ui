#!/usr/bin/env bash
#
# uninstall.sh - Restore stock Linux Mint Slick-Greeter package
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOCK_PACKAGE="slick-greeter"
STOCK_VERSION="2.2.6+zena"

# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

DRY_RUN=false
ASSUME_YES=false

usage() {
    cat <<EOF
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS]

Revert custom Slick-Greeter package and restore the official stock distro package.

${BOLD}Options:${NC}
  -y, --yes      Run non-interactively, accepting prompts
  -n, --dry-run  Show steps without making system changes
  -h, --help     Show this help message

${BOLD}Safety Notes:${NC}
  - Your existing /etc/lightdm configuration and wallpaper settings are preserved.
  - The official stock Slick-Greeter package will be reinstalled from Linux Mint repositories.
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
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
echo -e "${BOLD} Slick-Greeter Rollback / Uninstaller${NC}"
echo -e "${BOLD}======================================================${NC}"

# Check current installed package
CURRENT_VER=$(dpkg-query -W -f='${Version}' slick-greeter 2>/dev/null || echo "none")
info "Currently installed version: $CURRENT_VER"

if [[ "$CURRENT_VER" == "none" ]]; then
    warn "slick-greeter is not currently installed."
fi

# Find available stock repo version
# Filter out any locally-built custom versions to find the official upstream package.
info "Querying APT repository for stock slick-greeter version..."
REPO_VERSION=$(apt-cache madison slick-greeter | awk '{print $3}' | grep -vE '\+(custom|local|mod|build)[0-9]*$' | head -n 1 || true)

if [[ -n "$REPO_VERSION" ]]; then
    TARGET_STOCK_VER="$REPO_VERSION"
else
    TARGET_STOCK_VER="$STOCK_VERSION"
fi

info "Target stock repository version: $TARGET_STOCK_VER"

if [[ "$CURRENT_VER" == "$TARGET_STOCK_VER" ]]; then
    info "The stock package version ($TARGET_STOCK_VER) is already installed."
fi

if [[ "$DRY_RUN" == true ]]; then
    info "[Dry-Run] Would run: sudo apt-get install --reinstall -y slick-greeter=${TARGET_STOCK_VER}"
    info "[Dry-Run] Preserving /etc/lightdm/slick-greeter.conf"
    info "[Dry-Run] Would run verify.sh"
else
    if [[ "$ASSUME_YES" != true ]]; then
        read -r -p "Reinstall stock slick-greeter ($TARGET_STOCK_VER) from official repositories? [y/N] " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            info "Rollback aborted."
            exit 0
        fi
    fi

    info "Reinstalling stock package from official repositories..."
    sudo apt-get update
    sudo apt-get install --reinstall -y "slick-greeter=${TARGET_STOCK_VER}" || sudo apt-get install --reinstall -y slick-greeter

    pass "Stock Slick-Greeter restored."

    # Post-verification
    echo ""
    info "Verifying restored installation..."
    "${SCRIPT_DIR}/verify.sh"
fi

echo ""
echo -e "${GREEN}${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD} Rollback complete!${NC}"
echo -e "${GREEN}${BOLD}======================================================${NC}"
echo "Your LightDM settings in /etc/lightdm/ have been preserved."
echo "You may test the restored greeter with:"
echo "    slick-greeter --test-mode"
echo "Or lock/logout to view the restored login screen."
