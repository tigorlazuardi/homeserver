{
  config,
  pkgs,
  ...
}:
let
  volume = "/var/mnt/nas/torrents";
  # $1 = %N  | Torrent Name
  # $2 = %L  | Category
  # $3 = %G  | Tags
  # $4 = %F  | Content Path
  # $5 = %R  | Root Path
  # $6 = %D  | Save Path
  # $7 = %C  | Number of files
  # $8 = %Z  | Torrent Size
  # $9 = %T  | Current Tracker
  # $10 = %I | Info Hash v1
  # $11 = %J | Info Hash v2
  # $12 = %K | Torrent ID
  # mkNotify =
  #   event:
  #   pkgs.writeScriptBin "notify-${event}" # sh
  #     ''
  #       #!/usr/bin/env bash
  #       data=$(jq -n \
  #         --compact-output \
  #         --arg torrentName "$1" \
  #         --arg category "$2" \
  #         --arg tags "$3" \
  #         --arg contentPath "$4" \
  #         --arg rootPath "$5" \
  #         --arg savePath "$6" \
  #         --arg numFiles "$7" \
  #         --arg torrentSize "$8" \
  #         --arg tracker "$9" \
  #         --arg infoHashV1 "''${10}" \
  #         --arg infoHashV2 "''${11}" \
  #         --arg torrentId "''${12}" \
  #         '{
  #           torrentName: $torrentName,
  #           category: $category,
  #           tags: $tags,
  #           contentPath: $contentPath,
  #           rootPath: $rootPath,
  #           savePath: $savePath,
  #           numFiles: $numFiles,
  #           torrentSize: $torrentSize,
  #           tracker: $tracker,
  #           infoHashV1: $infoHashV1,
  #           infoHashV2: $infoHashV2,
  #           torrentId: $torrentId
  #         }');
  #       curl -u $NTFY_USER --data "$data" "https://ntfy.tigor.web.id/qbittorrent-${event}-raw"
  #     '';
  # notify-start = mkNotify "start";
  # notify-finish = mkNotify "finish";
in
{
  virtualisation.oci-containers.containers.qbittorrent = {
    image = "docker.io/linuxserver/qbittorrent:latest";
    ip = "10.88.2.2";
    httpPort = 8080;
    environment = {
      UMASK = "002";
      PUID = "1000";
      PGID = "1000";
      TZ = "Asia/Jakarta";
    };
    # environmentFiles = [
    #   config.sops.templates."ntfy/client.env".path
    # ];
    volumes = [
      # "${notify-start}/bin/notify-start:/usr/bin/notify-start"
      # "${notify-finish}/bin/notify-finish:/usr/bin/notify-finish"
      "${volume}/config:/config"
      "${volume}/downloads:/downloads"
      "${volume}/progress:/progress"
      "${volume}/watch:/watch"
      # Use VueTorrent interface as webui.
      "${pkgs.vuetorrent}/share/vuetorrent:/webui/vuetorrent:ro"
    ];
    ports = [
      "6881:6881"
      "6881:6881/udp"
    ];
  };
  system.activationScripts.qbittorrent = # sh
    ''
      mkdir -p ${volume}/{config,downloads,progress,watch}
      chown -R 1000:1000 ${volume}
    '';
  systemd.services."podman-qbittorrent".serviceConfig = {
    CPUWeight = 10;
    CPUQuota = "10%";
    IOWeight = 50;
  };
  services.nginx.virtualHosts =
    let
      inherit (config.virtualisation.oci-containers.containers.qbittorrent) ip httpPort;
      proxyPass = "http://${ip}:${toString httpPort}";
    in
    {
      "qbittorrent.tigor.web.id" = {
        forceSSL = true;
        tinyauth.locations = [ "/" ];
        locations."/".proxyPass = proxyPass;
      };
      "qbittorrent.lan".locations."/".proxyPass = proxyPass;
    };
  # services.homepage-dashboard.groups."Media Collectors".services.QBittorrent.settings = {
  #   description = "Torrent downloader";
  #   icon = "qbittorrent.svg";
  #   url = "https://qbittorrent.tigor.web.id";
  #   widget = {
  #     type = "qbittorrent";
  #     url = "http://qbittorrent.lan";
  #     enableLeechProgress = true;
  #   };
  # };
  # services.ntfy-sh.middlewares = [
  #   {
  #     topic = "qbittorrent-start-raw";
  #     command =
  #       with pkgs;
  #       ''${lib.getExe (
  #         writeShellScriptBin "qbittorrent-start-raw-handler" ''
  #           echo "$1"
  #           msg=$(echo "$1" | ${jq}/bin/jq -r '.message')
  #           torrentName=$(echo "$msg" | ${jq}/bin/jq -r '.torrentName')
  #           category=$(echo "$msg" | ${jq}/bin/jq -r '.category')
  #           tags=$(echo "$msg" | ${jq}/bin/jq -r '.tags')
  #           data=$(${jq}/bin/jq -n \
  #             --compact-output \
  #             --arg torrentName "$torrentName" \
  #             --arg category "$category" \
  #             --argjson tags "$(echo "$tags" | ${jq}/bin/jq -R 'split(",")')" \
  #             '{
  #               topic: "qbittorrent-start",
  #               title: "Torrent started: \($category)",
  #               message: $torrentName,
  #               icon: "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/qbittorrent.svg",
  #               tags: $tags
  #             }')
  #
  #           ${curl}/bin/curl -u $NTFY_USER --data "$data" 'https://${config.services.ntfy-sh.domain}'
  #         ''
  #       )} "$raw"'';
  #   }
  #   {
  #     topic = "qbittorrent-finish-raw";
  #     command =
  #       with pkgs;
  #       ''${lib.getExe (
  #         writeShellScriptBin "qbittorrent-finish-raw-handler" ''
  #           echo "$1"
  #           msg=$(echo "$1" | ${jq}/bin/jq -r '.message')
  #           torrentName=$(echo "$msg" | ${jq}/bin/jq -r '.torrentName')
  #           category=$(echo "$msg" | ${jq}/bin/jq -r '.category')
  #           tags=$(echo "$msg" | ${jq}/bin/jq -r '.tags')
  #           torrentSize=$(echo "$msg" | ${jq}/bin/jq -r '.torrentSize')
  #           numFiles=$(echo "$msg" | ${jq}/bin/jq -r '.numFiles')
  #           size=$(echo "$torrentSize" | numfmt --to=iec)
  #           body=$(cat << EOF
  #             $torrentName
  #
  #             Size  : $size
  #             Files : $numFiles
  #           EOF
  #           )
  #           data=$(${jq}/bin/jq -n \
  #             --compact-output \
  #             --arg category "$category" \
  #             --arg body "$body" \
  #             --argjson tags "$(echo "$tags" | ${jq}/bin/jq -R 'split(",")')" \
  #             '{
  #               topic: "qbittorrent-finish",
  #               title: "Torrent finished: \($category)",
  #               message: $body,
  #               icon: "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/qbittorrent.svg",
  #               tags: $tags
  #             }')
  #
  #           ${curl}/bin/curl -u $NTFY_USER --data "$data" 'https://${config.services.ntfy-sh.domain}'
  #         ''
  #       )} "$raw"'';
  #   }
  # ];
}
