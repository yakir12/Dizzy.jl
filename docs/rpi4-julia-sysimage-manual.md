# Building a Raspberry Pi 4 Julia sysimage from an x86_64 host

Cross-compile a Julia sysimage for aarch64 (Pi 4) on an x86_64 Linux box using
Podman + qemu user-mode emulation. Tested with Julia 1.12.6.

## Prerequisites

```bash
sudo apt install podman qemu-user-static
podman run --rm --privileged docker.io/tonistiigi/binfmt --install arm64
```

The `binfmt --install arm64` is one-time per host.

## 1. Start an aarch64 container with the right depot path

The depot path inside the container must match where the depot will live on
the Pi, otherwise paths baked in via `@__DIR__` / `pathof()` (e.g. BeepBeep's
`sounddir`) will be wrong.

```bash
podman run --rm -it --platform=linux/arm64 \
  -v "$PWD":/work:Z -w /work \
  -e JULIA_DEPOT_PATH=/home/pi/.julia \
  docker.io/library/julia:1.12 bash
```

You're now in an emulated aarch64 shell.

## 2. One-time setup inside the container

```bash
mkdir -p /home/pi/.julia
apt update && apt install -y gcc
```

`gcc` is needed because PackageCompiler links the sysimage with a C compiler,
and the official `julia` image doesn't ship one.

Optional but worth it if you'll iterate — commit this state to a reusable
image so you don't redo apt every session. From the **host**, in another
terminal:

```bash
podman ps                                # find the container ID
podman commit <id> julia-aarch64-build
```

Future runs use `julia-aarch64-build` instead of `docker.io/library/julia:1.12`.

## 3. Instantiate the project

```bash
cd /work/path/to/your/project            # the dir with Project.toml
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
julia --project=. -e 'using Pkg; Pkg.add("PackageCompiler")'
```

This pulls aarch64 JLL artifacts. First run takes a few minutes.

## 4. Generate precompile statements on the Pi

Skip baking *execution* into the build — hardware-touching code
(LibSerialPort, GPIO, etc.) won't run correctly under qemu. Instead, capture
compile traces from a real run on the Pi and feed those statements to the
build.

**On the Pi**, with the same Julia version (1.12.6):

```bash
julia --project=/path/to/project --trace-compile=stmts.jl docs/precompiled.jl
```

Then copy `stmts.jl` back to your host:

```bash
scp pi@<pi-host>:~/stmts.jl /work/path/to/project/
```

Regenerate `stmts.jl` only when your code paths change meaningfully — not
every build.

## 5. Build the sysimage

Back inside the container:

```bash
julia --project=. -e '
using PackageCompiler
create_sysimage(["Dizzy"];
    cpu_target = "cortex-a72",
    sysimage_path = "DizzyPrecompiled.so",
    precompile_statements_file = "stmts.jl",
)'
```

Expect this to be slow under emulation — tens of minutes is normal.

The `.so` ends up on your host filesystem via the bind mount, no copy needed.

## 6. Deploy to the Pi

```bash
scp DizzyPrecompiled.so pi@<pi-host>:/path/to/project/
```

On the Pi, make sure the project is instantiated (so package data files like
`BeepBeep/sounds/beep.wav` exist on disk):

```bash
julia --project=/path/to/project -e 'using Pkg; Pkg.instantiate()'
```

Then run with the sysimage:

```bash
julia --sysimage=/path/to/project/DizzyPrecompiled.so --project=/path/to/project
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
