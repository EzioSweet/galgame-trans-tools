#!/usr/bin/env luajit

local script_path = (arg and arg[0]) or ""
if script_path ~= "" then
  local script_dir = script_path:gsub("\\", "/"):match("^(.*)/[^/]*$") or "."
  package.path = script_dir .. "/?.lua;" .. script_dir .. "/?/init.lua;" .. package.path
end

local json = require("libs.dkjson")

local function usage()
  io.stderr:write("Usage:\n")
  io.stderr:write("  lua[|luajit] siglus-txt-transform.lua t2j <txt|txt-dir> [out-json|out-dir]\n")
  io.stderr:write("  lua[|luajit] siglus-txt-transform.lua j2t <txt|txt-dir> <json|json-dir> [out-txt|out-dir] [--space]\n")
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run_cmd(cmd)
  local handle = io.popen(cmd .. " 2>&1; printf '\\n__EXIT:%s' $?", "r")
  if not handle then
    error("Failed to run command: " .. cmd)
  end
  local output = handle:read("*a") or ""
  handle:close()

  local body, code = output:match("^(.*)\n__EXIT:(%d+)$")
  if not body then
    return output, 1
  end
  return body, tonumber(code)
end

local function get_cwd()
  local out, code = run_cmd("pwd")
  if code ~= 0 then
    error("Failed to get current directory.")
  end
  return out:gsub("%s+$", "")
end

local function join_path(a, b)
  if a:sub(-1) == "/" then
    return a .. b
  end
  return a .. "/" .. b
end

local function dirname(path)
  local normalized = path:gsub("\\", "/")
  local dir = normalized:match("^(.*)/[^/]*$") or "."
  if dir == "" then
    return "/"
  end
  return dir
end

local function basename(path)
  local normalized = path:gsub("\\", "/")
  return normalized:match("([^/]+)$") or normalized
end

local function extname(path)
  local name = basename(path)
  return name:match("(%.[^%.]+)$") or ""
end

