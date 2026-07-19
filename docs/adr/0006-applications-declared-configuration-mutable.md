---
status: accepted
---

# Applications are declared; their configuration is left mutable

This repo declares **which applications exist** on the machine, and deliberately does
**not** declare how most of them are configured. nvim starts with no plugins and no lua
config; VS Code's settings and extensions are installed by clicking inside VS Code;
Firefox's profile is whatever Firefox writes. Only the *presence* of these apps, and the
system-level plumbing they need to function, lives in Nix.

This is a real deviation from the repo's ethos — everything else here is declared, from
the disk layout to the login screen's PAM stack — so it is recorded rather than left to
look like an oversight.

## Why

**The declarative win is smallest exactly where iteration is fastest.** Disk layout and
boot chain are declared once and touched almost never; getting them from the repo is
enormously valuable. An editor config is touched several times a day while taste is still
forming. Routing each of those edits through `nixos-rebuild` taxes the activity most
sensitive to friction, and the payoff — reproducing a config that is *changing anyway* —
is at its weakest.

**Declaring config too early would encode taste that does not exist yet.** The maintainer
is new to nvim and to tiling generally (ADR-0005 chose COSMIC on the same reasoning:
learn on it, never be trapped by it). Pinning a plugin set now would be pinning guesses.

**Nix-managed VS Code extensions are actively worse here.** VS Code is the
get-work-done escape hatch — the tool reached for when nvim is costing more time than it
is teaching. An escape hatch that needs a rebuild to install an extension is not an
escape hatch.

## The boundary is about preserving the option, not declining it

The terminal choice looks inconsistent with this ADR and is not. **ghostty** was chosen
over **cosmic-term** partly *because* it has a home-manager module, and yet its config is
left mutable today. The distinction is between an option **foreclosed** and an option
**unexercised**: cosmic-term has no HM module, so its font and theme could *never* move
into the repo; ghostty's can, the day the config stops changing weekly. The same holds for
nvim (lua files can move to `xdg.configFile`), VS Code, and Firefox — every app chosen
here has a declarative path available and unused.

So the rule is: **prefer apps that could be declared, then decline to declare them yet.**
Not declaring is reversible. Choosing an app that cannot be declared is not.

## Considered Options

- **Fully Nix-declarative nvim** (`programs.neovim.plugins`) — rejected. One rebuild per
  plugin tried, and nixpkgs' `vimPlugins` set trails upstream. The cost lands entirely on
  learning, which is the point of having nvim at all.
- **A distro (LazyVim / NvChad) bootstrapped by hand** — rejected. Gives a working IDE on
  day one, but the config lands *outside* the repo with no path back in, and a reinstall
  would not restore it. That is the foreclosed-option failure this ADR is written against.
- **Declarative VS Code extensions** (`programs.vscode.extensions`) — rejected. Breaks the
  in-app install button and limits you to nixpkgs' extension set, for reproducibility of a
  thing whose whole job is being immediately available.

## Consequences

- **A reinstall does not restore editor or browser state.** Extensions, keybinds, and
  Firefox profile are lost and re-created by hand. This is accepted; none of it is
  precious, and none of it is a secret (contrast the Secure Boot signing key, which *is*
  declared and sops-encrypted precisely because it cannot be re-created).
- **`programs.nix-ld` becomes load-bearing.** Mutable VS Code means extensions fetch
  prebuilt binaries at runtime, linked against `/lib64/ld-linux-x86-64.so.2` — a path that
  does not exist on NixOS. Without nix-ld those extensions fail with `cannot execute:
  required file not found`, so nix-ld is not an optional nicety here but the thing that
  makes this decision viable.
- **nvim plugin versions, when they arrive, will sit outside the flake lock.** Whatever
  manages them (lazy.nvim or otherwise) will carry its own lockfile, so "one rebuild, one
  rollback" will not cover the editor. Accepted as the price of iteration speed.
- The boundary is expected to **move inward over time** — as taste settles, configs can be
  promoted into the repo one at a time without restructuring anything.
