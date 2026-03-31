#!/usr/bin/env bash
# =============================================================================
#  Zabbix Map Widget – Zoom & Pan Installer
#  Versión: 1.0.0
#
#  Uso:
#    bash install.sh [--zabbix-dir /ruta/al/frontend] [--uninstall] [--help]
#
#  Sin argumentos asume que el frontend está en /usr/share/zabbix
# =============================================================================

set -euo pipefail

# ── Colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "${GREEN}  [OK]${RESET}    $*"; }
info() { echo -e "${CYAN}  [..]${RESET}    $*"; }
warn() { echo -e "${YELLOW}  [!!]${RESET}    $*"; }
fail() { echo -e "${RED}  [ERROR]${RESET}  $*" >&2; exit 1; }

# ── Valores por defecto ───────────────────────────────────────────────────────
ZABBIX_DIR="/usr/share/zabbix"
UNINSTALL=false

# ── Argumentos ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --zabbix-dir)  ZABBIX_DIR="${2%/}"; shift 2 ;;
        --uninstall)   UNINSTALL=true;      shift   ;;
        --help|-h)
            echo ""
            echo "  Uso: bash install.sh [opciones]"
            echo ""
            echo "  Opciones:"
            echo "    --zabbix-dir PATH   Ruta al frontend de Zabbix (default: /usr/share/zabbix)"
            echo "    --uninstall         Revierte todos los cambios usando los backups"
            echo "    --help              Muestra esta ayuda"
            echo ""
            exit 0 ;;
        *) fail "Argumento desconocido: '$1'. Usa --help para ver las opciones." ;;
    esac
done

# ── Rutas derivadas (exportadas para uso en subshells Python) ─────────────────
export WIDGET_DIR="${ZABBIX_DIR}/widgets/map"
export ASSETS_JS="${WIDGET_DIR}/assets/js"
export WIDGET_JS="${ASSETS_JS}/class.widget.js"
export MANIFEST="${WIDGET_DIR}/manifest.json"
export ZOOM_JS="${ASSETS_JS}/class.map.zoom.js"
export BACKUP_DIR="${WIDGET_DIR}/.zoom-backup"

# =============================================================================
#  DESINSTALACIÓN
# =============================================================================
if $UNINSTALL; then
    echo ""
    echo -e "${BOLD}══ Zabbix Map Zoom – Desinstalando ══${RESET}"
    echo ""

    [[ -d "$BACKUP_DIR" ]] || fail "No se encontraron backups en ${BACKUP_DIR}. Nada que restaurar."

    if [[ -f "${BACKUP_DIR}/class.widget.js" ]]; then
        cp "${BACKUP_DIR}/class.widget.js" "$WIDGET_JS"
        ok "Restaurado: class.widget.js"
    fi

    if [[ -f "${BACKUP_DIR}/manifest.json" ]]; then
        cp "${BACKUP_DIR}/manifest.json" "$MANIFEST"
        ok "Restaurado: manifest.json"
    fi

    if [[ -f "$ZOOM_JS" ]]; then
        rm -f "$ZOOM_JS"
        ok "Eliminado: class.map.zoom.js"
    fi

    rm -rf "$BACKUP_DIR"
    ok "Directorio de backups eliminado"

    echo ""
    ok "Desinstalación completa."
    echo -e "  ${CYAN}Recarga la página del navegador (Ctrl+Shift+R) para aplicar los cambios.${RESET}"
    echo ""
    exit 0
fi

# =============================================================================
#  INSTALACIÓN
# =============================================================================
echo ""
echo -e "${BOLD}══ Zabbix Map Widget – Zoom & Pan Installer v1.0.0 ══${RESET}"
echo ""

# ── 1. Verificaciones previas ─────────────────────────────────────────────────
info "Verificando instalación de Zabbix en: ${ZABBIX_DIR}"

[[ -d "$ZABBIX_DIR" ]]  || fail "Directorio no encontrado: ${ZABBIX_DIR}"
[[ -d "$WIDGET_DIR" ]]  || fail "Widget de mapa no encontrado en: ${WIDGET_DIR}"
[[ -f "$WIDGET_JS" ]]   || fail "No encontrado: ${WIDGET_JS}\n         ¿Es correcta la ruta del frontend?"
[[ -f "$MANIFEST" ]]    || fail "No encontrado: ${MANIFEST}"

