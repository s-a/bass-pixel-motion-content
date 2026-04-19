# Workflow Acceptance Criteria

Dieses Dokument dient als harte Checkliste und Execution-Contract fuer die Ausfuehrung von Tasks im `bpm.exe` Environment.
Nur Tasks, die all diese Stufen einwandfrei passieren, gelten als erfuellt.

## Target Mission

1. Alle Configs laden (Schema, Registry, References).
2. Code erfuellt die `bpm.exe verify` Tests fehlerfrei.
3. Mindestens 1 virtueller Export via `--headless` durchgefuehrt und vom Agenten analysiert.
4. Der Troubleshooting & Feedback Vorgang (`WORKFLOW_LESSONS_LEARNED.md`) wurde verarbeitet.
5. Keine halbgaren, rein beschreibenden Resultate ohne validen Code.

## Quick Execution Order

Agents verwenden **immer** diese Pipeline:
1. Source-Of-Truth Files studieren.
2. Runtime-Contracts uebernehmen.
3. `<name>.manifest.jsonc` entwerfen.
4. `<name>.wgsl` schreiben.
5. `<name>.projekt.jsonc` erstellen.
6. `bpm.exe verify` ausfuehren und debuggen.
7. `bpm.exe export-frame` rendern und visuell auf Aesthetic bewerten. Beachte das referenz Audio assets/audio/preview-reference.wav ist 8 Sekunden lang, also keine `--seconds` Werte > 8 verwenden!
8. Pitfalls und Bugs untersuchen.
9. Workflow-Feedback anwenden und dokumentieren.

## Stop Conditions (Halt & Rewind)

In diesen Faellen ist blinder Output untersagt – der Agent muss sofort Halt machen, Vertraege pruefen und Code iterativ anpassen:
- `verify` ist makellos, doch das exportierte Bild zeigt schwere Rendering-Fehler/Leerstand.
- `scene.timeline` bleibt stur auf `0` stehen, obwohl Zeit verstreicht.
- Die Audio-Reaktivitaet schlaegt grundsaetzlich nicht aus.
- Shader-Parameter tun nicht, was explizit designed wurde.
- Parameter-Kreuzverschmutzung (**Cross-Coupling**): Eine Einstellung ändert fälschlicherweise andere visuelle Systeme. Parameter müssen streng orthogonal ("Ein Regler = Eine Wirkung") isoliert sein.
  - **SDF-Morphing (LLM TRAP):** Ein Parameter wie `cam_speed` oder `bass` darf **niemals** die SDF-Geometrie im `map()` deformieren oder zum Springen bringen.
  - **Kamera Believability:** Die Kamera muss physikalisch glaubwürdig bleiben. Sie darf niemals: 1. durch physikalische Wände/Objekte klippen. 2. durch `#audio` Rhythmen teleportiert oder gewobbelt werden (Audio = Surface/Fragment, niemals Camera Position).
- Dateipfed-Bezeichnungen zwischen Manifest, `.projekt` und Code sind out of sync.

## Verification Protocol

Das Validierungs-Setup.

### 1. Contract Pre-Check

- Manifest, Projekt und Shader teilen denselben Base-File-Namen.
- `entry` in Manifest verweist valid auf die exakte `.wgsl` Datei.
- `scene.shader` in Projekt verweist valid auf `.wgsl`.
- Reihenfolge `audio_sources` in Manifest korreliert absolut mit `scene.audio_scalars` im Code!
- `SceneUniform` (insb. `params` als Size 8 Array) liegt unveraendert im Shader.

### 2. Static Binary Verify

Ruft die Validator-Binary ueber den Installations-Path: `bpm_runtime_location.json` ab und validiert *beide* Settings:
```powershell
& $bpmExe verify --project <deine.projekt.jsonc>
& $bpmExe verify --file <deine.manifest.jsonc>
```

### 3. Shader Performance Audit

Fuer extrem performante visuelle Erlebnisse muss jeder Shader auf der Hardware evaluiert werden. Der Agent ist angehalten, die Ausfuehrungszeiten der Vektoren durch den `--shader-audit` Command sicherzustellen:
```powershell
& $bpmExe verify --file <deine.wgsl> --shader-audit
```
- Der Output muss im "Live Hardware Profiling" im Feld `gpu_scene_ms` unter dem kritischen Budget (`< 5.00 ms`) operieren (`✅ ok` Status).
- Vermeide tiefe Loops, komplexe Verzweigungen und extreme Texture-Sampling Last, falls der Audit "Critical" ausschlaegt.

