#!/bin/bash
sudo apt update
sudo apt install ccache -y
# === SETUP VARIABLE ===
kernel_dir="${PWD}"
objdir="${kernel_dir}/out"
builddir="${kernel_dir}/build"
anykernel="/tmp/src/android/AnyKernel3"
CLANG_DIR="/tmp/src/android/neutron-clang"
GCC64_DIR="/tmp/src/android/gcc64/aarch64--glibc--stable-2025.08-1"
GCC32_DIR="/tmp/src/android/gcc32"
TC_DIR="/tmp/src/android/"
CONFIG_FILE="blossom_defconfig"
mkdir tmp
export CCACHE_DIR=tmp
export USE_CCACHE=1
# === ENVIRONMENT EXPORT ===
export ARCH="arm64"
export KBUILD_BUILD_USER="t.me"
export KBUILD_BUILD_HOST="AnymoreProject"
export PATH="$CLANG_DIR/bin:$GCC64_DIR/bin:$GCC32_DIR/bin:$PATH"
export CCACHE=$(command -v ccache)

# === COLOR CODES ===
NC='\033[0m'
RED='\033[0;31m'
LRD='\033[1;31m'
LGR='\033[1;32m'

# === BUILD TIMER ===
BUILD_START=0
BUILD_END=0

# === TOOLCHAIN CHECK ===
if ! [ -d "$CLANG_DIR/bin" ]; then
    echo -e "${LGR}Neutron Clang not found! Installing using AntMan...${NC}"
    mkdir -p "$CLANG_DIR"
    cd "$CLANG_DIR"
    
    # Download and run AntMan
    if ! bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") -S; then
        echo -e "${LRD}AntMan installation failed! Aborting...${NC}"
        exit 1
    fi
    
    cd "$kernel_dir"
fi

# === CLEAN BUILD ===
echo -e "${LGR}Cleaning previous build...${NC}"
rm -rf "$objdir"
mkdir -p "$objdir"

# === CLEAN SOURCE TREE ===
echo -e "${LGR}Cleaning source tree with make mrproper...${NC}"
make mrproper
if [ $? -ne 0 ]; then
    echo -e "${LRD}Warning: make mrproper had issues, continuing...${NC}"
fi

# === REGENERATE DEFCONFIG IF NEEDED ===
if [ "$VAYU_CONFIG_REGEN" = "true" ]; then
    echo -e "${LGR}Regenerating defconfig...${NC}"
    make ARCH=$ARCH O=$objdir vendor/sm8150-perf_defconfig \
        vendor/debugfs.config \
        vendor/xiaomi/sm8150-common.config \
        vendor/xiaomi/vayu.config
    cp "$objdir/.config" "arch/arm64/configs/${CONFIG_FILE}"
else
    echo -e "${RED}Not regenerating config${NC}"
fi

# === FUNCTION: Generate defconfig ===
make_defconfig() {
    echo -e "${LGR}Generating defconfig...${NC}"
    make -s ARCH=$ARCH O=$objdir $CONFIG_FILE -j$(nproc)
    if [ $? -ne 0 ]; then
        echo -e "${LRD}Failed to generate defconfig${NC}"
        exit 1
    fi
}

# === FUNCTION: Compile kernel ===
compile() {
    BUILD_START=$(date +%s)

    echo -e "${LGR}######### Compiling kernel #########${NC}"
    make -j$(nproc --all) \
        O="$objdir" \
        ARCH="arm64" \
        SUBARCH="arm64" \
        DTC_EXT="dtc" \
        CLANG_TRIPLE="aarch64-linux-gnu-" \
        CROSS_COMPILE="aarch64-linux-gnu-" \
        CROSS_COMPILE_ARM32="arm-linux-gnueabi-" \
        CROSS_COMPILE_COMPAT="arm-linux-gnueabi-" \
        LD="ld.lld" \
        AR="llvm-ar" \
        NM="llvm-nm" \
        STRIP="llvm-strip" \
        OBJCOPY="llvm-objcopy" \
        OBJDUMP="llvm-objdump" \
        READELF="llvm-readelf" \
        HOSTCC="clang" \
        HOSTCXX="clang++" \
        HOSTAR="llvm-ar" \
        HOSTLD="ld.lld" \
        LLVM=1 \
        LLVM_IAS=1 \
        CC="ccache clang" \
        ${1:-}

    if [ $? -ne 0 ]; then
        echo -e "${LRD}Kernel compilation failed!${NC}"
        exit 1
    fi

    BUILD_END=$(date +%s)
}

