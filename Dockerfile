FROM archlinux:latest AS base
ARG TAGS
WORKDIR /usr/local/bin
USER root
RUN pacman -Sy
RUN pacman -S --noconfirm ansible curl git base-devel neovim

FROM base AS prime
ARG TAGS
USER root
WORKDIR /root

FROM prime
COPY . .
CMD ["sh", "-c", "ansible-playbook $TAGS local.yml"]


