{ pkgs, ... }:
{
  services.flatpak.packages = [
    "io.github.tobagin.karere"
  ];

  # Autostart Karekare on user login
  systemd.user.services.whatsapp = {
    Unit = {
      Description = "Karekare (WhatsApp Client)";
      After = [ "graphical-session.target" "network-online.target" ];
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
      ExecStart = "${pkgs.flatpak}/bin/flatpak run io.github.tobagin.karere";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