command -v python3 >/dev/null 2>&1 || fail "python3 es necesario. Instálalo con: apt install python3  o  yum install python3"

ok "Frontend de Zabbix encontrado"

# Detectar versión de Zabbix
ZABBIX_VERSION="desconocida"
if [[ -f "${ZABBIX_DIR}/include/defines.inc.php" ]]; then
    ZABBIX_VERSION=$(grep -oP "ZABBIX_VERSION',\s*'\K[0-9]+\.[0-9]+\.[0-9]+" \
                    "${ZABBIX_DIR}/include/defines.inc.php" 2>/dev/null | head -1 || echo "desconocida")
fi
info "Versión de Zabbix detectada: ${ZABBIX_VERSION}"

# Verificar si ya está instalado
if grep -q 'CMapZoom' "$WIDGET_JS" 2>/dev/null; then
    warn "El parche ya está aplicado en class.widget.js"
    warn "Si quieres reinstalar limpiamente, ejecuta primero:"
    warn "  bash install.sh --uninstall --zabbix-dir ${ZABBIX_DIR}"
    exit 0
fi

# ── 2. Backup ─────────────────────────────────────────────────────────────────
info "Creando backups en: ${BACKUP_DIR}"
mkdir -p "$BACKUP_DIR"
cp "$WIDGET_JS" "${BACKUP_DIR}/class.widget.js"
cp "$MANIFEST"  "${BACKUP_DIR}/manifest.json"
{
    echo "Fecha       : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Zabbix      : ${ZABBIX_VERSION}"
    echo "Frontend    : ${ZABBIX_DIR}"
    echo "Instalado por: $(whoami)@$(hostname)"
} > "${BACKUP_DIR}/install.log"
ok "Backups creados"

# ── 3. Crear class.map.zoom.js ────────────────────────────────────────────────
info "Creando: ${ZOOM_JS}"
mkdir -p "$ASSETS_JS"

# El contenido del archivo se escribe con python3 para evitar problemas
# con heredoc y caracteres especiales en bash.
python3 - "$ZOOM_JS" << 'PYEOF'
import sys

dest = sys.argv[1]

