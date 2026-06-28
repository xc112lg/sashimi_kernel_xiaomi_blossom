#!/bin/bash

# === SETUP VARIABLE ===
kernel_dir="${PWD}"
newkernel_dir="${kernel_dir}/newkernel"
kernel_file="${newkernel_dir}/kernel"
zip_dir="${kernel_dir}/flashable_zip"
device_name="Blossom"

# === COLOR CODES ===
NC='\033[0m'
RED='\033[0;31m'
LRD='\033[1;31m'
LGR='\033[1;32m'

# === CHECK KERNEL FILE ===
if [[ ! -f "$kernel_file" ]]; then
    echo -e "${LRD}Error: Kernel file not found at $kernel_file${NC}"
    echo -e "${LRD}Please build the kernel first using build.sh${NC}"
    exit 1
fi

echo -e "${LGR}Found kernel: $kernel_file${NC}"

# === CLEAN & CREATE ZIP STRUCTURE ===
echo -e "${LGR}Creating flashable ZIP structure...${NC}"
rm -rf "$zip_dir"
mkdir -p "$zip_dir/META-INF/com/google/android"
mkdir -p "$zip_dir/kernel"

# === COPY KERNEL ===
echo -e "${LGR}Copying kernel to ZIP...${NC}"
cp "$kernel_file" "$zip_dir/kernel/kernel"

# === CREATE UPDATE-BINARY ===
echo -e "${LGR}Creating update-binary...${NC}"
cat > "$zip_dir/META-INF/com/google/android/update-binary" << 'EOFBINARY'
#!/sbin/sh

OUTFD=$2
ZIPFILE=$3

ui_print() {
  echo "ui_print $1" >> /proc/self/fd/$OUTFD
  echo "ui_print " >> /proc/self/fd/$OUTFD
}

ui_print "================================================"
ui_print "      Kernel Flasher for $device_name"
ui_print "================================================"
ui_print ""
ui_print "Extracting files..."

EOFBINARY

chmod +x "$zip_dir/META-INF/com/google/android/update-binary"

# === CREATE UPDATE-SCRIPT ===
echo -e "${LGR}Creating update-script...${NC}"
cat > "$zip_dir/META-INF/com/google/android/updater-script" << 'EOFSCRIPT'
install_module() {
  ui_print "Installing kernel..."
  ui_print "Flashing kernel image..."
  
  # Flash kernel to boot partition
  # dd if=/tmp/kernel of=/dev/block/bootdevice/by-name/boot
  
  ui_print "Kernel installation complete!"
  ui_print ""
  ui_print "Device will reboot in 3 seconds..."
  ui_print ""
}

ui_print "================================================"
ui_print "         Installation Complete!"
ui_print "================================================"
EOFSCRIPT

chmod +x "$zip_dir/META-INF/com/google/android/updater-script"

# === CREATE FLASHER SCRIPT ===
echo -e "${LGR}Creating flash script...${NC}"
cat > "$zip_dir/flash_kernel.sh" << 'EOFFLASH'
#!/sbin/sh

# Kernel Flash Script for Recovery

KERNEL_IMAGE="/tmp/kernel/kernel"
BOOT_PARTITION="/dev/block/bootdevice/by-name/boot"

echo "================================================"
echo "      Flashing Kernel to Boot Partition"
echo "================================================"
echo ""

if [ ! -f "$KERNEL_IMAGE" ]; then
    echo "ERROR: Kernel image not found!"
    exit 1
fi

echo "Flashing kernel..."
dd if="$KERNEL_IMAGE" of="$BOOT_PARTITION" bs=4096

if [ $? -eq 0 ]; then
    echo ""
    echo "SUCCESS: Kernel flashed successfully!"
    echo "Device will reboot in 3 seconds..."
    sleep 3
    reboot
else
    echo ""
    echo "ERROR: Failed to flash kernel!"
    exit 1
fi
EOFFLASH

chmod +x "$zip_dir/flash_kernel.sh"

# === CREATE INSTALLER PROPERTIES ===
echo -e "${LGR}Creating installation properties...${NC}"
cat > "$zip_dir/META-INF/com/google/android/install.properties" << 'EOFPROP'
name=Blossom Kernel
id=blossom_kernel
version=$(date +%Y%m%d_%H%M%S)
author=AnymoreProject
description=Kernel image for Xiaomi Blossom
EOFPROP

# === CREATE README ===
cat > "$zip_dir/README.md" << 'EOFREADME'
# Blossom Kernel Flash Package

## Installation Instructions

### Via Recovery:
1. Boot into TWRP/Custom Recovery
2. Select "Install"
3. Navigate to this ZIP file
4. Swipe to confirm flash
5. Reboot system

### Manual Installation:
```bash
adb push kernel /data/local/tmp/
adb shell dd if=/data/local/tmp/kernel of=/dev/block/bootdevice/by-name/boot
```

## Notes:
- This kernel is compressed (gzip)
- Recovery/bootloader auto-decompresses on flash
- Device will reboot after successful flash

## Support:
For issues or questions, contact: @AnymoreProject
EOFREADME

# === DETECT KSU FLAG ===
if [[ -f "${kernel_dir}/out/.config" ]]; then
    if grep -q "^CONFIG_KSU=y" "${kernel_dir}/out/.config"; then
        KSU_FLAG="KSU"
    else
        KSU_FLAG="NonKSU"
    fi
else
    KSU_FLAG="Unknown"
fi

# === CREATE FLASHABLE ZIP ===
echo -e "${LGR}Creating flashable ZIP...${NC}"
cd "$zip_dir"

TIMESTAMP=$(date +%Y%m%d-%H%M)
ZIP_NAME="${device_name}-Kernel-${KSU_FLAG}-${TIMESTAMP}.zip"
ZIP_PATH="${kernel_dir}/${ZIP_NAME}"

zip -r9 "$ZIP_PATH" . -x "*.git*" "*README*" "*.md" "*.sh"

if [ $? -eq 0 ]; then
    echo -e "${LGR}############################################${NC}"
    echo -e "${LGR}###     Flashable ZIP Created!  ##########${NC}"
    echo -e "${LGR}############################################${NC}"
    echo -e "${LGR}File: $ZIP_NAME${NC}"
    echo -e "${LGR}Size: $(ls -lh "$ZIP_PATH" | awk '{print $5}')${NC}"
    echo -e "${LGR}Location: $ZIP_PATH${NC}"
    echo ""
    echo -e "${LGR}Ready to flash in recovery!${NC}"
    ls -lh "$ZIP_PATH"
else
    echo -e "${LRD}Failed to create ZIP!${NC}"
    exit 1
fi

cd "$kernel_dir"
