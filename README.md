# BC-250 Mesh Shader Patch (GFX1013)

Enables mesh shader support (required by Final Fantasy VII Rebirth and
other DX12 Ultimate titles) on the AMD BC-250. Without this, these
games refuse to launch at all with a "DX12 not supported" error.

## What this does

Forces `gfx_level` to report as GFX10_3 specifically for GFX1013
(your BC-250's real chip identity stays truthful everywhere else -
`family` is never changed, only the feature-tier value used for
capability checks). This unlocks mesh shaders, which genuinely exist
on this hardware but aren't enabled by default in Mesa.

Mesa's own existing safety check for this chip's known compute queue
issue is left completely untouched, so the compute queue disables
itself automatically - no extra runtime flag needed for that.

## Requirements

- Arch-based distro (CachyOS, etc.) or anything with `pacman`/build
  tools available. Adapt package names for other distros.
- `git`, `python3`, `ninja`, `python-mako`, `python-yaml`

```bash
sudo pacman -S --needed git python-mako python-yaml ninja base-devel
```

## Build instructions

```bash
mkdir -p ~/bc250-mesa-build && cd ~/bc250-mesa-build
git clone --depth 1 --branch mesa-26.1.4 https://gitlab.freedesktop.org/mesa/mesa.git mesa
cd mesa
patch -p1 --fuzz=5 -i /path/to/bc250_mesa_fix.patch
```

If any hunks report `FAILED`, check the `.rej` file it creates - the
line numbers can drift slightly between Mesa versions. The context
around each change is unique enough that manually applying the
few-line difference shown in the `.rej` file is straightforward.

Set up a Python virtual environment for Meson:

```bash
python3 -m venv venv
venv/bin/pip install meson
```

Build:

```bash
VENV="$HOME/bc250-mesa-build/mesa/venv"
PYTHONPATH="$VENV/lib/python3"*/site-packages "$VENV/bin/meson" setup build \
  -Dvulkan-drivers=amd -Dgallium-drivers=zink \
  -Dglx=disabled -Degl=disabled -Dgles2=disabled \
  -Dshared-llvm=disabled -Dllvm=disabled \
  -Dxmlconfig=disabled -Dlmsensors=disabled -Dvalgrind=disabled

PYTHONPATH="$VENV/lib/python3"*/site-packages ninja -C build src/amd/vulkan/libvulkan_radeon.so
```

This step (`ninja`) is the long one - expect 10-30+ minutes depending
on your CPU.

## Install

```bash
sudo cp build/src/amd/vulkan/libvulkan_radeon.so /usr/lib/libvulkan_radeon_modded.so
```

Create a Vulkan ICD file so the system knows how to find this driver
without replacing your default one:

```bash
cat > ~/radeon_modded_icd.x86_64.json << 'EOF'
{
  "file_format_version": "1.0.0",
  "ICD": {
    "library_path": "/usr/lib/libvulkan_radeon_modded.so",
    "api_version": "1.4.309"
  }
}
EOF
```

## Verify it worked

```bash
VK_ICD_FILENAMES=~/radeon_modded_icd.x86_64.json vulkaninfo | grep -i "deviceName\|meshShader ="
```

You should see your BC-250 listed, along with `meshShader = true`.

## Usage

Add this to the game's Steam launch options:

```
RADV_DEBUG=nodcc VK_ICD_FILENAMES=/home/YOURUSER/radeon_modded_icd.x86_64.json %command%
```

Replace `YOURUSER` with your actual username. `nodcc` works around a
DCC (Delta Color Compression) texture corruption bug on this chip -
it's required for correct visuals.

## Known limitations

- Async compute is unavailable on this chip due to a genuine,
  documented hardware bug (Mesa's own source has a comment noting
  this) - not something this patch can fix.
- Some other DX12 Ultimate features (hardware ray tracing, VRS) are
  untested with this patch and may have their own issues.
- This patch is specific to GFX1013 (BC-250) only - it has no effect
  on any other GPU and is safe to use as a general daily driver.

## Credit

Builds on the original BC-250 mesh shader patch concept from the
BC-250 community. See also the community documentation at
https://elektricm.github.io/amd-bc250-docs/ for broader BC-250 setup
help (kernel config, BIOS/VRAM settings, etc.).
