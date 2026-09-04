# Repair Arch Linux ARM extra's Hyprland stack when aquamarine's soname does
# not match what hyprland / hyprtoolkit require. extra publishes those
# packages independently, and a refresh can leave hyprland depending on
# libaquamarine.so=N while the only aquamarine in the db provides so=N+1.
#
# Sourced from install.sh and omarchy-upgrade-to-quattro-mac. Expects
# checkout, log, warn, and fail.

# aquamarine 0.(N+1).x provides libaquamarine.so=N (0.14 → 13, 0.15 → 14).
aquamarine_version_for_so() {
  local so="$1"
  [[ $so =~ ^[1-9][0-9]*$ ]] || return 1
  printf '0.%s.0\n' "$((so + 1))"
}

# Read libaquamarine.so sonames from pacman -Si style text on stdin.
hyprland_stack_parse_aquamarine_so() {
  grep -oE 'libaquamarine\.so=[0-9]+-64' | sed -E 's/libaquamarine\.so=([0-9]+)-64/\1/' | sort -un
}

hyprland_stack_required_aquamarine_so() {
  pacman -Si hyprland hyprtoolkit 2>/dev/null | hyprland_stack_parse_aquamarine_so
}

hyprland_stack_sync_aquamarine_so() {
  pacman -Si aquamarine 2>/dev/null | hyprland_stack_parse_aquamarine_so
}

hyprland_stack_resolves() {
  pacman -Sp hyprland hyprtoolkit hyprland-guiutils >/dev/null 2>&1
}

# Install a package that already provides the needed soname, if any enabled
# repo has one — including [omarchy-aarch64] after it is added.
hyprland_stack_install_provider() {
  local so="$1"
  sudo pacman -S --needed --noconfirm "libaquamarine.so=${so}-64" >/dev/null 2>&1
}

hyprland_stack_build_aquamarine() {
  local so="$1" version pkgbuild_dir build_dir
  version=$(aquamarine_version_for_so "$so") ||
    fail "could not map libaquamarine.so=$so to an aquamarine version."

  pkgbuild_dir="$checkout/pkgbuilds/aquamarine"
  [[ -f $pkgbuild_dir/PKGBUILD ]] ||
    fail "pkgbuilds/aquamarine/PKGBUILD is missing; cannot build libaquamarine.so=$so."

  log "Building aquamarine $version to provide libaquamarine.so=$so-64"
  sudo pacman -S --needed --noconfirm cmake hyprwayland-scanner pkgconf wayland-protocols

  build_dir="$(mktemp -d)"
  cp -a "$pkgbuild_dir/." "$build_dir/"
  (
    cd "$build_dir"
    OMARCHY_AQUAMARINE_SO="$so" OMARCHY_AQUAMARINE_PKGVER="$version" \
      makepkg --force --noconfirm --syncdeps
  ) || {
    rm -rf "$build_dir"
    fail "could not build aquamarine $version for libaquamarine.so=$so-64."
  }

  local -a built=()
  local artifact
  for artifact in "$build_dir"/aquamarine-*.pkg.tar.*; do
    [[ -f $artifact && $artifact != *.sig ]] || continue
    built+=("$artifact")
  done
  (( ${#built[@]} )) || {
    rm -rf "$build_dir"
    fail "aquamarine $version produced no package archive."
  }

  sudo pacman -U --noconfirm "${built[@]}"
  rm -rf "$build_dir"
}

ensure_hyprland_stack() {
  if ! pacman -Si hyprland >/dev/null 2>&1; then
    fail "hyprland is not in the enabled repos. Check that extra is configured, then retry."
  fi

  if hyprland_stack_resolves; then
    return 0
  fi

  local -a needed=() have=()
  mapfile -t needed < <(hyprland_stack_required_aquamarine_so)
  mapfile -t have < <(hyprland_stack_sync_aquamarine_so)

  (( ${#needed[@]} )) ||
    fail "could not read hyprland's libaquamarine.so dependency from the sync db."
  (( ${#needed[@]} == 1 )) ||
    fail "hyprland and hyprtoolkit want different libaquamarine sonames: ${needed[*]}"

  local so=${needed[0]}
  warn "Arch Linux ARM extra cannot resolve Hyprland: hyprland wants libaquamarine.so=$so-64, extra aquamarine provides ${have[*]:-nothing}."

  if hyprland_stack_install_provider "$so"; then
    if hyprland_stack_resolves; then
      log "Installed a repo package providing libaquamarine.so=$so-64"
      return 0
    fi
  fi

  hyprland_stack_build_aquamarine "$so"

  hyprland_stack_resolves ||
    fail "hyprland still cannot resolve after installing aquamarine for libaquamarine.so=$so-64."
  log "Hyprland dependencies resolve against aquamarine $(aquamarine_version_for_so "$so")"
}
