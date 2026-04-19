# Workflow Lessons Learned

Dieses Dokument dient nach Start und Visual Verify eines Tasks der Fehlerdiagnose (Troubleshooting) sowie der Handoff-Pipeline fuer Lessons Learned in die Workflow Meta-Dokumentation.

## Failure Modes And Debugging

Erste Analysestation fuer inkonsistente Verhaltensweisen bei validem Codeauswurf:

| Symptom | Ursache (Wahrscheinlichkeit) | Check | Fix |
|---|---|---|---|
| `timeline.z` bleibt 0 | Fehlende Audio-Analyse in Registry/File | `audio_sources` Check | Mindestens Audio-Features fordern! |
| `time` okay, `timeline` auf 0 | Timeline Contract verschlampt | Uniform + Manifest | Analyse anwerfen und Uniform uebernehmen |
| Muellwerte in Parametern | `SceneUniform` ist kompromittiert | Size der Arrays | Uniform niemals verkleinern/optimieren! |
| Fail auf harmloser Local-Var | WGSL Keyword Collision | Parsing Logs | Umbenennen und Keywords umschiffen |
| Wirre Audio-Reaktion | Offset zwischen Manifest und Matrix | `av(index)` vs Manifest| Stringenz in der Index-Kette herstellen |
| Zappeliges Artwork | Mikro vs. Makro verfehlt | Audio auf Geo-Scale | Heavy-Audio auf Details verlagern |
| Kein Bildfortschritt | Timeline in Logik kaum hinterlegt | `timeline.z` Calls | Dramaturgie (Anfang/Mitte/Ende) einbinden |
| User Interface fehlgeleitet | Parameter Target Offset | `mapping_targets` | Stringenz zwischen Manifest & Params setzen|

## Feedback & Optimization Handoff

Ein Task ist nicht abgeschlossen, ehe die Pipeline bewertet und evaluiert wurde, ob Workflow/Dokumentation Praeventionsluecken enthaelt.

### Mission
Nach jedem vollstaendigen Task evaluieren:
1. Traten Pitfalls / Fast-Fails auf? Und wenn ja, welche?
2. Warum (Ursprung)?
3. Haetten Best-Practices in bestehenden Workflows den Fehler vor Ausfuehrung geblockt?
4. Muss sich eine Workflow Regel aendern?

### Pitfall Classification (Failure Classes)
Waehle den Grundstein:
- `Bedienfehler`
- `fehlende Verifikation`
- `mehrdeutige Dokumentation`
- `widerspruechlicher Runtime-Contract`
- `fehlendes Beispiel/Troubleshooting`

### Change Threshold: The "None" Rule

`Workflow Feature Request: none` deklariert, dass der Workflow bereits reibungslos gepasst hat.
Darf NUR vergeben werden, wenn:
- Die aktuelle Dokumentation den Fehler bei genauer Befolgung klar abfaengt.
- Die Lektion bereits auf hohem Praesenz-Level definiert war (zB WGSL Verifikation).
- Es keinen Missing-Link in Guardrails / Troubleshooting gibt.
- Handelt es sich "nur" um kuenstlerische Iteration, ist `none` ebenfalls gueltig.

Besteht eine frueh erkennbare Praeventions-Luecke durch unklare Dokumente, MUSS ein Dokumentenverbesserungsvorschlag getaetigt werden, auf Grundlage des aufgetretenen Fehlers. (Beispiel: WGSL Parser crashed aufgrund Keyword-Kollision -> Workflow sollte explizite Guardrails erhalten).

### Post-Task Output Format (Mandatory)

Ganz am Ende der Task-Konversation MUSS die Auswertung in Code-Form mitgeteilt werden.

```text
Pitfall Review
- Pitfall: <kurze Beschreibung>
- Failure Class: <Klasse>
- Why It Happened: <Ursprungsanalyse>
- Prevention: <Agenten Prevention Strategy>

Workflow Feature Request
- Symptom: <...>
- Root Cause: <...>
- Proposed Document Improvement: <Verbesserungs Requirement>
```

(bzw. `Workflow Feature Request: none` wenn vollends unnoetig).
Kein Ende-Block, kein "Done"-Status!
