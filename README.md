# Zabbix Map Widget — Zoom & Pan

Agrega zoom interactivo y arrastre (pan) al widget de mapas de red de Zabbix
(**Monitoring → Maps** en el dashboard).

Compatible con **Zabbix 7.x**. No requiere librerías externas ni tocar la base de datos.

---

## Funcionalidades

| Interacción | Acción |
|---|---|
| Rueda del mouse | Zoom centrado en la posición del cursor |
| Botón `+` | Zoom in centrado en el mapa |
| Botón `−` | Zoom out centrado en el mapa |
| Botón `⊙` | Resetea al 100 % original |
| Clic + arrastrar | Pan (desplazamiento del mapa) |
| Pinch (táctil) | Zoom con dos dedos |
| Un dedo (táctil) | Pan táctil |
| Teclado `+` / `=` | Zoom in (cursor sobre el widget) |
| Teclado `-` / `_` | Zoom out (cursor sobre el widget) |
| Teclado `0` | Reset de zoom |

**Rango de zoom:** 20 % — 1000 %

---

## Requisitos

- Zabbix 7.x (frontend PHP en `/usr/share/zabbix` o ruta personalizada)
- `python3` disponible en el servidor
- Acceso root o permisos de escritura sobre el directorio del frontend

---

## Instalación rápida

```bash
# 1. Ir al directorio del script
cd /usr/share/zabbix/zabbix-map-zoom

# 2. Ejecutar el instalador
bash install.sh

# 3. Recargar el navegador con Ctrl+Shift+R
```

Si el frontend de Zabbix está en una ruta diferente:

```bash
bash install.sh --zabbix-dir /opt/zabbix/ui
```

---

## Desinstalación

```bash
bash install.sh --uninstall

# Con ruta personalizada:
bash install.sh --uninstall --zabbix-dir /opt/zabbix/ui
```

El script restaura automáticamente los archivos originales desde los backups
creados durante la instalación.

---

## Archivos que modifica el instalador

```
/usr/share/zabbix/widgets/map/
├── manifest.json                     ← agrega "class.map.zoom.js" a assets.js
├── assets/js/
│   ├── class.widget.js               ← 3 parches pequeños (ver abajo)
│   └── class.map.zoom.js             ← archivo NUEVO (clase CMapZoom)
└── .zoom-backup/                     ← backups automáticos (creados al instalar)
    ├── class.widget.js
    ├── manifest.json
    └── install.log
```

### Cambios exactos en `class.widget.js`

**Parche 1 — campo nuevo:**
```js
// Antes:
#map_svg = null;

// Después:
#map_svg = null;
#map_zoom = null;   // ← instancia de CMapZoom
```

**Parche 2 — limpieza en `onClearContents()`:**
```js
// Antes:
onClearContents() {
    this.#map_svg = null;
}

// Después:
onClearContents() {
    this.#map_zoom?.destroy();   // ← elimina listeners y botones
    this.#map_zoom = null;
    this.#map_svg = null;
}
```

**Parche 3 — instanciación en `#makeSvgMap()`:**
```js
// Antes:
this.#map_svg = new SVGMap(options);

// Después:
this.#map_zoom?.destroy();
this.#map_svg = new SVGMap(options);
this.#map_zoom = new CMapZoom(this.#map_svg);   // ← activa zoom
```

---

## Cómo funciona internamente

### Técnica: manipulación del `viewBox` del SVG

El mapa en el dashboard usa `useViewBox = true`, lo que significa que el SVG
renderiza con `viewBox="0 0 W H"`. El zoom se implementa modificando ese
atributo dinámicamente:

```
zoom in  →  viewBox más pequeño  →  el contenido se ve más grande
zoom out →  viewBox más grande   →  el contenido se ve más pequeño
pan      →  desplaza el origen del viewBox
```

**Por qué esta técnica es la correcta:**

| Alternativa | Problema |
|---|---|
| `CSS transform: scale()` | Desalinea la posición de los tooltips y menús contextuales |
| `CSS zoom` | No estándar en todos los navegadores, mismo problema de offsets |
| Librería panzoom | Dependencia externa, puede romper actualizaciones |
| **Modificar viewBox** | Nativo SVG, todos los eventos siguen en sus coordenadas correctas ✓ |

