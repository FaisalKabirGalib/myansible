import os
import subprocess
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def run(args: list[str], *, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(args, env=env, text=True, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f"Command failed: {args[0]}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def git(directory: Path, *args: str) -> str:
    return run(["git", "-C", str(directory), *args]).strip()


def commit(directory: Path) -> str:
    git(directory, "add", ".")
    git(
        directory,
        "-c",
        "user.name=Fixture",
        "-c",
        "user.email=fixture@example.invalid",
        "commit",
        "-qm",
        "Fixture",
    )
    return git(directory, "rev-parse", "HEAD")


def repository(directory: Path) -> None:
    directory.mkdir()
    git(directory, "init", "-q", "-b", "main")


def verify(root: Path) -> None:
    source = root / "source-gnupg"
    source.mkdir(mode=0o700)
    env = {**os.environ, "GNUPGHOME": str(source)}
    run(
        [
            "gpg",
            "--batch",
            "--pinentry-mode",
            "loopback",
            "--passphrase",
            "",
            "--quick-generate-key",
            "Ansible Fixture <fixture@example.invalid>",
            "ed25519",
            "sign",
            "0",
        ],
        env=env,
    )
    listing = run(["gpg", "--with-colons", "--list-keys"], env=env)
    fingerprint = next(line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:"))
    run(
        [
            "gpg",
            "--batch",
            "--pinentry-mode",
            "loopback",
            "--passphrase",
            "",
            "--quick-add-key",
            fingerprint,
            "cv25519",
            "encr",
            "0",
        ],
        env=env,
    )
    public = root / "public.asc"
    private = root / "private.asc"
    public.write_text(run(["gpg", "--batch", "--armor", "--export"], env=env))
    private.write_text(run(["gpg", "--batch", "--armor", "--export-secret-keys"], env=env))
    private.chmod(0o600)
    ssh_key = root / "ssh-key"
    run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(ssh_key)])
    password = root / "vault-password"
    password.write_text("disposable-test-password\n")
    password.chmod(0o600)
    for key in [private, ssh_key]:
        run(["ansible-vault", "encrypt", "--vault-password-file", str(password), str(key)])

    dotfiles = root / "dotfiles-source"
    repository(dotfiles)
    (dotfiles / "zsh").mkdir()
    (dotfiles / "zsh/.zshrc").write_text("export FIXTURE_VERSION=1\n")
    revision = commit(dotfiles)
    (dotfiles / "zsh/.zshrc").write_text("export FIXTURE_VERSION=2\n")
    commit(dotfiles)
    password_repo = root / "password-source"
    repository(password_repo)
    (password_repo / "README").write_text("Disposable password store\n")
    commit(password_repo)

    home = root / "target-home"
    home.mkdir()
    gpg_home = home / ".gnupg"
    gpg_home.mkdir(mode=0o700)
    run(["gpgconf", "--homedir", str(gpg_home), "--launch", "gpg-agent"])
    private_keys = gpg_home / "private-keys-v1.d"
    if private_keys.exists():
        private_keys.rmdir()

    play = [
        {
            "name": "Verify roles with disposable repositories and vaulted keys",
            "hosts": "localhost",
            "connection": "local",
            "become": False,
            "vars": yaml.safe_load((ROOT / "group_vars/all.yml").read_text())
            | {
                "target_home": str(home),
                "manage_personal_keys": True,
                "ssh_private_key_source": str(ssh_key),
                "ssh_authorized_key_files": [str(ssh_key) + ".pub"],
                "dotfiles_repo": str(dotfiles),
                "dotfiles_revision": revision,
                "dotfiles_update": True,
                "dotfiles_packages": ["zsh"],
                "gpg_pass_home": str(gpg_home),
                "gpg_pass_public_key_source": str(public),
                "gpg_pass_private_key_source": str(private),
                "gpg_pass_repository": str(password_repo),
            },
            "roles": [{"role": str(ROOT / "roles" / name)} for name in ["ssh", "dotfiles", "gpg_pass"]],
        }
    ]
    playbook = root / "fixture.yml"
    playbook.write_text(yaml.safe_dump(play, sort_keys=False))
    command = ["ansible-playbook", "-i", "localhost,", str(playbook), "--vault-password-file", str(password)]
    for iteration in range(2):
        output = run(command)
        recap = output.split("PLAY RECAP")[-1].strip()
        print(f"Run {iteration + 1}: {recap}")
        if iteration == 1:
            assert "changed=0 " in recap, recap
    assert (home / ".zshrc").read_text() == "export FIXTURE_VERSION=1\n"
    assert git(home / "homelab", "rev-parse", "HEAD") == revision
    assert (home / ".ssh/id_rsa").stat().st_uid == os.getuid()
    assert (home / ".ssh/id_rsa").stat().st_mode & 0o777 == 0o600
    run(["gpg", "--homedir", str(gpg_home), "--batch", "--list-secret-keys", fingerprint])
    fixture_env = {
        **os.environ,
        "GNUPGHOME": str(gpg_home),
        "PASSWORD_STORE_DIR": str(home / ".password-store"),
    }
    run(["pass", "ls"], env=fixture_env)
    message = root / "message"
    message.write_text("disposable encryption roundtrip\n")
    encrypted = root / "message.gpg"
    run(
        [
            "gpg",
            "--homedir",
            str(gpg_home),
            "--batch",
            "--recipient",
            fingerprint,
            "--output",
            str(encrypted),
            "--encrypt",
            str(message),
        ]
    )
    assert (
        run(["gpg", "--homedir", str(gpg_home), "--batch", "--decrypt", str(encrypted)])
        == message.read_text()
    )
    (home / ".zshrc").unlink()
    (home / ".zshrc").write_text("preserve existing configuration\n")
    failure = subprocess.run(command, text=True, capture_output=True, check=False)
    assert failure.returncode != 0 and "Preview dotfile links" in failure.stdout
    assert (home / ".zshrc").read_text() == "preserve existing configuration\n"
    print(
        "Verified pinned revision, SSH permissions, GPG recovery, decryption, idempotency, and Stow conflicts."
    )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="myansible-test-") as directory:
        root = Path(directory)
        try:
            verify(root)
        finally:
            for home in [root / "source-gnupg", root / "target-home/.gnupg"]:
                subprocess.run(
                    ["gpgconf", "--homedir", str(home), "--kill", "gpg-agent"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )


if __name__ == "__main__":
    main()
