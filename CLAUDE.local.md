# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is an Ansible-based automation repository for setting up development environments on Arch Linux and Ubuntu systems. It configures a complete developer workstation with dotfiles, shell tools, editors, and SSH keys.

## Architecture

### Playbook Structure

Two main playbooks orchestrate different setup scenarios:

- `local.yml` - Full local Arch Linux setup including git configuration and development tools
- `remote_server.yml` - Remote server setup without git configuration and dev packages

Both playbooks use a task-based modular architecture, with individual task files in the `tasks/` directory that can be included selectively.

### Task Modules

All tasks are modular YAML files in `tasks/` directory:

- `git_setup.yml` - Configures global git user.name and user.email
- `dotfiles.yml` - Clones dotfiles repo and uses GNU Stow via `./stowup` script
- `zsh.yml` - Installs zsh and related tools (fzf, fd/fd-find, eza/exa, zoxide, bat) with OS detection for Arch vs Ubuntu package name differences
- `nvim.yml` - Installs neovim and dependencies (nodejs, luarocks, ripgrep, lazygit)
- `tmux.yml` - Installs tmux and TPM (Tmux Plugin Manager)
- `dev.yml` - Installs TypeScript/Node.js development tools (npm, yarn, typescript, ts-node) plus Go and CLI utilities (tldr, duf, navi)
- `ssh.yml` - Installs OpenSSH, creates `.ssh` directory with correct permissions, and copies SSH keys from `ssh/` directory

### SSH Key Management

SSH keys are stored in the `ssh/` directory and copied to `~/.ssh/` with appropriate permissions (0600 for private, 0644 for public). The playbooks use variables `source_key` and `dest_key` to control key paths.

### OS Compatibility

The `zsh.yml` task detects the OS by reading `/etc/os-release` and installs the correct package names for each distribution (e.g., `fd` vs `fd-find`, `eza` vs `exa`).

## Common Commands

### Run Full Local Setup
```bash
ansible-playbook local.yml --ask-become-pass
```

### Run Remote Server Setup
```bash
ansible-playbook remote_server.yml --ask-become-pass
```

### Run with Specific Tags
```bash
# Install only dotfiles
ansible-playbook local.yml --tags dotfiles --ask-become-pass

# Install only nvim dependencies
ansible-playbook local.yml --tags nvim --ask-become-pass

# Install only ssh configuration
ansible-playbook local.yml --tags ssh --ask-become-pass
```

### Run Specific Task File
```bash
ansible-playbook local.yml --tags git-personal --ask-become-pass
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
The dotfiles task expects a repository with a `stowup` executable script that handles GNU Stow operations. The dotfiles repo URL is hardcoded to `https://github.com/FaisalKabirGalib/dotfiles.git`.

### Personal Git Configuration
Git user configuration in `git_setup.yml` is hardcoded with personal information and should be updated for different users.

### Error Handling
Several tasks use `ignore_errors: true` (nvim and zsh tasks) to allow playbook continuation even if package installation fails.
