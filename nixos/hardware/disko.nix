{ inputs, ...}:
{
  imports = [
    inputs.disko.nixosModules.disko
  ];

  disko.devices.disk = {
    main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-ADATA_LEGEND_900_2P182912Q7P9"; # Main NVME SSD
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
            end = "-20G";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/root" = {
                  mountOptions = [ "noatime" ];
                  mountpoint = "/";
                };
                "/home" = {
                  mountOptions = {
                    "compress=zstd" "noatime"
                  };
                  mountpoint = "/home";
                };
                "/home.snapshots" = {}; # for snapper
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [ "compress=zstd" "noatime" ];
                };
                # application runtime state
                "/varlib" = {
                  mountpoint = "/var/lib";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "/varlib/.snapshots" = {};
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
    extension = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-ADATA_LEGEND_900_2P18291Q1SG9"; # NVME SSD Mounted using PCIE lane under the GPU slot.
      content = {
        type = "gpt";
        partitions = {
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/state" = {
                  mountOptions = [ "noatime" "compress=zstd" ];
                  mountpoint = "/var/mnt/state";
                };
                "/state/.snapshots" = {};
              };
            };
          };
        };
      };
    };
  };
}