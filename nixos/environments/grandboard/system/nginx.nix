{ config, lib, ... }:
{
  security.acme.certs."grandboard.web.id" = {
    webroot = "/var/lib/acme/acme-challenge";
    group = "nginx";
    extraDomainNames =
      with lib;
      let
        domains = filterAttrs (
          name: value:
          (name != "grandboard.web.id") # Do not put exact domain here, otherwise let's encrypt will reject it because it already exists and cannot put in SAN.
          && (value.forceSSL || value.onlySSL)
          && (value.useACMEHost == "grandboard.web.id")
          && (hasSuffix "grandboard.web.id" name)
        ) config.services.nginx.virtualHosts;
      in
      attrNames domains;
  };
  security.acme.certs."grandboard.id" = {
    webroot = "/var/lib/acme/acme-challenge";
    group = "nginx";
    extraDomainNames =
      with lib;
      let
        domains = filterAttrs (
          name: value:
          (name != "grandboard.id")
          && (value.forceSSL || value.onlySSL)
          && (value.useACMEHost == "grandboard.id")
          && (hasSuffix "grandboard.id" name)
        ) config.services.nginx.virtualHosts;
      in
      attrNames domains;
  };
}
