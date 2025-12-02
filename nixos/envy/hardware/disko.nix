{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
  ];

  disko.devices.disk = {
    main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-SKHynix_HFM512GD3HX015N_FYA8N050111208Q0F";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            priority = 1;
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
            end = "-17G";
            content = {
              type = "btrfs";
              extraArgs = [
                "-f"
                "-L"
                "envy"
              ];
              subvolumes = {
                "/root" = {
                  mountOptions = [ "noatime" ];
                  mountpoint = "/";
                };
                "/home" = {
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                  mountpoint = "/home";
                };
                "/home/.snapshots" = { }; # for snapper
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                # application runtime state
                "/varlib" = {
                  mountpoint = "/var/lib";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "/varlib/.snapshots" = { };
              };
            };
          };
          swap = {
            size = "100%";
            content = {
              type = "swap";
              discardPolicy = "both";
              resumeDevice = true;
            };
          };
        };
      };
    };
  };

  services.snapper.configs = {
    home = {
      SUBVOLUME = "/home"; # only subvolumes with .snapshots under them can be used
      ALLOW_USERS = [ "tigor" ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
    };
    varlib = {
      SUBVOLUME = "/var/lib"; # only subvolumes with .snapshots under them can be used
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
    };
  };
}