### 4. Visual Headless Export

Fuer Visual/Review-Abstimmungen den Headless Mode von `bpm.exe` nutzen. Dateiausgabe strikt auf `.tmp/` mappen:
```powershell
& $bpmExe export-frame --project "pfad\deine.projekt.jsonc" --out ".tmp\output.jpg" --seconds 1.5 --headless
```

### 5. Required Visual Test Cases & Temporal Strictness

Um Dramaturgie-Regeln zu evaluieren, sind definierte Shots noetig. **WICHTIG:** Die exportierten Frames duerfen *ausschliesslich* aus der tatsaechlichen Laufzeit des zugewiesenen Audio-Preview-Demo-Samples stammen (keine `--seconds` Werte nutzen, die die Laenge des Tracks ueberschreiten!).
- Exportiere einen fruehen (z.B. Sek 5), mittleren und finalen Teil des echten Demo-Songs -> Evaluiere Progress ("Passiert visuell etwas auf der Timeline?").
- Verifiziere das Song-Progress-Motiv (Integriertes Interface/Umrandungen/Farben).
- Render bei Audio-Aktionen energetische vs. limitierte Szene und pruefe Dynamik.

### 6. Visual Quality Assurance & Prompt Compliance (Kunden-Perspektive)

Der Agent MUSS am Ende zwingend die generierten Frame-Exports aus der Sicht des Kunden (der den Eingangsprompt geschrieben hat) bewerten. "Es kompiliert und rendert" reicht NICHT aus!

- **Prompt Erwartung vs. Realitaet:** Pruefe streng, ob *alle* Aspekte und Anweisungen aus dem Eingangsprompt ausreichend, treffend und extrem hochwertig im visuellen Endresultat umgesetzt wurden.
- **Visual Excellence (State of the Tech):** Nutze modernste "Leading VJ", "Cinematic Aspects", ueberzeugendes Post-Processing, komplexe Kompositionen und dynamisches Lighting. Der Agent muss klar den Unterschied zwischen "Abfall / amateurhafter Programmierer-Kunst" (minderwertig) und "State of the Art" High-End-Produktionen erkennen koennen.
- **Strenges Fail-Kriterium:** Gibt der Agent minderwertige Arbeiten als "fertig" ab, ist dies ein harter Fail. Ist das Resultat optisch flach, reizlos oder erfuellt die Kundenerwartung nicht vollends, MUSS der Agent in eine weitere Iteration gehen, den Code umschreiben und erneut Frames exportieren, bis absolute Premium-Qualitaet erreicht ist.

## Final Output Rules & Quality Review

- Ausgabe beschraenkt sich minimal auf das angefragte Output Set (Manifest/Code/Projekt). Keine Vorwoerter.
- Keine Features erfinden, die nicht durch Contracts bestaetigt wurden.
- Das in `LESSONS_LEARNED` definierte Abschlusslog posten.

### Review Checklist

- [ ] Dateikonsistenz gewahrt (`kind`, `id` lowercase)
- [ ] Shader `SceneUniform` in Arrays unveraendert und absolut valide
- [ ] Manifest Audio & Mapping Targets stimmen mit WGSL Zugriffen ueberein
- [ ] Visuelle Timeline-Dramaturgie ist erkennbar
- [ ] Fortschritts-Motiv existiert und wirkt NICHT wie reines UI Overlay
- [ ] Verification-Run (`verify`) laeuft durch Fehler auf `$true`
- [ ] Hardware Shader-Audit (`--shader-audit`) zeigt Gruenes/Gelbes Licht in der `gpu_scene_ms` Performance-Metric
- [ ] Frame-Exports stammen aus der tatsaechlichen Audio-Laufzeit des Demo-Samples
- [ ] Visuelle Endabnahme (Visual QA) aus Kundenperspektive extrem streng evaluiert und bestanden
- [ ] Cinematic / State of the Tech / Leading VJ Qualitaet bestaetigt (kein Amateur-Look / Abfall)
- [ ] Parameter-Orthogonalitaet rigoros bewiesen (Kein Cross-Coupling der Settings!)
- [ ] Kopfueber `.tmp` Visual-Trace gelaufen und intensiv geprueft
- [ ] Workflow Feedback angewandt
