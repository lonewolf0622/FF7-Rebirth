#!/bin/bash
# bc250-comprehensive-nospoof.sh
#
# Builds a fresh, comprehensive no-spoof driver: base mesh shader patch
# plus every gfx_level >= GFX10_3 check we've found in files that are
# actually part of the mesh/task shader rendering path (RADV command
# buffer emission, shader compilation, ACO instruction selection).
#
# This is a genuinely different, isolated test - if it fails, you'll
# still have your working spoofed driver untouched.
#
# Requires: bc250_shotgun_no_spoof.patch in the same folder as this script

set -e

PATCH_FILE="$(dirname "$(readlink -f "$0")")/bc250_shotgun_no_spoof.patch"
TEST_ROOT="$HOME/bc250-comprehensive-test"
MESA_DIR="$TEST_ROOT/mesa"
CONTAINER_NAME="bc250-mesa-build"
DRIVER_OUT="$HOME/.local/lib/libvulkan_radeon_comprehensive.so"
ICD_OUT="$HOME/radeon_comprehensive_icd.x86_64.json"

echo "=== BC-250 Comprehensive No-Spoof Test Build ==="
echo "This is completely isolated from your working spoofed driver."
echo ""

if [ ! -f "$PATCH_FILE" ]; then
    echo "ERROR: Could not find bc250_shotgun_no_spoof.patch next to this script."
    exit 1
fi

# 1. Fresh clone
echo "[1/6] Cloning Mesa (mesa-26.1.4)..."
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT"
distrobox enter "$CONTAINER_NAME" -- git clone --depth 1 --branch mesa-26.1.4 \
    https://gitlab.freedesktop.org/mesa/mesa.git "$MESA_DIR"

# 2. Apply the base patch
echo "[2/6] Applying base no-spoof patch..."
cd "$MESA_DIR"
distrobox enter "$CONTAINER_NAME" -- bash -c "cd '$MESA_DIR' && patch -p1 --fuzz=5 -i '$PATCH_FILE'" || true

if ! grep -q "is_gfx1013\|CHIP_GFX1013" "$MESA_DIR/src/amd/vulkan/radv_shader_info.c"; then
    echo "ERROR: base patch didn't apply at all. Aborting."
    exit 1
fi
if ! grep -q "ps_clip_dists_in, pdev" "$MESA_DIR/src/amd/vulkan/radv_shader_info.c"; then
    echo "Fixing known call-site hunk issue..."
    sed -i 's/ps_clip_dists_in);/ps_clip_dists_in, pdev->info.family == CHIP_GFX1013);/' \
        "$MESA_DIR/src/amd/vulkan/radv_shader_info.c"
fi
rm -f "$MESA_DIR/src/amd/vulkan/radv_shader_info.c.rej"

echo "Base patch confirmed applied."

# 3. Bulk-extend every relevant gfx_level >= GFX10_3 check we've found
#    in files that are part of the actual mesh/task rendering path.
#    Each sed targets the SPECIFIC variable-access pattern used in that
#    file, rather than a blind global replace, to avoid corrupting
#    unrelated code.
echo "[3/6] Extending gfx_level checks across the mesh/task rendering path..."

cd "$MESA_DIR"

# radv_cmd_buffer.c - uses pdev->info.gfx_level and bare gfx_level
sed -i \
  -e 's/pdev->info\.gfx_level >= GFX10_3\b/(pdev->info.gfx_level >= GFX10_3 || pdev->info.family == CHIP_GFX1013)/g' \
  -e 's/pdev->info\.gfx_level == GFX10_3\b/(pdev->info.gfx_level == GFX10_3 || pdev->info.family == CHIP_GFX1013)/g' \
  -e 's/gfx_level >= GFX10_3\b/(gfx_level >= GFX10_3 || pdev->info.family == CHIP_GFX1013)/g' \
  src/amd/vulkan/radv_cmd_buffer.c

# radv_shader.c - uses pdev->info.gfx_level
sed -i \
  -e 's/pdev->info\.gfx_level >= GFX10_3\b/(pdev->info.gfx_level >= GFX10_3 || pdev->info.family == CHIP_GFX1013)/g' \
  -e 's/pdev->info\.gfx_level <= GFX10_3\b/(pdev->info.gfx_level <= GFX10_3 || pdev->info.family == CHIP_GFX1013)/g' \
  -e 's/pdev->info\.gfx_level != GFX10_3\b/(pdev->info.gfx_level != GFX10_3 \&\& pdev->info.family != CHIP_GFX1013)/g' \
  -e 's/pdev->info\.gfx_level < GFX10_3\b/(pdev->info.gfx_level < GFX10_3 \&\& pdev->info.family != CHIP_GFX1013)/g' \
  src/amd/vulkan/radv_shader.c

# radv_physical_device.c and radv_physical_device.h - already has some
# from base patch, extend the remaining ones
sed -i \
  -e 's/pdev->info\.gfx_level == GFX10_3\b/(pdev->info.gfx_level == GFX10_3 || pdev->info.family == CHIP_GFX1013)/g' \
  src/amd/vulkan/radv_physical_device.h

# radv_pipeline_graphics.c
sed -i \
  -e 's/pdev->info\.gfx_level < GFX10_3\b/(pdev->info.gfx_level < GFX10_3 \&\& pdev->info.family != CHIP_GFX1013)/g' \
  src/amd/vulkan/radv_pipeline_graphics.c

