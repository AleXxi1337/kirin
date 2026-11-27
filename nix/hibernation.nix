# Hibernation into a swapfile sized to this machine's RAM, so the same
# config works on any machine: nothing in it depends on the hardware.
#
# On boot, a service makes sure there is:
#   - a btrfs subvolume @swap (no copy-on-write, no compression for the
#     file), mounted on /swap; on other filesystems, /swapfile instead;
#   - a swapfile as big as the RAM (made anew if the RAM changed),
#     inside the root filesystem, so on a LUKS disk the image is encrypted;
# then turns it on.
#
# Where the image goes needs no resume=/resume_offset= kernel parameters:
# systemd (v255+) writes it to an EFI variable (HibernateLocation) when
# hibernating, and the systemd initrd (boot.initrd.systemd.enable) resumes from it.
#
# A host turns it on with: kirin.hibernation.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kirin.hibernation;
in
{
  options.kirin.hibernation.enable = lib.mkEnableOption "hibernation into a swapfile sized to this machine's RAM";

  config = lib.mkIf cfg.enable {
    # Resuming needs it: it reads where the image is (HibernateLocation).
    boot.initrd.systemd.enable = lib.mkDefault true;

    systemd.services.swapfile = {
      description = "Swapfile for hibernation, sized to the RAM";
      # An ordinary service, started with the rest once the filesystems are
      # up: swap is only needed by the time of hibernating. Not ordered
      # before swap.target: some mounts (/run/wrappers) come after that
      # target, so being both after the filesystems and before it made an
      # ordering cycle, and systemd broke it by dropping one of those
      # mounts (no /run/wrappers: no session, a black screen). The default
      # dependencies also stop it (swap off) before shutdown unmounts.
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      path = with pkgs; [
        btrfs-progs
        util-linux
        coreutils
        gawk
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu

        # As much swap as RAM, rounded up to whole GiB.
        mem_kib=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
        size_mib=$(( (mem_kib + 1048575) / 1048576 * 1024 ))
        size_bytes=$(( size_mib * 1024 * 1024 ))

        fstype=$(findmnt -no FSTYPE /)
        if [ "$fstype" = btrfs ]; then
          # The device under /, without the "[/@]" subvolume suffix.
          source=$(findmnt -no SOURCE /)
          device=''${source%%[*}
          file=/swap/swapfile

          mkdir -p /swap
          if ! mountpoint -q /swap; then
            top=$(mktemp -d)
            mount -o subvolid=5 "$device" "$top"
            [ -d "$top/@swap" ] || btrfs subvolume create "$top/@swap"
            umount "$top"
            rmdir "$top"
            mount -o subvol=@swap,noatime "$device" /swap
          fi

          current=$(stat -c %s "$file" 2>/dev/null || echo 0)
          if [ "$current" -ne "$size_bytes" ]; then
            swapoff "$file" 2>/dev/null || true
            rm -f "$file"
            # Makes it right for btrfs: no copy-on-write, no compression.
            btrfs filesystem mkswapfile --size "''${size_mib}m" "$file"
          fi
        else
          file=/swapfile
          current=$(stat -c %s "$file" 2>/dev/null || echo 0)
          if [ "$current" -ne "$size_bytes" ]; then
            swapoff "$file" 2>/dev/null || true
            rm -f "$file"
            fallocate -l "$size_bytes" "$file"
            chmod 600 "$file"
            mkswap "$file"
          fi
        fi

        swapon --show=NAME --noheadings | grep -qx "$file" || swapon "$file"
      '';
      preStop = ''
        for f in /swap/swapfile /swapfile; do
          [ -e "$f" ] && swapoff "$f" 2>/dev/null || true
        done
      '';
    };
  };
}
