{
  programs.go = {
    enable = true;
    env.GOPRIVATE = [ "github.com/Grand-Board/*" ];
  };
}
