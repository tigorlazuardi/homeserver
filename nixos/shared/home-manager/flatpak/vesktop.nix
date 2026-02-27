{ pkgs, ... }:
{
  home.packages = with pkgs; [ vesktop ];
  # Autostart Vesktop on user login
  systemd.user.services.vesktop = {
    Unit = {
      Description = "Vesktop Discord Client";
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
      ExecStartPre = "${pkgs.writeShellScript "wait-discord" ''
        # Wait for Discord server to be reachable
        while ! ${pkgs.netcat}/bin/nc -z discord.com 443; do
          ${pkgs.coreutils}/bin/sleep 1
        done
      ''}";
      ExecStart = "${pkgs.vesktop}/bin/vesktop";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
