---
status: accepted
---

# A second (unstable) nixpkgs is allowed, for leaf userland tools only

The flake now takes a **second nixpkgs input** tracking `nixos-unstable`, used through a
narrow overlay to pull individual packages that are unusable at their stable version.
The first is `claude-code`.

This amends the rule ADR-0001 set. That ADR's argument was not "one channel is sacred" —
it was that the two things pulling toward unstable, kernel 7.1 and gcc 16.1, were both
*reachable on stable*, so the rolling-breakage tax bought nothing. That reasoning holds
and stable remains the base. It simply does not cover a package whose stable version is
frozen for six months while upstream ships weekly.

## The boundary

A package may come from the unstable input only if it is a **leaf userland tool**:

- nothing else in the closure depends on it,
- it is not in the boot, disk, secrets, or system closure,
- removing it breaks only itself.

Everything load-bearing — kernel, lanzaboote, disko, sops-nix, home-manager, systemd,
the desktop stack — stays on the single stable channel, unconditionally. The
single-channel guarantee that made stable worth choosing still covers every part of the
machine where drift is dangerous.

The comment in `flake.nix` claiming the whole closure sits on one channel was true and is
now narrower. It says so rather than quietly becoming false.

## Why claude-code qualifies

Stable pins it at 2.1.187 for the life of the release, but it ships updates weekly, and
its built-in self-updater cannot write to a read-only `/nix/store` — so the stable
version is not merely behind, it is unable to catch up. It is a CLI in `home.packages`
that nothing depends on; if unstable breaks it, the machine still boots, unlocks, and
logs in.

## Considered Options

- **Stay on stable, accept a stale claude-code** — rejected. A months-old assistant that
  cannot self-update is the failure mode, not a compromise with it.
- **Install it outside Nix (npm or the official installer)** — rejected. Always current
  and self-updating, and consistent with ADR-0006's boundary, but ADR-0006 leaves an app's
  *configuration* mutable while still declaring the app. This would put the whole binary
  outside the repo, so a reinstall would not restore it. A new and worse precedent.
- **Move the whole config to unstable** — rejected on ADR-0001's original reasoning,
  unchanged: rolling breakage is a bad trade while the maintainer is still learning NixOS
  recovery.
- **A flake input for the single package rather than a full nixpkgs** — not available;
  claude-code ships in nixpkgs, not as its own flake.

## Consequences

- **The lock file now carries two nixpkgs.** Evaluation is slower and `nix flake update`
  pulls a second large tree. Real, recurring, and the main cost of this decision.
- **Unfree is allowed in two places now.** The unstable import carries its own
  `allowUnfreePredicate`, because a separately-imported nixpkgs does not see
  `nixpkgs.config` from the NixOS module. The named-packages discipline from
  `default.nix` is repeated there rather than replaced by `allowUnfree = true`, so the
  list in `default.nix` is no longer the complete inventory of unfree packages — it
  points at the other one.
- **Unstable breakage can now reach the machine**, bounded to leaf tools by the rule
  above. A broken claude-code cannot prevent a boot.
- **This list is expected to stay short.** Each addition should be able to state why its
  stable version is *unusable*, not merely older. "Newer" is not a qualification.
