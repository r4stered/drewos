# DrewOS — NixOS Configuration

Declarative NixOS configuration for a Framework 13 (AMD Ryzen 7040) laptop.
The repo *is* the machine: a rebuild reads it, a rollback returns to a prior
version of it, a reinstall points the installer back at it.

## Language

**Channel**:
The nixpkgs release track the config follows. `nixos-26.05` (stable) is a fixed,
six-month release; `nixos-unstable` is rolling. This repo tracks **stable**.
_Avoid_: version, branch (when you mean the release track)

**Default toolchain**:
The kernel and compiler NixOS uses when you configure nothing — conservative and
fully backed by the binary cache. On 26.05 that is kernel **6.18** and gcc **15**.
_Avoid_: "the kernel" / "the compiler" said bare — always say *default* or
*pinned-latest*, because the two differ and conflating them has caused confusion.

**Pinned-latest toolchain**:
A newer kernel or compiler opted into *explicitly, per-package, on the stable
channel* — `boot.kernelPackages = pkgs.linuxPackages_latest` (kernel **7.1**,
cache-backed) and `pkgs.gcc16` (**16.1**, scoped to a project dev shell). It is
NOT the same as switching to unstable; these versions ship on stable too.
_Avoid_: "unstable's kernel", "unstable's gcc"
