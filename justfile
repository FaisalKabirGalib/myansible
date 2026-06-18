docker:
    docker build -t archlinux .

# full local machine setup
local:
    ansible-playbook local.yml --ask-vault-pass --ask-become-pass

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
