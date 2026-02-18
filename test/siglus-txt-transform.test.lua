local IS_WINDOWS = package.config:sub(1, 1) == "\\"

-- Quote a shell argument safely for the active shell.
local function shell_quote(value)
  local str = tostring(value)
  if IS_WINDOWS then
    return '"' .. str:gsub('"', '""') .. '"'
  end
  return "'" .. str:gsub("'", "'\\''") .. "'"
end

-- Run command and capture combined stdout/stderr plus exit code.
local function run_cmd(cmd)
  local wrapped
  if IS_WINDOWS then
    wrapped = 'cmd /d /c "' .. cmd:gsub('"', '""') .. ' 2>&1 & echo __EXIT:%ERRORLEVEL%"'
  else
    wrapped = cmd .. " 2>&1; printf '\\n__EXIT:%s' $?"
  end
  local handle = io.popen(wrapped, "r")
  if not handle then
    error("failed to spawn shell command: " .. cmd)
  end
  local output = handle:read("*a") or ""
  handle:close()
  local body, code = output:match("^(.*)\r?\n__EXIT:(%-?%d+)%s*$")
  if not body then
    return output, 1
  end
  return body, tonumber(code)
end

local function read_file(path)
  local file, err = io.open(path, "rb")
  if not file then
    error("failed to open file: " .. path .. " (" .. tostring(err) .. ")")
  end
  local content = file:read("*a")
  file:close()
  return content or ""
end

local function normalize_text(value)
  value = value:gsub("\r\n", "\n")
  value = value:gsub("\r", "\n")
  return value:gsub("%s+$", "")
end

local function assert_true(condition, message)
  if not condition then
    error(message, 2)
  end
end

local function assert_contains(text, pattern, message)
  if not text:find(pattern, 1, true) then
    error((message or "pattern not found") .. ": " .. pattern, 2)
  end
end

local function assert_not_contains(text, pattern, message)
  if text:find(pattern, 1, true) then
    error((message or "unexpected pattern found") .. ": " .. pattern, 2)
  end
end

local function normalize_path(path)
  local normalized = tostring(path):gsub("\\", "/")
  if #normalized > 1 then
    normalized = normalized:gsub("/+$", "")
    if normalized:match("^%a:$") then
      normalized = normalized .. "/"
    end
  end
  return normalized
end

local function is_directory(path)
  local _, code = run_cmd("cd " .. shell_quote(normalize_path(path)))
  return code == 0
end

local function make_dir_once(path)
  local out, code = run_cmd("mkdir " .. shell_quote(path))
  if code ~= 0 and not is_directory(path) then
    error("mkdir failed: " .. out)
  end
end

local function ensure_dir(path)
  local normalized = normalize_path(path)
  if normalized == "" or normalized == "." then
    return
  end

  local root = ""
  local rest = normalized
  if rest:match("^%a:/") then
    root = rest:sub(1, 3)
    rest = rest:sub(4)
  elseif rest:sub(1, 1) == "/" then
    root = "/"
    rest = rest:sub(2)
  end

  local current = root
  for part in rest:gmatch("[^/]+") do
    if current == "" then
      current = part
    elseif current:sub(-1) == "/" then
      current = current .. part
    else
      current = current .. "/" .. part
    end

    if not is_directory(current) then
      make_dir_once(current)
    end
  end
end

local function write_file(path, content)
  local file, err = io.open(path, "wb")
  if not file then
    error("failed to write file: " .. path .. " (" .. tostring(err) .. ")")
  end
  file:write(content)
  file:close()
end

-- Create an isolated temp working directory for each test case.
local function make_temp_dir()
  local seed = tostring(math.random(100000, 999999))
  local base = os.tmpname():gsub("\\", "/")
  local dir = base .. ".dir." .. seed
  if IS_WINDOWS and dir:sub(1, 1) == "\\" then
    local drive = os.getenv("TEMP") or os.getenv("TMP")
    if drive and drive:match("^%a:") then
      dir = drive:gsub("\\", "/") .. dir
    end
  end
  ensure_dir(dir)
  assert_true(is_directory(dir), "temp dir creation failed: " .. dir)
  return dir
end

-- Execute the Lua CLI under test using LuaJIT.
local function run_cli(args, cwd)
  local script_path = "siglus-txt-transform.lua"
  local cd_cmd = IS_WINDOWS and ("cd /d " .. shell_quote(cwd)) or ("cd " .. shell_quote(cwd))
  local command = cd_cmd .. " && luajit " .. shell_quote(script_path)
  for _, arg in ipairs(args) do
    command = command .. " " .. shell_quote(arg)
  end
  return run_cmd(command)
end

local function path_join(a, b)
  return a .. "/" .. b
end

