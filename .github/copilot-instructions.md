# Project Guidelines

## Workspace State
- The `EasyAuth` workspace is currently a minimal scaffold with no source files, docs, or detected git metadata.
- Do not assume a language, framework, build system, or deployment target until project files are added.

## Build and Test
- Before proposing or running build, test, or package commands, inspect the workspace for the actual toolchain.
- Do not invent setup steps, scripts, or environment variables when the repository does not define them.

## Conventions
- Keep changes minimal and aligned to files that already exist.
- When scaffolding new code, prefer small, well-named files and avoid introducing extra frameworks or dependencies without a clear need.
- Add project documentation only when it reflects code or configuration that exists in the workspace.

## Collaboration
- If the repo is still empty for a requested task, first establish the target stack and entry points from the user request or newly added project files.
- Once the project gains source code or docs, update this file to capture real build commands, architecture boundaries, and repo-specific patterns.