content = r"""/*
** Zabbix Map Widget - Zoom & Pan Extension
**
** Adds interactive zoom (scroll wheel, buttons, pinch) and pan (drag, touch)
** to SVGMap instances by manipulating the SVG viewBox attribute.
**
** This approach is safe because:
**  - viewBox manipulation does NOT affect SVG event targets -> clicks, tooltips
**    and context menus ([data-menu-popup]) continue to work without changes.
**  - No external libraries required.
**  - Fully cleaned up via destroy() when the widget is cleared/replaced.
*/

class CMapZoom {

	/** @type {SVGSVGElement|null} */
	#svg_el = null;

	/** @type {Element|null} */
	#container = null;

	// Original (100 %) viewBox dimensions read from the SVG attribute.
	#orig_w = 0;
	#orig_h = 0;

	// Live viewBox state.
	#vb_x = 0;
	#vb_y = 0;
	#vb_w = 0;
	#vb_h = 0;

	/** @type {number} Current zoom level (1 = 100 %). */
	#zoom = 1;

	static MIN_ZOOM    = 0.2;   // 20 %
	static MAX_ZOOM    = 10;    // 1000 %
	static ZOOM_FACTOR = 1.3;   // Each step zooms by 30 %
	static PAN_THRESHOLD = 5;   // px - movement needed to distinguish drag from click

	// Pan state.
	#is_panning    = false;
	#did_pan       = false;
	#pan_start     = {x: 0, y: 0};
	#pan_vb_start  = {x: 0, y: 0};

	/** @type {Element|null} */
	#controls_el = null;

	/** @type {Object} - event handler references kept for removal */
	#handlers = {};

	/**
	 * @param {SVGMap} svg_map  The SVGMap instance to attach zoom/pan to.
	 */
	constructor(svg_map) {
		const svg_el = svg_map.canvas.root.element;

		// viewBox is only present in dashboard-widget (useViewBox=true) mode.
		if (!svg_el || !svg_el.hasAttribute('viewBox')) {
			return;
		}

		this.#svg_el    = svg_el;
		this.#container = svg_el.closest('.sysmap-widget-container') || svg_el.parentElement;

		// Parse the initial viewBox set by SVGCanvas.
		const vb = svg_el.getAttribute('viewBox').split(' ').map(Number);
		[this.#vb_x, this.#vb_y, this.#vb_w, this.#vb_h] = vb;
		this.#orig_w = vb[2];
		this.#orig_h = vb[3];

		this.#injectStyles();
		this.#buildControls();
		this.#bindEvents();
	}

	// -- Styles ----------------------------------------------------------------

	#injectStyles() {
		if (document.getElementById('map-zoom-styles')) {
			return;
		}

		const style = document.createElement('style');
		style.id = 'map-zoom-styles';
		style.textContent = `
			/* Grab cursor on the map surface */
			.sysmap-widget-container svg.map-zoom-enabled {
				cursor: grab;
				user-select: none;
				-webkit-user-select: none;
			}
			.sysmap-widget-container svg.map-zoom-enabled.map-zoom-panning {
				cursor: grabbing !important;
			}
			/* Elements with an action keep pointer cursor */
			.sysmap-widget-container svg.map-zoom-enabled [data-menu-popup],
			.sysmap-widget-container svg.map-zoom-enabled a {
				cursor: pointer;
			}

			/* Zoom control panel */
			.map-zoom-controls {
				position: absolute;
				right: 8px;
				bottom: 8px;
				display: flex;
				flex-direction: column;
				gap: 3px;
				z-index: 100;
			}
			.map-zoom-btn {
				width: 28px;
				height: 28px;
				padding: 0;
				margin: 0;
				border-radius: 4px;
				border: 1px solid #b0b0b0;
				background: rgba(248, 248, 248, 0.94);
				color: #333;
				font-size: 17px;
				font-weight: 600;
				line-height: 1;
				cursor: pointer;
				display: flex;
				align-items: center;
				justify-content: center;
				box-shadow: 0 1px 4px rgba(0, 0, 0, 0.22);
				transition: background 0.12s, border-color 0.12s;
			}
			.map-zoom-btn:hover {
				background: #fff;
				border-color: #888;
			}
			.map-zoom-btn:active {
				background: #e0e0e0;
			}

			/* Dark theme support */
			.theme-dark .map-zoom-btn {
				background: rgba(38, 38, 38, 0.92);
				border-color: #555;
				color: #c8c8c8;
				box-shadow: 0 1px 4px rgba(0, 0, 0, 0.5);
			}
			.theme-dark .map-zoom-btn:hover {
				background: rgba(58, 58, 58, 0.96);
				border-color: #888;
			}
			.theme-dark .map-zoom-btn:active {
				background: rgba(30, 30, 30, 0.96);
			}
		`;
		document.head.appendChild(style);
	}

	// -- Controls HTML ---------------------------------------------------------

	#buildControls() {
		this.#controls_el = document.createElement('div');
		this.#controls_el.className = 'map-zoom-controls';
		this.#controls_el.setAttribute('aria-label', 'Map zoom controls');

		this.#controls_el.innerHTML = [
			'<button class="map-zoom-btn" data-zoom-action="in"    title="Zoom in (+)">+</button>',
			'<button class="map-zoom-btn" data-zoom-action="reset" title="Reset zoom (0)">&#8857;</button>',
			'<button class="map-zoom-btn" data-zoom-action="out"   title="Zoom out (\u2212)">\u2212</button>'
		].join('');

		this.#container.style.position = 'relative';
		this.#container.appendChild(this.#controls_el);
		this.#svg_el.classList.add('map-zoom-enabled');
	}

	// -- Event binding ---------------------------------------------------------

	#bindEvents() {
		// Scroll-wheel zoom (centered on the cursor position).
		this.#handlers.wheel = (e) => {
			e.preventDefault();
			e.stopPropagation();
			const factor = e.deltaY < 0 ? CMapZoom.ZOOM_FACTOR : 1 / CMapZoom.ZOOM_FACTOR;
			const pivot  = this.#clientToSvg(e.clientX, e.clientY);
			this.#applyZoom(factor, pivot.x, pivot.y);
		};
		this.#svg_el.addEventListener('wheel', this.#handlers.wheel, {passive: false});

		// Mouse drag - pan the map.
		this.#handlers.mousedown = (e) => {
			if (e.button !== 0) return;
			// Do not intercept clicks on interactive elements.
			if (e.target.closest('[data-menu-popup]') || e.target.closest('a')) return;

			this.#is_panning   = true;
			this.#did_pan      = false;
			this.#pan_start    = {x: e.clientX, y: e.clientY};
			this.#pan_vb_start = {x: this.#vb_x, y: this.#vb_y};
		};
		this.#svg_el.addEventListener('mousedown', this.#handlers.mousedown);

		this.#handlers.mousemove = (e) => {
			if (!this.#is_panning) return;

			const dx = e.clientX - this.#pan_start.x;
			const dy = e.clientY - this.#pan_start.y;

			if (!this.#did_pan && Math.hypot(dx, dy) > CMapZoom.PAN_THRESHOLD) {
				this.#did_pan = true;
			}
			if (!this.#did_pan) return;

			this.#svg_el.classList.add('map-zoom-panning');

			const rect = this.#svg_el.getBoundingClientRect();
			this.#vb_x = this.#pan_vb_start.x - dx * (this.#vb_w / rect.width);
			this.#vb_y = this.#pan_vb_start.y - dy * (this.#vb_h / rect.height);
			this.#updateViewBox();
		};
		document.addEventListener('mousemove', this.#handlers.mousemove);

		this.#handlers.mouseup = () => {
			this.#is_panning = false;
			this.#svg_el.classList.remove('map-zoom-panning');
		};
		document.addEventListener('mouseup', this.#handlers.mouseup);

		// Capture-phase click: suppress click events that fire after a drag.
		this.#handlers.click_capture = (e) => {
			if (this.#did_pan) {
				e.stopPropagation();
				e.preventDefault();
				this.#did_pan = false;
			}
		};
		this.#svg_el.addEventListener('click', this.#handlers.click_capture, true);

		// Touch: single-finger pan + two-finger pinch-to-zoom.
		let touch_last_dist = null;
		let touch_last_pos  = null;

		this.#handlers.touchstart = (e) => {
			if (e.touches.length === 2) {
				touch_last_dist = this.#touchDist(e.touches);
				touch_last_pos  = null;
				e.preventDefault();
			} else if (e.touches.length === 1) {
				touch_last_pos  = {x: e.touches[0].clientX, y: e.touches[0].clientY};
				touch_last_dist = null;
			}
		};

		this.#handlers.touchmove = (e) => {
			if (e.touches.length === 2) {
				const dist = this.#touchDist(e.touches);
				const mid  = this.#touchMid(e.touches);
				if (touch_last_dist !== null && touch_last_dist > 0) {
					const pivot = this.#clientToSvg(mid.x, mid.y);
					this.#applyZoom(dist / touch_last_dist, pivot.x, pivot.y);
				}
				touch_last_dist = dist;
				e.preventDefault();
			} else if (e.touches.length === 1 && touch_last_pos !== null) {
				const dx   = e.touches[0].clientX - touch_last_pos.x;
				const dy   = e.touches[0].clientY - touch_last_pos.y;
				const rect = this.#svg_el.getBoundingClientRect();
				this.#vb_x -= dx * (this.#vb_w / rect.width);
				this.#vb_y -= dy * (this.#vb_h / rect.height);
				touch_last_pos = {x: e.touches[0].clientX, y: e.touches[0].clientY};
				this.#updateViewBox();
				e.preventDefault();
			}
		};

		this.#svg_el.addEventListener('touchstart', this.#handlers.touchstart, {passive: false});
		this.#svg_el.addEventListener('touchmove',  this.#handlers.touchmove,  {passive: false});

		// Zoom buttons (+, reset, -).
		this.#handlers.btn_click = (e) => {
			const btn = e.target.closest('[data-zoom-action]');
			if (!btn) return;
			e.stopPropagation();

			const cx = this.#vb_x + this.#vb_w / 2;
			const cy = this.#vb_y + this.#vb_h / 2;

			switch (btn.dataset.zoomAction) {
				case 'in':    this.#applyZoom(CMapZoom.ZOOM_FACTOR,     cx, cy); break;
				case 'out':   this.#applyZoom(1 / CMapZoom.ZOOM_FACTOR, cx, cy); break;
				case 'reset': this.reset(); break;
			}
		};
		this.#controls_el.addEventListener('click', this.#handlers.btn_click);

		// Keyboard shortcuts (+, -, 0) when the widget is hovered.
		this.#handlers.keydown = (e) => {
			if (!this.#container.matches(':hover')) return;
			const tag = document.activeElement?.tagName;
			if (tag === 'INPUT' || tag === 'TEXTAREA') return;

			const cx = this.#vb_x + this.#vb_w / 2;
			const cy = this.#vb_y + this.#vb_h / 2;

			if (e.key === '+' || e.key === '=') this.#applyZoom(CMapZoom.ZOOM_FACTOR,     cx, cy);
			if (e.key === '-' || e.key === '_') this.#applyZoom(1 / CMapZoom.ZOOM_FACTOR, cx, cy);
			if (e.key === '0')                  this.reset();
		};
		document.addEventListener('keydown', this.#handlers.keydown);
	}

	// -- Private helpers -------------------------------------------------------

	#clientToSvg(cx, cy) {
		const rect = this.#svg_el.getBoundingClientRect();
		return {
			x: (cx - rect.left) / rect.width  * this.#vb_w + this.#vb_x,
			y: (cy - rect.top)  / rect.height * this.#vb_h + this.#vb_y
		};
	}

	#applyZoom(factor, pivot_x, pivot_y) {
		const new_zoom      = Math.min(CMapZoom.MAX_ZOOM, Math.max(CMapZoom.MIN_ZOOM, this.#zoom * factor));
		const actual_factor = new_zoom / this.#zoom;
		this.#zoom = new_zoom;

		this.#vb_w = this.#orig_w / this.#zoom;
		this.#vb_h = this.#orig_h / this.#zoom;

		// Shift origin so the pivot stays at the same screen position.
		this.#vb_x = pivot_x - (pivot_x - this.#vb_x) / actual_factor;
		this.#vb_y = pivot_y - (pivot_y - this.#vb_y) / actual_factor;

		this.#updateViewBox();
	}

	#updateViewBox() {
		this.#svg_el.setAttribute('viewBox',
			`${this.#vb_x} ${this.#vb_y} ${this.#vb_w} ${this.#vb_h}`);
	}

	#touchDist(touches) {
		return Math.hypot(
			touches[0].clientX - touches[1].clientX,
			touches[0].clientY - touches[1].clientY
		);
	}

	#touchMid(touches) {
		return {
			x: (touches[0].clientX + touches[1].clientX) / 2,
			y: (touches[0].clientY + touches[1].clientY) / 2
		};
	}

	// -- Public API ------------------------------------------------------------

	reset() {
		this.#zoom = 1;
		this.#vb_x = 0;
		this.#vb_y = 0;
		this.#vb_w = this.#orig_w;
		this.#vb_h = this.#orig_h;
		this.#updateViewBox();
	}

	destroy() {
		this.#svg_el?.removeEventListener('wheel',      this.#handlers.wheel);
		this.#svg_el?.removeEventListener('mousedown',  this.#handlers.mousedown);
		this.#svg_el?.removeEventListener('click',      this.#handlers.click_capture, true);
		this.#svg_el?.removeEventListener('touchstart', this.#handlers.touchstart);
		this.#svg_el?.removeEventListener('touchmove',  this.#handlers.touchmove);
		document.removeEventListener('mousemove', this.#handlers.mousemove);
		document.removeEventListener('mouseup',   this.#handlers.mouseup);
		document.removeEventListener('keydown',   this.#handlers.keydown);
		this.#controls_el?.removeEventListener('click', this.#handlers.btn_click);
		this.#controls_el?.remove();
		this.#svg_el?.classList.remove('map-zoom-enabled', 'map-zoom-panning');
	}
}
"""

