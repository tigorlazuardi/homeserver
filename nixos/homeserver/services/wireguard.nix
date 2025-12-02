# Configuration wiki: "https://wiki.nixos.org/wiki/WireGuard#systemd.network"

{
  config,
  lib,
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];
  sops.secrets =
    let
      opts = {
        sopsFile = ./wireguard.yaml;
        mode = "640";
        owner = "systemd-network";
        group = "systemd-network";
      };
    in
    lib.genAttrs [
      "wireguard/server/private_key"
      "wireguard/server/public_key"
      "wireguard/clients/oppo-find-x8/private_key"
      "wireguard/clients/oppo-find-x8/public_key"
      "wireguard/clients/envy/private_key"
      "wireguard/clients/envy/public_key"
    ] (_: opts);

  sops.templates =
    let
      serverPublicKey = config.sops.placeholder."wireguard/server/public_key";
      endpoint = "wireguard.tigor.web.id:51820";
      dns = "10.0.0.1"; # AdGuard Home on WireGuard gateway

      clients = [
        {
          name = "oppo-find-x8";
          address = "10.0.0.2/32";
          privateKey = config.sops.placeholder."wireguard/clients/oppo-find-x8/private_key";
        }
        {
          name = "envy";
          address = "10.0.0.3/32";
          privateKey = config.sops.placeholder."wireguard/clients/envy/private_key";
        }
      ];

      mkClientConfig = client: {
        name = "wireguard-client-${client.name}.conf";
        value = {
          owner = "nginx";
          group = "nginx";
          mode = "0440";
          content = ''
            [Interface]
            PrivateKey = ${client.privateKey}
            Address = ${client.address}
            DNS = ${dns}

            [Peer]
            PublicKey = ${serverPublicKey}
            Endpoint = ${endpoint}
            AllowedIPs = 0.0.0.0/0
            PersistentKeepalive = 25
          '';
        };
      };
    in
    builtins.listToAttrs (map mkClientConfig clients);

  # Enable IP forwarding for routing client traffic
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  # NAT for WireGuard clients to access internet via server
  networking.nat = {
    enable = true;
    externalInterface = "eth0";
    internalInterfaces = [ "wg0" ];
  };

  networking.firewall.allowedUDPPorts = [ 51820 ];

  systemd.network = {
    networks."50-wg0" = {
      matchConfig.Name = "wg0";
      address = [
        "10.0.0.1/24"
      ];
    };
    netdevs."50-wg0" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = "wg0";
      };
      wireguardConfig = {
        ListenPort = 51820;
        PrivateKeyFile = config.sops.secrets."wireguard/server/private_key".path;
      };

      wireguardPeers = [
        {
          PublicKeyFile = config.sops.secrets."wireguard/clients/oppo-find-x8/public_key".path;
          AllowedIPs = [ "10.0.0.2/32" ];
        }
        {
          PublicKeyFile = config.sops.secrets."wireguard/clients/envy/public_key".path;
          AllowedIPs = [ "10.0.0.3/32" ];
        }
      ];
    };
  };
}
