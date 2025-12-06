{ lib, pkgs, ... }:
{
  services.flexget.settings =
    let
      script = pkgs.writers.writeJS "rss-feeder" { } ''
        const filters = ["ASMR", "KU-100", "KU100"]
        const title = process.argv[2]
        const url = process.argv[3]
        const folder = process.argv[4]
        let hasMatch = false
        for (const filter of filters) {
          if (title.includes(filter)) {
            hasMatch = true
            break
          }
        }
        if (!hasMatch) {
          console.error("Skipping non-matching title:", title)
          process.exit(0)
        }
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
        kimitsutenka = {
          channel_id = "UCZkZnbVO2bECxwcGlE9YOGg";
          folder = "asmr";
        };
        OtonashiKurumiArchives1 = {
          channel_id = "UCC3w1p4O70J6kQ_H76X35bA";
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
            exec.on_output.for_entries = ''${script} "{{title}}" "{{url}}" "${value.folder}"'';
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
