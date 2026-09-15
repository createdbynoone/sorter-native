# Sorter Native — Generation Triage (SwiftUI)

Port nativo (Swift 5 / SwiftUI, macOS 14+) de la app Electron en `../Sorter`, con la misma configuración de diseño que `../BMP Native` (controles nativos, paleta cálida-oscura, acento naranja `#F54F1B`, logo Brotherhood al inicio).

**Proyecto:** XcodeGen → `xcodegen generate` produce `Sorter.xcodeproj` (no se commitea; regenerar al agregar archivos).
**Build:** `xcodebuild -project Sorter.xcodeproj -scheme Sorter -configuration Debug -derivedDataPath build/DerivedData build` · o abrir en Xcode y ⌘R.
**Bundle id:** `com.brotherhood.sorter.native` (convive con la .app Electron).

## Estructura
```
Sorter/App/       SorterApp (entry, menú Triage, Settings scene), AppModel (@Observable: filtros, selección, focus, grupos), Types
Sorter/Core/      Store (DB JSON + reconcile + categorías), Paths/Prefs, Lock (PBKDF2), Thumbs (CGImageSource + AVAssetImageGenerator), Watcher (DispatchSource), Exporter (cover-crop 1080×1080 / 1080×1920) + Trash
Sorter/UI/        Theme, Components (Logo/Splash, MediaCard, GridView, InspectorView, Controls), Screens (MainView, FocusView, Sheets, LockScreen)
```

## Compatibilidad con la app Electron
- Lee/escribe el MISMO `~/Library/Application Support/Sorter/sorter-db.json` (entries + categories, timestamps en ms) y `sorter-prefs.json` (`unlockedAt` → el lock es de primer arranque, igual que Electron; `gridSize`/`inspectorOpen` son nuevos). Library de drops compartida (`library/`).
- Carpeta vigilada = `outputPath` de `~/Library/Application Support/bmp/bmp-prefs.json`, fallback `~/Desktop`; patrón `bmp_*.{jpg,png,webp,mp4,mov,webm}`.
- Thumbs propios en `thumbs-native/` (400px JPEG keyed por fingerprint) — la caché Electron usa otro hash, no vale la pena compartirla.
- Lock: PBKDF2-SHA512 200k iter, misma passphrase, salt/hash propios en `Lock.swift`.

## Comportamiento
- Tipografía: SF Pro para toda la UI (jerarquía por peso/color); SF Mono solo para datos reales (rutas, nombres de archivo); números en prosa con `.monospacedDigit()`; `Theme.caption` para metadata. Sin guiones largos en cadenas visibles.
- Grid `LazyVGrid` adaptativo (120–400 px, `[` `]`), agrupado por categoría → producto solo en **All** sin búsqueda; headers colapsables.
- Selección: click / ⌘click / ⇧click (rango desde el anchor), ⌘A, Esc. **Marquee** (drag-select desde un hueco del grid, ⇧/⌘ suma a la selección): `MarqueeCatcher` en `GridView` es un `NSView` bajo el contenido con un `NSEvent.addLocalMonitorForEvents` — el `NSHostingView` se queda los `mouseDown` porque el grid es `.focusable()`, así que no sirve `DragGesture` ni el responder chain. Excluye toolbar (`window.contentLayoutRect`), cards (frames vía `CardFramesKey`) y el overlay del inspector (`InspectorOverlay.reservedWidth`).
- Teclas con el grid enfocado: K M D U A (status, aplica a toda la selección), F/↩ focus, N nota, R reveal, I inspector, flechas navegan.
- **Inspector flotante** (`InspectorOverlay`, overlay top-trailing sobre grid y focus, como Electron): panel casi opaco (`Theme.surface` 94 % sobre `.thinMaterial`, sin glass — el glass dejaba sangrar las imágenes) + botón flotante para contraer/expandir. Estado, nota (autosave 400 ms), categoría + producto (radio en cada nivel, `+` para crear, click derecho renombrar/borrar).
- **Focus**: imagen con zoom (rueda, pinch, doble click) y pan; video con `VideoPlayer`; ← → espacio navegan; status auto-avanza; E exporta.
- Drag-out nativo desde una card entrega el archivo ORIGINAL (`.onDrag` con la URL) a Finder/BMP.
- Drop de archivos/carpetas al grid → `importPaths` (copia a library si no están en la carpeta vigilada).
- Trash discarded: `FileManager.trashItem` (papelera del volumen correcto), confirmación nativa, ⌘⌫.
- Export: cover-crop con CoreGraphics, JPEG 95 %, `NSOpenPanel` para destino, revela el primero en Finder. Sin watermark (igual que Electron hoy).

## Lo que NO está (vs Electron)
- Auto-update, selector de ícono del Dock, marquee de selección, rating (el campo se conserva en el JSON pero no hay UI).

## Rendimiento (v2.0.1)
- **Listas derivadas memoizadas**: `filtered`, `grouped`, `counts`, `statusCounts` se leen 6–10 veces por render (grid, focus, toolbar, footer, teclas). Se cachean en `AppModel` (`@ObservationIgnored`) con clave `(store.revision, filter, sort, search)`; `Store.revision` sube en cada mutación vía `touch()`. Toda mutación nueva del Store debe pasar por `touch()`, no por `scheduleFlush()`.
- `Store.flush()` hace snapshot del `SorterDB` (value type) y codifica/escribe en la cola serial `sorter.store.io`; `flushSync()` en `applicationWillTerminate`.
- **Nada de `repeatForever` en SwiftUI**: 34 cards "missing" con `Pulse` infinito = ~45 % CPU permanente. El placeholder es `PulseDot` (CABasicAnimation, `Controls.swift`) y solo mientras carga; si la carga falla, glifo estático (`loaded` en `MediaCard`).
- `Thumbs`: `NSCache` por bytes (`totalCostLimit` 160 MB, cost = bytesPerRow × height) en vez de `countLimit` 600 (≈480 MB posibles). Los JPEG de `thumbs-native/` se decodifican con `CGImageSource` fuera de main (antes `NSImage(contentsOf:)` decodificaba en main al primer draw). `load` respeta `Task.isCancelled` al scrollear.
- Focus: `Thumbs.full` decodifica off-main con tope 4096 px (un drop de 8K no reserva ~250 MB); `onDisappear` pausa y suelta el `AVPlayer` y la imagen.
- `LockScreen`: tick de 250 ms solo durante lockout. `DEAD_CODE_STRIPPING: YES`.
- Para medir: `ps -o rss=,time=,%cpu= -p <pid>` a intervalos (el `time` acumulado debe quedarse plano en reposo); `sample <pid> 3` si sube.
