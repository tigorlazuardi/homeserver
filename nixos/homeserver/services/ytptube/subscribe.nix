{ lib, pkgs, ... }:
{
  services.flexget.settings =
    let
      script = pkgs.writers.writeJS "rss-feeder" { } ''
        const url, folder = process.argv[2], process.argv[3]
        fetch("http://ytptube.podman/api/history", {
          method: "POST",
          body: JSON.stringify({
            url,
            folder,
            "cli": `--ignore-no-formats --match-filter "!is_live & live_status!=is_upcoming & availability=public"`,
          })
        })
          .then(async (res) => {
            if (res.status === 200) {
              console.error("Response ok from ytptube to accept", url)
              return
            }
            const text = await response.text()
            console.error(text)
            process.exit(1)
          })
          .catch((err) => {
            console.error(err)
            process.exit(1)
          })
      '';
      channels = {
        amuamu = {
          channel_id = "UCsDM-f9vIZ33P8yopY_tGpw";
          folder = "asmr";
        };
        Arloriza = {
          channel_id = "UCo1NRG1UDiCBx_20FanA5bw";
          folder = "asmr";
        };
      };
      tasks =
        with lib;
        mapAttrs' (
          name: value:
          nameValuePair ("ytptube-" + name) {
            rss = "https://www.youtube.com/feeds/videos.xml?channel_id=${value.channel_id}";
            accept_all = true;
            exec.on_output.for_entries = ''${script} "{{url}}" "${value.folder}"'';
          }
        ) channels;
    in
    {
      inherit tasks;
      schedules = [
        {
          tasks = "ytptube-*";
          interval.hours = 1;
        }
      ];
    };
}
