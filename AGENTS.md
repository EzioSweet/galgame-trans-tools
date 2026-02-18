# Repository Guidelines

## Project Structure & Module Organization
- Root scripts are the main tools.
- Shared Lua dependency is under `libs/`.
- Tests live in `test/`.
- User-facing docs are in `docs/`, with runnable samples in `example/`.
- Windows users can run the bundled runtime at `bin/luajit.exe`.

## Platform Compatibility
- All scripts are designed to run on Lua 5.1+ and LuaJIT.
- Code must can be run on Windows

## Coding Style & Naming Conventions
- Target Lua 5.1 compatibility (works with `lua`/`luajit`).
- Use 2-space indentation and keep functions small and procedural.
- Prefer descriptive `local` function names (`run_cmd`, `list_files`, `normalize_slashes`).
- Script filenames use kebab-case and CLI-focused names (for example, `string-search.lua`).
- Keep cross-platform behavior explicit; avoid Linux-only shell assumptions in CLI code.

## Testing Guidelines
- Add/extend tests in `test/*.test.lua` for behavior changes.
- Follow existing pattern: isolated temp workspace, run CLI, assert output/files.
- Cover Windows-sensitive paths and command behavior when touching filesystem logic.
- For new scripts, add at least happy-path and edge-case checks (wildcards, recursion flags, encoding/error paths).

## Commit & Pull Request Guidelines
- Use Angular commit message format
- Keep each commit focused on one logical change.
- PRs should include:
  - What changed and why
  - Exact commands run for verification
  - Before/after CLI output samples for UX/output-format changes
  - Platform notes if behavior differs on Windows vs Unix

