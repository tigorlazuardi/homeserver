{
  programs.go = {
    enable = true;
    env.GOPRIVATE = [ "gitlab.ai.bareksa.dev/*" ];
  };
}
