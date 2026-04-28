# setups.json Specification

`setups.json` defines the LED configurations available at runtime. Each configuration is called a **setup** and is activated by pressing a number key (`1`–`9`).

---

## Top-level structure

The file is a JSON **array** of setup objects. You need at least 1 and at most 9 setups (one per number key `1`–`9`, assigned in order).

```json
[
    { "name": "first",  "suns": [ ... ] },
    { "name": "second", "suns": [ ... ] }
]
```

---

## Setup object

Each setup has two required fields:

| Field  | Type   | Description |
|--------|--------|-------------|
| `name` | string | Human-readable label (at least 1 character). Printed when the setup is activated. |
| `suns` | array  | List of light sources (1–198). See below. |

No other fields are allowed. A typo like `"names"` will fail validation.

---

## Sun object

Each entry in `suns` represents one light source aimed at a fixed angular position on the LED ring. Only `mu` is required — all other fields have defaults.

### Fields

| Field          | Type    | Default | Description |
|----------------|---------|---------|-------------|
| `mu`           | number  | —       | **Required.** Angular position in degrees. Range: `[-180, 180)`. 0 = top, 90 = right, -90 = left, -180 = bottom. |
| `green`        | integer | `255`   | Brightness (1–255). |
| `int_interval` | number  | Inf     | Blink period in seconds. Minimum 0.01; must be a multiple of 0.01. If set, the light toggles on/off repeatedly. |
| `int_delay`    | number  | `0`     | Seconds to wait before the first blink toggle. Must be a multiple of 0.01. Requires `int_interval`. |
| `kappa`        | number  | Inf     | Concentration of the azimuth distribution (must be > 0). Higher = tighter around `mu`. Requires `az_interval`. |
| `az_interval`  | number  | Inf     | How often (in seconds) to pick a new random azimuth angle. Minimum 0.01; must be a multiple of 0.01. Requires `kappa`. |
| `az_delay`     | number  | `0`     | Seconds to wait before the first azimuth update. Must be a multiple of 0.01. Requires `az_interval`. |

No other fields are allowed.

---

## Examples

### Simplest possible setup — static light

Only `mu` is required. The light turns on at that position and stays there.

```json
[
    {
        "name": "south",
        "suns": [
            {"mu": -180}
        ]
    }
]
```

### Blinking light

Add `int_interval` to make the light toggle on and off every 1 second.

```json
[
    {
        "name": "blink",
        "suns": [
            {"mu": 0, "int_interval": 1.0}
        ]
    }
]
```

### Blinking light with a startup delay

Use `int_delay` to wait before the first toggle. `int_delay` requires `int_interval`.

```json
[
    {
        "name": "delayed blink",
        "suns": [
            {"mu": 0, "int_interval": 1.0, "int_delay": 2.0}
        ]
    }
]
```

### Wandering light (random azimuth)

`kappa` and `az_interval` must always be specified together. `kappa` controls how tightly the random positions cluster around `mu` — a high value (e.g. `10`) stays close to `mu`, a low value (e.g. `0.1`) wanders nearly anywhere on the ring.

```json
[
    {
        "name": "wander",
        "suns": [
            {"mu": 0, "kappa": 1.0, "az_interval": 0.5}
        ]
    }
]
```

### Multiple suns in one setup

Each sun gets a unique device ID based on its position in the array (first sun = device 1, second = device 2, etc.). Up to 198 suns per setup.

```json
[
    {
        "name": "two suns",
        "suns": [
            {"mu": 0,  "green": 200, "int_interval": 2.0},
            {"mu": -90, "green": 100, "kappa": 2.0, "az_interval": 1.0}
        ]
    }
]
```

### Multiple setups

```json
[
    {
        "name": "simple",
        "suns": [ {"mu": 0} ]
    },
    {
        "name": "complex",
        "suns": [
            {"mu": 45,  "green": 255, "int_interval": 0.5},
            {"mu": -45, "green": 128, "kappa": 5.0, "az_interval": 2.0}
        ]
    }
]
```

---

## Pitfalls

### `mu = 180` is not valid — use `-180` instead

The valid range is `[-180, 180)` — 180 is excluded because it is the same physical position as -180. The bottom of the ring is `-180`.

```json
{"mu": 180}   // INVALID — use -180
{"mu": -180}  // correct
```

### `kappa` and `az_interval` must appear together

Setting one without the other is rejected. They only make sense as a pair.

```json
{"mu": 0, "kappa": 1.0}              // INVALID — az_interval missing
{"mu": 0, "az_interval": 0.5}        // INVALID — kappa missing
{"mu": 0, "kappa": 1.0, "az_interval": 0.5}  // correct
```

### `int_delay` and `az_delay` require their interval counterpart

A delay without an interval is meaningless — no timer would ever be created.

```json
{"mu": 0, "int_delay": 1.0}                        // INVALID — int_interval missing
{"mu": 0, "az_delay": 1.0, "kappa": 1, "az_interval": 0.5}  // correct
```

### `kappa` must be strictly greater than zero

```json
{"mu": 0, "kappa": 0,   "az_interval": 0.5}  // INVALID — kappa must be > 0
{"mu": 0, "kappa": 0.1, "az_interval": 0.5}  // correct
```

### `green` must be at least 1

A value of 0 means the light is off and cannot blink (it would toggle between off and off). The default is 255.

```json
{"mu": 0, "green": 0}  // INVALID
{"mu": 0, "green": 1}  // correct (dim)
```

### No extra fields

Unknown fields are rejected. Check for typos in field names.

```json
{"mu": 0, "interval": 1.0}      // INVALID — should be "int_interval"
{"mu": 0, "int_interval": 1.0}  // correct
```

### At most 9 setups

Only the keys `1`–`9` are available (9 keys). A 10th setup would be silently unreachable even if the schema allowed it, so the schema rejects it outright.

### Setup name must not be empty

```json
{"name": "", "suns": [...]}   // INVALID
{"name": "x", "suns": [...]}  // correct
```

### Interval and delay values must be multiples of 0.01

All timing fields (`int_interval`, `az_interval`, `int_delay`, `az_delay`) are quantised to 10 ms precision. Values that are not multiples of 0.01 are rejected.

```json
{"mu": 0, "int_interval": 0.001}  // INVALID — not a multiple of 0.01
{"mu": 0, "int_interval": 1.005}  // INVALID — not a multiple of 0.01
{"mu": 0, "int_interval": 1.0}    // correct
```
