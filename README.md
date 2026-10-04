# DuoLid

App de barra de menús para macOS que recrea en un MacBook el efecto de transición del iPhone Duo al
abrir y cerrar la tapa: la pantalla se desenfoca y se oscurece a medida que la cierras, y se enfoca
al abrirla. La intensidad sigue en tiempo real al ángulo de la tapa, leído del sensor del propio Mac.

- El desenfoque es progresivo en el espacio: nace en la bisagra y crece hacia el borde superior.
  El contenido no se escala ni se mueve; solo se emborrona y se funde a negro.
- El negro avanza al doble de ritmo que el desenfoque: el borde superior llega a negro primero, y
  en el último tramo (≈33° → 12°) toda la pantalla se funde a negro opaco.
- Tapa abierta (≥ 100°): efecto invisible y ventana oculta (no gasta GPU). Al abrir, el recorrido es
  el inverso.

## Requisitos

- macOS 14 o posterior.
- Un MacBook con sensor de ángulo de tapa: MacBook Air M2 o posterior, MacBook Pro de 14"/16" (y el
  16" de 2019). Los M1 y los MacBook Pro de 13" no lo exponen. Sin sensor, la app usa un respaldo:
  al encenderse la pantalla anima de desenfocado a nítido en 0,6 s.
- Command Line Tools de Xcode (`xcode-select --install`) o Xcode.

## Compilar y ejecutar

```bash
scripts/build-app.sh             # crea build/DuoLid.app
scripts/build-app.sh --install   # además la copia a /Applications y la abre
open build/DuoLid.app            # o ejecutarla sin instalar
```

Para desarrollo también vale `swift build` / `swift run DuoLid`, y los tests con `scripts/test.sh`.

> **Nota:** con SwiftPM 6.4 y solo las Command Line Tools (sin Xcode), el sistema de compilación por
> defecto falla con `Unknown error parsing property list`. Los scripts lo detectan y usan
> `--build-system native`; si compilas a mano, añade esa opción (`swift build --build-system native`).

## Uso

Haz clic en el icono del portátil de la barra de menús:

| Control | Qué hace |
|---|---|
| **Desactivar / Activar efecto** | Apaga o enciende el efecto al momento. También con **⌃⌥⌘D** desde cualquier app. |
| Intensidad | Multiplica el desenfoque y el oscurecimiento (0–100 %). |
| Iniciar al arrancar sesión | Registra la app como ítem de inicio (`SMAppService`). |
| Panel de ajuste… | Ajustes finos y simulación del ángulo (ver abajo). |
| Salir | Cierra la app (⌘Q). |

### Panel de ajuste

Permite ajustar el efecto sin mover la tapa: un slider de **ángulo simulado**, un botón que reproduce
un cierre y apertura (con lecturas a 10 Hz como el sensor real), y los parámetros del efecto:
desenfoque máximo (hasta 72 pt), oscurecimiento máximo, exponente del degradado (cómo de deprisa
crece el efecto desde la bisagra), ritmo del oscurecimiento respecto al desenfoque, efecto mínimo en
la bisagra, *Invertir dirección del gradiente*, ángulo de efecto máximo (12°) y ángulo a partir del
cual es invisible (100°). Si sueles trabajar con la pantalla por debajo de 100°, baja este último. Al
cerrar el panel vuelve a mandar el sensor real.

Argumentos de línea de comandos para pruebas:

```bash
open build/DuoLid.app --args --tuning               # abre el panel al arrancar
open build/DuoLid.app --args --simulate-angle 40    # simula la tapa a 40° (cierra el panel para volver al sensor)
open build/DuoLid.app --args --no-sensor            # fuerza el respaldo de "pantalla encendida"
```

## Permisos

- **Sensor de la tapa:** ninguno. Se lee por IOKit/HID sin Monitorización de entrada.
- **Desenfoque:** ninguno. No captura la pantalla (no pide Grabación de pantalla): el servidor de
  ventanas desenfoca lo que hay detrás de la ventana del efecto.
- **Atajo ⌃⌥⌘D:** ninguno (usa `RegisterEventHotKey`, no requiere Accesibilidad).
- **Iniciar al arrancar sesión:** macOS puede pedir que lo apruebes en *Ajustes del Sistema → General →
  Ítems de inicio*; la app muestra un enlace si hace falta. Solo funciona con `DuoLid.app`, no con
  `swift run`.
- La app está firmada ad hoc. Si la descargas compilada en otro Mac, Gatekeeper puede bloquearla:
  compílala tú mismo o ábrela con clic derecho → Abrir.

> El desenfoque usa APIs privadas de Core Animation: un `CABackdropLayer` propio (la capa que usa
> `NSVisualEffectView` por dentro) con el filtro `variableBlur`, cuyo radio en cada punto es
> `radio × máscara`. Se cargan en tiempo de ejecución. Si faltan en una versión futura de macOS, la
> app pasa a `CGSSetWindowBackgroundBlurRadius` (desenfoque uniforme) y, si tampoco está, a
> `NSVisualEffectView` (desenfoque fijo que se funde). El log (`log show --predicate 'subsystem ==
> "DuoLid"'`) dice cuál está activo. Por usar APIs privadas, la app no es apta para la Mac App Store.

## Cómo funciona

**Sensor.** El sensor (`las`) es un dispositivo HID del coprocesador de sensores: VendorID `0x05AC`,
ProductID `0x8104`, UsagePage `0x0020` (Sensor), Usage `0x008A` (Orientation). El ángulo en grados
es un `UInt16` little-endian en los bytes 1–2 del *feature report* 1. Método tomado de
[LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) de Sam Gold.

Medido en un MacBook Air 13" M4 (`Mac16,12`) con [`Tools/lid-angle-probe.swift`](Tools/lid-angle-probe.swift):

| | |
|---|---|
| Rango | 0°–111° en el uso medido |
| Frecuencia de actualización del sensor | ~10 Hz (resolución de 1°) |
| Saltos entre lecturas con la tapa rápida | 10–14° |
| Coste de una lectura | ~0,16 ms de CPU |
| Input reports espontáneos | solo un latido de 1 Hz → hay que hacer polling |
| Apagado de pantalla | cerca de 0° (después de pasar por 11°, 8°, 6° y 3°) |

**Lectura.** `LidAngleSensor` consulta el sensor en una cola propia: a 60 Hz mientras la tapa se
mueve y a 10 Hz cuando lleva un segundo quieta (~0,4 % de CPU en reposo). Si deja de responder
(p. ej. tras un reposo), vuelve a buscar el dispositivo.

**Suavizado.** `AngleSmoother` convierte los escalones de 10 Hz en movimiento continuo a la frecuencia
de la pantalla: entre lecturas extrapola con la última velocidad medida (como mucho 100 ms) y un
muelle críticamente amortiguado (respuesta 0,15 s) sigue a ese objetivo sin rebotes. Con la tapa a
90°/s, la animación avanza 1,5° por fotograma en vez de saltar 9° cada seis.

**Efecto.** `EffectCurve` convierte el ángulo en progreso `p` (smoothstep entre 12° y 100°) y
`SpatialEffect` lo reparte por la pantalla según la altura `g` respecto a la bisagra:
desenfoque `= radio · p · peso(g)` y negro `= max(min(1, 2 · p · peso(g)), fundido final)`, con
`peso(g) = (0,05 + 0,95 · g)^1,35`. Una ventana sin bordes por pantalla integrada, en el nivel
`screenSaver`, transparente a los clics y en todos los Escritorios, desenfoca lo que hay detrás
con una máscara generada una vez y pinta encima un degradado negro de 16 paradas. Por fotograma
solo cambian el radio y los 16 alfas. Un `CADisplayLink` solo corre mientras hay algo que animar.

### Diagnóstico del sensor

```bash
swift Tools/lid-angle-probe.swift 30   # imprime el ángulo durante 30 s mientras mueves la tapa
```

Lista los sensores HID del coprocesador, abre el de la tapa y muestra cada cambio de ángulo, la
latencia de lectura y si el dispositivo envía datos por su cuenta. Útil si la app dice "Sin sensor".

## Estructura

```
Package.swift
Sources/DuoLidCore/        lógica sin interfaz (probada con swift test)
  LidAngleSensor.swift     lectura del sensor por IOKit/HID
  AngleSmoother.swift      predicción + muelle entre lecturas
  EffectCurve.swift        ángulo → intensidad
  SpatialEffect.swift      intensidad → blur y negro según la altura respecto a la bisagra
Sources/DuoLid/            app (SwiftUI + AppKit)
  DuoLidApp.swift          MenuBarExtra y AppDelegate
  AppModel.swift           une ajustes, motor, atajo y panel
  EffectEngine.swift       bucle de animación, sensor / respaldo al despertar
  OverlayWindow.swift      ventana del efecto y desenfoque
  VariableBlur.swift       CABackdropLayer + variableBlur y su máscara
  MenuContentView.swift    menú de la barra
  TuningPanel.swift        panel de ajuste con ángulo simulado
  GlobalHotKey.swift       atajo ⌃⌥⌘D
  LoginItem.swift          iniciar al arrancar sesión
  Settings.swift           ajustes persistentes
Resources/Info.plist       LSUIElement = true (sin icono en el Dock)
scripts/                   build-app.sh, test.sh
Tools/lid-angle-probe.swift
```

## Créditos

La lectura del sensor se basa en el trabajo de ingeniería inversa de
[samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor).
