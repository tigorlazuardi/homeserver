# Sukhoi - Autonomous coding agent for Plane issue automation
# https://github.com/tigorlazuardi/sukhoi
{ config, pkgs, ... }:
let
  domain = "sukhoi-booth9.tigor.web.id";
  volume = "/var/mnt/state/sukhoi-booth9";
  ip = "10.88.1.22";
  httpPort = 3000;

  jsonFormat = pkgs.formats.json { };

  defaultConfig = jsonFormat.generate "sukhoi.config.json" {
    repo = "https://github.com/Howezt/booth9.git";
    baseBranch = "development";
    classifier = {
      model = "haiku";
      enabled = true;
      complexity = {
        boilerplate =
          "Scaffolding directories or codes, creating dirs or files. Only create declaration like function or class names and only create stubs to satisfies an interface."
          + "They don't have any actual implementation, and the code inside implementation either immediately panics or throws.";
        simple =
          "Simple Bug fixes or simple tasks. Like adding a field to a specific struct, query, object or schema. "
          + "For queries, this should be like simply adding limit or simple where condition. "
          + "Logic bug is considered simple if task clearly defines what should be fixed, how to do it, and does not include complex logic. "
          + "Usually only requiring extra validation checks and throws or simple return when conditions are not met. "
          + "Anymore complex like rerouting to other implementation should not be considered simple."
          + "Example: endpoint should only return order with status expired";
        complex =
          "Requires architectural thinking or significant design decisions. "
          + "Examples: multi-step user flows, security-critical features (auth, permissions), data migrations, system design, cross-cutting concerns. "
          + "These tasks are often used to create MORE tasks to implement, and create design documents rather than actual implementations";
        typical = "Catch-all for tasks. Usually handles implementing a feature and significant Bugfixes that are opaque on what to do, etc";
      };
    };
    models = {
      opus = "opencode/claude-opus-4-6";
      glm = "opencode/glm-5";
      mimo = "opencode/mimo-v2-flash-free";
      haiku = "opencode/claude-haiku-4-5";
    };
    routing = [
      {
        name = "critical-fixes";
        match.labels = [ "critical" ];
        model = "opus";
      }
      {
        name = "complex-tasks";
        match.complexity = [ "complex" ];
        model = "opus";
      }
      {
        name = "typical";
        match.complexity = [ "typical" ];
        model = "mimo";
      }
      {
        name = "simple";
        match.complexity = [ "simple" ];
        model = "haiku";
      }
      {
        name = "boilerplate";
        match.complexity = [ "boilerplate" ];
        model = "haiku";
      }
    ];
    defaultModel = "mimo";
    worklog = {
      enabled = true;
      maxEntries = 20;
    };
  };

  opencodeConfig = jsonFormat.generate "opencode.json" { permission = "allow"; };
in
{
  sops.secrets."homeserver/sukhoi-booth9.env" = {
    sopsFile = ./sukhoi-booth9.env;
    format = "dotenv";
    key = "";
  };

  virtualisation.oci-containers.containers.sukhoi-booth9 = {
    image = "ghcr.io/tigorlazuardi/sukhoi:latest";
    ip = ip;
    httpPort = httpPort;
    autoStart = true;
    autoUpdate.enable = true;

    environmentFiles = [
      config.sops.secrets."homeserver/sukhoi-booth9.env".path
    ];

    environment = {
      PORT = toString httpPort;
      REPO_CACHE_DIR = "/repo-cache";
    };

    volumes = [
      "${defaultConfig}:/app/sukhoi.config.json:ro"
      "${opencodeConfig}:/app/opencode.json:ro"
      "${volume}/repo-cache:/repo-cache"
    ];
    podman.sdnotify = "healthy";
    extraOptions = [
      "--health-cmd=curl -f http://localhost:3000/health"
      "--health-startup-interval=1s"
      "--health-startup-retries=30"
    ];
  };

  systemd.services.podman-sukhoi-booth9 = {
    preStart = ''
      mkdir -p ${volume}/repo-cache
    '';
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://${ip}:${toString httpPort}";
      extraConfig = ''
        client_max_body_size 50M;
      '';
    };
  };
}