### Compatibilidad con eventos SVG

El SVG maneja `click`, `mouseover`, `mouseout` y `data-menu-popup` sobre las
**coordenadas del viewBox**, no sobre píxeles de pantalla. Al modificar el
viewBox:

- Los clics en hosts/elementos funcionan igual
- Los tooltips y menús contextuales se posicionan correctamente
- Los cursores `pointer` de los elementos interactivos se respetan

### Distinción click vs drag

Para no bloquear los menús contextuales al arrastrar, se usa un umbral de 5 px:

```
mousedown → mousemove < 5px → mouseup = CLICK normal (menú se abre)
mousedown → mousemove ≥ 5px → mouseup = DRAG (menú bloqueado en fase capture)
```

### Lifecycle y memoria

```
Widget carga mapa
  └─ #makeSvgMap()
       ├─ new SVGMap(options)      ← SVG renderizado
       └─ new CMapZoom(svg_map)    ← zoom activo

Widget recarga mapa (navegación a submapa, refresh)
  └─ #makeSvgMap()
       ├─ map_zoom.destroy()       ← listeners/botones eliminados
       ├─ new SVGMap(options)      ← nuevo SVG
       └─ new CMapZoom(svg_map)    ← zoom activo de nuevo

Widget destruido / clearContents()
  └─ map_zoom.destroy()           ← limpieza completa, sin memory leaks
```

---

## Personalización

Los parámetros del zoom se pueden ajustar en `class.map.zoom.js`:

```js
static MIN_ZOOM    = 0.2;   // Zoom mínimo (20 %)
static MAX_ZOOM    = 10;    // Zoom máximo (1000 %)
static ZOOM_FACTOR = 1.3;   // Factor por paso (30 % más/menos)
static PAN_THRESHOLD = 5;   // Píxeles para distinguir click de drag
```

Los estilos de los botones se inyectan via `<style id="map-zoom-styles">` en
el `<head>` del documento. Se pueden sobreescribir con CSS más específico sin
tocar el archivo JS.

---

## Solución de problemas

### El zoom no aparece después de instalar

1. Verifica que el script terminó sin errores
2. Haz **hard refresh** en el navegador: `Ctrl+Shift+R` (o `Cmd+Shift+R` en Mac)
3. Si Zabbix usa caché de assets, limpia la caché del servidor:
   ```bash
   # Nginx / Apache generalmente no cachean assets JS de Zabbix
   # Si usas un proxy reverso como Varnish, purga la caché
   ```
4. Comprueba la consola del navegador (F12) buscando errores de JavaScript

### El script dice "parche no encontrado"

Esto ocurre cuando la versión de `class.widget.js` difiere de la esperada.
Significa que Zabbix fue actualizado y los patrones de texto cambiaron.

Solución manual: aplica los 3 cambios de la sección **"Cambios exactos"** arriba
usando el editor que prefieras.

### Los clics en hosts dejan de funcionar

No debería ocurrir con esta implementación. Si sucede:

1. Desinstala con `bash install.sh --uninstall`
2. Verifica la versión de Zabbix con `grep ZABBIX_VERSION /usr/share/zabbix/include/defines.inc.php`
3. Reporta el problema indicando la versión exacta

### El arrastrar abre el menú contextual

El umbral de drag está en 5 px (`PAN_THRESHOLD`). En pantallas táctiles de alta
densidad puede necesitar ajuste. Edita `class.map.zoom.js` y aumenta el valor:

```js
static PAN_THRESHOLD = 10;  // más permisivo en touch
```

---

## Compatibilidad de versiones

| Zabbix | Estado |
|---|---|
| 7.0.x | Probado ✓ |
| 7.2.x | Probado ✓ |
| 6.x   | No soportado (arquitectura de widgets diferente) |

---

## Estructura del repositorio

```
zabbix-map-zoom/
├── install.sh    ← script de instalación/desinstalación
└── README.md     ← esta documentación
```

El archivo `class.map.zoom.js` se genera en el momento de la instalación
dentro del directorio del widget de Zabbix.