with open(dest, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"  Escrito: {dest}")
PYEOF

ok "Creado: class.map.zoom.js"

# ── 4. Parchear class.widget.js ───────────────────────────────────────────────
info "Parcheando: class.widget.js"

python3 - "$WIDGET_JS" << 'PYEOF'
import sys

path = sys.argv[1]

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

patches_applied = 0
errors = []

# ── Parche 1: agregar campo #map_zoom después de la declaración de #map_svg ───
OLD1 = (
    '\t/**\n'
    '\t * @type {SVGMap|null}\n'
    '\t */\n'
    '\t#map_svg = null;'
)
NEW1 = (
    '\t/**\n'
    '\t * @type {SVGMap|null}\n'
    '\t */\n'
    '\t#map_svg = null;\n'
    '\n'
    '\t/**\n'
    '\t * @type {CMapZoom|null}\n'
    '\t */\n'
    '\t#map_zoom = null;'
)

if '#map_zoom' in content:
    print("  [SKIP]  Parche 1: campo #map_zoom ya existe")
elif OLD1 in content:
    content = content.replace(OLD1, NEW1, 1)
    patches_applied += 1
    print("  [OK]    Parche 1: campo #map_zoom agregado")
else:
    errors.append("Parche 1: no se encontró el bloque de declaración de #map_svg.\n"
                  "           El archivo puede tener una versión diferente de Zabbix.")

