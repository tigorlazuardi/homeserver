local home = os.getenv("HOME")

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        gopls = {
          settings = {
            gopls = {
              usePlaceholders = false,
              hints = {
                assignVariableTypes = false,
                compositeLiteralFields = false,
                compositeLiteralTypes = false,
                constantValues = false,
                functionTypeParameters = false,
                parameterNames = false,
                rangeVariableTypes = false,
              },
            },
          },
        },
      },
    },
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        golangcilint = {
          args = {
            "run",
            "--config",
            home .. "/.golangci.yml",
            "--out-format",
            "json",
            "--issues-exit-code=1",
          },
        },
      },
    },
  },
}
