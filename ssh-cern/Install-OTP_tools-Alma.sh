#!/bin/bash

################################################################################
# Script Name: Install-OTP_tools.sh
# Description: Setup for CERN 2FA using 'pass', 'pass-otp', and 'zbar'.
#              Uses 'dnf' (Fedora/RHEL/Alma) as the primary package manager.
#              Automates secret initialization from a QR code image.
# Author: Shuwei Ye (yesw@bnl.gov)
# Date: 2026-Feb
# Version: 20260226-r1
################################################################################

# --- Function: Usage ---
show_usage() {
    echo "Usage: $(basename "$0") [-h|--help] [--version]"
    echo ""
    echo "This script sets up CERN 2FA using 'pass', 'pass-otp', and 'zbar'."
    echo "It installs required tools via 'dnf', generates GPG keys if needed,"
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
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
fi
case "$ID $ID_LIKE" in
    *rhel*|*fedora*) ;;
    *) echo "Warning: This script is intended for Fedora/RHEL/Alma. Detected OS: ${NAME:-$(uname -s)}"
       exit 1 ;;
esac

# Ensure GPG can prompt for passphrase in the terminal
export GPG_TTY=$(tty)

# --- Check if CERN_2FA already exists ---
if pass show CERN_2FA >/dev/null 2>&1; then
    echo "Check: CERN_2FA secret already exists in the password store. Skipping setup."
else
    # --- OS & Package Manager Detection ---
    OS_TYPE="linux"
    PKG_MGR="dnf"

    if ! command -v dnf >/dev/null 2>&1; then
        echo "Error: This script is intended for Fedora/Alma/RHEL based systems with 'dnf'."
        exit 1
    fi

    echo "Detected Platform: $OS_TYPE | Package Manager: $PKG_MGR"

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

    # --- GPG Directory Permission Check ---
    get_owner() { stat -c '%U' "$1"; }

    if [[ -d "$HOME/.gnupg" ]]; then
        owner=$(get_owner "$HOME/.gnupg")
        if [[ "$owner" != "$USER" ]]; then
            echo "Warning: Fixing $HOME/.gnupg ownership..."
            sudo chown -R "$USER" "$HOME/.gnupg"
        fi
        chmod 700 "$HOME/.gnupg"
    else
        mkdir -p "$HOME/.gnupg"
        chmod 700 "$HOME/.gnupg"
    fi

    # --- Tool Installation Logic ---
    install_tool() {
        local binary=$1; local pkg_name=$2
        if ! command -v "$binary" >/dev/null 2>&1; then
            echo "Action: Installing $pkg_name via $PKG_MGR..."
            sudo dnf install -y "$pkg_name"
        fi
    }

    install_tool "pass" "pass"
    install_tool "zbarimg" "zbar"
    install_tool "expect" "expect"
    install_tool "gpg" "gnupg"

    if ! pass otp --help >/dev/null 2>&1; then
        sudo dnf install -y pass-otp
    fi

    # Configure Pinentry
    install_tool "pinentry-curses" "pinentry"
    PINENTRY_PATH=$(command -v pinentry-curses || command -v pinentry)

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