# ── Parche 2: destroy en onClearContents ──────────────────────────────────────
OLD2 = (
    '\tonClearContents() {\n'
    '\t\tthis.#map_svg = null;\n'
    '\t}'
)
NEW2 = (
    '\tonClearContents() {\n'
    '\t\tthis.#map_zoom?.destroy();\n'
    '\t\tthis.#map_zoom = null;\n'
    '\t\tthis.#map_svg = null;\n'
    '\t}'
)

if 'this.#map_zoom?.destroy()' in content:
    print("  [SKIP]  Parche 2: destroy ya existe en onClearContents")
elif OLD2 in content:
    content = content.replace(OLD2, NEW2, 1)
    patches_applied += 1
    print("  [OK]    Parche 2: destroy() en onClearContents agregado")
else:
    errors.append("Parche 2: no se encontró el bloque onClearContents() esperado.")

# ── Parche 3: instanciar CMapZoom en #makeSvgMap ──────────────────────────────
OLD3 = (
    '\t\tthis.#map_svg = new SVGMap(options);\n'
    '\t}'
)
NEW3 = (
    '\t\tthis.#map_zoom?.destroy();\n'
    '\t\tthis.#map_svg = new SVGMap(options);\n'
    '\t\tthis.#map_zoom = new CMapZoom(this.#map_svg);\n'
    '\t}'
)

