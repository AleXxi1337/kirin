# kirin

A desktop shell on Hyprland and Quickshell, in the spirit of macOS: a bar
with a taskbar, a launcher, notifications, a lock screen that is also the
login, video wallpapers, Material You colours from the wallpaper, tiling
and a desktop-like windows mode.

Only NixOS is supported for now (x86_64, with flakes).

- [Install on a new machine](#install-on-a-new-machine)
- [Add kirin to your NixOS](#add-kirin-to-your-nixos)
- [Examples: the simplest and the fullest](#examples)
- [After installing](#after-installing)
- [Updating](#updating)
- [Changing kirin](#changing-kirin)
- [When something goes wrong](#when-something-goes-wrong)

## Install on a new machine

This puts NixOS with kirin on an empty disk, from the NixOS installer. It
erases the disk.

What you need:

- the **minimal NixOS ISO** (nixos.org → Download → Minimal ISO image),
  written to a USB stick, or attached to a virtual machine;
- the machine booting in **UEFI** mode (without Secure Boot);
- the internet;
- in a **virtual machine**, 3D graphics (virt-manager: Video → Virtio with
  "3D acceleration", Display Spice → Listen type None, OpenGL on), 4 GB of
  memory or more and a 30 GB disk. Without 3D graphics Hyprland is slow.

Boot the ISO; it logs you in as `nixos`. Then:

**1. Become root.**

```sh
sudo -i
```

**2. Find the disk.** `lsblk` lists them: in a VM it's usually `vda`, on a
laptop `nvme0n1` or `sda`. Below it's `/dev/vda`; put yours instead. On
`nvme0n1` the partitions are `nvme0n1p1` and `nvme0n1p2`, not `nvme0n11`.

```sh
lsblk
```

**3. Partition it:** a 512 MB boot partition and the rest for the system.

```sh
parted /dev/vda -- mklabel gpt
parted /dev/vda -- mkpart ESP fat32 1MB 512MB
parted /dev/vda -- set 1 esp on
parted /dev/vda -- mkpart root ext4 512MB 100%
```

**4. Format and mount.**

```sh
mkfs.fat -F 32 -n boot /dev/vda1
mkfs.ext4 -L nixos /dev/vda2
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/boot /mnt/boot
```

**5. Get the configuration** (kirin's template) and describe the hardware.

```sh
mkdir -p /mnt/etc/nixos
cd /mnt/etc/nixos
nix --extra-experimental-features 'nix-command flakes' flake init -t github:AleXxi1337/kirin
nixos-generate-config --root /mnt --show-hardware-config > hardware-configuration.nix
```

You now have three files: `flake.nix` (where NixOS and kirin come from),
`configuration.nix` (your system: the user, kirin, the time zone…) and
`hardware-configuration.nix`. Look at `configuration.nix` and change what
you like (the time zone, say) with `nano configuration.nix`.

**6. Lock the versions, then install.** The lock step first: made during
the install, the lock file fails its own check ("NAR hash mismatch").

```sh
nix --extra-experimental-features 'nix-command flakes' flake lock
nixos-install --flake /mnt/etc/nixos#kirin
```

It downloads a lot and builds kirin's plugins: a while. At the end it asks
for a root password.

**7. Restart** and take the ISO out.

```sh
reboot
```

kirin's lock screen comes up: the user is `user`, the password `kirin`.
Change it right away (Super+Q opens a terminal):

```sh
passwd
```

## Add kirin to your NixOS

Already on NixOS with a flake: add kirin as an input and turn it on.

In `flake.nix`:

```nix
inputs.kirin.url = "github:AleXxi1337/kirin";
```

add its module to your system's:

```nix
nixosConfigurations.mymachine = nixpkgs.lib.nixosSystem {
  modules = [
    kirin.nixosModules.default
    ./configuration.nix
  ];
};
```

(`kirin` needs to be among the `outputs` function's arguments:
`outputs = { nixpkgs, kirin, ... }:`), and in `configuration.nix`:

```nix
kirin = {
  enable = true;
  user = "you";
};
```

Then:

```sh
sudo nixos-rebuild switch --flake .#mymachine
```

and log out (or restart): greetd now starts kirin, its lock screen is the
login.

If your flake isn't in `/etc/nixos`, or its system isn't named as the
machine (`networking.hostName`), tell kirin where it is, for updates:
`kirin.update.flake` and `kirin.update.host` (see the fullest example).

Don't make kirin's nixpkgs follow yours (`kirin.inputs.nixpkgs.follows`):
kirin builds Hyprland and its titlebar plugin from its own, and the plugin
has to match that Hyprland exactly.

## Examples

### The simplest

What `nix flake init -t github:AleXxi1337/kirin` gives you.

`flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    kirin.url = "github:AleXxi1337/kirin";
  };

  outputs =
    { nixpkgs, kirin, ... }:
    {
      nixosConfigurations.kirin = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          kirin.nixosModules.default
          ./configuration.nix
        ];
      };
    };
}
```

`configuration.nix`:

```nix
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "kirin";

  users.users.user = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "kirin";
  };

  kirin = {
    enable = true;
    user = "user";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "26.05";
}
```

### The fullest

Every option of kirin's, and how to override what it turns on.

`flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Yours: a fork, or a branch (github:you/kirin/dev).
    kirin.url = "github:AleXxi1337/kirin";
  };

  outputs =
    { nixpkgs, kirin, ... }:
    {
      nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          kirin.nixosModules.default
          ./configuration.nix
        ];
      };
    };
}
```

`configuration.nix`:

```nix
{ lib, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "laptop";
  time.timeZone = "Europe/Berlin";

  users.users.alex = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "change-me";
  };

  kirin = {
    enable = true;

    # Whose session greetd starts (kirin's lock screen is the login).
    user = "alex";

    # The checkout of kirin you change and commit, in the home directory.
    # Default: ".kirin".
    path = ".kirin";

    # What it's cloned from at the first login. With a fork, this and
    # inputs.kirin.url both point at it (Settings → Update says if they
    # don't). Default: kirin's repository.
    repo = "https://github.com/AleXxi1337/kirin.git";

    update = {
      # Where this system's flake is, for Settings → Update.
      # Default: "/etc/nixos".
      flake = "/home/alex/nixos-config";
      # Its nixosConfigurations entry for this machine.
      # Default: networking.hostName.
      host = "laptop";
    };

    # A swapfile as big as the RAM, for hibernation. Default: off.
    hibernation.enable = true;
    # Sleep, then hibernate once the battery runs low. Needs
    # hibernation. Default: off.
    sleep.thenHibernate = true;

    # A quiet boot: no boot menu (hold Space to see it), no kernel text,
    # a splash screen that also asks for the disk's password. Default: on.
    boot.splash = true;
  };

  # What kirin turns on are defaults: yours win. For instance tuned instead
  # of power-profiles-daemon (kirin talks to either):
  services.power-profiles-daemon.enable = lib.mkForce false;
  services.tuned = {
    enable = true;
    ppdSupport = true;
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "26.05";
}
```

What kirin turns on, all overridable: Hyprland, PipeWire, NetworkManager,
Bluetooth, UPower, power-profiles-daemon, udisks2, gvfs, polkit, XDG
portals, fonts, a quiet boot with a splash screen (Plymouth), greetd
(starting kirin's session) and the packages
`install/manifest.toml` lists.

## After installing

At every login kirin keeps its checkout in `~/.kirin`: cloned from the
repository at the first one (copied from the system, without git history,
if there's no network then: Settings → Update connects it later) and linked
into `~/.config`. Your settings are in `~/.config/kirin/config.json`, set
from the settings window.

A few keys:

| Keys | What |
|---|---|
| Super+Space | Launcher (apps, files, `/wallpaper`, `/clipboard`, a calculator) |
| Super+I | Settings |
| Super+Q | Terminal |
| Super+E | Files |
| Super+C | Close the window |
| Alt+Tab | Switch windows |
| Super+1…0 | Workspaces |
| Super+Ctrl+Shift+T | Tiling ↔ windows mode |
| Print, Shift+Print | Screenshot of an area, of the screen |

All of them can be changed in Settings → Shortcuts.

## Updating

Settings → Update shows your version, the latest one and what's new; it
checks once a day too, with a notification and a dot on the bar's gear.

- **One-click system update** on (it asks for your password once): Update does
  it all, `nix flake update kirin` and the rebuild too, without a password.
  Nothing updates on its own: the daily check only tells you.
- Off: the page shows the commands. By hand:

  ```sh
  sudo nix flake update kirin --flake /etc/nixos
  sudo nixos-rebuild switch --flake /etc/nixos#kirin
  git -C ~/.kirin merge --ff-only $(jq -r .rev /etc/kirin/system.json)
  ```

If Hyprland or the titlebar plugin changed, log out and in again.
Changes of yours in `~/.kirin` hold the update until you commit or stash
them (Settings → Update has a Stash button).

## Changing kirin

The shell isn't in the Nix store: change the files in `~/.kirin`, and
Quickshell and Hyprland pick most changes up as you save (else
`kirin reload`). Commit them, push them to your fork.

The titlebar plugin is compiled: the system has one built for its Hyprland.
`kirin plugins --build` builds yours from `~/.kirin` and uses it from the
next login; `kirin plugins --reset` goes back to the system's.

Back to the factory settings: Settings → About.

## When something goes wrong

- **A black screen after logging in**: Ctrl+Alt+F2, log in, and look at
  `cat /run/user/$(id -u)/kirin-init.log` and `journalctl -b -u greetd`.
- **"NAR hash mismatch" while installing**: `nix flake lock` first, then
  install again.
- **Hyprland very slow in a virtual machine**: its graphics need 3D
  acceleration (see [above](#install-on-a-new-machine)).
- **An update fails**: Settings → Update shows why; the full log is
  `journalctl -u kirin-update`.

## Layout

| Path | What |
|---|---|
| `config/quickshell/kirin` | The shell (Quickshell): bar, launcher, notifications, lock screen, settings… |
| `config/hypr` | Hyprland's config (Lua): keys, window modes, placement, sleep… |
| `share/` | Linked into `~/.local/share` (the settings app's desktop entry, symbols) |
| `assets/` | The default wallpaper |
| `plugins/bars` | The titlebar plugin (C++, Hyprland) |
| `plugins/video` | The video wallpaper QML module (C++, Qt) |
| `cli/` | The `kirin` command |
| `install/manifest.toml` | What kirin needs: packages, fonts, links, folders (the module and `kirin init` both read it) |
| `nix/` | The NixOS module and packages |
| `templates/default` | A whole system with kirin |
