-- Quote a shell argument safely for POSIX sh.
local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Run command and capture combined stdout/stderr plus exit code.
local function run_cmd(cmd)
  local handle = io.popen(cmd .. " 2>&1; printf '\\n__EXIT:%s' $?", "r")
  if not handle then
    error("failed to spawn shell command: " .. cmd)
  end
  local output = handle:read("*a") or ""
  handle:close()
  local body, code = output:match("^(.*)\n__EXIT:(%d+)$")
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
  if not text:find(pattern, 1, false) then
    error((message or "pattern not found") .. ": " .. pattern, 2)
  end
end

-- Create an isolated temp working directory for each test case.
local function make_temp_dir()
  local out, code = run_cmd("mktemp -d")
  assert_true(code == 0, "mktemp failed: " .. out)
  local dir = out:gsub("%s+$", "")
  assert_true(dir ~= "", "mktemp returned empty directory")
  return dir
end

-- Execute the Lua CLI under test using LuaJIT.
local function run_cli(args, cwd)
  local script_path = "siglus-txt-transform.lua"
  local command = "cd " .. shell_quote(cwd) .. " && luajit " .. shell_quote(script_path)
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
  local out, code = run_cmd("cp " .. shell_quote(source) .. " " .. shell_quote(target))
  assert_true(code == 0, "copy fixture failed: " .. out)
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
  local f = assert(io.open(json_path, "wb"))
  f:write(content)
  f:close()

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
  local _, code_mkdir = run_cmd("mkdir -p " .. shell_quote(source_txt_dir) .. " " .. shell_quote(input_json_dir))
  assert_true(code_mkdir == 0, "mkdir failed")
  copy_fixture("01.ss.txt", path_join(source_txt_dir, "01.ss.txt"))
  copy_fixture("01.ss.json", path_join(input_json_dir, "01.ss.json"))

  local out, code = run_cli({ "j2t", source_txt_dir, input_json_dir, output_txt_dir }, ".")
  assert_true(code == 0, "j2t directory failed: " .. out)
  local actual = normalize_text(read_file(path_join(output_txt_dir, "01.ss.txt")))
  assert_contains(actual, "○0000000007○「フフン♪　フーン♪」", "source line missing")
  assert_contains(actual, "●0000000007●「フフン♪　フーン♪」", "translated line missing")
end

local tests = {
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
