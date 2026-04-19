# Blender Migration Guide

Dieses Dokument definiert den strikten Workflow fuer LLM-Agenten, die die Aufgabe erhalten, Legacy-Projekte aus `.blend` Dateien (z. B. aus dem "Concert Loops Pack") in die BPM (Bass Pixel Motion) Engine umzuwandeln.

## Die BPM "Pre-Flight" Extraction Analysis

Eine Blender-Migration ist niemals eine 1:1 Kopie von XYZ-Koordinaten. Blender nutzt Modifier, Node-Trees und Drivers, um prozedurale Welten zu erschaffen. 
Bevor ein Agent WGSL-Code (`#import <engine::bpm_kernel_bindings>`) verfasst, MUSS die exportierte JSON-Datei (`import_blend_4x.py`) auf folgende Aspekte **kritisch geprueft und ausgewertet** werden:

### 1. Geometric Context (Modifiers & Displacements)
Eine Szene besteht oft nur aus ein paar Primitiven (Cubes, Planes), die jedoch in der Laufzeit komplett entfremdet werden.
- **Check `modifiers`-Array:** Suche nach `SUBSURF`, `DISPLACE`, `ARMATURE` oder `NODES` (Geometry Nodes). 
- **Implikation:** Wenn ein `Displace` Modifier auf einer Plane liegt (wie in organischen Terrains), darf der Agent **keine statische** `sd_plane()` nutzen. Die Geometrie muss in WGSL stattdessen durch 3D-Noise Funktionen (Bsp. `snoise3`) abgebildet werden.

### 2. Advanced Material Node Trees
Blender-Szenen tragen ihre Komplexitaet oft im Shading (insbesondere bei "Concert Loops").
- **Check `materials[].nodes`:** Welche Nodes treiben das Material an?
- **Procedural Textures:** Nodes wie `ShaderNodeTexNoise`, `ShaderNodeTexVoronoi` oder `ShaderNodeTexMusgrave` auf dem Displacement-Output oder der Alpha-Maske erzwingen eine direkte Implementierung von Noise in WGSL.
- **Coordinate Manipulation:** Werden Vektoren durch `ShaderNodeMapping` veraendert? Wenn diese gepatched/animiert sind, erfordert das WGSL ein Panning (Translation) ueber `scene.time`. Das bedeutet, das Material bewegt sich ueber starre Geometrie.

### 3. Emissive & Contouring "Hacks" (Intersect / Fresnel)
Viele elektronische Visuals nutzen Randlichter, um Grid-Lines oder Sci-Fi Konturen aufleuchten zu lassen.
- **Detection:** Suche nach `ShaderNodeEmission` gemixed mit *Fresnel*, *Layer Weight* oder eng beschnittenen *ColorRamp* (`ShaderNodeValToRGB`) Nodes.
- **WGSL Translation:** Mappe dies ueber Raymarching-Berechnungen wie `dot(normal, view_dir)` fuer Rim-Lighting oder ueber High-Frequency Modulo- / Sine-Berechnungen mit scharfem `smoothstep`, um leuchtende Linien auf Noise-Feldern nachzuzeichnen.

### 4. Animation Data: Keyframes vs. Drivers
Statische Werte in der Blender-JSON sind irrelevant, wenn Animation-Data anliegt.
- **Keyframes (`fcurves`):** Enthaelt das JSON Pfade wie `location` Keyframes, muss die Delta-Bewegung ermittelt werden. (Beispiel: Kamera bewegt sich kontinuierlich in +Z-Richtung -> in BPM wird dies zu `scene.time * scroll_speed`).
- **Drivers (`drivers`):** Wenn z. B. `#frame / fps` als Expression auf einem Node-Input, Rotation oder Location liegt, ist das eine fortlaufende Zeitbindung. Direkte Übersetzung zu `scene.time`.
- **Audio Bake:** Liegen hochfrequente "zappelige" Keyframes an, die nach einer Audio-Waveform aussehen, **muss** dies an die internen BPM Audio-Analyser gebunden werden: `#audio "audio.stem.kicks.rms"`. 

### 6. User Intent & Workflow (MANDATORY)
Dem Agenten muss unmissverstaendlich klar sein: Wenn der User eine "Migration" wuenscht, erwartet er ein **umfassendes, performantes und state-of-the-art Raymarching-Remake**. Ein einfaches Abpausen von Koordinaten reicht nicht! Die Migration soll optische Engine-Features (z.b. reaktives Audio, dynamisches Glow) voll ausschoepfen. 
**Regel:** Der Agent SOLL proaktiv Verbesserungen oder kuenstlerische Erweiterungen (z.B. Audio-Reaktivitaet wo vorher keine war, zusaetzliches Strobe-Light, komplexe Fog-Verlaeufe) andenken, MUSS aber zwingend beim Nutzer rueckfragen (!), um diese freischalten zu lassen, bevor eigenmaechtig wilde Designentscheidungen getroffen werden.

*Hinweis: Beachte ausserdem die strikten Regeln zu "Render Stability & Glitch Prevention" aus der Haupt-Dokumentation (`TECHNICAL_DETAILS.md`), um Raymarching-Flimmern und Float-Precision-Fehler bei Loops zu vermeiden!*

### 8. GLTF/Meshes vs. Procedural 2D/Raymarching
Der Agent muss bevorzugt immer mathematische Shader-Loesungen entwickeln (2D Shader oder Raymarching). **Der Export und Import via GLTF-Modellen (`#gltf`) ist nur in absoluten Ausnahmefaellen/Sonderfaellen zulaessig!** Fast alle Legacy Concert Loops und Blend-Files koennen muehelos und deutlich performanter ueber prozedurale 2D-Techniken, SDF-Primitives und Kamera-Projektionen abgebildet werden. GLTF-Load-Routinen verstopfen das System und hemmen den prozeduralen Flow der Bass Pixel Motion Engine.

## Fehlerpraevention
- **Tunnel vs. Terrain:** Eine Plane ueber dem Kopf und am Boden ist oft kein umschlossener Tunnel, sondern ein offener Layer-Horizont (Landscape). Checke die Dimensionen im Blender JSON ganz genau!
- **SDF Signs:** Im Raymarching gilt: *Negativ ist im Objekt, Positiv ist der freie Raum*. Baust du eine umgebende Röhre oder Decke aus der Sichtweise der Kameraposition, sorge streng dafuer, dass das SDF an der Kamera-Koordinate positiv evaluert (`f_dist = 1.5 - abs(p_rel.y)` bei Planes auf Y = 1.5 & -1.5).
