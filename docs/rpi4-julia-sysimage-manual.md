# Building a Raspberry Pi 4 Julia sysimage from an x86_64 host

Cross-compile a Julia sysimage for aarch64 (Pi 4) on an x86_64 Linux box using
Podman + qemu user-mode emulation. Tested with Julia 1.12.6.

Each step below is tagged with where it runs:

- 🖥️  **HOST** — your x86_64 Linux machine
- 📦 **CONTAINER** — the emulated aarch64 shell running on the host
- 🍓 **PI** — the Raspberry Pi 4

## Prerequisites — 🖥️ HOST

```bash
sudo apt install podman qemu-user-static
podman run --rm --privileged docker.io/tonistiigi/binfmt --install arm64
```

The `binfmt --install arm64` is one-time per host.

## 1. Start an aarch64 container — 🖥️ HOST

The depot path inside the container must match where the depot will live on
the Pi, otherwise paths baked in via `@__DIR__` / `pathof()` (e.g. BeepBeep's
`sounddir`) will be wrong.

Note: since I've done step 2. this can be replaced
```bash
podman run --rm -it --platform=linux/arm64 \
  -v "$PWD":/work:Z -w /work \
  -e JULIA_DEPOT_PATH=/home/pi/.julia \
  docker.io/library/julia:1.12 bash
```
with this:
```bash
podman run --rm -it --platform=linux/arm64 \
  -v "$PWD":/work:Z -w /work \
  -e JULIA_DEPOT_PATH=/home/pi/.julia \
  julia-aarch64-build bash
```

You're now in an emulated aarch64 shell — every command from here through
step 5 runs **inside the container**.

## 2. One-time setup — 📦 CONTAINER

```bash
mkdir -p /home/pi/.julia
apt update && apt install -y gcc
```

`gcc` is needed because PackageCompiler links the sysimage with a C compiler,
and the official `julia` image doesn't ship one.

Optional but worth it if you'll iterate — commit this state to a reusable
image so you don't redo apt every session. From the **🖥️ HOST**, in another
terminal:

```bash
podman ps                                # find the container ID
podman commit <id> julia-aarch64-build
```

Future runs use `julia-aarch64-build` instead of `docker.io/library/julia:1.12`.

NOTE: I have done this!

## 3. Instantiate the project — 📦 CONTAINER

```bash
cd # where you'll have down access to both a Project.toml file as well as the Dizzy.jl folder
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
julia --project=. -e 'using Pkg; Pkg.add("PackageCompiler")'
```

This pulls aarch64 JLL artifacts. First run takes a few minutes.

## 4. Generate precompile statements — 🍓 PI, then 🖥️ HOST

Skip baking *execution* into the build — hardware-touching code
(LibSerialPort, GPIO, etc.) won't run correctly under qemu. Instead, capture
compile traces from a real run on the Pi and feed those statements to the
build.

### 4a. 🍓 PI — generate the trace

With the same Julia version (1.12.6) installed on the Pi:

```bash
julia --project=/path/to/project --trace-compile=stmts.jl docs/precompiled.jl
```

### 4b. 🖥️ HOST — pull the trace back

```bash
scp pi@<pi-host>:~/stmts.jl /work/path/to/project/
```

(`/work` here is the directory you bind-mounted in step 1, so the file lands
where the container can see it.)

Regenerate `stmts.jl` only when your code paths change meaningfully — not
every build.

## 5. Build the sysimage — 📦 CONTAINER

```bash
julia -tauto --project=. -e '
using PackageCompiler
create_sysimage(["Dizzy"];
    cpu_target = "cortex-a72",
    sysimage_path = "DizzyPrecompiled.so",
    precompile_statements_file = "stmts.jl",
)'
```

Expect this to be slow under emulation — tens of minutes is normal.

The `.so` ends up on your host filesystem via the bind mount, no copy needed.
You can now `exit` the container.

## 6. Deploy to the Pi — 🖥️ HOST, then 🍓 PI

### 6a. 🖥️ HOST — ship the sysimage

```bash
scp DizzyPrecompiled.so pi@<pi-host>:/path/to/project/
```

### 6b. 🍓 PI — instantiate (once) and run

Make sure the project is instantiated so package data files like
`BeepBeep/sounds/beep.wav` exist on disk:

```bash
julia --project=/path/to/project -e 'using Pkg; Pkg.instantiate()'
```

Then run with the sysimage:

```bash
julia --sysimage=dizzy/DizzyPrecompiled.so --project=dizzy/Project.toml -tauto
```

`using Dizzy` should be near-instant.

## Notes & gotchas

- **Julia version must match exactly** between container and Pi (1.12.6 ↔
  1.12.6). Sysimages are not portable across minor versions.
- **`cpu_target = "cortex-a72"`** locks the image to A72-or-superset CPUs. A76
  (Pi 5) works; A53 (Pi 3) does not. For broader compat:
  `"generic;cortex-a72,clone_all"` (larger image).
- **Depot path must match.** If the Pi user changes, rebuild with the new
  `JULIA_DEPOT_PATH`.
- **`stmts.jl` is hardware-aware.** Anything that doesn't run during the trace
  pass on the Pi won't get precompiled. Make sure your trace exercises
  representative code paths.
- The container is ephemeral; without a committed image, gcc and the depot
  disappear when you `exit`. Use the `podman commit` step in §2, or accept
  the rebuild cost.
