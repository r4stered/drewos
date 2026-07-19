# Track the stable nixpkgs channel; opt into newer tooling per-package

We follow the stable `nixos-26.05` channel rather than `nixos-unstable`. The two
things that pulled us toward unstable — Linux **7.1** and gcc **16.1** — are both
reachable on stable as explicit opt-ins: `boot.kernelPackages = pkgs.linuxPackages_latest`
resolves to kernel 7.1 (cache-backed, identical to what unstable would give), and
`pkgs.gcc16` (16.1.0) is available for a per-project `nix develop` shell. Choosing
stable buys a calm six-month base and avoids unstable's rolling-breakage tax, which
matters while the maintainer is still new to NixOS recovery.

The default stdenv is deliberately left at gcc 15: newer compilers are scoped to the
projects that need them via dev shells, so the whole system stays on the binary cache.

## Considered Options

- **nixos-unstable** — rejected. Its only draws here (latest kernel, latest compiler)
  are available on stable as opt-ins, so the rolling-breakage cost isn't worth it.
- **Override the global stdenv to gcc 16** — rejected. Loses binary-cache hits and
  rebuilds the world from source on every rebuild; not worth it for a per-project need.
