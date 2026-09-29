local M = {}

M.on_save = function()
  local saved = {}
  local seen_unnamed = {}
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local tabnr = vim.api.nvim_tabpage_get_number(tabpage)
    local wins = vim.api.nvim_tabpage_list_wins(tabpage)
    for _, winid in ipairs(wins) do
      local bufnr = vim.api.nvim_win_get_buf(winid)
      if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
        local bo = vim.bo[bufnr]
        if bo.modified and bo.buflisted and bo.buftype == "" then
          local name = vim.api.nvim_buf_get_name(bufnr)
          if name == "" then
            -- Unnamed ([No Name]) buffers are dropped from resession's layout
            -- (buf_filter), so remember where they were so on_post_load can put
            -- them back: the tab, and whether it was the tab's only window.
            if not seen_unnamed[bufnr] then
              seen_unnamed[bufnr] = true
              table.insert(saved, {
                name = "",
                tabnr = tabnr,
                sole = #wins == 1,
                filetype = bo.filetype,
                contents = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
              })
            end
          else
            table.insert(saved, {
              name = name,
              filetype = bo.filetype,
              contents = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
            })
          end
        end
      end
    end
  end
  return saved
end

M.on_post_load = function(data)
  if not data then
    return
  end
  local by_name = {}
  local unnamed = {}
  for _, buf in ipairs(data) do
    if buf.name == "" then
      table.insert(unnamed, buf)
    else
      by_name[buf.name] = buf
    end
  end
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and not vim.bo[bufnr].modified then
      local saved = by_name[vim.api.nvim_buf_get_name(bufnr)]
      if saved then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, saved.contents)
        by_name[vim.api.nvim_buf_get_name(bufnr)] = nil
      end
    end
  end

  -- Recreate the unnamed ([No Name]) buffers and put them back in a window.
  local created = {}
  for _, buf in ipairs(unnamed) do
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.bo[bufnr].filetype = buf.filetype
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, buf.contents)
    vim.bo[bufnr].modified = true
    table.insert(created, { bufnr = bufnr, tabnr = buf.tabnr, sole = buf.sole })
  end

  if #created > 0 then
    local current_tab = vim.api.nvim_get_current_tabpage()
    local tabs = vim.api.nvim_list_tabpages()
    local function place(bufnr, tabnr, sole)
      if tabnr and tabnr >= 1 and tabnr <= #tabs then
        vim.api.nvim_set_current_tabpage(tabs[tabnr])
        local wins = vim.api.nvim_tabpage_list_wins(tabs[tabnr])
        if sole and #wins == 1 then
          -- the saved tab held only this unnamed buffer: take over the
          -- placeholder window that resession left there
          vim.api.nvim_win_set_buf(wins[1], bufnr)
          return true
        end
        -- the buffer shared its tab with other windows: open a split
        vim.cmd.split()
        vim.api.nvim_win_set_buf(0, bufnr)
        return true
      end
      return false
    end
    for _, item in ipairs(created) do
      if not place(item.bufnr, item.tabnr, item.sole) then
        -- Older session without recorded tab: reuse the current empty scratch
        -- window if there is one, otherwise open a new tab.
        local curbuf = vim.api.nvim_get_current_buf()
        if vim.api.nvim_buf_get_name(curbuf) == ""
            and not vim.bo[curbuf].modified
            and #vim.api.nvim_buf_get_lines(curbuf, 0, -1, false) == 0 then
          vim.api.nvim_win_set_buf(0, item.bufnr)
        else
          vim.cmd.tabnew()
          vim.api.nvim_win_set_buf(0, item.bufnr)
        end
      end
    end
    vim.api.nvim_set_current_tabpage(current_tab)
  end
end

return M
