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
