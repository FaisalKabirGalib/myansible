FROM archlinux:base-devel
RUN pacman -Syu --needed --noconfirm ansible git stow gnupg pass openssh sudo python-yaml \
    && useradd --create-home tester \
    && printf 'tester ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/tester \
    && chmod 0440 /etc/sudoers.d/tester
WORKDIR /workspace
COPY --chown=tester:tester . .
USER tester
CMD ["python", "tests/gpg_integration.py"]
