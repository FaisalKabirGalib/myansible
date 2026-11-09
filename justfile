set shell := ["bash", "-euo", "pipefail", "-c"]

set positional-arguments

setup:
    uv sync --locked
    uv run --locked ansible-galaxy collection install -r requirements.yml

check:
    for script in scripts/*.sh; do bash -n "$script"; done
    uv run --locked yamllint .
    uv run --locked ansible-lint --offline roles site.yml bootstrap.yml local.yml remote_server.yml gpg_setup.yml ssh_deploy_key.yml
    uv run --locked ruff check tests
    uv run --locked ruff format --check tests
    uv run --locked ansible-playbook site.yml --syntax-check
    uv run --locked ansible-playbook bootstrap.yml --syntax-check

plan host *args:
    ansible-playbook site.yml --limit "$1" --check "${@:2}"

apply host *args:
    ansible-playbook site.yml --limit "$1" "${@:2}"

full host *args:
    ansible-playbook site.yml --limit "$1" -e manage_personal_keys=true --ask-vault-pass "${@:2}"

secrets host *args:
    ansible-playbook site.yml --limit "$1" --tags ssh,gpg-pass -e manage_personal_keys=true --ask-vault-pass "${@:2}"

bootstrap host *args:
    ansible-playbook bootstrap.yml --limit "$1" "${@:2}"

update-dotfiles host *args:
    ansible-playbook site.yml --limit "$1" --tags dotfiles -e dotfiles_update=true "${@:2}"

test:
    uv run --locked python tests/gpg_integration.py

reset-plan:
    bash scripts/reset-arch-dev.sh --plan

reset:
    bash scripts/reset-arch-dev.sh --apply
