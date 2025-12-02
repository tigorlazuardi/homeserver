# AdGuard Home DNS server with wildcard DNS rewrites for tigor.web.id
#
# Config is generated from Nix but only copied if not exists,
# allowing manual edits via UI to persist.

{ config, lib, pkgs, ... }:
let
  # Server IP for DNS rewrites
  serverIP = "192.168.100.50";

  # Wildcard DNS rewrites for tigor.web.id
  dnsRewrites = [
    { domain = "tigor.web.id"; answer = serverIP; }
    { domain = "*.tigor.web.id"; answer = serverIP; }
  ];

  # AdGuard Home initial config
  adguardConfig = {
    http = {
      pprof = {
        port = 6060;
        enabled = false;
      };
      address = "0.0.0.0:3000";
      session_ttl = "720h";
    };
    users = [ ]; # Will be set up via UI on first run
    auth_attempts = 5;
    block_auth_min = 15;
    dns = {
      bind_hosts = [
        "192.168.100.50"
        "10.0.0.1"
      ];
      port = 53;
      # Upstream DNS servers (encrypted DNS with fallbacks)
      # Priority: QUIC > DoT > DoH, AdGuard primary, Cloudflare fallback
      upstream_dns = [
        # AdGuard DNS
        "quic://dns.adguard-dns.com"
        "tls://dns.adguard-dns.com"
        "https://dns.adguard-dns.com/dns-query"
        # Cloudflare DNS (fallback)
        "quic://cloudflare-dns.com"
        "tls://cloudflare-dns.com"
        "https://cloudflare-dns.com/dns-query"
      ];
      bootstrap_dns = [
        "94.140.14.14"
        "94.140.15.15"
      ];
      # DNS rewrites generated from nginx virtualHosts
      rewrites = dnsRewrites;
      # Performance settings
      cache_size = 4194304; # 4MB
      cache_ttl_min = 0;
      cache_ttl_max = 0;
      cache_optimistic = true;
      # Security
      enable_dnssec = true;
      # Rate limiting
      ratelimit = 0; # Disable for local network
    };
    filtering = {
      protection_enabled = true;
      filtering_enabled = true;
      parental_enabled = false;
      safe_search = {
        enabled = false;
      };
    };
    # Default filter lists
    filters = [
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
        name = "AdGuard DNS filter";
        id = 1;
      }
      {
        enabled = true;
        url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt";
        name = "AdAway Default Blocklist";
        id = 2;
      }
    ];
    user_rules = [ ];
    dhcp = {
      enabled = false;
    };
    # Logging
    log = {
      enabled = true;
      file = "";
      max_backups = 0;
      max_size = 100;
      max_age = 3;
      compress = false;
      local_time = false;
      verbose = false;
    };
    querylog = {
      enabled = true;
      file_enabled = true;
      interval = "2160h"; # 90 days
      size_memory = 1000;
      ignored = [ ];
    };
    statistics = {
      enabled = true;
      interval = "2160h"; # 90 days
      ignored = [ ];
    };
    schema_version = 29;
  };

  # Generate YAML config file
  configFormat = pkgs.formats.yaml { };
  configFile = configFormat.generate "AdGuardHome.yaml" adguardConfig;

  # Container name
  containerName = "adguardhome";

  # Data directory (on host)
  dataDir = "/var/lib/adguardhome";
in
{
  # AdGuard Home container
  virtualisation.oci-containers.containers.${containerName} = {
    image = "adguard/adguardhome:latest";
    autoStart = true;
    extraOptions = [
      "--network=host" # Use host network for DNS binding
      "--pull=newer" # Auto-update image
    ];
    volumes = [
      "${dataDir}/work:/opt/adguardhome/work"
      "${dataDir}/conf:/opt/adguardhome/conf"
    ];
  };

  # Pre-start to initialize config
  systemd.services."podman-${containerName}" = {
    preStart = ''
      mkdir -p ${dataDir}/work ${dataDir}/conf
      if [ ! -f "${dataDir}/conf/AdGuardHome.yaml" ]; then
        echo "Copying initial AdGuard Home config..."
        cp ${configFile} ${dataDir}/conf/AdGuardHome.yaml
        chmod 644 ${dataDir}/conf/AdGuardHome.yaml
      fi
    '';
  };

  # Open firewall for DNS and web UI
  networking.firewall = {
    allowedTCPPorts = [
      53    # DNS TCP
      3000  # Web UI
    ];
    allowedUDPPorts = [
      53    # DNS UDP
    ];
  };
}
