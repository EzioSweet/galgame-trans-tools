local IS_WINDOWS = package.config:sub(1, 1) == "\\"
local query = nil
local use_color = true
local recursive = false

for i = 1, #arg do
  if arg[i] == "--no-color" then
    use_color = false
  elseif arg[i] == "--sub" then
    recursive = true
  elseif query == nil then
    query = arg[i]
  else
    io.stderr:write("Usage: luajit string-search.lua [--no-color] [--sub] <pattern>\n")
    os.exit(1)
  end
end

if not query then
  io.stderr:write("Usage: luajit string-search.lua [--no-color] [--sub] <pattern>\n")
  os.exit(1)
end

local function run_cmd(cmd)
  local wrapped
  if IS_WINDOWS then
    wrapped = 'cmd /d /c "' .. cmd:gsub('"', '""') .. ' 2>&1 & echo __EXIT:%ERRORLEVEL%"'
  else
    wrapped = cmd .. " 2>&1; printf '\\n__EXIT:%s' $?"
  end

  local handle = io.popen(wrapped, "r")
  if not handle then
    error("Failed to run command: " .. cmd)
  end
  local output = handle:read("*a") or ""
  handle:close()

  local body, code = output:match("^(.*)\r?\n__EXIT:(%-?%d+)%s*$")
  if not body then
    return output, 1
  end
  return body, tonumber(code)
end

local function normalize_slashes(path)
  return tostring(path):gsub("\\", "/")
end

local function list_files()
  local list_cmd
  if IS_WINDOWS then
    if recursive then
      list_cmd = "dir /b /s /a-d ."
    else
      list_cmd = "dir /b /a-d ."
    end
  else
    if recursive then
      list_cmd = "find . -type f -print"
    else
      list_cmd = "find . -maxdepth 1 -type f -print"
    end
  end

  local out, code = run_cmd(list_cmd)
  if code ~= 0 then
    error("Failed to list files")
  end

  local windows_cwd_prefix = nil
  if IS_WINDOWS and recursive then
    local cwd_out, cwd_code = run_cmd("cd")
    if cwd_code == 0 then
      local cwd = (cwd_out:match("([^\r\n]+)") or ""):gsub("\r$", "")
      cwd = normalize_slashes(cwd):gsub("/+$", "")
      if cwd ~= "" then
        windows_cwd_prefix = cwd:lower() .. "/"
      end
    end
  end

  local files = {}
  for line in (out .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("\r$", "")
    if line ~= "" then
      if IS_WINDOWS then
        line = normalize_slashes(line)
        if recursive and windows_cwd_prefix then
          local lower_line = line:lower()
          if lower_line:sub(1, #windows_cwd_prefix) == windows_cwd_prefix then
            line = "./" .. line:sub(#windows_cwd_prefix + 1)
          end
        elseif not recursive then
          line = "./" .. line
        end
      end
      table.insert(files, line)
    end
  end
  table.sort(files)
  return files
end

local function glob_to_lua_pattern(glob)
  local magic = {
    ["^"] = true, ["$"] = true, ["("] = true, [")"] = true,
    ["%"] = true, ["."] = true, ["["] = true, ["]"] = true,
    ["+"] = true, ["-"] = true
  }
  local out = {}
  for i = 1, #glob do
    local ch = glob:sub(i, i)
    if ch == "*" then
      table.insert(out, ".*")
    elseif ch == "?" then
      table.insert(out, ".")
    elseif magic[ch] then
      table.insert(out, "%" .. ch)
    else
      table.insert(out, ch)
    end
  end
  return table.concat(out)
end

local lua_pattern = glob_to_lua_pattern(query)

local function colorize(s, code)
  if not use_color then
    return s
  end
  return string.char(27) .. "[" .. code .. "m" .. s .. string.char(27) .. "[0m"
end

local function split_lines(s)
  local lines = {}
  local start = 1
  while true do
    local pos = s:find("\n", start, true)
    if not pos then
      table.insert(lines, s:sub(start))
      break
    end
    table.insert(lines, s:sub(start, pos - 1))
    start = pos + 1
  end
  return lines
end

local function highlight_match(line)
  if not use_color then
    return line
  end
  return (line:gsub(lua_pattern, string.char(27) .. "[31m%0" .. string.char(27) .. "[0m"))
end

for _, file in ipairs(list_files()) do
  local f = io.open(file, "rb")
  if f then
    local content = f:read("*a") or ""
    f:close()
    local lines = split_lines(content)
    for i = 1, #lines do
      local line = lines[i]:gsub("\r$", "")
      if line:find(lua_pattern) then
        io.write(
          colorize(file, "36")
          .. ":"
          .. colorize(tostring(i), "33")
          .. ":"
          .. highlight_match(line)
          .. "\n"
        )
      end
    end
  else
    io.stderr:write("Failed to read file: " .. file .. "\n")
  end
end
