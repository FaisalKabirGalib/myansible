FROM archlinux:latest AS base
ARG TAGS
WORKDIR /usr/local/bin
USER root
RUN pacman -Sy --noconfirm && pacman -S --noconfirm ansible curl git base-devel neovim




FROM base AS prime
ARG TAGS
# Add group with GID 1000 only if it doesn't already exist
RUN if ! getent group galib > /dev/null 2>&1; then \
      groupadd --gid 1000 galib; \
    fi

# Add user with UID 1000, add to group with GID 1000, create home directory, and set shell
RUN if ! id -u galib > /dev/null 2>&1; then \
      useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash galib; \
    fi

# Lock the user's password to disable password login
RUN passwd -l galib

# Set up SSH directory and authorized keys (optional, if you need SSH access)
RUN mkdir -p /home/galib/.ssh && \
    chmod 700 /home/galib/.ssh && \
    touch /home/galib/.ssh/authorized_keys && \
    chmod 600 /home/galib/.ssh/authorized_keys && \
    chown -R galib:galib /home/galib/.ssh

# Add your SSH public key (replace with your actual public key) - optional
RUN echo "ssh-rsa YOUR_PUBLIC_KEY_HERE" >> /home/galib/.ssh/authorized_keys

# Switch back to the non-root user
USER root
WORKDIR /root

FROM prime
COPY . .
CMD ["sh", "-c", "ansible-playbook $TAGS local.yml"]


