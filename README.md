# creel

*A creel is the wicker trap a crab boat hauls up from the seabed. This one hauls up a disposable, per-project container for [Claude Code](https://www.anthropic.com/claude-code) (the crab) on Docker (the boat).*

Lol

Run [Claude Code](https://www.anthropic.com/claude-code) inside a per-project Docker sandbox.

`creel` generates a small Dockerfile in each project, builds a **local, per-project image** tagged from the directory name, and launches Claude Code inside it with your project bind-mounted and your login persisted in a named volume. Toolchains (compilers, proof assistants, TeX Live, and so on) are declared once in a metadata table and compiled into the image on demand, so each project pulls only what it needs.

For now, it is a single, dependency-free Python 3 file. As with any creel, it admits any shell, even fish.

---

## Why

Two reasons you might want Claude Code in a container:

- **Isolation.** The agent can read and write your project directory but not the rest of your home directory, and it runs under hardened defaults. This matters most when you use `--yolo` (skip-permissions mode).
- **Reproducible, disposable toolchains.** Each project gets exactly the compilers it needs, baked into an image, without polluting your host. Blow the image away and rebuild any time.

---

## Requirements

- Docker (daemon running, current user able to run `docker`)
- Python 3.9+ (standard library only, nothing to `pip install`)
- A Claude Code login: a Claude subscription (Pro/Max) or an Anthropic API key

---

## Install

```sh
install -m755 creel ~/.local/bin/creel   # or anywhere on PATH
```

That is the whole installation. The script has a `#!/usr/bin/env python3` shebang and no extension, so it behaves as a normal `creel` command.

---

## Quick start

From any project root:

```sh
creel --rust --cpp        # provision this project's image with Rust + C++
creel                      # later runs reuse the saved toolchain set
```

First run inside a fresh setup you will need to authenticate once (see [Authentication](#authentication)). After that, every project shares the same login.

---

## Usage

```
creel [toolchain flags] [options] [-- <args forwarded to claude>]
```

### Toolchain flags

Each supported toolchain has a `--<name>` flag (see [Supported toolchains](#supported-toolchains)). Flags are **case-insensitive** (`--isabelle` and `--Isabelle` are equivalent).

Selection is **absolute, not additive**. Passing any toolchain flag replaces the saved set for that project; running with no toolchain flags recalls the saved set. So:

```sh
creel --rust --python     # image has Rust + Python; set saved
creel                      # reuses Rust + Python
creel --go                 # image now has ONLY Go
```

The saved set lives in `.creel/selection.json`, together with the session mode (see [Session state](#session-state)) and the provision command (see below).

### Extra provisioning

`--provision CMD` bakes one extra shell command into the image as a final `RUN` layer, executed as the unprivileged `dev` user at build time:

```sh
creel --rust --provision 'cargo install cargo-mutants'
```

Use it for tools that live in your home directory (`cargo install`, `pip install --user`, `npm` prefixes) and that you want to survive container recreation: unlike an in-session install, a provisioned tool is part of the image, so `--fresh` and `--stateless` runs keep it. Because it is the last layer, changing the command rebuilds only that layer, never the toolchains above it.

Like the session mode, the command is saved in `.creel/selection.json` and recalled on later runs; passing `--provision` replaces it, and `--provision ''` clears it. Chain several tools with `&&`. The `CREEL_PROVISION` environment variable acts as the flag's default when the flag is absent.

### Options

| Flag | Effect |
|------|--------|
| `--shell` | Open `bash` in the container instead of launching `claude` |
| `--yolo` | Launch `claude` with `--dangerously-skip-permissions` |
| `--concise` | Load the [concise-output](https://github.com/NTCoding/claude-skillz/blob/main/concise-output/SKILL.md) skill for the session (terse, high-signal replies) |
| `--no-firewall` | Disable the default-deny egress firewall (on by default) |
| `--mic` | Forward the host PulseAudio/PipeWire socket so Claude Code's `/voice` dictation can record (saved per project; off by default, `--no-mic` turns it back off) |
| `--stateless` | Use a throwaway container per session (saved per project) |
| `--stateful` | Reuse a persistent per-project container (saved; the default) |
| `--fresh` | Discard the persistent container and start over |
| `--stop` | Stop the persistent container and exit |
| `--provision CMD` | Bake `CMD` into the image as a final user `RUN` layer (saved per project) |
| `--test` | Build, then run each selected toolchain's smoke test and report |
| `--rebuild` | Rebuild the image with `--no-cache` |
| `--regen` | Overwrite `.creel/Dockerfile` even if it was hand-edited |
| `--no-git` | Do not bind-mount `~/.gitconfig` (read-only) into the box |
| `--print-dockerfile` | Print the resolved Dockerfile to stdout and exit |
| `-h`, `--help` | Grouped help listing every toolchain |

### Forwarding arguments to Claude Code

Anything after a bare `--` is passed straight to `claude`:

```sh
creel --rust -- --model opus
creel -- --help            # show Claude Code's own help
```

### Examples

```sh
creel --python --latex               # data work plus a minimal TeX Live for reports
creel --python --latex-complete      # same, but the full TeX Live set
creel --lean --isabelle              # a proof-assistant workbench
creel --cuda --python                # GPU work (needs the NVIDIA Container Toolkit)
creel --rust --gcc --test            # build, then smoke-test each toolchain
creel --rust --provision 'cargo install cargo-mutants'   # extra tool, baked in
creel --rust --yolo                  # unattended; the default-deny firewall is already on
creel --shell                        # poke around the current project's image
creel --stop                         # stop this project's persistent container
CREEL_DRY_RUN=1 creel --go       # show the docker commands without running
```

---

## Supported toolchains

Eighteen toolchains across four categories. "Method" is how each is installed: `apt` (Debian package), `npm` (global npm install on the Node base), or `script` (upstream installer, run as root or as the unprivileged `dev` user).

### Languages / compilers

| Flag | Installs | Method | Notes |
|------|----------|--------|-------|
| `--rust` | rustup + cargo (stable, minimal) | script (user) |  |
| `--gcc` | GNU C (gcc, make, gdb) | apt |  |
| `--cpp` | C++ (g++, cmake, make, gdb) | apt |  |
| `--c` | fuller C (gcc, clang, make, cmake, gdb, valgrind) | apt |  |
| `--python` | python3, pip, venv, pipx | apt |  |
| `--ts` | TypeScript (typescript, ts-node, tsx) on the Node base | npm |  |
| `--go` | Go toolchain (distro golang-go) | apt | distro Go (1.19 on bookworm) |
| `--java` | JDK + Maven (default-jdk, maven) | apt |  |
| `--csharp` | .NET SDK (LTS, dotnet-install into ~/.dotnet) | apt, script (user) |  |
| `--qsharp` | Q# (Quantum Development Kit, pip qsharp) | apt, script (user) | Python module, no CLI |

### GPU / accelerators

| Flag | Installs | Method | Notes |
|------|----------|--------|-------|
| `--cuda` | CUDA toolkit 12.8 (nvcc + libraries), needs --gpus at run time | script (root) | ~3-4 GB; amd64 only; host needs NVIDIA driver + Container Toolkit |

### Typesetting

| Flag | Installs | Method | Notes |
|------|----------|--------|-------|
| `--latex` | TeX Live minimal (base + recommended, latexmk) | apt | moderate |
| `--latex-complete` | TeX Live full (adds extra + science, biber) | apt | large |

### Math / proof assistants

| Flag | Installs | Method | Notes |
|------|----------|--------|-------|
| `--sage` | SageMath (distro package, no docs/Jupyter) | apt | large; distro Sage ~9.5, use conda for current |
| `--sage-complete` | SageMath + documentation + Jupyter kernel | apt | large; distro Sage ~9.5, use conda for current |
| `--lean` | Lean 4 via elan (stable) | script (user) |  |
| `--isabelle` | Isabelle2025-2 bundle (arch-aware download) | script (root) | ~1.2 GB |
| `--tamarin` | Tamarin prover via Linuxbrew (+ maude, graphviz) | apt, script (user) | heavy/slow |

A few of these deserve a word:

- **`--gcc` vs `--c`.** `--gcc` is a minimal GNU C toolchain. `--c` is a fuller set that adds clang, cmake, and valgrind. They combine without conflict.
- **`--latex` vs `--latex-complete`.** `--latex` covers everyday documents (base + recommended packages, latexmk); `--latex-complete` adds `texlive-latex-extra`, `texlive-science`, and biber for bibliographies and heavier package needs. Likewise `--sage-complete` adds the Sage documentation and Jupyter kernel on top of `--sage`; the core `sagemath` package is monolithic, so `--sage` is already as small as Debian offers.
- **`--go` and `--sage`** use the Debian package for a zero-maintenance, arch-agnostic install, which means they track the base image's distro version rather than the latest upstream. For current Go, swap in the official tarball; for current Sage, use conda.
- **`--isabelle`** downloads the official bundle and picks the right architecture from `dpkg --print-architecture` (amd64 or arm64). The version is pinned in the script (see [Maintenance](#maintenance)).
- **`--cuda`** installs the CUDA toolkit (nvcc plus libraries), not a driver. The driver comes from the host through the NVIDIA Container Toolkit, and `creel` adds `--gpus` to `docker run` automatically. It is amd64-only and the toolkit version is pinned (see [CUDA and GPUs](#cuda-and-gpus)).
- **`--qsharp`** installs the modern Rust-based Quantum Development Kit as a Python package (the deprecated .NET/iqsharp QDK is not used). It ships no standalone compiler CLI: run Q# through Python, e.g. `python3 -c 'import qsharp; print(qsharp.eval("..."))'` or `qsharp.run()` on a `.qs` file's contents. It combines naturally with `--python` for notebooks and scripting.
- **`--tamarin`** is the heavy one. Tamarin ships no Debian package, so the flag bootstraps Linuxbrew and installs via the official tap, which drags in GHC and maude and can take many minutes on first build. Reach for it only when a project needs it.

---

## Authentication

Claude Code stores its state under `~/.claude` (config, plus `.credentials.json` for OAuth logins on headless Linux) and session data under `~/.local/share/claude`. `creel` maps both to **named Docker volumes** (`creel-auth`, `creel-data`) rather than to your host home directory. Consequences:

- Your login is **isolated from your host** yet **shared across all creel projects**, so you authenticate once.
- Nothing is baked into any image layer, so credentials never leak into an image.

You can authenticate in any of three ways:

1. **OAuth login (subscription).** On first use, run `creel --no-firewall --shell` (the login flow touches domains outside the firewall allowlist), then `claude` inside the container, and follow the printed URL/code flow. The token persists in the `creel-auth` volume, so you only do this once. Or authenticate in any single project and every project inherits it.
2. **API key.** Export `ANTHROPIC_API_KEY` on the host; `creel` forwards it into the container.
3. **OAuth token (subscription, headless).** Run `claude setup-token` on the host to mint a `CLAUDE_CODE_OAUTH_TOKEN`, export it, and `creel` forwards it.

To share your host login instead of an isolated volume, point the auth volume at your home directory:

```sh
export CREEL_RUN_EXTRA="-v $HOME/.claude:/home/dev/.claude"
```

---

## How it works

**Per-project image.** The image is tagged `creel/<project-dir-name>` and is local only. Nothing is pushed anywhere or shared between projects except the auth/data volumes.

**Generated Dockerfile.** On each run, `creel` renders a Dockerfile from the toolchain table containing **only the selected toolchains**, then builds it. The build context is just `.creel/`, so it stays tiny regardless of project size (the project is bind-mounted at run time, never copied into the image).

**Host-matched user.** The container runs as a `dev` user created with your host UID and GID, so files the agent writes into the project stay owned by you rather than by root.

**Checksum guard.** The rendered Dockerfile is compared against the on-disk copy via a checksum sidecar (`.creel/.dockerfile.sha256`):

- If you have not touched the file, template or selection changes are adopted silently (you will see `>> refreshed .creel/Dockerfile from template`).
- If you have hand-edited the file, `creel` keeps your version and warns instead of clobbering it.
- `--regen` forces an overwrite when you want to discard your edits.

**Stable ordering for caching.** Toolchain blocks always render in the table's canonical order regardless of the order you pass flags, so Docker's layer cache survives adding a toolchain (only layers at and after the new block are invalidated).

---

## Session state

By default sessions are **stateful**: the first run creates a persistent per-project container (`creel-<project>`) kept alive in the background, and every session is a `docker exec` into it. Anything written inside the container between sessions survives: `pip install --user`, `cargo install`, npm prefixes, shell history, dotfiles, scratch files outside the project.

What does *not* persist or work:

- **System packages.** The hardening (`--cap-drop=ALL`, `no-new-privileges`) blocks `sudo`, so `apt install` fails at run time by design. Toolchains belong in the image; select the flag and rebuild.
- **Toolchain changes.** The persistent container keeps running on the image it was created from. After changing the selection, `creel` warns and keeps the old container; run `creel --fresh` to recreate it on the new image (discarding in-container state). Tools you always want should therefore be baked in with `--provision` (see [Extra provisioning](#extra-provisioning)) rather than installed in-session, so recreation costs nothing.
- **Creation-time settings.** GPU flags, `CREEL_RUN_EXTRA`, the firewall on/off state, and the `--mic` audio mount are fixed when the container is created; `--fresh` applies changes. Per-session choices (`--shell`, `--yolo`, `--concise`, forwarded `claude` args, `ANTHROPIC_API_KEY`) stay flexible, since each session is its own `exec`.

The keep-alive container is just an idle `sleep`; stop it any time with `creel --stop` (the next run restarts it, state intact).

Prefer the old throwaway behavior? `creel --stateless` switches the project to one-shot containers (`docker run --rm`); `creel --stateful` switches back. Like toolchain flags, the mode is saved in `.creel/selection.json` and recalled on later runs.

---

## Security model

The container is meant to be a boundary, especially in `--yolo` mode:

- Runs as an unprivileged host-matched user, with `--cap-drop=ALL` and `--security-opt=no-new-privileges`. Even though the `dev` user has a passwordless sudoers entry (needed at build time), runtime privilege escalation is blocked, which is the safer posture for skip-permissions runs. All toolchains are therefore provisioned at build time, not at run time.
- The project directory is bind-mounted read-write (intended: the agent edits your code). The rest of your host home is not visible.
- Git identity is forwarded read-only (`~/.gitconfig`, not a secret). SSH keys and cloud credentials are deliberately **not** mounted. Pushing to a remote needs a scoped token you supply on purpose.
- Anything reachable inside the container, including the credentials in the mounted `~/.claude`, is readable by the agent. Use this for trusted repositories.
- The host microphone is not reachable unless you opt in with `--mic`, which forwards the host audio socket (see [Voice dictation](#voice-dictation)). The socket grants full audio-server access (recording included), so the flag is off by default and saved per project, never globally.

By default outbound traffic is locked down to a default-deny egress firewall with an allowlist (Anthropic API, npm, GitHub, common package registries, plus anything you add). Pass `--no-firewall` to allow normal network egress instead. See [Firewall](#firewall) for what it does and its trade-offs.

---

## CUDA and GPUs

`--cuda` bakes the CUDA toolkit into the image and wires GPU access into `docker run`. Two things are worth understanding:

- **The image carries the toolkit; the host carries the driver.** `--cuda` installs `nvcc` and the CUDA libraries but not a driver. GPU access at run time depends on the host having a working NVIDIA driver and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html). Without those, the container builds fine but `docker run --gpus` fails.
- **`--gpus` is added automatically.** When any selected toolchain needs a GPU, `creel` appends `--gpus all` to the run. Override the device selection with `CREEL_GPUS`, for example `CREEL_GPUS=device=0` to expose a single GPU, or `CREEL_GPUS=` (empty) to omit the flag entirely.

CUDA is amd64-only here, and the toolkit version is pinned (see [Maintenance](#version-pinned-pieces)). A build without a GPU still works for compilation; running GPU kernels obviously needs the hardware.

Quick check that the GPU is visible inside the box:

```sh
creel --cuda --shell
# then, inside:  nvidia-smi   (needs the host Container Toolkit)
```

---

## Testing

`--test` builds the image for the current selection, then runs a smoke test for each selected toolchain inside the container and prints a pass/fail table. It is meant both as a sanity check after changing toolchains and as something you can run in CI.

```sh
creel --rust --gcc --latex --test
```

```
>> testing 3 toolchain(s) in creel/myproject
   rust   PASS
   gcc    PASS
   latex  PASS
>> 3 passed, 0 failed
```

The tests are quick and, where cheap, actually exercise the toolchain rather than just checking a version: the C/C++/clang tests compile and run a program, the Java and LaTeX tests compile real inputs, and the rest run a representative command. On failure, the last few lines of output are shown inline, and the command exits non-zero so CI catches it. Each toolchain's test is the `test` field on its table entry, so a new toolchain gets a test the same way it gets everything else.

The CUDA test is `nvcc --version`, which validates the toolkit without requiring a GPU. A real kernel run needs the hardware and the host Container Toolkit.

---

## Firewall

A default-deny egress firewall is applied inside the container **by default**, so the agent can reach only an allowlist and nothing else. This is the strongest of the sandboxing options and pairs naturally with `--yolo`. Pass `--no-firewall` to disable it for a session.

What it allows by default: DNS, loopback, the local host network, established connections, GitHub's published IP ranges (fetched from the `/meta` API so `git` and `gh` work), and these resolved domains: `registry.npmjs.org`, `api.anthropic.com`, `sentry.io`, `statsig.anthropic.com`, `statsig.com`, plus the common package registries `pypi.org`, `files.pythonhosted.org`, `crates.io`, `static.crates.io`, `index.crates.io`, `deb.debian.org`, `security.debian.org`. Everything else outbound is rejected. Add more with `CREEL_FIREWALL_ALLOW`:

```sh
CREEL_FIREWALL_ALLOW="proxy.golang.org sum.golang.org" creel
```

How it works: the firewall machinery (a small init script plus `iptables`/`ipset`/`gosu`) is baked into every image, so the firewall is a pure run-time toggle needing no rebuild. When on, the container is granted `NET_ADMIN` and `NET_RAW` (plus `SETUID`/`SETGID` so `gosu` can drop privileges), starts as root just long enough for an entrypoint to apply the `iptables` rules, then drops to the unprivileged `dev` user via `gosu` before running Claude Code. The init script fails closed: if it cannot confirm that egress is actually restricted (it verifies that `example.com` is unreachable), the container aborts rather than running unprotected. In stateful mode, `creel` additionally waits for the entrypoint's ready signal before exec'ing into the container, so a session never starts ahead of the rules.

Two things to know:

- **Authenticate first.** The OAuth login flow may touch domains outside the allowlist. Log in once with `--no-firewall` (the token persists in the auth volume); work sessions only need `api.anthropic.com`.
- **Trade-off with capabilities.** The firewall necessarily adds `NET_ADMIN`/`NET_RAW` (and `SETUID`/`SETGID`, used once by the entrypoint to shed root), which the fully-locked posture drops. This is a deliberate exchange: slightly more container capability in return for a hard egress boundary. The rest of the hardening (unprivileged final user, `no-new-privileges`, everything else dropped) is unchanged. If you prefer zero added capabilities over the egress boundary, run with `--no-firewall`.

If a session behaves as though the network is down, it usually means something it needs is not on the allowlist; add the domain via `CREEL_FIREWALL_ALLOW` and rerun.

---

## Voice dictation

Claude Code has a built-in [voice dictation](https://code.claude.com/docs/en/voice-dictation.md) mode (`/voice`): it records from a microphone and streams the audio to Anthropic's transcription service. Recording needs an audio device, which a container does not have by default. `--mic` closes that gap:

```sh
creel --mic          # saved in .creel/selection.json; later runs recall it
creel --no-mic       # turn it back off
```

With the flag on, `creel` locates the host's PulseAudio/PipeWire socket (`$XDG_RUNTIME_DIR/pulse/native`, with a WSLg fallback), bind-mounts it into the container, and points `PULSE_SERVER` at it. The SoX recorder Claude Code uses on Linux is baked into every image, so like the firewall this is a pure run-time toggle: no rebuild, no added capabilities (the host-matched `dev` user passes the audio server's peer-credential check). In stateful mode the mount is a creation-time setting; `creel` warns when the saved value and the running container disagree, and `--fresh` applies the change.

What to expect per host:

- **Linux desktop** (PulseAudio, or PipeWire with its pulse-compat socket): works.
- **WSL2 with WSLg**: works, via `/mnt/wslg/PulseServer`.
- **macOS / Windows Docker Desktop**: does not work; Docker runs in a VM with no host audio socket to mount. Use the host OS dictation instead: the terminal is local, so dictated text reaches Claude Code in the container like any other typing.
- **Headless hosts**: no audio server, same answer as above. When no socket is found, `creel` prints a note and starts the session without audio.

Two requirements on the Claude Code side: voice needs a claude.ai account login (`/login` once inside the container, it persists in the auth volume; an `ANTHROPIC_API_KEY` alone does not qualify), and transcription streams over a WebSocket to `wss://api.anthropic.com/api/ws/speech_to_text/voice_stream`. That host is already on the firewall allowlist, so `/voice` works with the firewall on.

If auto-detection picks the wrong socket (or none), point `CREEL_MIC_SOCKET` at the right one.

---

## Customization

All customization is via environment variables, no editing required:

| Variable | Default | Purpose |
|----------|---------|---------|
| `CREEL_BASE_IMAGE` | `node:22-bookworm-slim` | Base image (Node is required for the CLI) |
| `CREEL_AUTH_VOLUME` | `creel-auth` | Named volume holding your Claude login |
| `CREEL_DATA_VOLUME` | `creel-data` | Named volume for session/history data |
| `CREEL_RUN_EXTRA` | (empty) | Extra `docker run` flags, split with shell quoting rules |
| `CREEL_GPUS` | `all` | Value for `--gpus` when a GPU toolchain is selected; empty omits it |
| `CREEL_FIREWALL_ALLOW` | (empty) | Extra domains to allow through the firewall, space-separated |
| `CREEL_MIC_SOCKET` | (auto-detected) | Host audio socket forwarded by `--mic`, when auto-detection misses |
| `CREEL_PROVISION` | (unset) | Default for `--provision` when the flag is absent |
| `CREEL_DRY_RUN` | (unset) | If set, print the `docker build`/`docker run` commands and exit |
| `ANTHROPIC_API_KEY` | (unset) | Forwarded into the container if present |
| `CLAUDE_CODE_OAUTH_TOKEN` | (unset) | Forwarded into the container if present |

Example: share a cargo registry cache across projects to avoid recompiling crates:

```sh
export CREEL_RUN_EXTRA="-v $HOME/.cargo/registry:/home/dev/.cargo/registry"
```

---

## Maintenance

### Adding a toolchain

Add one `Toolchain` entry to the `TOOLCHAINS` table. No Dockerfile editing: the entry's fields are rendered into the image automatically. Fields:

| Field | Meaning |
|-------|---------|
| `name` | The `--flag`, the selection key |
| `category` | Help grouping (`LANG`, `TYPESET`, `MATH`) |
| `summary` | One-line help text |
| `apt` | apt packages, batched into the single root apt layer |
| `npm` | global npm packages, added to the Claude Code install layer |
| `root_run` | a complete `RUN ...` block executed as root (before the user switch) |
| `user_run` | a complete `RUN ...` block executed as the `dev` user |
| `path` | directories to prepend to `PATH` |
| `env` | `(KEY, VALUE)` pairs emitted as `ENV` |
| `size` | help annotation, e.g. `"~1.2 GB"` |
| `note` | caveat surfaced in help and printed at build time |

Prefer `apt` when a good package exists. Use `user_run` for anything that installs into a user home (rustup, elan, dotnet), and `root_run` for anything writing to system paths. Example:

```python
Toolchain("zig", LANG, "Zig compiler",
          user_run=ZIG_RUN, path=("/home/dev/.zig",), size="~50 MB"),
```

where `ZIG_RUN` is a plain (raw) string containing the full `RUN` instruction. Keep such fragments as raw strings so shell tokens (`$HOME`, `${ver}`, `$(...)`) survive verbatim into the Dockerfile.

Place the new entry where you want it in build order. Earlier entries build first, so put rarely-changing toolchains ahead of experimental ones to preserve layer cache.

### Version-pinned pieces

Most toolchains float with the distro or their own version manager, but a few are pinned in the script and need a manual bump:

- **Isabelle.** The release string lives in the `ISABELLE_RUN` fragment (`ver="Isabelle2025-2"`). Update it when a new Isabelle ships (roughly yearly).
- **CUDA.** The toolkit package is pinned in the `CUDA_RUN` fragment (`cuda-toolkit-12-8`). Bump it to match the CUDA version your host driver supports.
- **Base image.** `CREEL_BASE_IMAGE` sets the Debian release, which determines the versions of the apt-installed toolchains (Go, Sage, JDK, TeX Live) and the CUDA repo path (`debian12`). Bumping the base image (for example to a newer Node/Debian) moves all of them at once.
- **.NET** tracks the LTS channel and **Lean/Rust** track their `stable` channels, so those self-update on rebuild.

### Regenerating after updating the script

When you pull a newer `creel`, the next run refreshes each project's `.creel/Dockerfile` automatically **if you have not hand-edited it**. If you have (or if a project predates the checksum sidecar and cannot be proven unedited), run `creel --regen` once in that project to adopt the new template.

### Files written into each project

`creel` creates a `.creel/` directory containing:

- `Dockerfile` — the generated build definition
- `selection.json` — the saved toolchain set, session mode, and provision command for this project
- `.dockerfile.sha256` — the checksum sidecar for the edit guard

Add `.creel/` to your project `.gitignore`, or commit `Dockerfile` and `selection.json` if you want to pin the environment for collaborators (in that case still ignore `.dockerfile.sha256`).

---

## Other features and tips

- **`--print-dockerfile`** renders the resolved Dockerfile to stdout without building, useful for inspection or piping into a linter.
- **`CREEL_DRY_RUN=1`** prints the exact `docker build` and `docker run` commands instead of executing them. Handy for understanding what the tool does or for debugging.
- **`selection.json`** is plain JSON, so other tooling can read or generate it.
- **Network at build time.** The script-installed toolchains fetch from `sh.rustup.rs`, `dot.net`, `pypi.org`, `raw.githubusercontent.com`, `isabelle.in.tum.de`, `developer.download.nvidia.com`, and Homebrew. Provisioning them needs normal outbound network during `docker build`. (This is the build; the `--firewall` allowlist governs the running session, not the build.)
- **Image size.** Heavy toolchains (`--latex`, `--sage`, `--isabelle`, `--tamarin`, `--cuda`) add minutes and 1 to 4 GB each. Because images are per-project, this only affects projects that ask for them.

---

## Troubleshooting

- **`docker not found on PATH`** — install Docker or ensure your user can run it.
- **Files created by the agent are owned by root** — should not happen, since the container runs as your UID/GID. If it does, your host UID/GID likely differs from what the image was built with; rebuild with `creel --rebuild`.
- **Auth prompt every time** — the `creel-auth` volume may not be persisting. Confirm `docker volume ls` shows it and that nothing removed it between runs.
- **Tamarin build is slow or fails** — Linuxbrew in Docker is finicky and slow on first build. Rerun; if it keeps failing, that flag is the most fragile and the least essential to keep.
- **Dockerfile changes are ignored** — you probably hand-edited it, so the guard is protecting your edits. Use `--regen` to overwrite, or edit the script's template instead.
- **A newly added toolchain is missing from the session** — in stateful mode the persistent container keeps running on its original image. Run `creel --fresh` to recreate it on the current image (this discards in-container state).
- **Session behaves as though the network is down** — the default firewall is blocking a domain the session needs. Add it via `CREEL_FIREWALL_ALLOW`, or run with `--no-firewall` if you don't want the egress boundary.

---

## Roadmap

Natural next steps as the toolchain count grows:

- **Shell completions.** argparse pairs with `shtab` to emit bash/zsh/fish completions from the same table, no per-shell maintenance.
- **External registry.** Splitting `TOOLCHAINS` into an importable module or a `toml`/`json` file so people can contribute toolchain definitions without touching the launcher logic.
- **Per-toolchain firewall allowlists.** The `--firewall` allowlist is currently global (plus `CREEL_FIREWALL_ALLOW`); a toolchain could declare the domains it needs (for example crates.io for Rust, pypi.org for Python) and have them added automatically when selected.


