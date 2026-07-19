# home-manager as a NixOS module, not standalone

User-level config (git, shell, terminal, and later the desktop) is managed by
home-manager wired in as a **NixOS module** (`home-manager.nixosModules.home-manager`
imported into `nixosConfigurations`), so a single `nixos-rebuild switch` builds the
system and the user config into **one generation** with **one rollback** — the direct
expression of this repo's "the repo IS the machine" goal. We set `useGlobalPkgs = true`
(home-manager shares the system's nixpkgs — one channel, no drift) and
`useUserPackages = true` (user packages install as part of system activation). User
config thus rides inside the same secure-boot-signed, TPM-sealed generation as the system.

## Considered Options

- **Standalone `homeConfigurations` + `home-manager switch`** — rejected. A separate
  activation lifecycle earns its keep only when the user config must be portable across
  machines you don't own (work laptops, remote/non-NixOS hosts). This is a single,
  fully-NixOS personal laptop, so that portability buys nothing and costs a split-brain
  "did I run the second command?" lifecycle plus a second thing to roll back.

## Consequences

- You cannot rebuild *just* home without touching the system generation — an acceptable
  loss on a single-user personal machine.
- The commit-signing git config decided in #14 (`gpg.format = ssh`, `commit.gpgsign`,
  `allowedSignersFile`) lives in `programs.git` under this module.
