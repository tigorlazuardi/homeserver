{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
  ];

  disko.devices.disk = {
    main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-PNY_CS2241_1TB_SSD_PNL04240437686500871";
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
                "nexus"
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
    adata = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-ADATA_SX8200PNP_2L082L47182A";
      content = {
        type = "gpt";
        partitions = {
          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [
                "-f"
                "-L"
                "adata"
              ];
              subvolumes = {
                "/data" = {
                  mountOptions = [
                    "noatime"
                    "compress=zstd"
                    "nofail"
                  ];
                  mountpoint = "/var/mnt/adata";
                };
                "/data/.snapshots" = { };
              };
            };
          };
        };
      };
    };
    # kyo = {
    #   type = "disk";
    #   device = "/dev/disk/by-id/nvme-K350-1TB_0004253001512";
    #   content = {
    #     type = "gpt";
    #     partitions = {
    #       root = {
    #         size = "100%";
    #         content = {
    #           type = "btrfs";
    #           extraArgs = [ "-f" "-L" "kyo" ];
    #           subvolumes = {
    #             "/data" = {
    #               mountOptions = [
    #                 "noatime"
    #                 "compress=zstd"
    #                 "nofail"
    #               ];
    #               mountpoint = "/var/mnt/kyo";
    #             };
    #             "/data/.snapshots" = { };
    #           };
    #         };
    #       };
    #     };
    #   };
    # };
    # hgst = {
    #   type = "disk";
    #   device = "/dev/disk/by-id/ata-HGST_HTS721010A9E630_JR10004M3NZVHF";
    #   content = {
    #     type = "gpt";
    #     partitions = {
    #       root = {
    #         size = "100%";
    #         content = {
    #           type = "btrfs";
    #           extraArgs = [
    #             "-f"
    #             "-L"
    #             "hgst"
    #           ];
    #           subvolumes = {
    #             "/data" = {
    #               mountOptions = [
    #                 "noatime"
    #                 "compress=zstd"
    #                 "nofail"
    #               ];
    #               mountpoint = "/var/mnt/hgst";
    #             };
    #             "/data/.snapshots" = { };
    #           };
    #         };
    #       };
    #     };
    #   };
    # };
    # wdc = {
    #   type = "disk";
    #   device = "/dev/disk/by-id/ata-WDC_WDS500G2B0A-00SM50_19432C802119";
    #   content = {
    #     type = "gpt";
    #     partitions = {
    #       root = {
    #         size = "100%";
    #         content = {
    #           type = "btrfs";
    #           extraArgs = [
    #             "-f"
    #             "-L"
    #             "wdc"
    #           ];
    #           subvolumes = {
    #             "/data" = {
    #               mountOptions = [
    #                 "noatime"
    #                 "compress=zstd"
    #                 "nofail"
    #               ];
    #               mountpoint = "/var/mnt/wdc";
    #             };
    #             "/data/.snapshots" = { };
    #           };
    #         };
    #       };
    #     };
    #   };
    # };
    # vgen = {
    #   type = "disk";
    #   device = "/dev/disk/by-id/ata-V-GEN05SM23AR512INT_512GB_VGAR2023053000068434";
    #   content = {
    #     type = "gpt";
    #     partitions = {
    #       root = {
    #         size = "100%";
    #         content = {
    #           type = "btrfs";
    #           extraArgs = [
    #             "-f"
    #             "-L"
    #             "vgen"
    #           ];
    #           subvolumes = {
    #             "/data" = {
    #               mountOptions = [
    #                 "noatime"
    #                 "compress=zstd"
    #                 "nofail"
    #               ];
    #               mountpoint = "/var/mnt/vgen";
    #             };
    #             "/data/.snapshots" = { };
    #           };
    #         };
    #       };
    #     };
    #   };
    # };
  };
}
