return {
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
}
