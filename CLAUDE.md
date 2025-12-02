# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NixOS flake-based dotfiles managing multiple machines with shared configurations, home-manager integration, and secrets management.

## Common Commands

```bash
# Build and switch to new configuration
sudo nixos-rebuild switch --flake .#<hostname>

# Build without switching (dry-run/test)
nixos-rebuild build --flake .#<hostname>

# Available hostnames: nexus, homeserver, envy

# Secrets management (sops-nix with age encryption)
sops secrets/users.yaml          # Edit secrets (requires /opt/age-key.txt for decryption)
sops encrypt secrets/file.yaml   # Encrypt a file
sops encrypt -i secrets/file.yaml # Encrypt in-place
```

## Architecture

### Flake Structure
- `flake.nix` - Entry point, defines inputs (home-manager, disko, nix-flatpak, sops-nix, vscode-server, nix-index-database)
- `nixos/default.nix` - Creates nixosConfigurations using `mkNixosConfiguration` helper that applies common modules

### Machine Hierarchy
```
nixos/
├── common/system/     # Shared across ALL machines (boot, cli, fish, git, neovim, sops)
├── nexus/             # Desktop workstation (KDE, flatpak, gaming)
├── homeserver/        # Server (podman, nginx, webhook, openssh)
├── envy/              # Minimal config (hardware only)
├── shared/home-manager/  # Reusable home-manager modules (flatpak apps, git, vscode)
└── environments/      # Work/project-specific configs that overlay onto machines
    ├── aldhyaksa/     # Personal environment
    ├── bareksa/       # Work environment (Go, git config)
    ├── claude-code/   # Claude Code specific setup
    └── grandboard/    # Server services (nginx, tinyauth)
```

### Configuration Pattern
- System-level configs: `nixos/<machine>/default.nix` imports hardware, services, and user config
- Home-manager integration: Machines import `home-manager.nixosModules.home-manager` and set `home-manager.users.<user>`
- Environments compose into machines via imports in home-manager or system configs

### Secrets
- Location: `secrets/` directory at repo root
- Encryption: sops with age keys
- Decryption key: `/opt/age-key.txt` (must exist on target machine)
- Can encrypt without the key, decryption requires the key file

## Important Conventions

- All Nix configuration files must be in `nixos/` directory
- Flatpak apps are managed declaratively via nix-flatpak in `shared/home-manager/flatpak/`
- Hardware configs include disko for declarative disk partitioning