# === FUNCTION: Check output ===
completion() {
    local image="${objdir}/arch/arm64/boot/Image"
    local output_dir="${kernel_dir}/newkernel"
    local output_kernel="${output_dir}/kernel"
    local root_kernel="${kernel_dir}/kernel"

    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"

    if [[ -f "$image" ]]; then
        echo -e "${LGR}############################################"
        echo -e "${LGR}############# Build Successful!  ##########"
        echo -e "${LGR}############################################${NC}"
        echo -e "${LGR}Kernel Image: $image${NC}"
        
        # Copy kernel to newkernel folder
        echo -e "${LGR}Copying kernel to: $output_kernel${NC}"
        cp "$image" "$output_kernel"
        
        # Compress with gzip (maximum compression)
        echo -e "${LGR}Compressing kernel with gzip...${NC}"
        gzip -9 -f "$output_kernel"
        
        # Rename from kernel.gz back to kernel (bootloader detects compression by magic bytes)
        mv "${output_kernel}.gz" "$output_kernel"
        
        # Also copy to root for Android build system
        echo -e "${LGR}Copying kernel to root: $root_kernel${NC}"
        cp "$output_kernel" "$root_kernel"
        
        echo -e "${LGR}Output locations:${NC}"
        echo -e "${LGR}  - $output_kernel${NC}"
        echo -e "${LGR}  - $root_kernel${NC}"
        ls -lh "$output_kernel" "$root_kernel"
    else
        echo -e "${LRD}############################################"
        echo -e "${LRD}##      Kernel build failed :'(           ##"
        echo -e "${LRD}############################################${NC}"
        exit 1
    fi
}

# === FUNCTION: Show build time ===
show_build_time() {
    local duration=$((BUILD_END - BUILD_START))
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))

    echo -e "${LGR}############################################${NC}"
    echo -e "${LGR} Build Time : ${hours}h ${minutes}m ${seconds}s${NC}"
    echo -e "${LGR}############################################${NC}"
}

# === DETECT KSU FLAG === (DISABLED - not packaging)
# detect_ksu_flag() {
#     if grep -q "^CONFIG_KSU=y" "$objdir/.config"; then
#         KSU_FLAG="KSU"
#     else
#         KSU_FLAG="NonKSU"
#     fi
# }

# === PACK ANYKERNEL ZIP === (DISABLED - only producing kernel)
# pack_anykernel() {
#     echo -e "${LGR}Packing AnyKernel3 ZIP...${NC}"
#     cd "$anykernel"
#     rm -f *.zip
#     zip -r9 "kernel.zip" . -x "*.git*" "*README*" "*.md"
#     cd "$kernel_dir"
# }

# === AUTO RENAME ZIP === (DISABLED - not packaging)
# auto_rename_zip() {
#     ZIP_ORI=$(ls "$anykernel"/*.zip | head -n 1)
#     DEVICE="[Vayu]-Anymore"
#     NEWZIP="${DEVICE}-${KSU_FLAG}-$(date +%Y%m%d-%H%M).zip"
#     mv "$ZIP_ORI" "$anykernel/$NEWZIP"
#     echo "Renamed ZIP -> $NEWZIP"
# }

# === BUILD EXECUTION ===
make_defconfig
compile
completion
show_build_time
# detect_ksu_flag  # DISABLED
# pack_anykernel   # DISABLED
# auto_rename_zip  # DISABLED

cd "$kernel_dir"
