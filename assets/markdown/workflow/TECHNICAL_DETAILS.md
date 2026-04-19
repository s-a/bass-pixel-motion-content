# Workflow Technical Details

Dieses Dokument definiert die technischen Randbedingungen, Runtime-Contracts und Projekt-Architekturen fuer die Bass Pixel Motion Engine (`bpm.exe`). Es dient als primäre technische Referenz für LLM-Agents.

## Source Of Truth Matrix

| Frage | Bindende Quelle |
|---|---|
| Welche Manifest-Felder sind erlaubt? | `schema/scene-shader-manifest.schema.v1.json` |
| Welche Projekt-Felder sind erlaubt? | `schema/project-file-definition.v1.schema.json` |
| Welche Video-FX-Felder sind erlaubt? | Konkrete Datei in `video-fx/*.v1.jsonc` |
| Welche Audio-Feature-IDs sind erlaubt?| `registry/feature-params.jsonc` |
| Reihenfolge Audio-Signale Shader | `audio_sources` im Manifest |
| Reihenfolge der `scene.params` | `mapping_targets` oder `params_schema` (automatisch via `#color` oder `#gui_param` Makro) |
| Exaktes `SceneUniform` Layout | Runtime-Contract plus funktionierende Referenzshader (`calibration.wgsl`) |
| Kanonische Projekt-Referenz | `calibration.projekt.jsonc` |
| Bindung von Shader, Manifest, Song | `<name>.projekt.jsonc` |

## Project Model

Ein vollstaendiges BPM-Projekt besteht aus genau drei Dateien im Content-Repository (mit identischem `<name>`):
1. `<name>.manifest.jsonc`: Deklariert Shader-Audio-Quellen, Assets und UI-Mapping-Targets.
2. `<name>.wgsl`: WGSL-Fragment-Shader.
3. `<name>.projekt.jsonc`: Projekt-Instanz (Song, Audio-Settings und Video-FX-Kette).

## Workspace And Asset Rules

