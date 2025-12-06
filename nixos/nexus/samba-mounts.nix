# Samba network mounts from homeserver
{ config, pkgs, ... }:
{
  # Samba credentials from sops
  sops.secrets.samba-credentials = {
    sopsFile = ./samba.yaml;
    mode = "0400";
  };

  # Install cifs-utils with setuid wrapper for user mounts
  environment.systemPackages = [ pkgs.cifs-utils ];

  security.wrappers."mount.cifs" = {
    program = "mount.cifs";
    source = "${pkgs.cifs-utils}/bin/mount.cifs";
    owner = "root";
    group = "root";
    setuid = true;
  };

  fileSystems."/mnt/homeserver/nas" = {
    device = "//homeserver/nas";
    fsType = "cifs";
    options = [
      "credentials=${config.sops.secrets.samba-credentials.path}"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
      "_netdev"
      "vers=3.0"
      "uid=1000"
      "gid=100"
      "file_mode=0644"
      "dir_mode=0755"
    ];
  };

  fileSystems."/mnt/homeserver/wolf" = {
    device = "//homeserver/wolf";
    fsType = "cifs";
    options = [
      "credentials=${config.sops.secrets.samba-credentials.path}"
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
      "_netdev"
      "vers=3.0"
      "uid=1000"
      "gid=100"
      "file_mode=0644"
      "dir_mode=0755"
    ];
  };
}