# radv_queue.c
sed -i \
  -e 's/pdev->info\.gfx_level >= GFX10_3\b/(pdev->info.gfx_level >= GFX10_3 || pdev->info.family == CHIP_GFX1013)/g' \
  src/amd/vulkan/radv_queue.c

# radv_device.c
sed -i \
  -e 's/pdev->info\.gfx_level == GFX10_3\b/(pdev->info.gfx_level == GFX10_3 || pdev->info.family == CHIP_GFX1013)/g' \
  -e 's/pdev->info\.gfx_level >= GFX10_3\b/(pdev->info.gfx_level >= GFX10_3 || pdev->info.family == CHIP_GFX1013)/g' \
  src/amd/vulkan/radv_device.c

# ac_shader_util.c and .h - already has one fix from earlier, these use
# bare gfx_level (function parameter, not pdev->info.gfx_level)
sed -i \
  -e 's/gfx_level >= GFX10_3 ? 29/(gfx_level >= GFX10_3 || family == CHIP_GFX1013) ? 29/' \
  src/amd/common/ac_shader_util.c

# ac_nir_lower_ngg.c - this one is an assert, uses state.ac->gfx_level
sed -i \
  -e 's/assert(state\.ac->gfx_level >= GFX10_3);/assert(state.ac->gfx_level >= GFX10_3 || state.ac->family == CHIP_GFX1013);/' \
  src/amd/common/nir/ac_nir_lower_ngg.c

# ACO compiler - the isel assert
sed -i \
  -e 's/assert(!mesh_shading || ctx\.program->gfx_level >= GFX10_3);/assert(!mesh_shading || ctx.program->gfx_level >= GFX10_3 || ctx.options->family == CHIP_GFX1013);/' \
  src/amd/compiler/instruction_selection/aco_isel_setup.cpp

echo "Bulk extension complete. Verifying changes..."
TOTAL_CHANGES=$(grep -rc "family == CHIP_GFX1013\|family != CHIP_GFX1013" \
    src/amd/vulkan/radv_cmd_buffer.c src/amd/vulkan/radv_shader.c \
    src/amd/vulkan/radv_physical_device.c src/amd/vulkan/radv_physical_device.h \
    src/amd/vulkan/radv_pipeline_graphics.c src/amd/vulkan/radv_queue.c \
    src/amd/vulkan/radv_device.c src/amd/common/ac_shader_util.c \
    src/amd/common/nir/ac_nir_lower_ngg.c \
    src/amd/compiler/instruction_selection/aco_isel_setup.cpp 2>/dev/null | \
    awk -F: '{sum+=$2} END {print sum}')
echo "Total family==CHIP_GFX1013 references now present: $TOTAL_CHANGES"

# 4. Build
echo "[4/6] Building (this can take 10-30+ minutes)..."
distrobox enter "$CONTAINER_NAME" -- bash -c "
    cd '$MESA_DIR'
    meson setup build \
      -Dvulkan-drivers=amd -Dgallium-drivers=zink \
      -Dglx=disabled -Degl=disabled -Dgles2=disabled \
      -Dshared-llvm=disabled -Dllvm=disabled \
      -Dxmlconfig=disabled -Dlmsensors=disabled -Dvalgrind=disabled
    ninja -C build src/amd/vulkan/libvulkan_radeon.so
"

if [ ! -f "$MESA_DIR/build/src/amd/vulkan/libvulkan_radeon.so" ]; then
    echo "!!! BUILD FAILED - check errors above !!!"
    exit 1
fi

# 5. Install
echo "[5/6] Installing..."
mkdir -p "$HOME/.local/lib"
cp "$MESA_DIR/build/src/amd/vulkan/libvulkan_radeon.so" "$DRIVER_OUT"

cat > "$ICD_OUT" << EOF
{
  "file_format_version": "1.0.0",
  "ICD": {
    "library_path": "$DRIVER_OUT",
    "api_version": "1.4.309"
  }
}
EOF

# 6. Check for missing runtime libs (reuse the same host-side detection)
RUNTIME_LIBS_DIR="$HOME/.local/lib/bc250-runtime-libs"
mkdir -p "$RUNTIME_LIBS_DIR"
MISSING_LIBS=$(ldd "$DRIVER_OUT" 2>/dev/null | grep "not found" | awk '{print $1}')
if [ -n "$MISSING_LIBS" ]; then
    for lib in $MISSING_LIBS; do
        LIB_PATH=$(distrobox enter "$CONTAINER_NAME" -- find /usr/lib /usr/lib64 -iname "$lib" 2>/dev/null | head -1)
        if [ -n "$LIB_PATH" ]; then
            distrobox enter "$CONTAINER_NAME" -- cp "$LIB_PATH" "$RUNTIME_LIBS_DIR/"
        fi
    done
fi

echo ""
echo "[6/6] Build complete."
echo ""
echo "IMPORTANT: Test with the MINIMAL SAMPLE FIRST, not the real game:"
echo ""
echo "  cd ~/Vulkan-Samples"
echo "  LD_LIBRARY_PATH=$RUNTIME_LIBS_DIR VK_ICD_FILENAMES=$ICD_OUT \\"
echo "    stdbuf -oL -eL ./build/app/bin/Release/x86_64/vulkan_samples sample mesh_shading"
echo ""
echo "This driver is completely separate from your working spoofed setup."
