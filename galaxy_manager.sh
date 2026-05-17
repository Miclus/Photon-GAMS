#!/bin/bash

echo ""
echo "========================================"
echo "  Galaxy GAMS Resolution Manager"
echo "========================================"
echo ""
echo "1. Download high resolution version (backup low resolution image)"
echo "2. Restore backup (delete downloaded image)"
echo ""
read -p "Please select an option (1 or 2): " choice

case $choice in
    1)
        download
        ;;
    2)
        restore
        ;;
    *)
        echo "Invalid choice, exiting."
        exit 1
        ;;
esac

download() {
    echo ""
    echo "Downloading high resolution version..."

    if [ -f "shaders/image/galaxy_gams.png" ]; then
        echo "Low res image found, backing up..."
        mv "shaders/image/galaxy_gams.png" "shaders/image/galaxy_gams.png.backup"
        echo "Backup completed: galaxy_gams.png.backup"
    else
        echo "Low res image not found"
    fi
    
    echo ""
    echo "Downloading new image from GitHub..."

    mkdir -p "shaders/image"

    if command -v curl &> /dev/null; then
        curl -L -o "shaders/image/galaxy_gams.png" \
            "https://raw.githubusercontent.com/OUdefie17/Photon-GAMS/main/shaders/image/galaxy_gams.png"
    elif command -v wget &> /dev/null; then
        wget -O "shaders/image/galaxy_gams.png" \
            "https://raw.githubusercontent.com/OUdefie17/Photon-GAMS/main/shaders/image/galaxy_gams.png"
    else
        echo "[✗] Error: curl or wget not found, cannot download"
        if [ -f "shaders/image/galaxy_gams.png.backup" ]; then
            echo "Restoring backup..."
            mv "shaders/image/galaxy_gams.png.backup" "shaders/image/galaxy_gams.png"
        fi
        exit 1
    fi

    if [ -f "shaders/image/galaxy_gams.png" ]; then
        echo ""
        echo "[✓] Download successful!"
        echo ""
    else
        echo ""
        echo "[✗] Download failed, please check your internet connection"
        echo ""
        if [ -f "shaders/image/galaxy_gams.png.backup" ]; then
            echo "Restoring backup file..."
            mv "shaders/image/galaxy_gams.png.backup" "shaders/image/galaxy_gams.png"
        fi
        exit 1
    fi
}

restore() {
    echo ""
    echo "Restoring backup..."

    if [ -f "shaders/image/galaxy_gams.png" ]; then
        size=$(stat -c%s "shaders/image/galaxy_gams.png" 2>/dev/null || stat -f%z "shaders/image/galaxy_gams.png" 2>/dev/null)
        if [ -n "$size" ] && [ "$size" -lt 20971520 ]; then
            echo "[✓] Current image is already low resolution"
            echo ""
            exit 0
        fi
        echo "Deleting downloaded image..."
        rm -f "shaders/image/galaxy_gams.png"
        echo "Deletion completed"
    fi

    if [ -f "shaders/image/galaxy_gams.png.backup" ]; then
        echo "Restoring backup file..."
        mv "shaders/image/galaxy_gams.png.backup" "shaders/image/galaxy_gams.png"
        echo "[✓] Restore completed!"
    else
        echo "[✗] Backup file not found"
    fi
    echo ""
}
