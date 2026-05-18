# Godot 4 on macOS HiDPI — sizing playbook

**Problem:** Game window opens at half-size on retina Mac. UI text tiny. Resizing window helps but feels wrong.

**Root cause:** With `display/window/dpi/allow_hidpi=true` (the default in Godot 4), all window APIs operate in **physical pixels**. macOS retina is 2× (3× on some Pro displays), so a `viewport_width=1600` produces a 1600-physical-pixel window that occupies only 800 logical points of screen — appears half-size to the user.

## Options, ordered by effort

### 1. Project-setting hack (prototype-grade)

Add to `[display]` in `project.godot`:

```ini
window/size/viewport_width=1600
window/size/viewport_height=900
window/size/window_width_override=3200
window/size/window_height_override=1800
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/dpi/allow_hidpi=true
```

Viewport is the design resolution; window override is physical pixels (2× viewport = 1× logical on retina).

- ✅ One-file edit, zero code.
- ❌ Hardcoded 2× — breaks on 3× displays and non-retina Macs.
- ❌ Wrong on Windows/Linux without conditional branches.

**Use for:** throwaway prototypes, single-developer dev machines.

### 2. content_scale + autoboot (medium)

Same project.godot stretch settings, no window override. In `main.gd` or a `WindowBoot` autoload:

```gdscript
func _ready() -> void:
    var scale := DisplayServer.screen_get_scale()
    get_window().content_scale_factor = scale
```

Game renders crisp at native; UI laid out in design pixels.

- ✅ Adapts to any DPI.
- ❌ Still doesn't choose a sensible initial window size.

### 3. Runtime sizing (production)

`WindowBoot` autoload:

```gdscript
extends Node

const DESIGN_W := 1600
const DESIGN_H := 900

func _ready() -> void:
    var scale := DisplayServer.screen_get_scale()
    var w := int(DESIGN_W * scale)
    var h := int(DESIGN_H * scale)
    DisplayServer.window_set_size(Vector2i(w, h))
    var screen := DisplayServer.screen_get_size()
    DisplayServer.window_set_position((screen - Vector2i(w, h)) / 2)
```

Works on any display, survives monitor swaps.

- ✅ Always right.
- ✅ ~10 lines, no project.godot DPI fiddling.
- This is what Godot's own editor does.

## Easy global UI scale (orthogonal to DPI)

If everything just looks small regardless of DPI, use the global UI multiplier:

```ini
window/stretch/scale=1.5
```

Cheap fix when DPI isn't the issue — UI was just laid out small.

## What's in this project today

Option 1 (project-setting hack). The override `window_width=3200, window_height=1800` assumes 2× retina. For M2 onward, replace with a `WindowBoot` autoload (Option 3).

## Reference settings to remember

| Setting | Meaning |
|---|---|
| `viewport_width/height` | Game's internal design resolution. UI laid out in these units. |
| `window_width_override` | OS window size in **physical pixels**. Hack workaround for DPI. |
| `stretch/mode` | `disabled` = no scaling, `canvas_items` = UI/2D scales, `viewport` = full framebuffer scales. |
| `stretch/aspect` | `keep` = letterbox, `expand` = fill, `keep_height` etc. |
| `stretch/scale` | Multiplier on UI rendering. Cheap text-too-small fix. |
| `dpi/allow_hidpi` | `true` = window APIs use physical pixels (default 4.x). `false` = OS scales window post-render. |
| `DisplayServer.screen_get_scale()` | Returns 2.0 on retina, 1.0 elsewhere. Runtime DPI query. |
