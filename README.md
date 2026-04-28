# Dizzy

[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

Dizzy is a Julia package for controlling a circular LED arena in real time. It drives a ring of 198 green LEDs arranged around a behavioural experiment board, letting you define and switch between lighting setups — static lights, blinking lights, or lights that randomly move around the ring — by pressing a key.

---

## Hardware

The arena consists of a 198-LED DotStar strip bent into a ring. An Arduino running `src/dizzy.ino` (FastLED + PacketSerial) sits between the ring and the host computer (typically a Raspberry Pi). The host connects via USB serial at 115200 baud.

Each LED represents a discrete azimuth position on the ring. Position 0° points north, -90° east, 90° west, and ±180° south. For how these azimuths relate to the physical layout of the room and tent, see [this figure](docs/room%20layout/azimuths.png).

---

## Concepts

### Setups

A **setup** is a named lighting configuration. You define up to 9 setups in a JSON file (one per number key `1`–`9`). Three built-in setups are always available:

| Key | Behaviour |
|-----|-----------|
| `0` | All LEDs off |
| `s` | All 198 LEDs on, blinking in sync every 1 second |
| `r` | Random positions, intensities, and timings |
| `q` | Quit |

### Suns

Each setup is made up of one or more **suns** — individual light sources placed at a position on the ring. A sun can be:

- **Static** — fixed position, always on.
- **Blinking** — toggles on and off at a configurable interval.
- **Moving** — periodically picks a new azimuth drawn from a [von Mises distribution](https://en.wikipedia.org/wiki/Von_Mises_distribution) centred on `mu`, controlled by concentration parameter `kappa`. Higher `kappa` keeps the sun close to `mu`; lower `kappa` lets it wander freely around the ring. For the relationship between `kappa` and the full-width at half-maximum of the distribution, see [this figure](docs/fwhm%20and%20kappa/fwhm%20and%20kappa.png).
- **Blinking & moving** — a sun that is both blinking and moving.

Multiple suns can coexist in a single setup. See [`docs/specs.md`](docs/specs.md) for the full JSON format.

---

## Usage

### 1. Install

```julia
] add https://github.com/yakir12/Dizzy.jl
```

### 2. Write a `setups.json`

Create a JSON file defining your lighting configurations. A minimal example with two setups:

```json
[
    {
        "name": "static north",
        "suns": [
            {"mu": 0}
        ]
    },
    {
        "name": "wandering south",
        "suns": [
            {"mu": -180, "kappa": 2, "az_interval": 0.5}
        ]
    }
]
```

See [`docs/specs.md`](docs/specs.md) for all available fields, defaults, constraints, and pitfalls.

### 3. Run

```julia
using Dizzy
load_start()                         # looks for ~/setups.json
load_start("/path/to/setups.json")   # or specify a path
load_start(; sound = true)   # or with sound cues for each keyboard press
```

Dizzy opens the serial port, loads your setups, and prints `ready…`. Press `1`–`9` to activate a setup, `0` to turn all LEDs off, or `q` to quit.

### 4. Logging

Every state change is written to a CSV log file in the current working directory, named `<datetime> <setup name>.log`. Columns: `datetime`, `id` (1-based sun index), `azimuth` (degrees), `intensity`.

Please move or delete `.log` files regularly so the Raspberry Pi does not fill up.

