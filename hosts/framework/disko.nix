# STUB disk layout — tracer-bullet slice (#16).
#
# This exists only to give the dry-build an honest root filesystem + ESP so
# `nixos-rebuild build` exercises real module composition. It is deliberately
# trivial: a plain GPT with a vfat ESP and a single ext4 root, NO encryption.
#
# The real layout — LUKS2 + btrfs subvolumes (/root, /home, /nix), zstd/noatime,
# TRIM, zram-only swap — lands in its own slice (#17) and replaces this file
# wholesale. Don't build on top of this; it's scaffolding.
{
  disko.devices.disk.main = {
    # Placeholder — the real device comes from `lsblk` at install time (#17).
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
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
