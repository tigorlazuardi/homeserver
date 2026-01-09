{
  programs.go = {
    enable = true;
    env.GOPRIVATE = [ "github.com/Grand-Board/*" ];
  };
  programs.git.extraConfig = {
    url."git@github.com:Grand-Board/" = {
      insteadOf = "https://github.com/Grand-Board/";
    };
  };
}
