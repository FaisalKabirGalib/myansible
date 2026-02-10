# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is an Ansible-based automation repository for setting up development environments on Arch Linux and Ubuntu systems. It configures a complete developer workstation with dotfiles, shell tools, editors, SSH keys, and GPG/pass password management.

## Architecture

### Playbook Structure

Four main playbooks orchestrate different setup scenarios:

- `local.yml` - Full local Arch Linux setup including git configuration, development tools, and GPG/pass
- `remote_server.yml` - Remote server setup without git configuration and dev packages
- `gpg_setup.yml` - Standalone GPG and password manager setup (includes `tasks/gpg_pass.yml`)
- `pass.yml` - Empty playbook (placeholder)

Both main playbooks use a task-based modular architecture, with individual task files in the `tasks/` directory that can be included selectively.

### Task Modules

All tasks are modular YAML files in `tasks/` directory:

- `git_setup.yml` - Configures global git user.name and user.email (tag: `git-personal`)
- `dotfiles.yml` - Clones dotfiles repo from GitHub and uses GNU Stow via `./stowup` script
- `zsh.yml` - Installs zsh and related tools (fzf, fd/fd-find, eza/exa, zoxide, bat) with OS detection for Arch vs Ubuntu package name differences
- `nvim.yml` - Installs neovim and dependencies (nodejs, luarocks, ripgrep, lazygit)
- `tmux.yml` - Installs tmux and TPM (Tmux Plugin Manager)
- `dev.yml` - Installs TypeScript/Node.js development tools (npm, yarn, typescript, ts-node) plus Go and CLI utilities (tldr, duf, navi)
- `ssh.yml` - Installs OpenSSH, creates `.ssh` directory with correct permissions, and copies SSH keys from `ssh/` directory
- `gpg_pass.yml` - Sets up GPG keys and pass password manager with Ansible Vault encryption

### Docker Support

The repository includes a Dockerfile for containerized Ansible execution:

- Multi-stage build based on `archlinux:latest`
- Installs ansible, curl, git, base-devel, neovim
- Accepts `TAGS` build argument for selective playbook execution
- Use `./build_docker` script to build the Docker image

### SSH Key Management

SSH keys are stored in the `ssh/` directory:
- `id_rsa` / `id_rsa.pub` - Default SSH key pair
- `contabo` / `contabo.pub` - Contabo server-specific key
- `kube_rsa` / `kube_rsa.pub` - Kubernetes-related key

Keys are copied to `~/.ssh/` with appropriate permissions (0600 for private, 0644 for public). The playbooks use variables `source_key` and `dest_key` to control key paths.

### GPG and Pass Password Manager

The `gpg_pass.yml` task handles:

1. **GPG Key Import**: Uses Ansible Vault to decrypt and import GPG private key from `keys/pass_private.pgp`
2. **Public Key Import**: Imports `keys/pass_public.pgp`
3. **Trust Setup**: Sets GPG key trust to ultimate level
4. **Pass Installation**: Installs pass package (OS-specific: pacman for Arch, apt for Ubuntu/Debian)
5. **Password Store**: Clones password repository from `https://github.com/FaisalKabirGalib/mypass.git` to `~/.password-store`

The task uses `block/rescue/always` structure for error handling and temporary file cleanup. Vault-encrypted files are stored in `keys/` directory with vault password in `vars/secrets.yml`.

### OS Compatibility

The `zsh.yml` task detects the OS by reading `/etc/os-release` and installs the correct package names for each distribution (e.g., `fd` vs `fd-find`, `eza` vs `exa`). The `gpg_pass.yml` task also has OS-specific package installation for pass.

## Common Commands

### Run Full Local Setup
```bash
ansible-playbook local.yml --ask-become-pass
```

### Run Remote Server Setup
```bash
ansible-playbook remote_server.yml --ask-become-pass
```

### Run GPG/Pass Setup Only
```bash
ansible-playbook gpg_setup.yml --ask-become-pass
```

### Run with Specific Tags
```bash
# Install only dotfiles
ansible-playbook local.yml --tags dotfiles --ask-become-pass

# Install only nvim dependencies
ansible-playbook local.yml --tags nvim --ask-become-pass

# Install only ssh configuration
ansible-playbook local.yml --tags ssh --ask-become-pass

# Configure git personal info only
ansible-playbook local.yml --tags git-personal --ask-become-pass
```

### Docker Build and Run
```bash
# Build Docker image
./build_docker

# Run playbook in Docker with tags
docker run --rm archlinux sh -c "ansible-playbook local.yml"
```

### Test Playbook (Check Mode)
```bash
ansible-playbook local.yml --check --ask-become-pass
```

### Test Playbook
The `test.yml` file can be used for testing sudo privileges and OS detection.

## Key Variables

Both main playbooks define:
- `source_key: "./ssh/id_rsa"` - Source SSH private key path
- `dest_key: "{{ lookup('env', 'HOME') }}/.ssh/id_rsa"` - Destination SSH key path

## Important Patterns

### Dotfiles Integration
The dotfiles task expects a repository with a `stowup` executable script that handles GNU Stow operations. The dotfiles repo URL is hardcoded to `https://github.com/FaisalKabirGalib/dotfiles.git` and uses the `server` branch.

### Personal Git Configuration
Git user configuration in `git_setup.yml` is hardcoded with personal information (name: "Faisal Kabir Galib", email: "faisalkabirgalib@gmail.com") and should be updated for different users.

### GPG Vault Encryption
The `gpg_pass.yml` task uses `ansible.builtin.unvault` to decrypt the private GPG key at runtime. The vault password is stored in `vars/secrets.yml`. The task includes error handling with a rescue block that warns if vault decryption fails.

### Password Store
The pass setup clones from `https://github.com/FaisalKabirGalib/mypass.git` and initializes with the imported GPG key ID.

### Error Handling
Several tasks use `ignore_errors: true` (nvim and zsh tasks) to allow playbook continuation even if package installation fails. The `gpg_pass.yml` task uses structured `block/rescue/always` for more sophisticated error handling and cleanup.
