#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/etc/modprobe.d" "$tmp_dir/sys/class/dmi/id" "$tmp_dir/sys/bus/acpi/devices/camera"
export INSTALLED_PACKAGES="$tmp_dir/installed" CALL_LOG="$tmp_dir/calls"
export PATH="$tmp_dir/bin:$ROOT/bin:$PATH" OMARCHY_PATH="$ROOT"

cat > "$tmp_dir/bin/pacman" <<'SH'
#!/bin/bash
[[ $1 == "-Q" ]] || exit 1
grep -Fxq -- "$2" "$INSTALLED_PACKAGES"
SH
cat > "$tmp_dir/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$CALL_LOG"
[[ ${FAIL_HEADERS:-0} != 1 || $* != *-headers* ]]
SH
cat > "$tmp_dir/bin/lspci" <<'SH'
#!/bin/bash
printf '%s\n' 'NVIDIA [10de:2560]' 'Broadcom [14e4:43a0]' 'Motorcomm YT6801 Ethernet'
SH
cat > "$tmp_dir/bin/id" <<'SH'
#!/bin/bash
echo input
SH
for command in sudo lsmod omarchy-hw-nvidia-gsp omarchy-hw-elgato-camlink-4k; do
  printf '#!/bin/bash\nexit 0\n' > "$tmp_dir/bin/$command"
done
chmod +x "$tmp_dir/bin/"*

for installed in linux-omarchy linux-t2 linux; do
  echo "$installed" > "$INSTALLED_PACKAGES"
  : > "$CALL_LOG"
  bash -euo pipefail "$ROOT/migrations/1789444024.sh" >/dev/null
  if [[ $installed == "linux" ]]; then
    [[ ! -s $CALL_LOG ]] || fail "header repair skips systems without a supported kernel"
  else
    [[ $(cat "$CALL_LOG") == "$installed-headers" ]] || fail "header repair covers existing $installed installs"
  fi
done
pass "header repair covers existing Omarchy and T2 installs"
echo MacBook8,1 > "$tmp_dir/sys/class/dmi/id/product_name"
echo TUXEDO > "$tmp_dir/sys/class/dmi/id/sys_vendor"
echo OVTI08F4 > "$tmp_dir/sys/bus/acpi/devices/camera/hid"

for installed in 'linux-omarchy' 'linux linux-omarchy' 'linux' 'linux-t2' 'linux linux-omarchy linux-t2'; do
  expected=linux-omarchy-headers
  [[ $installed == *linux-t2* ]] && expected=linux-t2-headers
  read -ra packages <<< "$installed"
  printf '%s\n' "${packages[@]}" > "$INSTALLED_PACKAGES"
  : > "$CALL_LOG"
  omarchy-pkg-add-kernel-headers
  [[ $(cat "$CALL_LOG") == "$expected" ]] || fail "headers match supported kernel with $installed installed"
  pass "headers match supported kernel with $installed installed"
done

# Run every DKMS installer against hardware fixtures and stub package writes.
# Redirect absolute filesystem paths in sourced leaves into the fixture too.
for family in linux-omarchy linux-t2; do
  printf '%s\n' linux "$family" > "$INSTALLED_PACKAGES"
  for script in \
    bin/omarchy-install-gaming-xbox-controllers \
    install/hardware/nvidia.sh \
    install/hardware/apple/fix-spi-keyboard.sh \
    install/hardware/intel/ipu7-camera.sh \
    install/hardware/fix-bcm43xx.sh \
    install/hardware/fix-tuxedo-backlight.sh \
    install/hardware/fix-yt6801-ethernet-adapter.sh; do
    sed -e "s|/etc/|$tmp_dir/etc/|g" -e "s|/sys/|$tmp_dir/sys/|g" \
      -e "s|/lib/modules/|$tmp_dir/lib/modules/|g" "$ROOT/$script" > "$tmp_dir/installer.sh"
    : > "$CALL_LOG"
    bash -e "$tmp_dir/installer.sh" >/dev/null
    [[ $(head -1 "$CALL_LOG") == "$family-headers" ]] || fail "$script installs $family headers first" "$(cat "$CALL_LOG")"
    (( $(wc -l < "$CALL_LOG") == 2 )) || fail "$script installs its driver after the headers"
    ! grep -wq linux-headers "$CALL_LOG" || fail "$script avoids stock headers"

    : > "$CALL_LOG"
    if FAIL_HEADERS=1 bash -e "$tmp_dir/installer.sh" >/dev/null; then
      fail "$script stops when headers cannot be installed"
    fi
    [[ $(cat "$CALL_LOG") == "$family-headers" ]] || fail "$script must not install DKMS drivers without headers"
    pass "$script uses $family headers and stops on header installation failure"
  done
done
