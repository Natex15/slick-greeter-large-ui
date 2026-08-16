#!/usr/bin/env bash
#
# verify.sh - Verify Slick-Greeter Large UI installation and LightDM configuration
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# Override pass/warn with counting versions for verification
pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    PASS_COUNT=$((PASS_COUNT + 1))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    WARN_COUNT=$((WARN_COUNT + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

section() {
    echo ""
    echo -e "${BOLD}=== $* ===${NC}"
}

section "System & Distribution Check"

if command -v lsb_release >/dev/null 2>&1; then
    DISTRO_ID=$(lsb_release -si 2>/dev/null || echo "Unknown")
    DISTRO_RELEASE=$(lsb_release -sr 2>/dev/null || echo "Unknown")
    DISTRO_CODENAME=$(lsb_release -sc 2>/dev/null || echo "Unknown")
    info "Detected OS: $DISTRO_ID $DISTRO_RELEASE ($DISTRO_CODENAME)"

    if [[ "$DISTRO_ID" =~ ^(Linuxmint|LinuxMint)$ ]]; then
        if [[ "$DISTRO_CODENAME" == "zena" || "$DISTRO_RELEASE" =~ ^22\. ]]; then
            pass "Supported OS: Linux Mint $DISTRO_RELEASE ($DISTRO_CODENAME)"
        else
            warn "Linux Mint detected, but codename '$DISTRO_CODENAME' is not 22.3 (zena). Patch compatibility should be verified."
        fi
    else
        warn "Non-Mint distribution detected: $DISTRO_ID. This patch is tailored for Linux Mint Slick-Greeter."
    fi
else
    warn "lsb_release command not found."
fi

section "Display Manager & LightDM Check"

# Check default display manager
DM_PATH="/etc/X11/default-display-manager"
if [[ -f "$DM_PATH" ]]; then
    ACTIVE_DM=$(cat "$DM_PATH" 2>/dev/null || true)
    info "Default display manager file: $ACTIVE_DM"
    if [[ "$ACTIVE_DM" == *"/lightdm"* || "$ACTIVE_DM" == "lightdm" ]]; then
        pass "LightDM is set as the default display manager."
    else
        warn "Default display manager is set to '$ACTIVE_DM' (not LightDM)."
    fi
else
    info "No /etc/X11/default-display-manager found, checking systemd service..."
fi

# Check systemd lightdm service
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet lightdm 2>/dev/null; then
        pass "LightDM service is currently active (running)."
    else
        info "LightDM service is currently not active or system is in a non-graphical target."
    fi
fi

# Check LightDM config for slick-greeter session
if command -v lightdm >/dev/null 2>&1; then
    LIGHTDM_CONFIG=$(lightdm --show-config 2>&1 || true)
    if echo "$LIGHTDM_CONFIG" | grep -q "greeter-session=slick-greeter"; then
        pass "LightDM configuration has greeter-session=slick-greeter"
    else
        warn "greeter-session is not explicitly reported as slick-greeter in 'lightdm --show-config'."
    fi
else
    fail "lightdm command not found in PATH."
fi

section "Slick-Greeter Package & Binary Check"

if dpkg -l slick-greeter >/dev/null 2>&1; then
    INSTALLED_VER=$(dpkg-query -W -f='${Version}' slick-greeter 2>/dev/null || true)
    info "Installed slick-greeter version: $INSTALLED_VER"

    if [[ "$INSTALLED_VER" =~ \+(custom|local|mod|build)[0-9]*$ ]]; then
        pass "Custom Large UI package is currently installed ($INSTALLED_VER)."
    elif [[ "$INSTALLED_VER" == "2.2.6+zena"* ]]; then
        info "Stock Slick-Greeter 2.2.6+zena package is installed."
    else
        info "Other Slick-Greeter version installed: $INSTALLED_VER"
    fi
else
    fail "slick-greeter package is NOT installed."
fi

GREETER_BIN="/usr/sbin/slick-greeter"
if [[ -x "$GREETER_BIN" ]]; then
    pass "Slick-Greeter binary present and executable: $GREETER_BIN"
    BIN_VER=$("$GREETER_BIN" --version 2>/dev/null || true)
    if [[ -n "$BIN_VER" ]]; then
        info "Binary reported version: $BIN_VER"
    fi
else
    fail "Slick-Greeter binary not found at $GREETER_BIN"
fi

section "Slick-Greeter Configuration Check"

CONF_FILE="/etc/lightdm/slick-greeter.conf"
if [[ -f "$CONF_FILE" ]]; then
    pass "Configuration file exists: $CONF_FILE"
    if [[ -r "$CONF_FILE" ]]; then
        info "Current configuration:"
        while IFS= read -r line; do
            echo "    $line"
        done < "$CONF_FILE"
    else
        info "Config file exists but is not readable without root/sudo."
    fi
else
    info "No custom $CONF_FILE found (using default distro settings)."
fi

section "Verification Summary"
echo -e "Passed checks : ${GREEN}$PASS_COUNT${NC}"
echo -e "Warnings      : ${YELLOW}$WARN_COUNT${NC}"
echo -e "Failures      : ${RED}$FAIL_COUNT${NC}"

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "\n${GREEN}${BOLD}Verification status: OK${NC}"
    exit 0
else
    echo -e "\n${RED}${BOLD}Verification status: ISSUES DETECTED${NC}"
    exit 1
fi
