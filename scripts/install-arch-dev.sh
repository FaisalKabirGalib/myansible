#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin
unset VIRTUAL_ENV PYTHONHOME PYTHONPATH
umask 077

usage() {
  cat <<'HELP'
Usage: bash install-arch-dev.sh [--without-secrets] [--verify]

Installs myansible/server on arch-dev as galib, using the preserved
SSH configuration and homelab deploy key. Prompts for the vault password
unless --without-secrets is supplied. Prompts for sudo access if needed.

--verify additionally installs validation tooling and runs lint, syntax,
disposable-key integration tests, and a final maintenance plan.
HELP
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

main() {
  local personal_keys=true verify=false argument
  for argument in "$@"; do
    case "$argument" in
      --without-secrets) personal_keys=false ;;
      --verify) verify=true ;;
      --help|-h) usage; return ;;
      *) usage >&2; fail "Unknown option: $argument" ;;
    esac
  done
  [[ $(uname -n) == arch-dev ]] || fail 'This installer only permits hostname arch-dev.'
  [[ $(id -un) == galib && $EUID -ne 0 ]] || fail 'Run as galib; the installer uses sudo where needed.'
  [[ -f /etc/arch-release ]] || fail 'Arch Linux is required.'
  [[ $(getent passwd galib | cut -d: -f6) == /home/galib ]] || fail 'Unexpected account home.'
  [[ -d /home/galib/.ssh && ! -L /home/galib ]] || fail 'A normal home directory with preserved .ssh is required.'
  [[ $(ssh -G github-homelab 2>/dev/null | awk '$1 == "hostname" {print $2}') == github.com ]] ||
    fail 'Configure homelab access with bootstrap.yml on your controller first.'

  local log_path repository=/home/galib/myansible
  local public_url=https://github.com/FaisalKabirGalib/myansible.git
  log_path=$(mktemp "/tmp/myansible-install-$(TZ=Asia/Dhaka date +%Y%m%d-%H%M%S)-XXXXXX.log")
  exec > >(tee "$log_path") 2>&1
  printf 'Install log: %s\n' "$log_path"
  local -a become_options=() secret_options=()
  if ! sudo -n true 2>/dev/null; then become_options+=(--ask-become-pass); fi
  sudo pacman -S --needed --noconfirm ansible git

  if [[ -e "$repository" ]]; then
    [[ -d "$repository/.git" && ! -L "$repository" ]] || fail 'The destination is not a normal Git checkout.'
    [[ $(git -C "$repository" remote get-url origin) == "$public_url" ]] || fail 'Unexpected repository origin.'
    [[ $(git -C "$repository" branch --show-current) == server ]] || fail 'Expected the server branch.'
    [[ -z $(git -C "$repository" status --porcelain) ]] || fail 'Commit or stash checkout changes before updating.'
    git -C "$repository" pull --ff-only origin server
  else
    git clone --branch server --single-branch "$public_url" "$repository"
  fi
  cd "$repository"
  printf 'Installing repository commit: %s\n' "$(git rev-parse --short HEAD)"
  ansible-galaxy collection install -r requirements.yml
  if "$personal_keys"; then secret_options+=(-e manage_personal_keys=true --ask-vault-pass); fi
  ansible-playbook site.yml --limit arch-dev -c local "${secret_options[@]}" "${become_options[@]}"

  if "$verify"; then
    just setup
    just check
    just test
    ansible-playbook site.yml --limit arch-dev -c local --check "${become_options[@]}"
  fi
  printf 'INSTALL_OK: environment installed; log: %s\n' "$log_path"
  printf 'Open a new SSH session or run exec zsh to use the configured shell.\n'
}

main "$@"
