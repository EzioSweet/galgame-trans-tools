local recursive = false
local args = {}
local force_color = nil
local IS_WINDOWS = package.config:sub(1, 1) == "\\"

for i = 1, #arg do
  if arg[i] == "--sub" then
    recursive = true
  elseif arg[i] == "--color" then
    force_color = true
  elseif arg[i] == "--no-color" then
    force_color = false
  else
    table.insert(args, arg[i])
  end
end

local from = args[1]
local to = args[2]

if not from or not to then
  io.stderr:write("Usage: luajit batch-replace.lua [--sub] [--color|--no-color] <from> <to>\n")
  os.exit(1)
end

local function escape_lua_pattern(s)
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function escape_replacement(s)
  return (s:gsub("%%", "%%%%"))
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

local escaped_from = escape_lua_pattern(from)
local escaped_to = escape_replacement(to)
local escaped_to_pattern = escape_lua_pattern(to)
local use_color
if force_color ~= nil then
  use_color = force_color
else
  use_color = os.getenv("NO_COLOR") == nil
end

local function colorize(s, code)
  if not use_color then
    return s
  end
  return string.char(27) .. "[" .. code .. "m" .. s .. string.char(27) .. "[0m"
end

local function highlight_replaced_text(line)
  if not use_color or to == "" then
    return line
  end
  return (line:gsub(escaped_to_pattern, string.char(27) .. "[31m%0" .. string.char(27) .. "[0m"))
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
  return files
end

for _, file in ipairs(list_files()) do
  local in_file = io.open(file, "rb")
  if in_file then
    local content = in_file:read("*a")
    in_file:close()

    local replaced = content:gsub(escaped_from, escaped_to)
    if replaced ~= content then
      local old_lines = split_lines(content)
      local new_lines = split_lines(replaced)

      local out_file = io.open(file, "wb")
      if out_file then
        out_file:write(replaced)
        out_file:close()
        local max_lines = #old_lines
        if #new_lines > max_lines then
          max_lines = #new_lines
        end
        for i = 1, max_lines do
          if old_lines[i] ~= new_lines[i] then
            local line_content = new_lines[i]
            if line_content == nil then
              line_content = "<deleted>"
            end
            line_content = highlight_replaced_text(line_content)
            io.write(
              colorize(file, "36")
              .. ":"
              .. colorize(tostring(i), "33")
              .. ":"
              .. line_content
              .. "\n"
            )
          end
        end
      else
        io.stderr:write("Failed to write file: " .. file .. "\n")
      end
    end
  else
    io.stderr:write("Failed to read file: " .. file .. "\n")
  end
end
