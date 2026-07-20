# Declarative disk layout.
#
# GPT with a ~1G vfat ESP (/boot) and a single LUKS2 container spanning the rest.
# Inside the LUKS container: one btrfs filesystem with subvolumes /root, /home,
# /nix — all zstd/noatime. Encryption, subvolumes, and TRIM here; zram swap and
# snapper live in the host module (default.nix). See ADR-0003.
let
  # One compression/atime policy shared by every btrfs subvolume, single-sourced.
  btrfsMountOptions = [ "compress=zstd" "noatime" ];
in
{
  disko.devices.disk.main = {
    # Correct for a single-NVMe Framework 13, but VERIFY WITH `lsblk` BEFORE RUNNING
    # DISKO — it destroys whatever is at this path. The install pulls the config from
    # GitHub, so a correction must be committed and pushed before installing.
    device = "/dev/nvme0n1";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            # Restrict the ESP: only root can read it (it holds the boot image).
            mountOptions = [ "umask=0077" ];
          };
        };
        # Everything else is one LUKS2 container. TPM2+PIN enrollment (ADR-0003)
        # happens out-of-band at install; disko only declares the container so
        # `boot.initrd.luks.devices."cryptroot"` is generated for us.
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings = {
              # TRIM through the LUKS layer for SSD longevity. ADR-0003 accepts the
              # block-usage metadata leak this implies.
              allowDiscards = true;
            };
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              # Three sibling top-level subvolumes. Snapper watches /home only
              # (default.nix), so / and /nix are never snapshotted — /nix's
              # exclusion is a consequence of that, not of any nesting.
              subvolumes = {
                # / — snapshotting the system is NixOS generations' job, not snapper's.
                "/root" = {
                  mountpoint = "/";
                  mountOptions = btrfsMountOptions;
                };
                # /home — the only subvolume snapper watches (see default.nix).
                "/home" = {
                  mountpoint = "/home";
                  mountOptions = btrfsMountOptions;
                };
                # /nix — build artifacts, deliberately outside snapper's scope.
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = btrfsMountOptions;
                };
              };
            };
          };
        };
      };
    };
  };
}
