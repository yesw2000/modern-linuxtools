#!/bin/bash

################################################################################
# Script Name: Install-OTP_tools.sh
# Description: Cross-platform setup for CERN 2FA using 'pass', 'pass-otp',
#              and 'zbar'. Prioritizes Homebrew (brew) on all platforms.
#              Automates secret insertion using 'expect'.
# Author: Shuwei Ye (yesw@bnl.gov)
# Date: 2026-Feb
# Version: 20260226-r1
################################################################################

# --- Function: Usage ---
show_usage() {
    echo "Usage: $(basename "$0") [-h|--help] [--version]"
    echo ""
    echo "This script sets up CERN 2FA using 'pass', 'pass-otp', and 'zbar'."
    echo "It installs required tools via Homebrew (or fallback package manager),"
    echo "and initializes the CERN 2FA secret from a QR code image."
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message and exit"
    echo "  --version      Show the script version and exit"
}

# --- Argument Parsing ---
case "$1" in
    -h|--help)
        show_usage
        exit 0
        ;;
    --version)
        echo "$(basename "$0") version $(grep "^# Version:" "$0" | sed 's/^# Version: //')"
        exit 0
        ;;
    -*)
        echo "Error: Unknown option '$1'"
        show_usage
        exit 1
        ;;
esac

# --- OS Check ---
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Warning: This script is intended for macOS. Detected OS: $(uname -s)"
    exit 1
fi

# Ensure GPG can prompt for passphrase in the terminal
export GPG_TTY=$(tty)

# --- Check if CERN_2FA already exists ---
if pass show CERN_2FA >/dev/null 2>&1; then
    echo "Check: CERN_2FA secret already exists in the password store. Skipping setup."
else
    # --- QR Code Image Input & Validation ---
    while true; do
        read -p "Enter path to CERN 2FA QR Image: " pathOfCERN_QRCodeImg
        if [[ -f "$pathOfCERN_QRCodeImg" ]]; then
            mime_type=$(file --mime-type -b "$pathOfCERN_QRCodeImg")
            [[ "$mime_type" =~ ^image/ ]] && break
            echo "Error: Not an image."
        else
            echo "Error: File not found."
        fi
    done

    # --- Package Manager Selection & Installation ---
    PKG_MGR="unknown"

    # 1. Try to find or install Homebrew (Recommended by user)
    if ! command -v brew >/dev/null 2>&1; then
        # Check standard Linuxbrew/Homebrew locations before installing
        if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        elif [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f "$HOME/.linuxbrew/bin/brew" ]]; then
            eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
        else
            echo "Action: Homebrew not found. Installing Homebrew (brew.sh)..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            
            # Load brew for the current session
            if [[ -d /home/linuxbrew/.linuxbrew/bin ]]; then
                eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            elif [[ -d /opt/homebrew/bin ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
        fi
    fi

    if command -v brew >/dev/null 2>&1; then
        PKG_MGR="brew"
    else
        # Fallback to native managers only if brew installation failed
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            if command -v dnf >/dev/null 2>&1; then PKG_MGR="dnf"
            elif command -v apt-get >/dev/null 2>&1; then PKG_MGR="apt"
            fi
        fi
    fi

    if [[ "$PKG_MGR" == "unknown" ]]; then
        echo "Error: Could not find or install a supported package manager."
        exit 1
    fi

    echo "Using Package Manager: $PKG_MGR"

    # --- Tool Installation Logic ---
    install_tool() {
        local binary=$1; local pkg_name=$2
        if ! command -v "$binary" >/dev/null 2>&1; then
            echo "Action: Installing $pkg_name via $PKG_MGR..."
            case $PKG_MGR in
                brew)   brew install "$pkg_name" ;;
                dnf)    sudo dnf install -y "$pkg_name" ;;
                apt)    sudo apt-get update && sudo apt-get install -y "$pkg_name" ;;
            esac
        fi
    }

    # Install tools via Brew (or fallback)
    install_tool "pass" "pass"
    install_tool "zbarimg" "zbar"
    install_tool "expect" "expect"
    install_tool "gpg" "gnupg"

    if ! pass otp --help >/dev/null 2>&1; then
        install_tool "pass-otp" "pass-otp"
    fi

    # Pinentry setup (Brew versions)
    if [[ "$PKG_MGR" == "brew" ]]; then
        brew install pinentry
        # Locate pinentry binary in brew path
        PINENTRY_PATH=$(brew --prefix)/bin/pinentry
        # On macOS, pinentry-mac is better
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install pinentry-mac
            PINENTRY_PATH=$(brew --prefix)/bin/pinentry-mac
        fi
    else
        install_tool "pinentry-curses" "pinentry"
        PINENTRY_PATH=$(command -v pinentry-curses || command -v pinentry)
    fi

    mkdir -p ~/.gnupg
    echo "pinentry-program $PINENTRY_PATH" > ~/.gnupg/gpg-agent.conf
    gpgconf --kill gpg-agent

    # --- Setup & Configuration ---
    echo "Extracting OTP secret..."
    otp_uri=$(zbarimg --raw "$pathOfCERN_QRCodeImg" | head -n 1)
    [[ -z "$otp_uri" ]] && { echo "Error: Extraction failed."; exit 1; }

    if ! gpg -k | grep -q "pub"; then
        echo "No GPG key found. Starting interactive generation..."
        gpg --full-generate-key
    fi

    gpg_key=$(gpg -k --with-colons | awk -F: '/^pub/ {print $5; exit}')
    pass init "$gpg_key"

    echo "Automating CERN_2FA secret insertion..."
    expect <<EOF
set timeout 30
spawn pass otp insert CERN_2FA
expect {
    -re "Enter (OTP Secret|otpauth:// URI).*" { send "$otp_uri\r"; exp_continue }
    -re "Retype (OTP Secret|otpauth:// URI).*" { send "$otp_uri\r"; exp_continue }
    "already exists" { send "y\r"; exp_continue }
    eof
}
EOF
fi

# Final Verification
echo "Verification: Current CERN 2FA Code:"
pass otp CERN_2FA
echo "Success: CERN 2FA setup completed."
