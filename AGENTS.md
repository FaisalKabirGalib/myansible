# AGENTS.md - Coding Agent Guidelines

This document provides instructions for AI coding agents working in this Ansible repository.

## Project Overview

This is an Ansible playbook collection for system configuration, targeting Arch Linux and Ubuntu. It handles dotfiles, SSH, GPG, password manager (pass), and development environment setup.

## Build/Lint/Test Commands

### Running Playbooks

```bash
# Run main playbook (local machine setup)
ansible-playbook local.yml --ask-become-pass

# Run with specific tags
ansible-playbook local.yml --tags "ssh,git-personal" --ask-become-pass

# Run remote server setup
ansible-playbook remote_server.yml --ask-become-pass

# Run GPG setup only
ansible-playbook gpg_setup.yml --ask-become-pass

# Run test playbook
ansible-playbook test.yml

# Check mode (dry run)
ansible-playbook local.yml --check --ask-become-pass

# Verbose output
ansible-playbook local.yml -v --ask-become-pass
ansible-playbook local.yml -vvv --ask-become-pass  # debug level
```

### Linting

```bash
# Install ansible-lint if needed
pip install ansible-lint

# Lint all YAML files
ansible-lint

# Lint specific file
ansible-lint local.yml

# Lint with specific profile
ansible-lint --profile production
```

### Vault Operations

```bash
# Encrypt a file
ansible-vault encrypt vars/secrets.yml

# Edit encrypted file
ansible-vault edit vars/secrets.yml

# View encrypted file
ansible-vault view vars/secrets.yml

# Run playbook with vault password
ansible-playbook local.yml --ask-vault-pass --ask-become-pass
```

### Testing a Single Task/Role

```bash
# Run specific tags (equivalent to running single test)
ansible-playbook local.yml --tags "ssh" --ask-become-pass

# Start at specific task
ansible-playbook local.yml --start-at-task "Install ssh key" --ask-become-pass

# List all tasks
ansible-playbook local.yml --list-tasks

# List all tags
ansible-playbook local.yml --list-tags
```

### Docker Testing

```bash
# Build and run in Docker
docker build -t ansible-test .
docker run -it ansible-test

# Build with specific tags
docker build --build-arg TAGS="--tags ssh" -t ansible-test .
```

## Code Style Guidelines

### YAML Formatting

- Use 2-space indentation
- Use `---` document start marker at file beginning
- Keep lines under 120 characters
- Use single quotes for simple strings, double quotes for strings with variables
- No trailing whitespace

### Task Naming Conventions

```yaml
# Good: Action-first naming
- name: Install OpenSSH tools
- name: Clone dotfiles repository
- name: Ensure .ssh directory exists
- name: Set GPG key trust to ultimate

# Avoid: Vague names
- name: SSH stuff
- name: Do the thing
```

### Module Usage

```yaml
# Prefer FQCN for core modules (optional but recommended)
- name: Check if system is Arch Linux
  ansible.builtin.command: cat /etc/os-release
  register: os_release

# Short names are acceptable for common modules
- name: Install packages
  package:
    name: openssh
    state: present
```

### Variable Conventions

```yaml
# Environment lookups
dest: "{{ lookup('env', 'HOME') }}/.ssh/id_rsa"
dest: "{{ lookup('env','HOME') }}/dotfiles"  # no space after comma is also acceptable

# Playbook-level variables
vars:
  source_key: "./ssh/id_rsa"
  dest_key: "{{ lookup('env', 'HOME') }}/.ssh/id_rsa"

# Include vaulted variables
- name: Load vaulted SSH secrets
  include_vars: vars/secrets.yml
  no_log: true
```

### Tags

```yaml
# Always add tags for selective execution
tags:
  - ssh
  - install

# Use lowercase tags
tags:
  - dotfiles
  - git-personal
  - dev
```

### Error Handling

