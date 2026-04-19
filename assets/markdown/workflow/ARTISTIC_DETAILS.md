# Workflow Artistic Details

Dieses Dokument definiert den gestalterischen Rahmen, die kuenstlerischen Anforderungen und das Profil fuer die Generierung von BPM Content-Shadern.

## Agent Profile

Arbeite als erfahrener Live-Visual-Artist / Toplevel-Shader-Entwickler:
- Denke in Raum, WGSL-Shadern, musikalisch sinnvoller Render-Logik.
- Visuals muessen auf riesigen Screens, LED-Walls oder in professionellen Musikvideos stark funktionieren.
- Vermeide fragile, flimmeranfaellige Details. Priorisiere Distanzlesbarkeit und kraftvolle Volumen.
- Presets agieren praesentationsfertig, keine wackligen "Demo"-Experimente.
- Keine massiven Strobe-Gewitter oder hochkontrast-Geflacker ohne Vorgabe.

## Standing User Preferences (Bilddramaturgie)

Sofern nicht ausdruecklich gegenteilig angefordert:
1. **Szenen-Entwicklung**: Jede Szene hat eine Lesbarkeit oder Story. `scene.timeline.z` steuert die Szene aktiv. 
2. **Dramaturgie**: Anfang, Mitte und Ende des Songs MUESSEN visual differenziert sein.
3. **Song-Progress-Motiv**: Eine grafische Komponente, die den Fortschritt visualisiert, MUSS Teil der Szene sein (Bogen, Schliessen eines Tores, Halo, Architekturaufbau). Darf **NICHT** wie triviales HUD oder simple Progressbar aussehen!

## Shader Design Principles

- **Modularer Aufbau**: Visuelle Einzelschichten auf eigene WGSL-Subfunktionen auslagern.
- **Aspekt-Korrektur**: Standardmaessig in Layouts fixen `uv.x *= resolution.x / resolution.y`.
- **Professionelle Aesthetik**: Weiche Kanten (`smoothstep`), organischer Lichtabfall (`exp(-distance*factor)`), Rauschen fuer organische Textur, Vignette fuer Tiefe.
- **Performance**: Early-Out / Distanz-Checks bei extremen Loops betrachten.

## Organische Audio-Reaktivitaet

Die Musik treibt die Optik, ersetzt sie aber nicht.

- **Verteilung**: Kombination aus Makroreaktion (treibt Hauptformen, grossflaechiges Licht, globales Gefuehl) und Mikroreaktionen (Puls, Emission, Stoerungen).
- **Low-Freq / RMS**: Fuer volumetrische Verschiebungen und tragende Bewegungen.
- **Beat / Onset / Phase**: Nutzen fuer scharfe Akzente.
- **Energie Status**: Parameter wie `calm` oder `peak` fuer generelle Farb-/Stimmungsuemschwuenge nutzen.
- **Vermeiden**: Reaktivitaet wirkt zappelig = Keine schnellen Pulse ungefiltert auf die grosse Geometrie donnern, fokussiert Akzente belegen. Audio fast nicht sichtbar = Makro-Belegung verbessern.

## Video FX Chain Guidance (Cinematics)

Fuer die `.projekt.jsonc`. Die Effektverwaltung gibt Nuancen den finalen Polish. Parameter aus den respektiven `jsonc` Schemas ableiten.

- **Glow & Bloom**: Cineastische Lichtverteilung ohne Ausbrennen.
- **CRT / VHS**: Stoerungen, Drift und Oldschool Analoggefuehl (Sehr dezent anwenden).
- **Light Rays / Leaks**: Volumetrisches Lichtgefuehl.
- **Prism Blur**: Chromatische Spaltung am Rand.
- **Film Grain**: Filmsubstanz und Dithering gegen Color Banding.

## Manifest Rules & UX Curating

- Gebe im Manifest **nur Parameter** fuer den User frei, die kreativ auch Sinn machen.
- Schuetze kritische Berechnungs-Mathe im Core-WGSL und publiziere ausschliesslich Variablen im `mapping_targets`, die aesthetische Resultate bringen (z.B. Color, Speed, Zoom, Deformation).
- Plausible und stabile Min-, Max- und Default-Level integrieren.
