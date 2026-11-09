# Myansible

One set of roles maintains Arch Linux development machines. Host differences belong in inventory; new machines do not need separate branches or copied playbooks. Homelab owns the dotfiles, and this repository installs them.

## Commands

Install `ansible`, `git`, `just`, and `uv` on the controller, then run `just setup` to install the locked validation tools and pinned Ansible collections. The controller needs SSH access to the selected host and that host needs sudo access.

```sh
just plan arch-dev
just apply arch-dev
just full arch-dev
```

`plan` uses Ansible check mode. `apply` performs routine maintenance without opening the vault. `full` runs the same playbook with personal SSH and GPG imports enabled and prompts for the vault password. Add `--ask-become-pass` to any command when sudo requires a password.

Run from the target itself with `just apply arch-dev -c local`. Direct equivalent:

```sh
ansible-playbook site.yml --limit arch-dev
ansible-playbook site.yml --limit arch-dev -e manage_personal_keys=true --ask-vault-pass
```

All operations use the target user's home directory, including when the controller has a different username or home. Connect as a regular user; only system packages, login-shell changes, and ownership repair use sudo.

## Bootstrap a machine

1. Add its SSH name to `inventory/hosts.yml` under `servers`.
2. Add its username, expected hostname, and repository access settings to `host_vars/<name>.yml`.
3. Run `just bootstrap <name>` from a controller with authenticated `gh` access to the homelab repository.
4. Run `just plan <name>`, then `just apply <name>`.
5. Run `just full <name>` if that machine should receive your personal private keys.

Bootstrap installs missing Python/Git prerequisites, generates a machine-specific deploy key, registers it read-only with GitHub, trusts GitHub's published host keys, and creates the `github-homelab` SSH alias. Use `dotfiles_repo: git@github-homelab:FaisalKabirGalib/homelab.git` for this access method. Bootstrap requires an existing Arch Linux user with SSH and sudo access; it does not create or provision the VM itself.

Bootstrap is an apply operation. Ansible cannot fully preview a host that does not yet have Python. A first-time maintenance plan can also skip checks that need a not-yet-cloned repository or not-yet-installed tool.

## Configuration layout

```text
site.yml                    main maintenance playbook
bootstrap.yml               initial prerequisites and GitHub access
inventory/hosts.yml         machine groups and connection targets
group_vars/all.yml          shared paths, package list, repository revisions, identity
group_vars/servers.yml     server additions and Docker enablement
host_vars/arch-dev.yml      connection settings and machine-specific overrides
roles/
  bootstrap/                machine deploy key and repository access
  packages/                 system packages
  ssh/                      ownership, authorized keys, optional personal key import
  dotfiles/                 Git checkout and Stow links
  dev_tools/                Git identity, shells, editors, assistant CLIs, Docker
  gpg_pass/                 optional personal GPG and password-store setup
tests/gpg_integration.py    isolated role integration test
```

Change `packages_extra` or `dotfiles_packages` in the appropriate group or host file. `target_user`, `target_group`, and `target_home` default to facts collected from the target. `manage_personal_keys` defaults to false. Secret values remain in the existing vault-encrypted files; never put passwords in inventory or command arguments.

`local.yml` and `remote_server.yml` are compatibility aliases for the shared full setup on localhost. `arch_dev.yml` delegates to normal maintenance for arch-dev. `gpg_setup.yml` and `ssh_deploy_key.yml` remain focused entry points. Old `tasks/` paths delegate to roles instead of maintaining duplicate implementations.

## Dotfile updates

New clones use the commit pinned in `dotfiles_revision`. Existing checkouts are preserved by default, including their current revision and local edits. Routine apply does not pull, reset, or synchronize files from the controller.

To advance a machine, update the pin, review and commit or back up any local edits, then run:

```sh
just update-dotfiles arch-dev
```

Git refuses updates that would overwrite modified tracked files, and Stow refuses conflicting user files. The existing arch-dev checkout contains changes from the former rsync workflow; those are preserved. Its old checkout is not claimed to be an exact copy of the new pin. Resolve that migration separately before requesting an update.

## Secrets and checks

`just secrets arch-dev` applies only SSH/GPG configuration with a vault prompt. Private keys are installed on disk; use `ssh-add ~/.ssh/id_rsa` in the interactive shell when you want to load a key into its agent.

```sh
just check
just test
```

`check` runs YAML linting, Ansible linting and syntax checks, and Python linting/format checks. `test` needs passwordless sudo and Git, OpenSSH, GnuPG, pass, and Stow. It generates disposable vaulted keys and local Git repositories, tests the real SSH/dotfiles/GPG roles, checks encryption/decryption and idempotency, and confirms a Stow conflict preserves the existing file. It uses an isolated home directory and removes the fixtures afterward. It never reads the real vault password or decrypts real password-store entries.

GitHub Actions runs these checks on pushes and pull requests using `uv.lock` and `requirements.yml`. To upgrade tooling deliberately, update the lockfile and collection pins, run the checks, and apply twice to a test machine; the second run should report `changed=0`.