if 'new CMapZoom' in content:
    print("  [SKIP]  Parche 3: CMapZoom ya instanciado en #makeSvgMap")
elif OLD3 in content:
    # Reemplazar solo la ÚLTIMA ocurrencia (dentro de #makeSvgMap)
    idx = content.rfind(OLD3)
    content = content[:idx] + NEW3 + content[idx + len(OLD3):]
    patches_applied += 1
    print("  [OK]    Parche 3: instancia de CMapZoom en #makeSvgMap agregada")
else:
    errors.append("Parche 3: no se encontró 'this.#map_svg = new SVGMap(options);' en #makeSvgMap.")

if errors:
    for e in errors:
        print(f"  [ERROR] {e}", file=sys.stderr)
    sys.exit(1)

if patches_applied > 0:
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"  Guardado: {path}  ({patches_applied} parche(s) aplicado(s))")
else:
    print("  Sin cambios necesarios.")
PYEOF

ok "Parcheado: class.widget.js"

# ── 5. Parchear manifest.json ─────────────────────────────────────────────────
info "Parcheando: manifest.json"

if grep -q 'class.map.zoom.js' "$MANIFEST"; then
    warn "manifest.json ya contiene class.map.zoom.js — sin cambios"
else
    python3 - "$MANIFEST" << 'PYEOF'
import sys, json

path = sys.argv[1]

with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

assets_js = data.setdefault('assets', {}).setdefault('js', [])

if 'class.map.zoom.js' not in assets_js:
    assets_js.insert(0, 'class.map.zoom.js')

with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent='\t')
    f.write('\n')

print(f"  Guardado: {path}")
PYEOF
    ok "Parcheado: manifest.json"
fi

# ── 6. Resumen final ──────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══ Instalación completada ══${RESET}"
echo ""
echo -e "  ${GREEN}Archivos modificados:${RESET}"
echo "    • ${WIDGET_JS}"
echo "    • ${MANIFEST}"
echo ""
echo -e "  ${GREEN}Archivo creado:${RESET}"
echo "    • ${ZOOM_JS}"
echo ""
echo -e "  ${CYAN}Backups guardados en:${RESET} ${BACKUP_DIR}"
echo ""
echo -e "  ${YELLOW}Próximos pasos:${RESET}"
echo "    1. Recarga la página del dashboard en el navegador (Ctrl+Shift+R)"
echo "    2. Abre un mapa en el dashboard (Monitoring → Maps o widget de mapa)"
echo "    3. Usa scroll, botones +/⊙/− o arrastra para hacer zoom y pan"
echo ""
echo -e "  ${CYAN}Para desinstalar:${RESET}"
echo "    bash install.sh --uninstall --zabbix-dir ${ZABBIX_DIR}"
echo ""
