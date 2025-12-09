{ pkgs, ... }:
{
  services.flatpak.packages = [
    "com.slack.Slack"
  ];

  # Autostart Slack on weekdays 08:00-18:00
  systemd.user.services.slack = {
    Unit = {
      Description = "Slack";
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
      ExecStartPre = "${pkgs.writeShellScript "wait-slack" ''
        # Wait for Slack server to be reachable
        while ! ${pkgs.netcat}/bin/nc -z slack.com 443; do
          ${pkgs.coreutils}/bin/sleep 1
        done
      ''}";
      ExecStart = "${pkgs.flatpak}/bin/flatpak run com.slack.Slack";
    };
  };

  systemd.user.timers.slack = {
    Unit = {
      Description = "Start Slack during work hours (Mon-Fri 08:00-18:00)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Timer = {
      OnCalendar = "Mon..Fri *-*-* 08..17:*:*";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
