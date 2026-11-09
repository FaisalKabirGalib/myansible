#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin
unset VIRTUAL_ENV PYTHONHOME PYTHONPATH
umask 077

usage() {
  cat <<'HELP'
Usage: bash scripts/reset-arch-dev.sh [--plan | --apply]

Only runs as galib on arch-dev (Arch Linux).
Default: print the package-removal plan without changing anything.

--apply backs up the home directory and Docker state under /var/backups,
removes non-baseline explicit packages and their unused dependencies,
then deletes /home/galib contents except .ssh and removes Docker state.

Preserves SSH access, Ansible/Python, sudo, the base OS, and backups.
Changes the login shell to Bash. Does not reinstall the environment.
HELP
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

readonly -a baseline_packages=(
  ansible ansible-core base bash bind cloud-guest-utils curl dosfstools e2fsprogs
  linux linux-lts linux-hardened linux-zen linux-firmware openbsd-netcat openssh
  python sudo pacman systemd systemd-sysvcompat glibc coreutils filesystem
  iproute2 iputils util-linux networkmanager dhcpcd grub
)

keep_package() {
  local candidate
  for candidate in "${baseline_packages[@]}"; do
    if [[ "$1" == "$candidate" ]]; then return 0; fi
  done
  return 1
}

stop_system_unit() {
  local state
  if ! state=$(systemctl show "$1" --property=LoadState --value 2>/dev/null); then
    [[ "$state" == not-found ]] || fail "Cannot inspect system unit: $1"
  fi
  if [[ "$state" != not-found ]]; then
    sudo -n systemctl stop "$1"
  fi
}

main() {
  local apply=false
  case "${1:---plan}" in
    --help|-h) usage; return ;;
    --plan) ;;
    --apply) apply=true ;;
    *) usage >&2; fail 'Unknown option.' ;;
  esac
  [[ $# -le 1 ]] || fail 'Only one option is accepted.'
  [[ $(uname -n) == arch-dev ]] || fail 'This script only permits hostname arch-dev.'
  [[ $(id -un) == galib && $EUID -ne 0 ]] || fail 'Run as galib; the script uses sudo where needed.'
  [[ -f /etc/arch-release ]] || fail 'Arch Linux is required.'

  local target_home=/home/galib
  local account_home
  account_home=$(getent passwd galib | cut -d: -f6)
  [[ "$account_home" == "$target_home" ]] || fail 'The account home must be /home/galib.'
  [[ -d "$target_home" && ! -L "$target_home" ]] || fail 'The home directory must not be a symlink.'
  [[ -d "$target_home/.ssh" && ! -L "$target_home/.ssh" ]] || fail 'A real .ssh directory is required.'
  [[ -s "$target_home/.ssh/authorized_keys" ]] || fail 'SSH authorized_keys must exist and be nonempty.'
  [[ -z $(find "$target_home/.ssh" -type l -print -quit) ]] || fail 'Resolve SSH symlinks before resetting.'
  [[ -z $(findmnt -rn -o TARGET | awk '$0 == "/home/galib" || index($0, "/home/galib/") == 1') ]] ||
    fail 'Unmount filesystems under the home directory before resetting.'

  local -a explicit_packages=() remove_packages=() removal_plan=()
  local package
  mapfile -t explicit_packages < <(pacman -Qqe)
  ((${#explicit_packages[@]})) || fail 'Could not read the installed-package list.'
  for package in "${explicit_packages[@]}"; do
    if ! keep_package "$package"; then
      remove_packages+=("$package")
    fi
  done
  local plan
  if ((${#remove_packages[@]})); then
    plan=$(pacman -Rs --print --print-format '%n' "${remove_packages[@]}") || fail 'Package removal cannot be resolved.'
    mapfile -t removal_plan <<< "$plan"
    for package in "${removal_plan[@]}"; do
      if keep_package "$package"; then
        fail "Dependency resolution would remove protected package: $package"
      fi
    done
  fi
  printf 'Target: arch-dev, %s\n' "$target_home"
  printf 'Preserve: .ssh, Ansible/Python, sudo, base OS, /var/backups\n'
  printf 'Delete: all other home contents, /var/lib/docker, /var/lib/containerd\n'
  printf 'Packages to remove (%s, including unused dependencies):\n' "${#removal_plan[@]}"
  if ((${#removal_plan[@]})); then printf '  %s\n' "${removal_plan[@]}"; fi
  if ! "$apply"; then
    printf 'Preview only. Run with --apply to execute.\n'
    return
  fi

  local runner
  if [[ "${BASH_SOURCE[0]}" == "$target_home/"* || "${BASH_SOURCE[0]}" != /* ]]; then
    runner=$(mktemp /tmp/myansible-reset.XXXXXX.sh)
    cp -- "${BASH_SOURCE[0]}" "$runner"
    exec /bin/bash "$runner" --apply
  fi
  cd /
  sudo -v
  local backup_dir home_bytes docker_bytes available_bytes
  home_bytes=$(du --apparent-size -sx --block-size=1 "$target_home" | cut -f1)
  docker_bytes=0
  local directory size
  for directory in /var/lib/docker /var/lib/containerd; do
    if sudo -n test -d "$directory"; then
      [[ ! -L "$directory" ]] || fail "Refusing symlink: $directory"
      size=$(sudo -n du --apparent-size -sx --block-size=1 "$directory" | cut -f1)
      docker_bytes=$((docker_bytes + size))
    fi
  done
  sudo -n install -d -m 0755 /var/backups
  available_bytes=$(df -B1 --output=avail /var/backups | tail -1 | tr -d ' ')
  (( available_bytes > home_bytes + docker_bytes + 104857600 )) || fail 'Not enough space for a complete backup.'
  backup_dir=$(sudo -n mktemp -d "/var/backups/myansible-reset-$(TZ=Asia/Dhaka date +%Y%m%d-%H%M%S)-XXXXXX")
  exec > >(sudo -n tee "$backup_dir/reset.log") 2>&1
  printf 'Backup: %s\n' "$backup_dir"
  sudo -n cp -- "${BASH_SOURCE[0]}" "$backup_dir/reset-script.sh"
  pacman -Q | sudo -n tee "$backup_dir/packages.txt" >/dev/null
  getent passwd galib | sudo -n tee "$backup_dir/user.txt" >/dev/null
  printf '%s\n' "${removal_plan[@]}" | sudo -n tee "$backup_dir/removal-plan.txt" >/dev/null
  find "$target_home/.ssh" -type f -exec sha256sum '{}' + |
    sudo -n tee "$backup_dir/ssh.sha256" >/dev/null

  stop_system_unit docker.socket
  stop_system_unit docker.service
  stop_system_unit containerd.service
  [[ -z $(findmnt -rn -o TARGET | awk '
    $0 == "/var/lib/docker" || index($0, "/var/lib/docker/") == 1 ||
    $0 == "/var/lib/containerd" || index($0, "/var/lib/containerd/") == 1') ]] ||
    fail 'Unmount Docker/containerd filesystems before resetting.'
  sudo -n tar --acls --xattrs --numeric-owner -cpf "$backup_dir/home.tar" -C /home galib
  sudo -n tar -tf "$backup_dir/home.tar" >/dev/null
  for directory in /var/lib/docker /var/lib/containerd; do
    if sudo -n test -d "$directory"; then
      sudo -n tar --acls --xattrs --numeric-owner -cpf "$backup_dir/${directory##*/}.tar" -C /var/lib "${directory##*/}"
      sudo -n tar -tf "$backup_dir/${directory##*/}.tar" >/dev/null
    fi
  done
  sudo -n chmod -R go-rwx "$backup_dir"
  printf 'Backups verified. Starting removal.\n'

  sudo -n usermod --shell /bin/bash galib
  local unit state
  for unit in gpg-agent.service gpg-agent.socket gpg-agent-extra.socket gpg-agent-browser.socket gpg-agent-ssh.socket; do
    if ! state=$(systemctl --user show "$unit" --property=LoadState --value 2>/dev/null); then
      [[ "$state" == not-found ]] || fail "Cannot inspect user unit: $unit"
    fi
    if [[ "$state" != not-found ]]; then systemctl --user stop "$unit"; fi
  done
  if [[ -d "$target_home/.gnupg" ]]; then
    gpgconf --homedir "$target_home/.gnupg" --kill all
  fi
  if ((${#remove_packages[@]})); then
    sudo -n pacman -Rns --noconfirm "${remove_packages[@]}"
  fi
  sudo -n find "$target_home" -mindepth 1 -maxdepth 1 ! -name .ssh -exec rm -rf -- '{}' +
  sudo -n rm -rf -- /var/lib/docker /var/lib/containerd

  sudo -n sha256sum --check --status "$backup_dir/ssh.sha256"
  [[ -z $(find "$target_home" -mindepth 1 -maxdepth 1 ! -name .ssh -print -quit) ]] || fail 'Unexpected home contents remain.'
  [[ $(getent passwd galib | cut -d: -f7) == /bin/bash ]] || fail 'The login shell was not changed to Bash.'
  pacman -Q ansible ansible-core python openssh sudo
  systemctl is-active --quiet sshd
  printf 'RESET_OK: home contains only .ssh; SSH checksums unchanged; sshd is active.\n'
  printf 'Verified backup and reset log: %s\n' "$backup_dir"
  printf 'Development environment is removed. Reinstall instructions are in the public myansible/server README.\n'
}

main "$@"