```yaml
# For non-critical tasks
- name: Install packages
  package:
    name: neovim
    state: present
  failed_when: false

# For conditional failure
- name: Start SSH agent
  expect:
    command: ssh-add ~/.ssh/id_rsa
  register: ssh_add_result
  failed_when: ssh_add_result.rc != 0 and "already added" not in ssh_add_result.stderr

# Block-based error handling
- name: GPG key import
  block:
    - name: Import key
      # ...
  rescue:
    - name: Handle failure
      debug:
        msg: "Import failed"
  always:
    - name: Cleanup
      file:
        path: "{{ temp_key.dest }}"
        state: absent
```

### Sensitive Data

```yaml
# Always use no_log for sensitive operations
- name: Load vaulted SSH secrets
  include_vars: vars/secrets.yml
  no_log: true

# Use ansible-vault for secrets
# Store in vars/secrets.yml (already encrypted)
```

### OS-Specific Conditionals

```yaml
# Check OS type
- name: Check if system is Arch Linux
  ansible.builtin.command: cat /etc/os-release
  register: os_release

- name: Install package for Arch
  pacman:
    name: pass
    state: present
  when: ansible_facts['os_family'] == "Archlinux"

- name: Install package for Ubuntu/Debian
  apt:
    name: pass
    state: present
    update_cache: true
  when: ansible_facts['os_family'] == "Debian"

# String matching in registered output
- name: Install package if archlinux
  package:
    name: zsh
    state: present
  when: '"Arch" in os_release.stdout'
```

### Idempotency Patterns

```yaml
# Use 'creates' for shell commands
- name: Stow dotfiles
  shell: |
    cd "{{ lookup('env','HOME') }}/dotfiles" && ./stowup
  args:
    creates: "{{ lookup('env','HOME') }}/.zshrc"

# Use 'changed_when' for commands
- name: Import GPG private key
  shell: gpg --batch --import "{{ temp_key.dest }}"
  register: gpg_import
  changed_when: "'imported' in gpg_import.stderr"

# Use 'state: present' for packages
- name: Install packages
  package:
    name: stow
    state: present
```

### File Structure

```
myansible/
├── local.yml           # Main local playbook
├── remote_server.yml   # Remote server playbook
├── gpg_setup.yml       # GPG-specific playbook
├── test.yml            # Test playbook
├── tasks/              # Task files (included by playbooks)
│   ├── dev.yml
│   ├── dotfiles.yml
│   ├── git_setup.yml
│   ├── gpg_pass.yml
│   ├── nvim.yml
│   ├── ssh.yml
│   ├── tmux.yml
│   └── zsh.yml
├── vars/               # Variables (vault-encrypted secrets)
│   └── secrets.yml
├── keys/               # GPG keys
├── ssh/                # SSH keys
└── Dockerfile          # Docker testing
```

### Best Practices

1. **Always use `become: yes`** for system-level changes
2. **Add `--ask-become-pass`** when running playbooks interactively
3. **Use tags** for all tasks to allow selective execution
4. **Use `no_log: true`** for any task handling sensitive data
5. **Prefer `command` over `shell`** when possible (more secure)
6. **Use `register`** to capture output for conditionals
7. **Set `changed_when: false`** for read-only commands
8. **Use `ansible_facts`** instead of `ansible_*` deprecated variables
9. **Include `ignore_errors: true`** for non-critical optional tasks
10. **Use `args: creates:`** to ensure shell/command idempotency

### Common Patterns

```yaml
# Package installation
- name: Install packages
  package:
    name:
      - package1
      - package2
    state: present
  tags:
    - tagname
    - install

# Git clone
- name: Clone repository
  git:
    repo: https://github.com/user/repo.git
    dest: "{{ lookup('env', 'HOME') }}/repo"
    version: main
    update: false

# File/directory management
- name: Ensure directory exists
  file:
    path: "{{ lookup('env', 'HOME') }}/.gnupg"
    state: directory
    mode: '0700'

# Include tasks
- include_tasks: tasks/ssh.yml
```