- **.tmp/**: Ausschliesslich fuer temporaere Pruef- und Debug-Artefakte (z.B. Frame-Exporte, Logs, Debug-JSON). Finale Dateien gehoeren ins Root.
- **Asset Locations**: `\assets\audio\`, `\assets\font\`, `\assets\glb\`, `\assets\image\`, `\assets\obj\`
- **Lizenzen**: Assets benoetigen eine beigelegte Lizenzdatei (z.B. `LICENSE`, `OFL.txt`).

## Runtime Contracts

### Path Contract
- `scene.shader` in Projekt referenziert `.wgsl`.
- Gleichnamiges Manifest-Sidecar muss vorliegen.
- `entry` im Manifest zeigt auf `.wgsl`.

### Coordinate System Contract
In der WebGPU-Engine gilt fuer alle Layout-Berechnungen (Typografie, Custom-Layouts):
- **Y=0 ist UNTEN**: Y waechst nach OBEN. (`scene.resolution.y` ist die Decke).
- **X=0 ist LINKS**: X waechst nach RECHTS.

### Audio Analysis Contract
- Die Engine analysiert nur deklarierte `audio_sources` (Manifest) bzw. `audio.*`-Mappings.
- Die Reihenfolge von `audio_sources` definiert den Index in `scene.audio_scalars` im Shader.
- `audio_history_samples`: Auf `32` setzen fuer Verlaufsdaten. Ohne angeforderte Analysen bleiben Livedaten auf 0.

**Empfohlene Audiosignalisierung:**
- *Basis:* `full`, `low`, `mid`, `high`, `rms`, `peak`
- *Dynamik/Rhythmus:* `envelope_slow/fast`, `onset`, `beat`, `beat_phase`, `bar_phase`
- *Stimmung:* `calm`, `driving`, `peak`
- *Spektral/Struktur:* `brightness`, `tension`, `build_up`, `drop`, `impact`

### Mapping Targets Contract
- Steuert die Belegung von `scene._raw_params_do_not_use` in Scene Shadern und `params.slots` in Video-FX Shadern.
- Die maximale Kapazität für Post-FX / Video-FX Parameter beträgt **32 Slots** (Index 0 bis 31). Die Slot-Reihenfolge wird ausschließlich durch die Reihenfolge der Einträge in `params_schema` bestimmt. Definitionen, die dieses Limit überschreiten, werden von der Engine-Validierung blockiert.
- Unabhaengig von `audio_sources`! Modifiziere die Reihenfolge nicht unbedacht.
- **Farben werden ausschliesslich ueber das `#color` Makro angefordert** — manuelle Index-Nummern sind verboten.
- **GUI-Parameter (Zahlen/Vektoren) werden ueber das `#gui_param` Makro angefordert** — manuelle Index-Nummern (`params.slots[0]`) sind verboten. Die Engine loest den Target-Namen zur Compile-Zeit auf und blockiert rohe Array-Zugriffe mit dem "Anti-Index Guard".
- **Farbrollen (`x-bpm-color-role`):** Wenn Farb-Targets im Manifest deklariert werden, muss eine der folgenden semantischen Rollen zugewiesen werden: `dominant`, `vibrant`, `muted`, `dark-vibrant`, `dark-muted`, `light-vibrant`, `light-muted`.
- **Property Naming & Kategorisierung**: UI-Labels in Manifest-Files (`name` in video-fx oder implizites Label) muessen _strikt clean_ sein. Keine redundanten Praefixe im Stile von `Scene / Pressure Depth` oder `Settings / Speed` als Name verwenden. Alle Parameter gehoeren per Definition zur Scene. Nutze das `category` Feld im JSON (oder entsprechende Gruppierungen) zur logischen Organisation in der UI, bezeichne den Parameter aber kurz und praegnant (z. B. `category: "Environment"`, Target-Suffix `pressure_depth` -> was logischerweise zu *Pressure Depth* fuehrt).

### Parameter Orthogonality Contract (Atomic Control)
- **Ein Parameter = Eine exakte Wirkung:** Jeder in der GUI veroeffentlichte Parameter (aus der Manifest-Datei) muss strikt entkoppelt von anderen Systemen arbeiten (kein "Cross-Coupling").
  - **Keine mathematische Kreuzverschmutzung:** Parameter wie `cam_speed` duerfen beispielsweise keinen morphing-artigen Einfluss auf prozedurale Geometrieverschiebungen wie `terrain_scale` oder Noise-Outputs haben.
  - **SDF CORE LAWS (FOR LLMs):**
    1. **map() IS STATIC:** NEVER inject `#audio`, dynamic properties, or `time * speed` offsets into `map()`. Physical geometry MUST be evaluated as camera-relative (`p_rel`). Attempting to add audio beats or speed jumps to the distance field breaks Lipschitz continuity, causing pulsating artifacts and scale-dragging.
    2. **fs_main() IS DYNAMIC:** ALL audio-reactivity, rhythmic glowing, and scrolling speed MUST be evaluated exclusively in the fragment shader as optical illusions (texture offsets, emission arrays).
    3. **CAMERA FLIGHT MUST BE BELIEVABLE:** Camera trajectory (+Z forward motion) must remain believable. It MUST NEVER fly through physical walls or geometry. It MUST NEVER be jittered/teleported rhythmically by `#audio` signals.

### Render Stability & Glitch Prevention (CRITICAL)
Alle Terrains, Waende, festen Geometrien und Raymarching-Strukturen muessen in WebGPU absolute **Sicht- und Rendering-Stabilitaet** aufweisen. Dies betrifft ALLE Shader (File-Migrations, Scratch-Entwicklungen, etc). **Grundsätzlich gilt: Glitches, flimmernde Kanten und zittrige Geometrien verstören den Betrachter und zerstören sofort die visuelle Illusion. Das muss zwingend verhindert werden.**
- **Verbot von Flimmern/Flickern:** Aliasing-Artefakte an Kanten oder Moiree-Muster in entfernten Rastern muessen drastisch durch saubere Normalenberechnungen oder Depth-Fog kompensiert werden. Hohe Frequenzen in `smoothstep`, Noise oder Texturen muessen mit zunehmender Distanz oder auf Basis der Bildschirmaufloesung gedaempft werden.
- **Unterschied zwischen Glitch & gewollter Deformation:** Unbeabsichtigtes Zertruemmern oder Zittern von _festen_ Architekturen (wie Waenden oder Boeden) ist ein Bug und absolut verboten. **Gewollte Deformationen** (Fluessigkeiten, Audio-verzerrte Energiewellen, explizite "Glitch"-Video-FX) sind hingegegen ein voellig valides kuenstlerisches Mittel. Der Agent muss klar trennen: Ist das Objekt starr konzipiert, oder ist es prozedurales Plasma, das sich dynamisch deformieren soll?
- **Precision Loss zwingend vermeiden:** Nutze ausschliesslich Camera-Relative Berechnungen (z.B. Domain Repitition via `fract()`), wenn du endlose Korridore oder weite Landschaften renderst. Lass die Koordinaten *nicht* unendlich wachsen (`p.z += scene.time * 50.0`), sondern loese den Loop durch zyklische Wraps oder Modulo-Arithmetik im Weltraum auf (`p.z = fract(...)`), um Floating-Point Ungenauigkeiten und daraus resultierendes "Zappeln" nach langen Laufzeiten bei stabilen Strukturen zu unterbinden.
- Vergewissere dich in Raymarchern durch iterative Tests und angemessene Halbschritte (`t_ray += d * 0.5`), dass organische SDFs (wie 3D-Noise) nicht uebersprungen werden, was fehlerhafte Loecher oder flackernde Polygone provoziert.

### Video-FX Params Schema Contract
- `params_schema` in Video-FX-Definitionen ist eine geordnete Array-Liste von Param-Objekten mit mindestens `name`, `type` und `default`.
- Die Reihenfolge der Eintraege in `params_schema` definiert die interne Slot-Reihenfolge.
- Projektwerte bleiben namensbasiert: `scene_video_fx[].params` ist ein JSON-Objekt mit `name -> value`.
- `name` ist die technische Identitaet des Parameters. Ein Rename ist breaking fuer Projektdateien und Shader-Referenzen.
- Die bindende Definition steht in [schema/video-fx-definition.schema.v1.json](/C:/git/ubuntu/bpm/bass-pixel-motion-content/schema/video-fx-definition.schema.v1.json).

### FluxFlow Contract

`FluxFlow` ist der generische stateful GPU-Systempfad fuer die BPM-Engine. Er erweitert das bisherige stateless Fullscreen-Modell um persistente GPU-Zustaende ueber Frames hinweg.

Ein `FluxFlow`-faehiges Manifest (`scene-shader` oder `video-fx`) deklariert optional einen `flux_flow` Block mit:
- `capacity`
- `geometry`
- `state`
- `stages`

Der Block beschreibt:
- wie viele Instanzen/Zustaende parallel existieren
- welches Render-Geometriemodell genutzt wird
- wie der persistente Zustand layoutet ist
- welche Shader-Einstiegspunkte fuer `init`, `update`, `render_vertex` und `render_fragment` verwendet werden

**Grundidee:**
- `init`: initialisiert Zustand auf der GPU
- `update`: schreibt den naechsten Zustand auf der GPU
- `render`: zeichnet aus dem aktuellen Zustand

`FluxFlow` ist generisch und nicht auf klassische Partikel beschraenkt. Es kann fuer stateful GPU-Systeme wie Partikel, Trails, Agenten, Schwarmfelder oder andere zeitbasierte Simulationen genutzt werden.

### FluxFlow Scene Shader Contract

`scene-shader` Manifeste duerfen in v1 ebenfalls einen `flux_flow` Block definieren.

Wenn ein `scene-shader` `flux_flow` nutzt, gilt:
- der Scene-Renderpfad wird nicht ueber klassisches `vs_main`/`fs_main` ausgefuehrt
- stattdessen verwendet die Engine die deklarierten `init`, `update`, `render_vertex` und `render_fragment` Stages
- der Shader wird mit dem `FluxFlow` Kernel-ABI komponiert, damit `#color` und `#audio` genauso nutzbar bleiben wie in FluxFlow-Post-FX

Wichtige Exklusivitaetsregel:
- Ein `scene-shader` darf **entweder** klassischer Scene-Shader **oder** `FluxFlow`-Scene-Shader sein.
- Ein Scene-Manifest darf `flux_flow` nicht mit klassischem `vs_main`/`fs_main` mischen.
- `passes` und `resource_inputs` werden durch diese Freischaltung fuer Scene-Shader **nicht automatisch** aktiviert.

### FluxFlow Multi-Stage Contract

Mehrere `FluxFlow`-Stufen in einem einzelnen Frame sind erlaubt.

Typischer Ablauf:
1. Scene-`FluxFlow` rendert die Szene.
2. Danach darf eine normale Post-FX-Kette laufen.
3. Innerhalb dieser Kette duerfen erneut `FluxFlow`-basierte Post-FX vorkommen.

Verbindlich dabei:
- jede `FluxFlow`-Stufe besitzt ihren **eigenen** GPU-State
- keine Stufe teilt Ping-Pong-Buffer, Uniform-Buffer oder Reinit-Zyklen mit einer anderen
- ein nachgelagerter `FluxFlow`-Post-FX verarbeitet nur das gerenderte Bild der vorherigen Stufe, **nicht** deren internen Simulationszustand

**Minimales Manifest-Beispiel:**
```jsonc
{
  "kind": "video-fx",
  "id": "minimal_flux_flow",
  "version": 1,
  "entry": "minimal_flux_flow.v1.wgsl",
  "video_targets": ["post"],
  "flux_flow": {
    "capacity": 1024,
    "geometry": { "kind": "billboard" },
    "state": {
      "fields": [
        { "name": "pos_age", "type": "vec4" },
        { "name": "style", "type": "vec4" }
      ]
    },
    "stages": {
      "init": "ff_init",
      "update": "ff_update",
      "render_vertex": "ff_vs",
      "render_fragment": "ff_fs"
    }
  }
}
```

**Minimales WGSL-Skelett:**
```wgsl
#import <engine::bpm_kernel_bindings>

struct ParticleState {
  pos_age: vec4<f32>,
  style: vec4<f32>,
}

struct RenderOut {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
}

@group(0) @binding(1)
var<storage, read> state_in: array<ParticleState>;

@group(0) @binding(2)
var<storage, read_write> state_out: array<ParticleState>;

@compute @workgroup_size(64)
fn ff_init(@builtin(global_invocation_id) gid: vec3<u32>) {
  let index = gid.x;
  if (index >= u32(params.runtime_meta.x)) {
    return;
  }
  let x = fract(f32(index) * 0.6180339);
  state_out[index] = ParticleState(
    vec4<f32>(x, 1.2, 0.0, 0.0),
    vec4<f32>(1.0, 1.0, 0.0, 0.0),
  );
}

@compute @workgroup_size(64)
fn ff_update(@builtin(global_invocation_id) gid: vec3<u32>) {
  let index = gid.x;
  if (index >= u32(params.runtime_meta.x)) {
    return;
  }
  var p = state_in[index];
  p.pos_age.y = p.pos_age.y - params.runtime_meta.w * 0.2;
  if (p.pos_age.y < -0.2) {
    p.pos_age.y = 1.2;
  }
  state_out[index] = p;
}

@vertex
fn ff_vs(
  @builtin(vertex_index) vertex_index: u32,
  @builtin(instance_index) instance_index: u32,
) -> RenderOut {
  let p = state_in[instance_index];
  var quad = array<vec2<f32>, 6>(
    vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(1.0, 1.0),
    vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, 1.0), vec2<f32>(-1.0, 1.0),
  );
  var uv = array<vec2<f32>, 6>(
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 1.0), vec2<f32>(1.0, 0.0),
    vec2<f32>(0.0, 1.0), vec2<f32>(1.0, 0.0), vec2<f32>(0.0, 0.0),
  );
  let aspect = params.texel_size.y / max(params.texel_size.x, 0.000001);
  let local = quad[vertex_index] * 0.01;
  var out: RenderOut;
  out.position = vec4<f32>(
    p.pos_age.x * 2.0 - 1.0 + local.x * 2.0 / aspect,
    1.0 - p.pos_age.y * 2.0 + local.y * 2.0,
    0.0,
    1.0,
  );
  out.uv = uv[vertex_index];
  return out;
}

@fragment
fn ff_fs(in: RenderOut) -> @location(0) vec4<f32> {
  let centered = in.uv * 2.0 - vec2<f32>(1.0, 1.0);
  let alpha = 1.0 - smoothstep(0.4, 1.0, length(centered));
  return vec4<f32>(vec3<f32>(1.0) * alpha, alpha);
}
```

### FluxFlow State Layout Contract

- `flux_flow.state.fields` ist die deklarative Beschreibung des persistenten GPU-Zustands.
- **WICHTIG (Datentyp-Restriktion):** Die erlaubten Feldtypen sind streng begrenzt auf C-style Aliasse und **dürfen nicht** in reiner WGSL-Syntax geschrieben werden (wie `f32` oder `i32` oder `vec4<f32>`). Das JSON-Manifest erzwingt via Schema-Validierung strikt einen der folgenden Enum-Werte: 
  - `"float"` (für f32 im Shader)
  - `"int"` (für i32 im Shader)
  - `"uint"` (für u32 im Shader)
  - `"vec2"` (für vec2f im Shader)
  - `"vec3"` (für vec3f im Shader)
  - `"vec4"` (für vec4f im Shader)
- Das Layout wird von der Engine in einen stabilen GPU-Stride uebersetzt.
- Shader und Manifest muessen dieselbe semantische Reihenfolge teilen.
- Der Zustand ist **pro Effekt-Instanz** isoliert; verschiedene `scene_video_fx`-Instanzen teilen sich keinen Zustand.

Wichtig:
- Persistenter State ist fuer **Identitaet und zeitliche Kontinuitaet** gedacht.
- Look-Parameter wie Groesse, Alpha, Farbe oder Geschwindigkeit sollten nicht blind dauerhaft eingebrannt werden, wenn sie live aenderbar bleiben muessen.
- Der State ist immer an genau **eine** `FluxFlow`-Stufe gebunden. Weder Scene- noch Post-FX-`FluxFlow`-Instanzen duerfen State untereinander teilen.

### FluxFlow Geometry Contract

`FluxFlow` unterstuetzt in v1:
- `billboard`
- `mesh`

Billboards sind der Standard fuer klassische GPU-Partikelsysteme.
Mesh-Geometrie ist fuer generischere stateful Systeme vorgesehen und benoetigt bei Bedarf `geometry.vertex_count`.

### FluxFlow Stage Contract

Ein `FluxFlow`-Shader ist kein normaler stateless Shader. Er muss die vier Stages explizit anbieten:
- `ff_init` oder entsprechender `init` Entry
- `ff_update`
- `ff_vs`
- `ff_fs`

Die Stage-Namen selbst sind frei waehlbar, aber das Manifest muss sie explizit referenzieren.

Die Engine validiert:
- dass alle deklarierten `FluxFlow`-Stages existieren
- dass `init` und `update` Compute-Shader sind
- dass `render_vertex` und `render_fragment` passende Render-Entries sind
- dass `scene-shader` Manifeste im `FluxFlow`-Modus keine klassische `vs_main`/`fs_main` Scene-Pipeline parallel definieren

### FluxFlow Runtime Lifecycle Contract

Die Runtime verwaltet `FluxFlow`-Systeme mit:
- zwei State-Buffern (Ping-Pong)
- explizitem `needs_init`
- `generation` fuer Reinit-Zyklen
- zeitlichem Delta fuer den `update` Pass

Reinit wird technisch erzwungen bei:
- Resize
- Zeitruecksprung / Seek
- Shader-/Projekt-Reload
- erneuter Aktivierung eines zuvor deaktivierten Effekts

Normale Parameteraenderungen sind davon konzeptionell getrennt. Wenn ein Effekt live reagierende Parameter haben soll, muss der Shader diese Werte aus den aktuellen Param-Slots lesen statt sie nur beim Spawn in den State zu schreiben.

### FluxFlow Authoring Rules

Beim Entwurf eines `FluxFlow`-Effekts gilt:
- `FluxFlow` nutzen, wenn echter Zustand ueber Frames notwendig ist.
- Kein `FluxFlow` nutzen, wenn ein einfacher stateless Fullscreen-Shader ausreicht.
- Keine CPU-Simulation im Produktpfad als Ersatz einbauen.
- Keine impliziten Sonderfaelle im Shader verstecken; Lifecycle, Spawn, Update und Render muessen im WGSL klar getrennt lesbar sein.
- `FluxFlow` ist eine generische technische Schicht und darf nicht als Spezialfall fuer nur einen Effekt dokumentiert oder entworfen werden.

### Engine Bindings Contract (Virtual Loader)
**HARD RULE:** Shader duerfen `struct SceneUniform` oder `struct Params` (in Video-FX) NIEMALS manuell deklarieren!

Die BPM Engine nutzt das "Virtual Loader" Paradigma. Die korrekten Puffergroessen und Speicher-Layouts werden dynamisch vom `wgsl_composer` generiert.
Um Zugriff auf Engine-Systemzeit, GUI-Parameter, Farben und Audio-Parameter zu erhalten, **muss** ganz oben im Shader importiert werden:

```wgsl
#import <engine::bpm_kernel_bindings>
```

Der interne `shader_audit` (aufgerufen via `bpm verify`) ueberwacht diese Regel strikt. Werden die Typsicherheits-Makros (`#color`, `#audio`, `#gui_param`) ohne diesen virtuellen Import verwendet, bricht die Validierung ab.

### Shader Macro Contract
- Shader nutzen fuer Engine-Daten den virtuellen Import `#import <engine::bpm_kernel_bindings>`.
- Darueber werden die Makros `#color "..."`, `#gui_param "..."` und `#audio "..."` freigeschaltet.
- Zusaetzlich unterstuetzt die Engine das `#string "..."` Makro fuer einfache Texte.
- Direkte Uniform-Definitionen, Helper-Aufrufe und rohe Index-Zugriffe sind verboten; Param-Zugriff erfolgt ausschliesslich ueber die Makros.
- Die bindenden Feld- und Typregeln stehen in den JSON-Schemas und den repo-eigenen gueltigen Beispielen. Wenn Doku und Schema voneinander abweichen, gilt das Schema.

### BpmColor Color Access Contract
Alle Farbwerte aus `_raw_params_do_not_use` MUESSEN ueber das `#color` Makro und die typsicheren Getter aus `engine::bpm_kernel_bindings` gelesen werden.

**BpmColor Struct:**
```wgsl
struct BpmColor {
    rgb: vec3<f32>, // Pre-multiplied (RGB * Alpha)
    a: f32,         // Raw Alpha-Kanal fuer Background-Transport
}
```

**Verwendung mit `#color` Makro:**
```wgsl
#import <engine::bpm_kernel_bindings>

// Farbe lesen — IMMER ueber das #color Makro (keine Index-Nummern!):
let bg = #color "scene.bg_color";         // -> BpmColor (rgb + a)
let accent = #color "scene.accent_color"; // -> BpmColor (rgb + a)

// Farben frei mischen ueber .rgb:
let mixed = mix(bg.rgb, accent.rgb, 0.5);

// Finales Output-Encoding (vec3 + Alpha):
return encode_output_alpha(mixed, bg.a);
```

**Regeln:**
- **NIEMALS** `get_scene_color(0)` oder `params.slots[0]` mit manuellen Index-Nummern aufrufen. Nutze IMMER `#color "scene.target_name"` für Farben und `#gui_param "target_name"` für Zahlenwerte. Die Engine ersetzt das Makro zur Compile-Zeit.
- **ANTI-PATTERN:** Das Makro darf **niemals inline in Klammern gekapselt werden** (z.B. `(#color "scene.bg_color").rgb`). Der strikt evaluierte Regex-Parser der Engine bricht bei Schachtelungen ab. Weise den Wert immer in einer separaten Zeile einer lokalen Variable zu.
- Der Target-Name (z.B. `"scene.bg_color"`) muss im `mapping_targets` Array der `.manifest.jsonc` definiert sein. Fehlt er, blockiert die Engine das Rendering mit einer klaren Fehlermeldung.
- `encode_output_alpha(vec3<f32>, f32)` nimmt gemischte RGB-Werte und den Raw-Alpha-Kanal entgegen.
- Direkte Konstruktion von `BpmColor(...)` im Shader ist verboten. Der AST-Auditor blockiert dies.
- Fuer vollstaendig opaken Hintergrund: `encode_output_alpha(final_rgb, bg_opaque())`.
- `get_scene_bg_alpha()` existiert nicht mehr — Alpha ist in `BpmColor.a` enthalten.

### Audio Access Contract
Manuelle Array-Indizierung ist strikt verboten! Alle Audiosignale MUESSEN ueber das `#audio` Makro angefordert werden.

Das `#audio` Makro gibt keinen rohen `f32` Wert zurück, sondern ein `BpmAudioSignal` Struct. Der Typ wird direkt ueber `engine::bpm_kernel_bindings` bereitgestellt; der Wert muss explizit über `.clamped_safe` (oder `.value`) extrahiert werden.

**Verwendung mit `#audio` Makro:**
```wgsl
#import <engine::bpm_kernel_bindings>

// Audio lesen — IMMER ueber das #audio Makro (keine Index-Nummern!):
let kick_signal = #audio "drums.kick";
let spectrum_signal = #audio "spectrum.band_12";

// Explizite Extraktion:
    let safe_kick = kick_signal.clamped_safe;  // Garantiert 0.0 - 1.0 (Standard/Sicher)
    let raw_value = spectrum_signal.value;     // Rohwert (Kann > 1.0 peakern)
```
Die Engine loest den gewünschten String zur Compile-Zeit in den korrekten Puffer-Index auf und wrappt ihn automatisch als BpmAudioSignal.

**Wann nutze ich was? (VJ & Creator Perspektive)**
- Nutze **standardmäßig** `.clamped_safe`. Das ist dein logischer Sicherheitsgurt. Nutze ihn, um technische Artefakte und Berechnungsfehler bei Farbmischungen, sauberen LERPs oder passgenauen UV-Koordinaten zu verhindern.
- Nutze `.value`, wenn du **Explosivität, organische Agilität und echte Lebendigkeit** auf dem Screen brauchst! Das Entfernen des "Sicherheitsnetzes" fängt die pure, ungebändigte Energie des Tracks ein. Wenn ein heftiger Kick-Drop reinknallt und die Peaks weit über `1.0` schießen, fängt `.value` dieses Übersteuern gnadenlos ab. Das ist dein Werkzeug für brachiale Objekt-Skalierungen, ausrastendes HDR-Glow und lebendige, atmende Visuals, die organisch mit der Musik eskalieren statt steril zu wirken.

**Wertebereiche (Value Domains)**
Alle exakten min/max Limits (`min_value`, `max_value`) sowie Response-Curves für die jeweiligen Audio-IDs sind zentral in `registry/feature-params.jsonc` konfiguriert. LLM-Agenten sollten bei Unklarheiten über den spezifischen Zahlenraum eines Signals (z. B. ob ein Peak-Wert negativ werden oder ein Count bis ins Unendliche wachsen kann) stets in dieses Schema schauen.

**Anti-Pattern & Parser-Limits:**
Das Makro darf **niemals inline in Klammern gekapselt werden** (z. B. `(#audio "drums.kick").clamped_safe`). Der strikt evaluierte Regex-Parser der Engine schlägt bei Klammer-Schachtelungen fehl (`invalid #audio directive`).
✅ **Good-Practice:** Weist das Makro immer **zuerst in einer sauberen, zweizeiligen Anweisung** einer Variablen zu:
let a = #audio "drums.kick";
let val = a.clamped_safe;
```

### Text Rendering Contract
Fuer einfache technische HUDs und Beschriftungen in Shadern (die keine manuellen Textur-Bindings nutzen wollen), stellt die Engine ein High-Performance Text-Render-Modul bereit.

**Verwendung mit `#string` und `#font` Makro:**
```wgsl
#import <engine::bpm_kernel_bindings_text>

// Das Makro generiert zur Compile-Zeit ein festes array<u32, 128>:
let label_kick = #string "KICK";

// Das Font Makro loest auf einen Asset-Slot Index auf:
// Im Manifest muss "hud_font" unter `asset_slots` deklariert sein!
let main_font = #font "hud_font"; 

// Array und Font-ID an den Renderer uebergeben:
// bpm_draw_text(chars, font_id, uv, center_pos, size)
let text_alpha = bpm_draw_text(label_kick, main_font, uv, vec2<f32>(0.5, 0.5), vec2<f32>(0.02, 0.04));
```

**Regeln für Strings und Fonts:**
- Typografie wird direkt ueber `asset_slots` im Manifest bereitgestellt (keine komplexen Textur-Matrizen noetig). `asset_slots: { "mein_font": { "required": true, "kinds": ["font", "ttf", "otf"] } }` muss im Manifest (`.manifest.jsonc`) deklariert sein. Die Zuweisung, auf welchen Dateipfad referenziert wird, passiert in der Projektdatei (`.projekt.jsonc`) unter `assets: { "mein_font": { "path": "assets/font/Roboto.ttf" } }`.
- Texte im `#string` Makro muessen striktes **ASCII** sein, damit sie kompatibel zum WebGPU Buffer sind.
- Die **maximale Laenge betraegt 128 Zeichen**.
- Kurze Strings werden vom Rust `wgsl_composer` automatisch mit `0u` (Null-Terminierung) bis exakt 128 Elemente aufgefuellt, sodass die `bpm_draw_text` Funktion eine einheitliche und stabile Signatur hat `fn bpm_draw_text(chars: array<u32, 128>, font_id: u32, ...)`. Abstuerze durch Length-Mismatches sind dadurch ausgeschlossen.

### Timeline Contract
Song-Positionen via `scene.timeline`:
- `.x`: Aktuelle Sekunde
- `.y`: Gesamtdauer
- `.z`: Fortschritt `0.0..1.0` (current/total)
- `.w`: Curve Smoothing
*Hinweis: `scene.timeline` erfordert angeforderte Audio-Quellen, ansonsten ist es `0`! `scene.time` ist unabhaengige Renderzeit.*

### Vertex Shader Contract
```wgsl
@vertex
fn vs_main(@builtin(vertex_index) vi: u32) -> VertexOut {
    var p = array<vec2<f32>, 3>(
        vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0)
    );
    var out: VertexOut;
    out.clip_position = vec4<f32>(p[vi], 0.0, 1.0);
    out.uv = p[vi] * 0.5 + 0.5;
    return out;
}
```

## Advanced Technical Workflows

### Appendix A: GLTF Preprocessor & High-Poly Support
- Nutze Makros wie `#gltf` und `#gltf_node` im Code fuer direkten `glb` Extrakt.
- Die BPM-Engine unterstuetzt native 3D-Geometrie. Über 1024 Vertices wird automatisch das Storage Mesh ueberschrieben.
- Komplexe Modelle erhalten.

### Appendix B & C: Analysis And Inspection
- **Inspect GLTF:** `bpm.exe inspect-gltf <pfad.glb>`
- **Inspect Blend:** Nutze die Python Skripte im Ordner `scripts/py/` direkt ueber Blender, z.B.:
  `blender.exe -b <blend_file> -P scripts/py/inspect_blend_4x.py`
- Dynamische Blender-Modifier uebertragen sich nicht in GLB, diese muessen im WGSL Vertex-Shader nachprogrammiert werden!
- Blender "Bake Sound to F-Curves" muessen durch BPM `audio_scalars` Verknuepfungen simuliert werden.

## Technical Hard Rules Recap
- KEINE Schemas erfinden, immer `scene-shader-manifest` und referenzierte `.schema.json` als Vorlage lesen.
- Parameter und Werte niemals raten, immer aus bestehenden JSONC und Projektdateien ziehen.
- Shader duerfen NIEMALS `struct SceneUniform` oder V-FX `struct Params` manuell definieren. Es MUSS zwingend `#import <engine::bpm_kernel_bindings>` genutzt werden.
- Farb-, Audio- und Zahlenwerte NUR ueber die `#color "..."`, `#audio "..."` und `#gui_param "..."` Makros lesen. Manuelle Index-Nummern (wie `params.slots[x]`) sind absolut verboten und triggern den "Anti-Index Guard".
- Makros niemals inline klammern `(#audio "x").value`. Der strict-evaluierte Parser stuerzt ab. Nutze immer den zweizeiligen Split: Zuweisung, dann Property lesen.
- `#audio` gibt ein `BpmAudioSignal` zurück. Der Typ kommt direkt aus `#import <engine::bpm_kernel_bindings>`; der Wert wird über `.clamped_safe` oder `.value` abgefragt.
- `BpmColor` NIEMALS direkt konstruieren. Der AST-Auditor blockiert `BpmColor(vec3(...), ...)`.
- `encode_output_alpha()` erwartet `vec3<f32>` (gemischte RGB) und `f32` (Alpha).
- `get_scene_bg_alpha()` existiert nicht mehr. Alpha steckt in `BpmColor.a`.
- `#string "..."` generiert **immer** ein `array<u32, 128>` (mit `0u` Padding bei Kuerze) und ist auf maximal 128 ASCII-Zeichen strikt limitiert. Laengere Texte brechen den Compile-Vorgang ab.
