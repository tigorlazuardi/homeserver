{
  # ACME certificate for planet-melon.com
  security.acme.certs."planetmelon.space" = {
    webroot = "/var/lib/acme/acme-challenge";
    group = "nginx";
  };
}
