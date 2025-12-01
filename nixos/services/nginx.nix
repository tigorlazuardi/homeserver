{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Despite this being an option declaration, this is instead set default values
  # for every nginx virtual hosts.
  options =
    let
      inherit (lib)
        mkOption
        types
        mkDefault
        ;
    in
    {
      services.nginx.virtualHosts = mkOption {
        type = types.attrsOf (
          types.submodule {
            # All locations will have proxyWebsockets enabled by default to imitate caddy behavior.
            options.locations = mkOption {
              type = types.attrsOf (
                types.submodule {
                  config.proxyWebsockets = mkDefault true;
                }
              );
            };
            config = {
              # By default, uses existing ACME certificates if available (Certs will have multiple SAN)
              # to reduce API calls to Let's Encrypt.
              #
              # Certs must be defined in config.security.acme.certs to work.
              useACMEHost = mkDefault "tigor.web.id";
            };
          }
        );
      };
    };
  config =
    let
      inherit (lib)
        filterAttrs
        mapAttrs'
        nameValuePair
        attrNames
        hasSuffix
        ;
    in
    {
      networking.firewall.allowedTCPPorts = [
        80
        443
      ];
      services.nginx = {
        enable = true;
        # This option sets ssl_stapling which is removed by let's encrypt.
        # See https://forum.hestiacp.com/t/ssl-stapling-ignored-no-ocsp-responder-url-in-the-certificate/18944/4
        #
        # So we just copy the default value from NixOS but remove the ssl_stapling option.
        #
        # recommendedTlsSettings = true;
        recommendedOptimisation = true;
        recommendedGzipSettings = true;
        recommendedProxySettings = true;
        commonHttpConfig =
          let
            realIpsFromList = lib.strings.concatMapStringsSep "\n" (x: "set_real_ip_from  ${x};");
            fileToList = x: lib.strings.splitString "\n" (builtins.readFile x);
            cfipv4 = fileToList (
              pkgs.fetchurl {
                url = "https://www.cloudflare.com/ips-v4";
                sha256 = "0ywy9sg7spafi3gm9q5wb59lbiq0swvf0q3iazl0maq1pj1nsb7h";
              }
            );
            cfipv6 = fileToList (
              pkgs.fetchurl {
                url = "https://www.cloudflare.com/ips-v6";
                sha256 = "1ad09hijignj6zlqvdjxv7rjj8567z357zfavv201b9vx3ikk7cy";
              }
            );
          in
          # nginx
          ''
            # Keep in sync with https://ssl-config.mozilla.org/#server=nginx&config=intermediate
            ssl_session_timeout 1d;
            ssl_session_cache shared:SSL:10m;
            # Breaks forward secrecy: https://github.com/mozilla/server-side-tls/issues/135
            ssl_session_tickets off;
            # We don't enable insecure ciphers by default, so this allows
            # clients to pick the most performant, per https://github.com/mozilla/server-side-tls/issues/260
            ssl_prefer_server_ciphers off;

            # Increase the maximum size of the hash table
            proxy_headers_hash_max_size 1024;

            # Increase the bucket size of the hash table
            proxy_headers_hash_bucket_size 128;
            ${realIpsFromList cfipv4}
            ${realIpsFromList cfipv6}
            real_ip_header CF-Connecting-IP;

            log_format json escape=json
            '{'
              '"time":"$time_iso8601",'
              '"remote_addr":"$remote_addr",'
              '"remote_user":"$remote_user",'
              '"request":"$request",'
              '"status": "$status",'
              '"body_bytes_sent":"$body_bytes_sent",'
              '"request_time":"$request_time",'
              '"http_referrer":"$http_referer",'
              '"http_user_agent":"$http_user_agent",'
              '"http_x_forwarded_for":"$http_x_forwarded_for",'
              '"http_host":"$http_host",'
              '"server_name":"$server_name",'
              '"request_uri":"$request_uri",'
              '"https":"$https",'
              '"scheme":"$scheme",'
              '"request_method":"$request_method",'
              '"request_length":"$request_length",'
              '"uri":"$uri",'
              '"request_completion":"$request_completion",'
              '"upstream":"$upstream_addr",'
              '"level":"$level"'
            '}';

            map $status $level {
              ~^[23] "info";
              default "error";
            }

            map $status $status_200_299 {
              ~^2 1;
              default 0;
            }

            map $status $status_300_399 {
              ~^3 1;
              default 0;
            }

            map $status $status_400_499 {
              ~^4 1;
              default 0;
            }

            map $status $status_500_plus {
              ~^[5-9] 1;
              default 0;
            }

            access_log /var/log/nginx/access.log json if=$status_200_299;
            access_log /var/log/nginx/access_redirect.log json if=$status_300_399;
            access_log /var/log/nginx/access_client_error.log json if=$status_400_499;
            access_log /var/log/nginx/access_server_error.log json if=$status_500_plus;
          '';
      };
      services.nginx.virtualHosts =
        let
          containers = config.virtualisation.oci-containers.containers;
          proxyReadyHttpContainers = filterAttrs (
            _: c: (c.ip != null) && (c.httpPort != null) && (!c.socketActivation.enable)
          ) containers;
          socketActivatedContainers = filterAttrs (_: c: c.socketActivation.enable) containers;
          httpHosts = mapAttrs' (
            name: value:
            (nameValuePair "${name}.podman" {
              locations."/".proxyPass = "http://${value.ip}:${toString value.httpPort}";
            })
          ) proxyReadyHttpContainers;
          socketActivatedHosts = mapAttrs' (
            name: value:
            (nameValuePair "${name}.podman" {
              locations."/".proxyPass = "http://unix:${
                config.systemd.socketActivations."podman-${name}".address
              }";
            })
          ) socketActivatedContainers;
        in
        httpHosts // socketActivatedHosts;
      services.nginx.appendHttpConfig =
        # Catch all server. Return 444 for all requests (end connection without response)
        #nginx
        ''
          server {
              listen 0.0.0.0:80 default_server;
              listen [::0]:80 default_server;
              server_name _;
              return 444;
          }
          server {
              listen 0.0.0.0:443 ssl default_server;
              listen [::0]:443 ssl default_server;
              server_name _;
              ssl_reject_handshake on; # Reject SSL connection 
              return 444;
          }
        '';
      security.acme = {
        acceptTerms = true;
        defaults.email = "tigor.hutasuhut@gmail.com";
        defaults.dnsResolver = "192.168.100.5:53";
        certs."tigor.web.id" = {
          webroot = "/var/lib/acme/acme-challenge";
          group = "nginx";
          extraDomainNames =
            let
              domains = filterAttrs (
                name: value:
                (name != "tigor.web.id") # Do not put exact domain here, otherwise let's encrypt will reject it because it already exists and cannot put in SAN.
                && (value.forceSSL || value.onlySSL)
                && (value.useACMEHost == "tigor.web.id")
                && (hasSuffix "tigor.web.id" name)
              ) config.services.nginx.virtualHosts;
            in
            attrNames domains;
        };
      };
      users.users.nginx.extraGroups = [ "acme" ];

      # Alloy configuration for nginx log scraping
      environment.etc."alloy/nginx-logs.alloy".text =
        lib.mkIf config.services.alloy.enable
          #hocon
          ''
            loki.source.file "nginx_access" {
              targets = [
                {
                  __path__ = "/var/log/nginx/access.log",
                  filename = "access.log",
                  job = "nginx",
                },
              ]
              forward_to = [loki.process.nginx.receiver]
            }

            loki.source.file "nginx_access_redirect" {
              targets = [
                {
                  __path__ = "/var/log/nginx/access_redirect.log",
                  filename = "access_redirect.log",
                  job = "nginx",
                },
              ]
              forward_to = [loki.process.nginx.receiver]
            }

            loki.source.file "nginx_access_client_error" {
              targets = [
                {
                  __path__ = "/var/log/nginx/access_client_error.log",
                  filename = "access_client_error.log",
                  job = "nginx",
                },
              ]
              forward_to = [loki.process.nginx.receiver]
            }

            loki.source.file "nginx_access_server_error" {
              targets = [
                {
                  __path__ = "/var/log/nginx/access_server_error.log",
                  filename = "access_server_error.log",
                  job = "nginx",
                },
              ]
              forward_to = [loki.process.nginx.receiver]
            }

            loki.source.file "nginx_error" {
              targets = [
                {
                  __path__ = "/var/log/nginx/error.log",
                  filename = "error.log",
                  job = "nginx",
                },
              ]
              forward_to = [loki.process.nginx.receiver]
            }

            loki.process "nginx" {
              stage.json {
                expressions = {
                  body_bytes_sent = "body_bytes_sent",
                  host = "http_host",
                  http_referrer = "http_referrer",
                  http_user_agent = "http_user_agent",
                  http_x_forwarded_for = "http_x_forwarded_for",
                  level = "level",
                  remote_addr = "remote_addr",
                  request_length = "request_length",
                  request_method = "request_method",
                  scheme = "scheme",
                  status = "status",
                  time = "time",
                  uri = "uri",
                  upstream = "upstream",
                }
              }

              stage.labels { // For low cardinality fields
                values = {
                  log_level = "level",
                }
              }

              stage.structured_metadata { // For high cardinality fields
                values = {
                  host_name = "host",
                  http_referrer = "http_referrer",
                  http_request_method = "request_method",
                  http_request_size = "request_length",
                  http_response_status_code = "status",
                  http_user_agent = "http_user_agent",
                  http_x_forwarded_for = "http_x_forwarded_for",
                  http_response_body_size = "body_bytes_sent",
                  network_peer_address = "remote_addr",
                  url_path = "uri",
                  url_scheme = "scheme",
                  user_agent_original = "http_user_agent",
                  upstream_address = "upstream",
                }
              }

              stage.timestamp {
                source = "time"
                format = "2006-01-02T15:04:05Z07:00"
              }

              forward_to = [otelcol.receiver.loki.default.receiver]
            }
          '';
      services.homepage-dashboard.groups.Networking.services.NGINX.settings = {
        description = "Reverse Proxy and TLS termination for all services";
        href = "https://tigor.web.id";
        icon = "nginx.svg";
      };
    };
}