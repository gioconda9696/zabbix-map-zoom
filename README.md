# Zabbix Map Widget — Zoom & Pan

Adds interactive zoom and drag (pan) to the Zabbix network map dashboard widget
(**Monitoring → Maps**).

Compatible with **Zabbix 7.x**. No external libraries or database changes required.

---

## Features

| Interaction | Action |
|---|---|
| Mouse wheel | Zoom centered on cursor position |
| `+` button | Zoom in centered on the map |
| `−` button | Zoom out centered on the map |
| `⊙` button | Reset to 100 % |
| Click + drag | Pan (scroll the map) |
| Pinch (touch) | Two-finger zoom |
| One finger (touch) | Touch pan |
| Keyboard `+` / `=` | Zoom in (cursor over the widget) |
| Keyboard `-` / `_` | Zoom out (cursor over the widget) |
| Keyboard `0` | Reset zoom |

**Zoom range:** 20 % — 1000 %

---

## Requirements

- Zabbix 7.x (PHP frontend at `/usr/share/zabbix` or custom path)
- `python3` available on the server
- Root access or write permissions on the frontend directory

---

## Quick Install

```bash
# 1. Go to the script directory
cd /usr/share/zabbix/zabbix-map-zoom

# 2. Run the installer
bash install.sh

# 3. Hard refresh your browser with Ctrl+Shift+R
```

If the Zabbix frontend is at a different path:

```bash
bash install.sh --zabbix-dir /opt/zabbix/ui
```

---

## Uninstall

```bash
bash install.sh --uninstall

# With a custom path:
bash install.sh --uninstall --zabbix-dir /opt/zabbix/ui
```

The script automatically restores original files from the backups
created during installation.

---

## Files Modified by the Installer

```
/usr/share/zabbix/widgets/map/
├── manifest.json                     ← adds "class.map.zoom.js" to assets.js
├── assets/js/
│   ├── class.widget.js               ← 3 small patches (see below)
│   └── class.map.zoom.js             ← NEW file (CMapZoom class)
└── .zoom-backup/                     ← automatic backups (created on install)
    ├── class.widget.js
    ├── manifest.json
    └── install.log
```

### Exact Changes in `class.widget.js`

**Patch 1 — new field:**
```js
// Before:
#map_svg = null;

// After:
#map_svg = null;
#map_zoom = null;   // ← CMapZoom instance
```

**Patch 2 — cleanup in `onClearContents()`:**
```js
// Before:
onClearContents() {
    this.#map_svg = null;
}

// After:
onClearContents() {
    this.#map_zoom?.destroy();   // ← removes listeners and buttons
    this.#map_zoom = null;
    this.#map_svg = null;
}
```

**Patch 3 — instantiation in `#makeSvgMap()`:**
```js
// Before:
this.#map_svg = new SVGMap(options);

// After:
this.#map_zoom?.destroy();
this.#map_svg = new SVGMap(options);
this.#map_zoom = new CMapZoom(this.#map_svg);   // ← activates zoom
```

---

## How It Works

### Technique: SVG `viewBox` Manipulation

The dashboard map uses `useViewBox = true`, which means the SVG renders with
`viewBox="0 0 W H"`. Zoom is implemented by dynamically modifying that attribute:

```
zoom in  →  smaller viewBox  →  content appears larger
zoom out →  larger viewBox   →  content appears smaller
pan      →  shifts the viewBox origin
```

**Why this technique is the right one:**

| Alternative | Problem |
|---|---|
| `CSS transform: scale()` | Misaligns tooltip and context menu positions |
| `CSS zoom` | Non-standard across browsers, same offset issues |
| panzoom library | External dependency, may break on updates |
| **Modify viewBox** | Native SVG, all events stay in correct coordinates ✓ |

### SVG Event Compatibility

The SVG handles `click`, `mouseover`, `mouseout`, and `data-menu-popup` based on
**viewBox coordinates**, not screen pixels. By modifying the viewBox:

- Clicks on hosts/elements work as usual
- Tooltips and context menus are positioned correctly
- `pointer` cursors on interactive elements are preserved

### Click vs Drag Detection

To avoid blocking context menus while dragging, a 5 px threshold is used:

```
mousedown → mousemove < 5px → mouseup = normal CLICK (menu opens)
mousedown → mousemove ≥ 5px → mouseup = DRAG (menu blocked in capture phase)
```

### Lifecycle & Memory

```
Widget loads map
  └─ #makeSvgMap()
       ├─ new SVGMap(options)      ← SVG rendered
       └─ new CMapZoom(svg_map)    ← zoom active

Widget reloads map (submap navigation, refresh)
  └─ #makeSvgMap()
       ├─ map_zoom.destroy()       ← listeners/buttons removed
       ├─ new SVGMap(options)      ← new SVG
       └─ new CMapZoom(svg_map)    ← zoom active again

Widget destroyed / clearContents()
  └─ map_zoom.destroy()           ← full cleanup, no memory leaks
```

---

## Customization

Zoom parameters can be adjusted in `class.map.zoom.js`:

```js
static MIN_ZOOM    = 0.2;   // Minimum zoom (20 %)
static MAX_ZOOM    = 10;    // Maximum zoom (1000 %)
static ZOOM_FACTOR = 1.3;   // Step factor (30 % per step)
static PAN_THRESHOLD = 5;   // Pixels to distinguish click from drag
```

Button styles are injected via `<style id="map-zoom-styles">` in the
document `<head>`. They can be overridden with more specific CSS without
modifying the JS file.

---

## Troubleshooting

### Zoom does not appear after installing

1. Verify the script completed without errors
2. **Hard refresh** your browser: `Ctrl+Shift+R` (or `Cmd+Shift+R` on Mac)
3. If Zabbix caches assets, clear the server cache:
   ```bash
   # Nginx / Apache usually don't cache Zabbix JS assets
   # If you use a reverse proxy like Varnish, purge the cache
   ```
4. Check the browser console (F12) for JavaScript errors

### The script says "patch not found"

This happens when the `class.widget.js` version differs from what is expected.
It means Zabbix was updated and the text patterns have changed.

Manual fix: apply the 3 changes from the **"Exact Changes"** section above
using your preferred editor.

### Clicks on hosts stop working

This should not happen with this implementation. If it does:

1. Uninstall with `bash install.sh --uninstall`
2. Check the Zabbix version with `grep ZABBIX_VERSION /usr/share/zabbix/include/defines.inc.php`
3. Report the issue with the exact version number

### Dragging opens the context menu

The drag threshold is 5 px (`PAN_THRESHOLD`). On high-density touch screens
it may need adjustment. Edit `class.map.zoom.js` and increase the value:

```js
static PAN_THRESHOLD = 10;  // more permissive on touch
```

---

## Version Compatibility

| Zabbix | Status |
|---|---|
| 7.0.x | Tested ✓ |
| 7.2.x | Tested ✓ |
| 6.x   | Not supported (different widget architecture) |

---

## Repository Structure

```
zabbix-map-zoom/
├── install.sh    ← install/uninstall script
└── README.md     ← this documentation
```

The `class.map.zoom.js` file is generated at install time inside the Zabbix
widget directory.
