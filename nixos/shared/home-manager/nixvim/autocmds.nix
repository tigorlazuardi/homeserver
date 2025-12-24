{
  programs.nixvim.autoGroups = {
    CheckTime = { };
    ResizeSplits = { };
    LastLoc = { };
    CloseWithQ = { };
    ManUnlisted = { };
    WrapText = { };
    AutoCreateDir = { };
    WindowTitle = { };
  };
  programs.nixvim.autoCmd = [
    {
      event = [
        "FocusGained"
        "TermClose"
        "TermLeave"
      ];
      callback.__raw = ''
        function()
            if vim.o.buftype ~= "nofile" then
              vim.cmd("checktime")
            end
        end
      '';
      group = "CheckTime";
      desc = "Check if we need to reload the file when it changed";
    }
    {
      event = [
        "BufEnter"
        "BufReadPost"
      ];
      group = "WindowTitle";
      callback.__raw = ''
        function()
          if vim.o.buftype ~= "nofile" then
            vim.opt.titlestring = ([[%s - %s]]):format(_M.platform or "nvim",vim.fn.expand("%:p"))
          end
        end
      '';
      desc = "Set window title to current file";
    }
    {
      event = [ "VimResized" ];
      callback.__raw = ''
        function()
          local current_tab = vim.fn.tabpagenr()
          vim.cmd "tabdo wincmd ="
          vim.cmd("tabnext " .. current_tab)
        end
      '';
      group = "ResizeSplits";
      desc = "resize splits if window got resized";
    }
    {
      event = [ "BufReadPost" ];
      callback.__raw = ''
        function(event)
            local exclude = { "gitcommit" }
            local buf = event.buf
            if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].lazyvim_last_loc then
              return
            end
            vim.b[buf].lazyvim_last_loc = true
            local mark = vim.api.nvim_buf_get_mark(buf, '"')
            local lcount = vim.api.nvim_buf_line_count(buf)
            if mark[1] > 0 and mark[1] <= lcount then
              pcall(vim.api.nvim_win_set_cursor, 0, mark)
            end
        end
      '';
      group = "LastLoc";
      desc = "go to last loc when opening a buffer";
    }
    {
      event = [ "FileType" ];
      pattern = [
        "PlenaryTestPopup"
        "checkhealth"
        "dbout"
        "gitsigns-blame"
        "grug-far"
        "help"
        "lspinfo"
        "neotest-output"
        "neotest-output-panel"
        "neotest-summary"
        "notify"
        "qf"
        "spectre_panel"
        "startuptime"
        "tsplayground"
      ];
      callback.__raw = ''
        function(event)
            vim.bo[event.buf].buflisted = false
            vim.schedule(function()
              vim.keymap.set("n", "q", function()
                vim.cmd("close")
                pcall(vim.api.nvim_buf_delete, event.buf, { force = true })
              end, {
                buffer = event.buf,
                silent = true,
                desc = "Quit buffer",
              })
            end)
        end
      '';
      group = "CloseWithQ";
      desc = "close buffer with certain filetypes with q";
    }
    {
      event = [ "FileType" ];
      pattern = [ "man" ];
      callback.__raw = ''
        function(event)
            vim.bo[event.buf].buflisted = false
        end
      '';
      group = "ManUnlisted";
      desc = "make it easier to close man-files when opened inline";
    }
    {
      event = [ "FileType" ];
      pattern = [
        "text"
        "plaintex"
        "typst"
        "gitcommit"
        "markdown"
      ];
      callback.__raw = ''
        function()
            vim.opt_local.wrap = true
        end
      '';
      group = "WrapText";
      desc = "enable wrap for text files";
    }
    {
      event = [ "BufWritePre" ];
      callback.__raw = ''
        function(event)
            if event.match:match("^%w%w+:[\\/][\\/]") then
              return
            end
            local file = vim.uv.fs_realpath(event.match) or event.match
            vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
        end
      '';
      group = "AutoCreateDir";
      desc = "Auto create dir when saving a file, in case some intermediate directory does not exist";
    }
  ];
}
