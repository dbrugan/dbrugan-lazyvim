return {
  {
    "stevearc/resession.nvim",
    config = function()
      local resession = require("resession")

      -- resession's built-in autosave is replaced below (see the save-on-change
      -- timer and the guarded VimLeavePre): its own VimLeavePre save would
      -- overwrite the session during a forced/terminal-close exit, when nvim
      -- has already unloaded the buffers (content unreachable).
      resession.setup({
        autosave = { enabled = false },
        extensions = {
          buffer_text = {},
        },
      })

      local aug = vim.api.nvim_create_augroup("resession_swap", { clear = true })

      -- Keep the session current while editing.  A crash or force-close never
      -- runs the exit sequence, so the [No Name] content (which has no swap
      -- file at all) would otherwise be lost.  Save a moment after the last
      -- keystroke, plus a slow timer as a safety net for idle changes.
      local session_active = false
      local save_timer = assert(vim.uv.new_timer())
      local function schedule_session_save()
        if not session_active then
          return
        end
        save_timer:start(1500, 0, vim.schedule_wrap(function()
          pcall(resession.save, "last", { notify = false })
        end))
      end
      vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
        group = aug,
        callback = schedule_session_save,
      })
      local idle_timer = assert(vim.uv.new_timer())
      local function start_idle_save()
        idle_timer:start(60 * 1000, 60 * 1000, vim.schedule_wrap(function()
          if session_active then
            pcall(resession.save, "last", { notify = false })
          end
        end))
      end

      vim.api.nvim_create_autocmd("SwapExists", {
        group = aug,
        callback = function()
          local info = vim.fn.swapinfo(vim.v.swapname)
          local user = vim.uv.os_get_passwd().username
          if info.error or info.pid <= 0 or info.user ~= user then
            vim.v.swapchoice = "r" -- stale swap: auto-recover
          else
            vim.v.swapchoice = "e" -- live instance: edit anyway
          end
        end,
      })

      local function prune_stale_swaps()
        for _, dir in ipairs(vim.opt.directory:get()) do
          dir = vim.fn.expandcmd(dir):gsub("/+$", "") .. "/"
          if vim.fn.isdirectory(dir) == 1 then
            local groups = {}
            for _, name in ipairs(vim.fn.readdir(dir)) do
              if name:match("%.sw.$") then
                local path = dir .. name
                local info = vim.fn.swapinfo(path)
                if not info.error and info.pid <= 0 then
                  local orig = info.fname or ""
                  groups[orig] = groups[orig] or {}
                  table.insert(groups[orig], { path = path, name = name, mtime = info.mtime or 0 })
                end
              end
            end
            for _, list in pairs(groups) do
              if #list > 1 then
                local keep
                for _, item in ipairs(list) do
                  if item.name:match("%.swp$") then
                    keep = item
                    break
                  end
                end
                if not keep then
                  table.sort(list, function(a, b)
                    return a.mtime > b.mtime
                  end)
                  keep = list[1]
                end
                for _, item in ipairs(list) do
                  if item ~= keep then
                    os.remove(item.path)
                  end
                end
              end
            end
          end
        end
      end

      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
          prune_stale_swaps()
          if vim.fn.argc() > 0 then
            return
          end
          session_active = true
          start_idle_save()
          local swap_recover = require("resession.swap_recover")
          swap_recover.recover_session_file(vim.fn.stdpath("data") .. "/session/last.json")
          -- LazyVim sets 'confirm', which turns resession's buffer juggling on
          -- a restored (modified) buffer into a "Save changes?" dialog and can
          -- silently discard the restored unsaved content.  Suppress it while
          -- the session is being loaded so the files just open as modified.
          local confirm = vim.o.confirm
          vim.o.confirm = false
          local ok = pcall(resession.load, "last", { silence_errors = true })
          vim.o.confirm = confirm
          if not ok then
            vim.notify("[resession] failed to load session", vim.log.levels.ERROR)
          end
        end,
      })

      vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
          -- On a forced exit (SIGTERM/SIGHUP/kill, vim.v.exiting > 0) nvim has
          -- already unloaded the buffers before this fires, so a save here would
          -- silently drop the [No Name] content we saved while editing.  Skip it
          -- and keep the last save-on-change snapshot on disk.
          if vim.v.exiting ~= vim.NIL and vim.v.exiting > 0 then
            return
          end
          resession.save("last", { notify = false })
        end,
      })
    end,
  },
}
