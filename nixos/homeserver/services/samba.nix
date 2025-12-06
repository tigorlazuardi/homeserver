# Samba - Network File Sharing
{ config, ... }:
{
  services.samba = {
    enable = true;
    openFirewall = true;

    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "homeserver";
        "netbios name" = "homeserver";
        security = "user";
        "hosts allow" = "192.168.0. 192.168.100. 10.88. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };

      nas = {
        path = "/var/mnt/nas";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "homeserver";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "homeserver";
        "force group" = "homeserver";
      };

      wolf = {
        path = "/var/mnt/wolf";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "homeserver";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "homeserver";
        "force group" = "homeserver";
      };
    };
  };

  # Enable samba-wsdd for Windows network discovery
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
}