local function stem(name, suffix)
  if name:sub(-#suffix) == suffix then
    return name:sub(1, #name - #suffix)
  end
  return name
end

local function is_directory(path)
  local _, code = run_cmd("test -d " .. shell_quote(path))
  return code == 0
end

local function ensure_dir(path)
  local out, code = run_cmd("mkdir -p " .. shell_quote(path))
  if code ~= 0 then
    error("Failed to create directory: " .. out)
  end
end

local function list_files_by_ext(dir_path, extension)
  local out, code = run_cmd("ls -1 " .. shell_quote(dir_path))
  if code ~= 0 then
    error("Failed to list directory: " .. dir_path)
  end

  local lower_ext = extension:lower()
  local files = {}
  for line in (out .. "\n"):gmatch("(.-)\n") do
    if line ~= "" and extname(line):lower() == lower_ext then
      table.insert(files, line)
    end
  end
  table.sort(files)
  return files
end

local function read_text(path)
  local file, err = io.open(path, "rb")
  if not file then
    error("Failed to read file: " .. path .. " (" .. tostring(err) .. ")")
  end
  local content = file:read("*a")
  file:close()
  return content or ""
end

local function write_text(path, content)
  local file, err = io.open(path, "wb")
  if not file then
    error("Failed to write file: " .. path .. " (" .. tostring(err) .. ")")
  end
  file:write(content)
  file:close()
end

local function parse_txt_entries(txt_content)
  local normalized = txt_content:gsub("\r\n", "\n"):gsub("\r", "\n")
  local entries = {}

  for line in (normalized .. "\n"):gmatch("(.-)\n") do
    local id, message = line:match("^○(%d+)○(.*)$")
    if id then
      table.insert(entries, { id = id, message = message })
    end
  end

  return entries
end

local function txt_to_json_content(txt_content)
  local entries = parse_txt_entries(txt_content)
  if #entries == 0 then
    return "[]\n"
  end

  local lines = { "[" }
  for i = 1, #entries do
    table.insert(lines, "    {")
    table.insert(lines, '        "message": ' .. json.quotestring(entries[i].message))
    if i < #entries then
      table.insert(lines, "    },")
    else
      table.insert(lines, "    }")
    end
  end
  table.insert(lines, "]")
  return table.concat(lines, "\n") .. "\n"
end

local function utf8_chars(text)
  local chars = {}
  for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    table.insert(chars, ch)
  end
  return chars
end

local function add_spaces_between_chars(text)
  local chars = utf8_chars(text)
  if #chars <= 1 then
    return text
  end
  return table.concat(chars, " ")
end

local function json_to_txt_content(source_txt_content, json_content, options)
  options = options or {}
  local source_entries = parse_txt_entries(source_txt_content)
  local json_entries, _, decode_err = json.decode(json_content, 1, nil)
  if decode_err then
    error(decode_err)
  end

  if type(json_entries) ~= "table" then
    error("JSON content must be an array.")
  end

  if #source_entries ~= #json_entries then
    error(string.format("Entry count mismatch: source=%d, json=%d", #source_entries, #json_entries))
  end

  local lines = {}
  for i = 1, #source_entries do
    local source = source_entries[i]
    local translated = json_entries[i]

    if type(translated) ~= "table" or type(translated.message) ~= "string" then
      error(string.format('Invalid JSON entry at index %d: missing string field "message".', i - 1))
    end

    local translated_message = translated.message
    if options.space then
      translated_message = add_spaces_between_chars(translated_message)
    end

    table.insert(lines, "○" .. source.id .. "○" .. source.message)
    table.insert(lines, "●" .. source.id .. "●" .. translated_message)
    table.insert(lines, "")
  end

  return table.concat(lines, "\n") .. "\n"
end

local function to_json_file_name(txt_file_name)
  return stem(basename(txt_file_name), ".txt") .. ".json"
end

local function to_txt_file_name(json_file_name)
  return stem(basename(json_file_name), ".json") .. ".txt"
end

local function to_default_j2t_file_name(txt_path)
  return stem(basename(txt_path), ".txt") .. ".out.txt"
end

local function run_t2j(input_path_arg, output_path_arg)
  local input_is_dir = is_directory(input_path_arg)
  if input_is_dir then
    if not output_path_arg then
      error("Output directory is required when input is a directory.")
    end
    ensure_dir(output_path_arg)
    local txt_files = list_files_by_ext(input_path_arg, ".txt")
    for i = 1, #txt_files do
      local file_name = txt_files[i]
      local in_file = join_path(input_path_arg, file_name)
      local out_file = join_path(output_path_arg, to_json_file_name(file_name))
      local txt = read_text(in_file)
      write_text(out_file, txt_to_json_content(txt))
    end
    return
  end

  local out_file = output_path_arg
  if not out_file then
    out_file = join_path(get_cwd(), to_json_file_name(basename(input_path_arg)))
  end

  ensure_dir(dirname(out_file))
  write_text(out_file, txt_to_json_content(read_text(input_path_arg)))
end

local function run_j2t(source_path_arg, json_path_arg, output_path_arg, options)
  local source_is_dir = is_directory(source_path_arg)
  local json_is_dir = is_directory(json_path_arg)

  if source_is_dir ~= json_is_dir then
    error("For j2t, source txt and json input must both be files or both be directories.")
  end

  if source_is_dir then
    if not output_path_arg then
      error("Output directory is required when inputs are directories.")
    end
    ensure_dir(output_path_arg)
    local json_files = list_files_by_ext(json_path_arg, ".json")
    for i = 1, #json_files do
      local json_file = json_files[i]
      local base_txt_name = to_txt_file_name(json_file)
      local source_txt_file = join_path(source_path_arg, base_txt_name)
      local in_json_file = join_path(json_path_arg, json_file)
      local out_txt_file = join_path(output_path_arg, base_txt_name)
      write_text(
        out_txt_file,
        json_to_txt_content(read_text(source_txt_file), read_text(in_json_file), options)
      )
    end
    return
  end

  local out_file = output_path_arg
  if not out_file then
    out_file = join_path(dirname(source_path_arg), to_default_j2t_file_name(source_path_arg))
  end

  ensure_dir(dirname(out_file))
  write_text(out_file, json_to_txt_content(read_text(source_path_arg), read_text(json_path_arg), options))
end

local function main()
  local mode = arg[1]
  local args = {}
  for i = 2, #arg do
    table.insert(args, arg[i])
  end

  if mode == "t2j" then
    if #args < 1 or #args > 2 then
      usage()
      os.exit(1)
    end
    run_t2j(args[1], args[2])
    return
  end

  if mode == "j2t" then
    local space = false
    local positional = {}
    for i = 1, #args do
      if args[i] == "--space" then
        space = true
      else
        table.insert(positional, args[i])
      end
    end

    if #positional < 2 or #positional > 3 then
      usage()
      os.exit(1)
    end

    run_j2t(positional[1], positional[2], positional[3], { space = space })
    return
  end

  usage()
  os.exit(1)
end

local ok, err = pcall(main)
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end
