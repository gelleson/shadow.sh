#!/bin/bash
set -e

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
REPO_URL="https://raw.githubusercontent.com/gelleson/shadow/main/shadow.sh"

main() {
    mkdir -p "$INSTALL_DIR"

    echo "Downloading shadow..."
    curl -fsSL "$REPO_URL" -o "$INSTALL_DIR/shadow"
    chmod +x "$INSTALL_DIR/shadow"

    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo ""
        echo "Add to your shell profile:"
        echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
        echo ""
    fi

    echo "Installed shadow to $INSTALL_DIR/shadow"
}

main "$@"
