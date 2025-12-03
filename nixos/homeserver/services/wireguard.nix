# WireGuard VPN Server using networking.wireguard
{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "wg.tigor.web.id";
  externalInterface = "eth0";
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
  serverPublicKey = config.sops.placeholder."wireguard/server/public_key";
  endpoint = "wireguard.tigor.web.id:51820";
  dns = "10.0.0.1"; # AdGuard Home on WireGuard gateway
in
{
  environment.systemPackages = [ pkgs.wireguard-tools ];

  sops.secrets =
    let
      opts = {
        sopsFile = ./wireguard.yaml;
      };
    in
    lib.genAttrs [
      "wireguard/server/private_key"
      "wireguard/server/public_key"
      "wireguard/clients/oppo-find-x8/private_key"
      "wireguard/clients/envy/private_key"
    ] (_: opts);

  sops.templates =
    let
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

  # Enable IP forwarding
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  # Firewall
  networking.firewall = {
    allowedUDPPorts = [ 51820 ];
    trustedInterfaces = [ "wg0" ];
    checkReversePath = "loose";
  };

  # NAT for WireGuard clients
  networking.nat = {
    enable = true;
    externalInterface = externalInterface;
    internalInterfaces = [ "wg0" ];
  };

  # WireGuard server
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.0.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets."wireguard/server/private_key".path;

    postSetup = ''
      ${pkgs.iptables}/bin/iptables -A FORWARD -i wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -A FORWARD -o wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o ${externalInterface} -j MASQUERADE
    '';

    postShutdown = ''
      ${pkgs.iptables}/bin/iptables -D FORWARD -i wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -D FORWARD -o wg0 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o ${externalInterface} -j MASQUERADE
    '';

    peers = [
      {
        publicKey = "LPnjJF6iGnzeZA8i4kmjQU3b2fKU7u35uqGBQ0cSCnY="; # oppo-find-x8
        allowedIPs = [ "10.0.0.2/32" ];
      }
      {
        publicKey = "wNG7mSjPZgkNSXkdmPGOFGl6jNEfvs+cglkTbxdCMz4="; # envy
        allowedIPs = [ "10.0.0.3/32" ];
      }
    ];
  };

  # Static HTML page for WireGuard client configs
  services.nginx.virtualHosts.${domain} =
    let
      clientLinks = lib.concatMapStringsSep "\n" (client: ''
        <div class="client">
          <h2>${client.name}</h2>
          <div class="qr" id="qr-${client.name}"></div>
          <a href="/configs/${client.name}.conf" download="${client.name}.conf">Download Config</a>
        </div>
      '') clients;
      webroot = pkgs.writeTextDir "index.html" ''
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>WireGuard Configs</title>
          <script src="https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js"></script>
          <style>
            body { font-family: system-ui, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; background: #1a1a2e; color: #eee; }
            h1 { color: #88d498; }
            .client { background: #16213e; padding: 20px; margin: 20px 0; border-radius: 8px; }
            .client h2 { margin-top: 0; color: #e94560; }
            .qr { background: white; padding: 10px; display: inline-block; margin: 10px 0; }
            a { display: inline-block; background: #88d498; color: #1a1a2e; padding: 10px 20px; text-decoration: none; border-radius: 4px; margin-top: 10px; }
            a:hover { background: #6ab57a; }
          </style>
        </head>
        <body>
          <h1>WireGuard Client Configs</h1>
          ${clientLinks}
          <script>
            async function loadQR(name) {
              const res = await fetch('/configs/' + name + '.conf');
              const text = await res.text();
              const qr = qrcode(0, 'M');
              qr.addData(text);
              qr.make();
              document.getElementById('qr-' + name).innerHTML = qr.createImgTag(4);
            }
            ${lib.concatMapStringsSep "\n" (client: "loadQR('${client.name}');") clients}
          </script>
        </body>
        </html>
      '';
      configDir = "/var/lib/wireguard-configs";
    in
    {
      forceSSL = true;
      tinyauth.enable = true;
      root = webroot;
      locations = {
        "/".index = "index.html";
        "/configs/" = {
          alias = "${configDir}/";
          extraConfig = ''
            default_type application/octet-stream;
          '';
        };
      };
    };

  # Create directory with symlinks to the sops-rendered config files
  systemd.tmpfiles.rules = [
    "d /var/lib/wireguard-configs 0755 nginx nginx -"
  ]
  ++ map (
    client:
    "L+ /var/lib/wireguard-configs/${client.name}.conf - - - - ${
      config.sops.templates."wireguard-client-${client.name}.conf".path
    }"
  ) clients;
}
