#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# EV3 Pybricks Development Environment Setup - Linux (Arch / Debian)
# =============================================================================

# -- Colors & output helpers --------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}\n"; }

# -- Resolve project root -----------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# -- Distro detection ---------------------------------------------------------
DISTRO_FAMILY="unknown"

detect_distro() {
    if command -v pacman &>/dev/null; then
        DISTRO_FAMILY="arch"
        info "Detected Arch-based distribution"
    elif command -v apt &>/dev/null; then
        DISTRO_FAMILY="debian"
        info "Detected Debian/Ubuntu-based distribution"
    else
        DISTRO_FAMILY="unknown"
        warn "Could not detect package manager. System packages will need manual installation."
    fi
}

# -- System dependencies ------------------------------------------------------
install_system_deps() {
    header "Installing System Dependencies"

    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        info "Installing packages via pacman..."
        sudo pacman -S --needed --noconfirm python python-pip libusb hidapi base-devel
    elif [[ "$DISTRO_FAMILY" == "debian" ]]; then
        info "Updating package lists..."
        sudo apt update
        info "Installing packages via apt..."
        sudo apt install -y python3 python3-pip python3-venv libusb-1.0-0-dev libhidapi-dev build-essential
    else
        warn "Skipping system package installation (unknown distro)."
        warn "Please manually install: python3, pip, venv, libusb, hidapi"
        return 0
    fi

    success "System dependencies installed."
}

# -- Python version check -----------------------------------------------------
check_python_version() {
    header "Checking Python Version"

    if ! command -v python3 &>/dev/null; then
        error "python3 not found. Please install Python 3.10 or higher."
        exit 1
    fi

    local py_version
    py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')
    local py_major py_minor
    py_major=$(python3 -c 'import sys; print(sys.version_info.major)')
    py_minor=$(python3 -c 'import sys; print(sys.version_info.minor)')

    if [[ "$py_major" -lt 3 ]] || [[ "$py_major" -eq 3 && "$py_minor" -lt 10 ]]; then
        error "Python 3.10+ is required. Found: Python $py_version"
        exit 1
    fi

    success "Found Python $py_version"
}

# -- Virtual environment -------------------------------------------------------
setup_venv() {
    header "Setting Up Virtual Environment"

    local venv_dir="$PROJECT_ROOT/.venv"

    if [[ -d "$venv_dir" ]]; then
        info "Virtual environment already exists at $venv_dir"
        info "To recreate, delete it first: rm -rf $venv_dir"
    else
        info "Creating virtual environment at $venv_dir..."
        python3 -m venv "$venv_dir"
        success "Virtual environment created."
    fi

    # shellcheck disable=SC1091
    source "$venv_dir/bin/activate"
    info "Virtual environment activated."

    info "Upgrading pip..."
    pip install --upgrade pip --quiet
    success "pip upgraded to $(pip --version | awk '{print $2}')"
}

# -- Python packages -----------------------------------------------------------
install_python_packages() {
    header "Installing Python Packages"

    local requirements="$PROJECT_ROOT/requirements.txt"

    if [[ ! -f "$requirements" ]]; then
        error "requirements.txt not found at $requirements"
        exit 1
    fi

    info "Installing packages from requirements.txt..."
    pip install -r "$requirements"
    success "Python packages installed."

    info "Verifying installations..."
    python3 -c "import pybricksdev; print('  pybricksdev: ' + pybricksdev.__version__)" 2>/dev/null \
        || warn "Could not verify pybricksdev import"
}

