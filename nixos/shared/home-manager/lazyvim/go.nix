{
  home.file.".golangci.yml".text = /* yaml */ ''
    linters:
      disable-all: true
      enable:
        # performance
        - prealloc
        - noctx

        # security
        - gosec
        - exportloopref

        # bugs / correctness
        - govet
        - staticcheck
        - ineffassign
        - typecheck
        - errcheck
        - bodyclose
        - sqlclosecheck
        - rowserrcheck
        - durationcheck
        - nilerr
        - nilnil

    linters-settings:
      gosec:
        excludes: []
      govet:
        enable-all: true

    issues:
      exclude-use-default: false
  '';
}
