# Safe diagnostics Pencil and typography reconciliation

Date: 2026-09-17

Pencil file: `/Users/stasyudkin/.pencil/documents/12d0964c-5822-4806-bfe2-7ef00579dcd9/pencil-welcome-desktop.pen`

Pencil state: `KIFo1` — `23 · Безопасная диагностика`

The `.pen` document was read but not edited. This document specifies the exact truthful correction for the owner of that state.

## Why the current canvas cannot ship as Safe diagnostics

State `KIFo1` currently includes three log controls and six log-like rows, including `profile loaded: [redacted]` and `tunnel ready · identifiers removed`. The production log pipeline retains raw messages and supports substring filtering; removing a few fields or displaying `[redacted]` is not a closed privacy contract.

The safe runtime deliberately reads only structural connection/failure types and the platform enum. Its complete schema is `schema`, `category`, `stage`, `code`, `platform`, and `reachability: not_checked`.

## Exact Pencil update for KIFo1

Keep the root size `393 × 852`, background `#060608`, centered navigation title, 20 px horizontal gutter, dark surfaces, ritual-red accent, and rounded-card visual language. Apply only these changes inside `KIFo1`:

1. Remove the right-side Pause action `FtWoe` and its icon `yPyex`.
2. Remove the control row `Q5Xu2` (`Фильтр`, `Редакция`, `Экспорт`). None of these controls has a safe structured-data source.
3. Replace `MkVph` and every child log row with:
   - a summary card titled with the translated `<category> · <stage>`;
   - the fixed limitation `Доступность интернета не проверялась`;
   - scoped copy stating that this report contains only the fields shown and excludes raw logs, URLs, email, configuration, tokens, and identifiers;
   - a complete read-only JSON preview of the six-field schema;
   - best-effort temporary-copy cleanup copy;
   - `Создать файл`, followed only after creation by `Поделиться файлом`.
4. Remove the bottom dock `t3cEGu`. Safe diagnostics is pushed from Logs as a child route, not a selectable top-level destination.
5. Change all human-readable text in this state from explicit `Inter` to the platform/locale system family. For the pictured iOS state the visual reference is SF Pro; this is a design reference, not an embedded app asset.
6. Change JSON preview text from explicit `JetBrains Mono` to the platform monospace family. For the pictured iOS state the visual reference is SF Mono; this is also not embedded.
7. Add a canvas note: `Typography follows runtime platform/locale fonts; no Inter or SF font binary is bundled.`

## Runtime mapping

- `diagnostic-summary-card` maps to the Pencil summary card.
- `diagnostic-preview-card` maps to the read-only JSON surface.
- The preview string and exported file remain byte-identical.
- Connected means tunnel state only; it never implies internet reachability.
- Create never uploads or shares. Share requires a separate user action and the OS picker.

## Security boundary

No safe-diagnostics component may import the raw log repository, providers, entities, filter state, file shares, or logger sinks. The separate Logs screen remains outside this proof and may contain sensitive data.