# -- udev rules ----------------------------------------------------------------
setup_udev_rules() {
    header "Setting Up udev Rules (USB Access)"

    local udev_file="/etc/udev/rules.d/99-pybricksdev.rules"

    if [[ -f "$udev_file" ]]; then
        info "udev rules already exist at $udev_file"
        info "To regenerate, delete the file first: sudo rm $udev_file"
        return 0
    fi

    info "Generating udev rules for EV3 USB access..."

    local pybricksdev_bin="$PROJECT_ROOT/.venv/bin/pybricksdev"
    if [[ -x "$pybricksdev_bin" ]]; then
        "$pybricksdev_bin" udev | sudo tee "$udev_file" > /dev/null
    elif command -v pybricksdev &>/dev/null; then
        pybricksdev udev | sudo tee "$udev_file" > /dev/null
    else
        warn "pybricksdev not found. Skipping udev rules."
        warn "After installation, run: pybricksdev udev | sudo tee $udev_file"
        return 0
    fi

    sudo udevadm control --reload-rules
    sudo udevadm trigger
    success "udev rules installed. Reconnect your EV3 if it's plugged in."
}

# -- VS Code extensions --------------------------------------------------------
setup_vscode() {
    header "VS Code Extensions"

    if ! command -v code &>/dev/null; then
        info "VS Code CLI not found. If you use VS Code, consider installing these extensions:"
        info "  - lego-education.ev3-micropython"
        info "  - ms-python.python"
        info "  - ms-python.vscode-pylance"
        return 0
    fi

    info "Installing recommended VS Code extensions..."

    local extensions=("lego-education.ev3-micropython" "ms-python.python" "ms-python.vscode-pylance")
    local installed
    installed=$(code --list-extensions 2>/dev/null || true)

    for ext in "${extensions[@]}"; do
        if echo "$installed" | grep -qi "$ext"; then
            info "  $ext (already installed)"
        else
            if code --install-extension "$ext" --force &>/dev/null; then
                success "  Installed $ext"
            else
                warn "  Failed to install $ext"
            fi
        fi
    done
}

# -- Summary -------------------------------------------------------------------
print_summary() {
    header "Setup Complete!"

    local py_version
    py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')

    echo -e "${GREEN}${BOLD}What was configured:${NC}"
    echo -e "  ${GREEN}*${NC} System dependencies installed (${DISTRO_FAMILY})"
    echo -e "  ${GREEN}*${NC} Python ${py_version}"
    echo -e "  ${GREEN}*${NC} Virtual environment: ${PROJECT_ROOT}/.venv"
    echo -e "  ${GREEN}*${NC} Python packages from requirements.txt"
    echo -e "  ${GREEN}*${NC} udev rules for EV3 USB access"
    echo ""
    echo -e "${YELLOW}${BOLD}Next steps:${NC}"
    echo ""
    echo -e "  1. Activate the virtual environment:"
    echo -e "     ${CYAN}source .venv/bin/activate${NC}"
    echo ""
    echo -e "  2. Prepare a microSD card with the EV3 MicroPython image:"
    echo -e "     ${CYAN}https://pybricks.com/install/mindstorms-ev3/installation/${NC}"
    echo -e "     Download the ~360MB image and flash it with Etcher or dd."
    echo ""
    echo -e "  3. Insert the microSD card into your EV3 and boot it up."
    echo -e "     (Status light turns green when ready)"
    echo ""
    echo -e "  4. Connect the EV3 via mini-USB cable and start coding!"
    echo ""
    echo -e "  5. Open VS Code in this project directory:"
    echo -e "     ${CYAN}code ${PROJECT_ROOT}${NC}"
    echo ""
}

# -- Main ----------------------------------------------------------------------
main() {
    header "EV3 Pybricks Development Environment Setup"
    info "Project: $PROJECT_ROOT"

    local skip_system=false

    for arg in "$@"; do
        case $arg in
            --skip-system-deps) skip_system=true ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-system-deps  Skip system package installation"
                echo "  -h, --help          Show this help"
                exit 0
                ;;
            *)
                warn "Unknown option: $arg"
                ;;
        esac
    done

    detect_distro

    if [[ "$skip_system" == false ]]; then
        install_system_deps
    else
        info "Skipping system dependency installation (--skip-system-deps)"
    fi

    check_python_version
    setup_venv
    install_python_packages
    setup_udev_rules
    setup_vscode
    print_summary
}

main "$@"
