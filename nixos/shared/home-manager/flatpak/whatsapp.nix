{ pkgs, ... }:
let
  flatpakName = "com.rtosta.zapzap";
in
{
  services.flatpak.packages = [
    flatpakName
  ];

  # Autostart Karekare on user login
  systemd.user.services.whatsapp = {
    Unit = {
      Description = "Whatsapp";
      After = [
        "graphical-session.target"
        "network-online.target"
      ];
      Wants = [ "network-online.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.writeShellScript "wait-whatsapp" ''
        # Wait for WhatsApp server to be reachable
        while ! ${pkgs.netcat}/bin/nc -z web.whatsapp.com 443; do
          ${pkgs.coreutils}/bin/sleep 1
        done
      ''}";
      ExecStart = "${pkgs.flatpak}/bin/flatpak run ${flatpakName}";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
