docker:
    docker build -t archlinux .

# full local machine setup
local:
    ansible-playbook local.yml --ask-vault-pass --ask-become-pass

# install ansible collections needed for the mac playbook
mac-deps:
    ansible-galaxy collection install -r requirements.yml

# full mac machine setup (no sudo needed)
mac: mac-deps
    ansible-playbook mac.yml

# run only specific tags on mac, e.g. just mac-tags dotfiles,zsh
mac-tags tags:
    ansible-playbook mac.yml --tags {{tags}}

# install just the terminal bundle (zsh, tmux, nvim+lazygit+lazydocker, dotfiles,
# and ghostty/kitty/wezterm casks) on the Mac
terminal: mac-deps
    ansible-playbook mac.yml --tags terminal

# install/configure tmux, TPM, and its plugins (needs dotfiles stowed for tmux.conf)
tmux: mac-deps
    ansible-playbook mac.yml --tags tmux

# install extra CLI utilities (git-delta, dust, hyperfine, ncdu, yq, glow, sd, fx, xh)
cli-extras: mac-deps
    ansible-playbook mac.yml --tags cli-extras

# set up only the personal id_rsa key (passphrase-protected -- safe for
# shared/other machines, e.g. servers or other people's computers)
ssh-only:
    ansible-playbook mac.yml --ask-vault-pass --tags ssh-only

# set up both id_rsa and the server key (full SSH setup -- trusted machines only)
ssh-full:
    ansible-playbook mac.yml --ask-vault-pass --tags ssh-full

# set up pass end-to-end: install gnupg/pass/pinentry-mac, import + trust the GPG
# key, and clone mypass into ~/.password-store
pass:
    ansible-playbook mac.yml --ask-vault-pass --tags pass

# copy server_key to ~/.ssh/
server-key:
    ansible-playbook server_key.yml --ask-vault-pass --ask-become-pass

# test playbook
test:
    ansible-playbook test.yml --ask-vault-pass --ask-become-pass

# install an ansible-galaxy role
install role:
    ansible-galaxy install {{ role }}

# list all recipes
list:
    just --list
