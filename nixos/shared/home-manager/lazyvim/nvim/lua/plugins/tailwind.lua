return {
  "folke/noice.nvim",
  opts = {
    routes = {
      -- Shut up the No information available notifications
      {
        filter = {
          event = "notify",
          kind = "",
          find = "No information available",
        },
        opts = { skip = true },
      },
    },
  },
}
