local M = {}

local function read_json(path)
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if not ok then
    return nil
  end
  return data
end

local function write_json(path, data)
  vim.fn.writefile(vim.split(vim.json.encode(data), "\n", { plain = true }), path)
end

local function swap_dirs()
  local dirs = {}
  for _, dir in ipairs(vim.opt.directory:get()) do
    dir = vim.fn.expandcmd(dir):gsub("/+$", "") .. "/"
    if vim.fn.isdirectory(dir) == 1 then
      table.insert(dirs, dir)
    end
  end
  return dirs
end

--- Extract the recovered buffer lines for a file that has a stale swap file,
--- using nvim's own recovery in an isolated headless process.  Leaves the
--- swap file on disk untouched.
--- @param fname string
--- @return string[]|nil lines
local function recover_lines(fname)
  local cmd = {
    "nvim",
    "--headless",
    "-u",
    "NONE",
    "-n",
    "-r",
    fname,
    "-c",
    "lua print('__RECOVER_LINES__' .. vim.json.encode(vim.api.nvim_buf_get_lines(0, 0, -1, false)))",
    "-c",
    "qa!",
  }
  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local encoded = out:match("__RECOVER_LINES__(.*)")
  if not encoded then
    return nil
  end
  encoded = encoded:gsub("\r$", "")
  local ok, lines = pcall(vim.json.decode, encoded)
  if not ok or type(lines) ~= "table" then
    return nil
  end
  return lines
end

local function file_lines(fname)
  if vim.fn.filereadable(fname) ~= 1 then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, fname)
  if not ok then
    return nil
  end
  return lines
end

--- Insert or replace a buffer_text entry for a file.
local function upsert_buffer_text(buffer_text, fname, lines)
  local ft = vim.filetype.match({ filename = fname }) or ""
  for _, buf in ipairs(buffer_text) do
    if buf.name == fname then
      buf.contents = lines
      if buf.filetype == nil or buf.filetype == "" then
        buf.filetype = ft
      end
      return
    end
  end
  table.insert(buffer_text, {
    name = fname,
    filetype = ft,
    contents = lines,
  })
end

--- Recover stale swaps of session file buffers into the session's buffer_text
--- data, then delete the swap files.  Should be called before resession loads
--- the session so the recovered content is restored by the buffer_text
--- extension and no swap E325 prompt can appear.
--- @param data table Session data (as loaded from the session json file).
M.recover_session_swaps = function(data)
  local wanted = {}
  for _, buf in ipairs(data.buffers or {}) do
    local name = buf.name
    if name and name ~= "" and name ~= "null" and vim.fn.filereadable(name) == 1 then
      wanted[name] = true
    end
  end
  for _, buf in ipairs(data.buffer_text or {}) do
    if buf.name and buf.name ~= "" then
      wanted[buf.name] = true
    end
  end

  data.buffer_text = data.buffer_text or {}
  local recovered = {}

  for _, dir in ipairs(swap_dirs()) do
    for _, name in ipairs(vim.fn.readdir(dir)) do
      if name:match("%.sw.$") then
        local path = dir .. name
        local info = vim.fn.swapinfo(path)
        if not info.error and info.pid <= 0 and info.fname and wanted[info.fname] then
          if not recovered[info.fname] then
            recovered[info.fname] = true
            local lines = recover_lines(info.fname)
            if lines then
              local current = file_lines(info.fname)
              if current == nil or not vim.deep_equal(lines, current) then
                upsert_buffer_text(data.buffer_text, info.fname, lines)
              end
            end
          end
          os.remove(path)
        end
      end
    end
  end
end

--- Recover stale swaps of the "last" session into its saved session file.
--- @param session_file string
M.recover_session_file = function(session_file)
  if vim.fn.filereadable(session_file) ~= 1 then
    return
  end
  local data = read_json(session_file)
  if not data then
    return
  end
  M.recover_session_swaps(data)
  write_json(session_file, data)
end

return M
