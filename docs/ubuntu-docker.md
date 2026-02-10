# Ubuntu Server Docker Setup

## Building the Image

```bash
./build_docker_ubuntu
# or manually:
docker build -f Dockerfile.ubuntu -t ubuntu-server .
```

## Running the Container

### Option 1: Interactive shell (recommended)
```bash
docker run --rm -it ubuntu-server bash
# Then run: sudo ansible-playbook ubuntu_server.yml
```

### Option 2: Run playbook in one command
```bash
docker run --rm ubuntu-server bash -c "sudo ansible-playbook ubuntu_server.yml"
```

### Option 3: Run with specific tags
```bash
docker run --rm ubuntu-server bash -c "sudo ansible-playbook ubuntu_server.yml --tags zsh"
```

## Testing

### 1. Verify user creation
```bash
docker run --rm ubuntu-server bash -c "id galib"
```

### 2. Verify sudo access
```bash
docker run --rm ubuntu-server bash -c "su - galib -c 'sudo whoami'"
```

### 3. Verify password login
```bash
docker run --rm ubuntu-server bash -c "su - galib -c 'echo 1135 | su - root -c whoami'"
```

### 4. Verify dotfiles installation
```bash
docker run --rm ubuntu-server bash -c "su - galib -c 'ls -la ~/dotfiles'"
```

### 5. Verify shell configuration
```bash
docker run --rm -it ubuntu-server bash -c "su - galib"
# Then inside: run 'zsh' to test shell
```

## Login Credentials

- **Username**: galib
- **Password**: 1135
- **Sudo**: Yes (passwordless)

## Manual SSH Access

```bash
# Build and run in background
docker run -d --name myserver ubuntu-server sleep infinity

# Exec into container
docker exec -it myserver su - galib

# Or with password prompt
docker exec -it myserver bash
su - galib  # password: 1135
```
