# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`creel` is a single, dependency-free Python 3 script (stdlib only, no extension, `#!/usr/bin/env python3` shebang) that runs Claude Code inside a per-project Docker sandbox. There is no package, no build step, no test framework — the deliverable is the `creel` file itself, documented by `README.md`.

Install is just `install -m755 creel ~/.local/bin/creel`.

## Commands

```sh
CREEL_DRY_RUN=1 ./creel --rust --cpp   # print the docker build/run commands without executing — main dev loop
./creel --print-dockerfile              # render the resolved Dockerfile to stdout, no build
./creel --rust --gcc --test             # build, then run each selected toolchain's smoke test (exits non-zero on failure)
./creel --regen                         # overwrite a hand-edited .creel/Dockerfile with the template
python3 -c 'import ast,sys; ast.parse(open("creel").read())'   # syntax check without docker
```

`--test` is the only test facility; there is no unit-test suite. To exercise a single toolchain, select only that flag: `./creel --lean --test`.

Note that `--test`, `--rebuild`, and any non-dry run require a working Docker daemon and will pull/build multi-GB images for the heavy toolchains (`latex`, `sage`, `isabelle`, `tamarin`, `cuda`).

## Architecture

The whole design is *one metadata table renders one Dockerfile*. Adding a capability means adding a table row, never editing a Dockerfile.

- **`Toolchain` dataclass + `TOOLCHAINS` list** — the single source of truth. Each entry declares its `apt` packages, `npm` globals, `root_run`/`user_run` Dockerfile blocks, `path`/`env` additions, `gpu` flag, and smoke `test`. Everything downstream is derived from this: the `--<name>` CLI flags and their help grouping (`build_parser`), the rendered image (`render_dockerfile`), the `--gpus` decision, and the test table (`run_tests`).
- **Install fragments** (`RUST_RUN`, `CUDA_RUN`, `ISABELLE_RUN`, …) are raw strings holding *complete* `RUN` instructions, so shell tokens (`$HOME`, `${ver}`, `$(...)`) reach the Dockerfile verbatim. Keep new ones raw.
- **`render_dockerfile`** sorts the selection by the table's canonical order (not flag order) so Docker's layer cache survives adding a toolchain — only layers at and after the new entry invalidate. It batches all apt packages into one root layer, all npm globals into the Claude Code install layer, emits root runs, then `USER_BLOCK` (creates the host-UID-matched `dev` user), then user runs, then `ENV`/`PATH`.
- **`guard_write` / `.creel/.dockerfile.sha256`** — the edit guard. `creel` rewrites `.creel/Dockerfile` only when its on-disk sha256 still matches what `creel` last wrote; a hand-edited file is kept with a warning unless `--regen`. Any change to the render logic therefore silently propagates to unedited projects on next run.
- **Firewall** — `FIREWALL_SH` + `FW_ENTRY_SH` are base64-embedded into *every* image (works on both the legacy builder and BuildKit, no heredocs), so the firewall is a pure run-time toggle needing no rebuild. It is **on by default** (`--no-firewall` opts out). When on, the run adds `NET_ADMIN`/`NET_RAW`, starts as root via the `creel-fw-entry` entrypoint, applies default-deny egress with an ipset allowlist (Anthropic/npm/GitHub plus common package registries), then `gosu`s down to `dev`. The script fails closed: if `example.com` is still reachable it aborts. In stateful mode, the entrypoint touches `/run/creel/fw-ready` (a tmpfs, so it cannot go stale across restarts) and `main` polls for it before exec'ing, so a session never starts ahead of the rules.
- **Sessions** — the mode is saved in `selection.json` next to the toolchains; `--stateful` (default) / `--stateless` update it, neither recalls it. Stateful runs a keep-alive container `creel-<project>` (`docker run -d --init ... sleep infinity`) and does one `docker exec` per session, keeping per-session choices (`--shell`, `--yolo`, env, passthrough) flexible; `--fresh` recreates the container (needed after toolchain/image changes, which only produce a warning), `--stop` stops it. Stateless is the old `docker run --rm` path.
- **`main`** ends in `os.execvp("docker", ...)` — the run (stateless) or exec (stateful) — so the TTY, signals, and exit code belong to docker.

## Conventions that matter

- **Stdlib only.** No third-party imports, ever. It must run from bash, zsh, or fish identically.
- **Selection semantics:** passing any toolchain flag *replaces* the saved set in `.creel/selection.json`; passing none recalls it. The session mode is saved the same way but independently — a mode flag alone never touches the toolchain set. Flags are case-insensitive (`normalize_flags`). Dashed flag names (`--latex-complete`) map to their argparse attribute via `tc.name.replace("-", "_")`.
- **Per-project state** lives in `<project>/.creel/` (`Dockerfile`, `selection.json`, `.dockerfile.sha256`); cross-project state lives in the named volumes `creel-auth` and `creel-data`.
- **Build-time provisioning only.** The runtime posture is `--cap-drop=ALL` + `--security-opt=no-new-privileges` (in both modes), so sudo/apt cannot install toolchains at run time. New capabilities belong in the image. Stateful mode persists what the `dev` user can write (pip --user, cargo install, dotfiles), nothing more.
- **Never mount secrets.** `~/.gitconfig` is forwarded read-only; SSH keys and cloud credentials are deliberately excluded. Only `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN` are passed through.
- **Configuration is env-var only** (`CREEL_*`, see the Readme table) — do not add config files or require editing the script.
- **Pinned versions** needing manual bumps: `ver="Isabelle2025-2"` in `ISABELLE_RUN`, `cuda-toolkit-12-8` in `CUDA_RUN`, and `BASE_IMAGE` (which also determines the CUDA repo path `debian12` and the distro versions of Go/Sage/JDK/TeX Live).
- Changes to toolchains or flags should be reflected in `README.md`, which documents the table field-by-field and lists every supported toolchain.