local fixture_dir = "example/siglus-txt-transform"

local function copy_fixture(name, target)
  local source = path_join(fixture_dir, name)
  write_file(target, read_file(source))
end

-- Verify single-file t2j conversion matches fixture JSON exactly.
local function test_t2j_file()
  local work_dir = make_temp_dir()
  local txt_path = path_join(work_dir, "01.ss.txt")
  local out_json_path = path_join(work_dir, "01.ss.json")
  copy_fixture("01.ss.txt", txt_path)

  local out, code = run_cli({ "t2j", txt_path, out_json_path }, ".")
  assert_true(code == 0, "t2j file failed: " .. out)

  local actual = normalize_text(read_file(out_json_path))
  local expected = normalize_text(read_file(path_join(fixture_dir, "01.ss.json")))
  assert_true(actual == expected, "t2j output mismatch")
end

-- Verify --space inserts spaces between UTF-8 characters in translated text.
local function test_j2t_file_with_space()
  local work_dir = make_temp_dir()
  local txt_path = path_join(work_dir, "01.ss.txt")
  local json_path = path_join(work_dir, "01.ss.json")
  local out_txt_path = path_join(work_dir, "01.space.txt")
  copy_fixture("01.ss.txt", txt_path)
  copy_fixture("01.ss.json", json_path)

  local content = read_file(json_path)
  content = content:gsub("エルフの娘", "天空", 1)
  write_file(json_path, content)

  local out, code = run_cli({ "j2t", txt_path, json_path, out_txt_path, "--space" }, ".")
  assert_true(code == 0, "j2t --space failed: " .. out)

  local actual = normalize_text(read_file(out_txt_path))
  assert_contains(actual, "●0000000006●天 空", "space insertion mismatch")
end

-- Verify directory-mode j2t resolves source txt files by matching basename.
local function test_j2t_directory()
  local work_dir = make_temp_dir()
  local source_txt_dir = path_join(work_dir, "txt-source")
  local input_json_dir = path_join(work_dir, "json-input")
  local output_txt_dir = path_join(work_dir, "txt-output")
  ensure_dir(source_txt_dir)
  ensure_dir(input_json_dir)
  copy_fixture("01.ss.txt", path_join(source_txt_dir, "01.ss.txt"))
  copy_fixture("01.ss.json", path_join(input_json_dir, "01.ss.json"))

  local out, code = run_cli({ "j2t", source_txt_dir, input_json_dir, output_txt_dir }, ".")
  assert_true(code == 0, "j2t directory failed: " .. out)
  local actual = normalize_text(read_file(path_join(output_txt_dir, "01.ss.txt")))
  assert_contains(actual, "○0000000007○「フフン♪　フーン♪」", "source line missing")
  assert_contains(actual, "●0000000007●「フフン♪　フーン♪」", "translated line missing")
end

-- Verify CLI rejects non-UTF-8 input so outputs are always UTF-8.
local function test_rejects_non_utf8_input()
  local work_dir = make_temp_dir()
  local bad_txt_path = path_join(work_dir, "bad.txt")
  local out_json_path = path_join(work_dir, "bad.json")
  write_file(bad_txt_path, string.char(0xFF, 0xFE, 0xFA))

  local out, code = run_cli({ "t2j", bad_txt_path, out_json_path }, ".")
  assert_true(code ~= 0, "t2j should fail for non-utf8 input")
  assert_contains(out, "must be UTF-8", "missing utf8 validation error")
end

-- Verify no Linux-only shell commands are hardcoded in the CLI.
local function test_no_linux_only_commands_in_cli()
  local content = read_file("siglus-txt-transform.lua")
  assert_not_contains(content, "run_cmd(\"pwd\")", "should not call pwd")
  assert_not_contains(content, "test -d ", "should not call test -d")
  assert_not_contains(content, "mkdir -p ", "should not call mkdir -p")
  assert_not_contains(content, "ls -1 ", "should not call ls -1")
end

local tests = {
  { name = "no linux-only commands in cli", fn = test_no_linux_only_commands_in_cli },
  { name = "rejects non-utf8 input", fn = test_rejects_non_utf8_input },
  { name = "t2j file", fn = test_t2j_file },
  { name = "j2t file with --space", fn = test_j2t_file_with_space },
  { name = "j2t directory", fn = test_j2t_directory },
}

local passed = 0
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if ok then
    io.stdout:write("[PASS] " .. t.name .. "\n")
    passed = passed + 1
  else
    io.stderr:write("[FAIL] " .. t.name .. ": " .. tostring(err) .. "\n")
  end
end

if passed ~= #tests then
  error(string.format("tests failed: %d/%d passed", passed, #tests))
end

io.stdout:write(string.format("All %d tests passed.\n", passed))
