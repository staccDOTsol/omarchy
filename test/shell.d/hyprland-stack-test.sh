#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

helper="$ROOT/install/helpers/hyprland-stack.sh"
pkgbuild="$ROOT/pkgbuilds/aquamarine/PKGBUILD"

[[ -f $helper ]] || fail "the Hyprland stack helper ships"
[[ -f $pkgbuild ]] || fail "the aquamarine ABI PKGBUILD ships"
pass "the Hyprland stack repair files ship"

# Source only the pure helpers: the rest talks to pacman and must not run here.
eval "$(awk '
  $0 == "aquamarine_version_for_so() {" {inside=1}
  $0 == "hyprland_stack_parse_aquamarine_so() {" {inside=1}
  inside {print}
  inside && $0 == "}" {inside=0}
' "$helper")"

[[ $(aquamarine_version_for_so 13) == "0.14.0" ]] ||
  fail "libaquamarine.so=13 maps to aquamarine 0.14.0"
[[ $(aquamarine_version_for_so 14) == "0.15.0" ]] ||
  fail "libaquamarine.so=14 maps to aquamarine 0.15.0"
if aquamarine_version_for_so 0 >/dev/null 2>&1; then
  fail "soname 0 is rejected"
fi
if aquamarine_version_for_so thirteen >/dev/null 2>&1; then
  fail "a non-numeric soname is rejected"
fi
pass "aquamarine versions follow the so=(minor-1) mapping"

parsed=$(hyprland_stack_parse_aquamarine_so <<'EOF'
Depends On      : cairo  aquamarine  libaquamarine.so=13-64  libgcc
Depends On      : aquamarine  libaquamarine.so=13-64  cairo
Provides        : libaquamarine.so=14-64
EOF
)
[[ $parsed == $'13\n14' ]] ||
  fail "sonames are parsed from pacman -Si text" "got: $(printf '%q' "$parsed")"
pass "sonames are parsed from pacman -Si text"

# The live failure: extra hyprland 0.56.1-3 wants so=13, extra aquamarine
# 0.15.0-2 provides so=14. The PKGBUILD must default to that missing ABI and
# refuse to package a tag whose CMake SOVERSION disagrees.
grep -qE '^_sover=\$\{OMARCHY_AQUAMARINE_SO:-13\}' "$pkgbuild" ||
  fail "the aquamarine PKGBUILD defaults to the so=13 hyprland 0.56.1 wants"
grep -qE '^pkgver=\$\{OMARCHY_AQUAMARINE_PKGVER:-0\.14\.0\}' "$pkgbuild" ||
  fail "the aquamarine PKGBUILD defaults to the 0.14.0 tag that sets SOVERSION 13"
grep -qF 'SOVERSION' "$pkgbuild" ||
  fail "the aquamarine PKGBUILD checks CMake SOVERSION against the requested ABI"
grep -qF 'provides=("libaquamarine.so=${_sover}-64")' "$pkgbuild" ||
  fail "the aquamarine PKGBUILD provides the requested soname"
pass "the aquamarine PKGBUILD targets the missing libaquamarine.so=13 ABI"

# A repo package that already provides the soname must win over a local build,
# so publishing aquamarine to [omarchy-aarch64] later is enough.
grep -qF 'libaquamarine.so=${so}-64' "$helper" ||
  fail "the helper installs a repo provider before building"
grep -qF 'hyprland_stack_build_aquamarine' "$helper" ||
  fail "the helper builds aquamarine when extra's soname does not match"
pass "the helper prefers a repo provider and builds only when extra is skewed"
