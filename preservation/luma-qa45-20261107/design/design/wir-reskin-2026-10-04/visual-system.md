# WIR Baseline — визуальная система редизайна 2026

Статус документа: визуальная спецификация для создания копий экранов рядом с `WIR Baseline`. Исходные экраны не изменяются. `WIR Baseline` — единственный source of truth для структуры, UX, навигации, текстов, состояний, порядка блоков и набора функций.

### Статус параметров

- **Зафиксировано для статической отрисовки Contour:** финальная палитра и геометрия из Parts 4, 5 и 7; Inter вместо исходного Roboto при сохранении исходных размеров body; заголовки 22/600; JetBrains Mono для JSON и logs; геометрия connection control, navigation capsule, profile surfaces, editable inputs и FAB. Эти значения являются основными для копий.
- **Exploratory:** палитры четырёх направлений в Part 1 служат сравнительными style previews и могут отличаться от финальной Contour palette.
- **Proposed, не реализовано статическим макетом:** motion из Part 8, системное поведение Liquid Glass, accessibility behavior и native transitions. Это guidance для будущей реализации, а не утверждение о готовом поведении приложения.
- Планируемый объём canvas: 178 копий (`89 исходных экранов × Light/Dark`) и 8 сравнительных preview (`4 направления × Light/Dark`). Этот документ не подтверждает завершение копирования, screenshot checks или визуальную валидацию всех фреймов.

## Рамка задачи и источники

- Меняется только presentation layer: цвет, типографическая иерархия, материалы, контуры, тени, радиусы, интервалы, декоративная графика и motion.
- Сохраняются исходные тексты и названия, порядок элементов, действия, CTA, маршруты и сценарии. Новые продуктовые сущности не добавляются.
- Рабочие экраны создаются как отдельная группа рядом с оригиналом. Рекомендуемое имя группы: `WIR Reskin — Contour 2026-10-04`. У каждого фрейма сохраняется исходное имя с суффиксом `— Contour`.
- В системе используются только реально известные экраны Baseline: intro, home, proxy list, proxy profile, settings, general, routing, DNS, inbound, TLS, WARP, logs, about, import dialogs, loading и error states. Account, Subscription и Upgrade не проектируются, пока они не появятся в Baseline.
- Визуальные референсы: [GCT Balance — мягкие цветовые поля и стеклянные слои]([REDACTED]), [FauxGuard — тонкая зелёная орбитальная геометрия]([REDACTED]), [graphite fintech — тактильный тёмный материал и лаймовые акценты]([REDACTED]).
- Apple-ориентир: [Human Interface Guidelines — Materials](https://developer.apple.com/design/human-interface-guidelines/materials) и [WWDC25: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/).

### Как используется Liquid Glass

Liquid Glass — функциональный слой для навигации, компактных действий, sheets и элементов, плавающих над контентом. Он не становится фоном каждой карточки. Данные, списки, поля и длинные настройки остаются на спокойных плотных поверхностях с предсказуемым контрастом.

В pen.dev материал изображается статически: Regular glass visual fill `#F9FCF3E8` в light и `#24392DE8` в dark, edge `#FFFFFFCC` в light и `#BBD9BD66` в dark, плюс мягкая тень. Это дизайн-guidance, а не подтверждение нативной реализации Liquid Glass. В iOS-сборке следует использовать системные API и поведение Apple, а не воспроизводить материал набором blur-эффектов вручную. Базовый характер — Regular. Clear допустим только в редком компактном контроле над насыщенным, гарантированно контрастным фоном после проверки текста; в текущем наборе экранов по умолчанию не нужен.

---

# Part 1 — Visual directions

## 1. Contour

### A. Название

**Contour**

### B. Основная идея

Спокойная инфраструктура, в которой соединение проявляется через тонкие вложенные незамкнутые контуры. Визуальный язык передаёт приватность как контролируемую границу, а скорость — как точное и уверенное движение линии. Он узнаваем без типичных щитов, глобусов и большой кнопки питания. Сдержанный зелёный спектр, графитово-хвойные поверхности и функциональный Liquid Glass создают premium-ощущение без неона и «хакерской» стилистики.

### C. Visual language

- **Background:** глубокий хвойно-графитовый в dark; мягкий серо-молочный с зелёным подтоном в light. Вокруг connection control возможна очень слабая радиальная подсветка 4–7% opacity.
- **Surfaces:** контентные поверхности плотные. Glass применяется к navigation bar, toolbar, floating action и sheet chrome.
- **Cards:** только там, где есть реальная группировка. Списки настроек собираются в секции, а не в отдельную карточку на каждую строку.
- **Borders:** тонкие, зелёно-серые, контрастнее у интерактивных элементов. Вложенные контуры используют 1–1.5 pt.
- **Radius:** 8 / 12 / 16 / 22 / 30; внутренний радиус всегда меньше внешнего.
- **Shadows:** холодно-зелёные, широкие и малоконтрастные; в dark elevation читается преимущественно через luminance и edge highlight.
- **Transparency:** только функциональный верхний слой. Контентные списки — 94–100% opacity.
- **Gradients:** неравномерные radial/mesh поля с небольшой амплитудой; линейный 45° градиент не используется.
- **Typography:** Inter Variable; спокойные medium/semibold заголовки, tabular figures для IP, времени, скорости и latency.
- **Iconography:** простые контурные символы с оптически единым stroke 1.5–1.75 pt. Системные SF Symbols допустимы в iOS. Декоративная графика не подменяет статусную иконку.
- **Spacing:** базовый шаг 4, основные интервалы 8 / 12 / 16 / 24 / 32.
- **Buttons:** компактные, не полностью pill; primary — зелёный fill, secondary — плотная поверхность или glass в плавающем контексте.
- **Toggles:** короткая тактильная дорожка, заметная ручка, статус дублируется подписью строки.
- **Navigation:** системная, плавающая над контентом, Regular Liquid Glass; активный раздел отмечен fill/контрастом, не только цветом.
- **Graphics:** вложенные открытые рамки с контролируемыми разрывами, которые собираются при подключении.
- **Motion:** линии сходятся без bounce; состояние становится устойчивым через замедление, а не через glow.

### D. Color direction

| Роль | Dark | Light |
|---|---|---|
| Canvas | `#101916` | `#F2F5EF` |
| Surface | `#192721` | `#FFFFFF` |
| Elevated | `#23392E` | `#E6EEE5` |
| Primary text | `#F3F6F2` | `#14231B` |
| Secondary text | `#B1C0B6` | `#50645A` |
| Accent | `#B8D8BA` | `#2D6847` |
| Text on accent | `#102318` | `#FFFFFF` |
| Connected | `#91D5A3` | `#286843` |
| Warning | `#E5BA72` | `#80540E` |
| Error | `#F19B94` | `#A63832` |
| Border | `#51685A` | `#A6B5AA` |

### E. Main VPN / Home

- **Disconnected:** вложенные рамки разомкнуты и слегка разведены; поверхность спокойная, статус остаётся исходной текстовой меткой. Исходный connection control сохраняет размер `148×130` и получает radius `44`; вокруг него находятся два открытых периметра с offsets `+18` и `+38`, радиусами `62` и `82`, stroke `1`, нижним разрывом и opacity `0.60` / `0.25`. Линии проходят по верхней, правой и левой сторонам и не образуют круг или power glyph.
- **Connecting:** разрывы в контурах последовательно смещаются к одной оси; тонкий segment движется по периметру. Исходная строка состояния и progress остаются на первом плане.
- **Connected:** рамки оптически совпадают, но сохраняют один фирменный разрыв; центр становится чуть светлее, Connected/Protected читается текстом и иконкой.
- **Selector:** исходный location/server selector остаётся на месте; получает плотную поверхность, chevron и короткую secondary line, если она уже есть.
- **IP / protection:** текущие значения не переименовываются; числа включают tabular figures. Группировка остаётся исходной.
- **Connect / Disconnect:** исходная зона нажатия сохраняется. Новый визуальный объект обрамляет её и реагирует на состояние, не создавая дополнительного действия.

### F. Character

| Параметр | Балл |
|---|---:|
| Premium | 9 |
| Technological | 9 |
| Trustworthy | 9 |
| Distinctive | 9 |
| Minimal | 8 |
| Emotional | 7 |
| Scalability | 9 |

### G. Риски

- Слишком тонкие линии могут теряться на слабых дисплеях; минимум 1 pt и проверка контраста обязательны.
- При избытке вложенных рамок motif станет декоративным шумом; на экран допускается один expressive cluster.
- Статическая imitation glass легко выглядит как дешёвый glassmorphism; она ограничена навигацией и chrome.

## 2. Obsidian

### A. Название

**Obsidian**

### B. Основная идея

Тактильный интерфейс из тёмного минерала и графитового стекла с точечным лаймовым сигналом. Он создаёт ощущение физического, надёжного инструмента, где действие ощущается весомым. От типичного VPN его отличают материальные края, низкая насыщенность и отсутствие иллюстраций про безопасность.

### C. Visual language

- **Background:** почти чёрный графит с тёпло-зелёным подтоном; light — каменно-серый, не чисто белый.
- **Surfaces:** толстые матовые плиты и редкие стеклянные управляющие слои.
- **Cards:** крупные функциональные группы; внутренние строки разделяются hairline.
- **Borders:** edge highlight сверху и слева, более тёмный edge снизу.
- **Radius:** 6 / 10 / 14 / 20; форма строже Contour.
- **Shadows:** направленные, короткие, создают тактильную толщину.
- **Typography:** Inter с более плотным tracking; числовые показатели крупнее.
- **Controls:** ощущаются как механические пластины; pressed сдвигается на 1 px и теряет часть тени.
- **Graphics:** расколотая или сдвигающаяся плита вокруг исходного connection control.
- **Motion:** короткое сцепление двух слоёв, без эластичного bounce.

### D. Color direction

| Роль | Dark | Light |
|---|---|---|
| Canvas | `#0F1210` | `#ECEFEA` |
| Surface | `#191E1A` | `#FAFBF8` |
| Elevated | `#242B25` | `#FFFFFF` |
| Primary text | `#F1F4EF` | `#171C18` |
| Secondary text | `#ABB3AC` | `#59625B` |
| Accent / connected | `#B5D76A` | `#4E6F1F` |
| Warning | `#E2B66B` | `#82530A` |
| Error | `#EC8F87` | `#A33631` |
| Border | `#3B433C` | `#C9CEC8` |

### E. Main VPN / Home

Disconnected — центральные пластины смещены на 6–8 px; Connecting — сходятся по одной оси; Connected — фиксируются коротким edge flash. Selector и показатели находятся на плотных графитовых слоях. Исходный connect control получает тактильную рамку, но не превращается в новый hardware metaphor и сохраняет текущий label.

### F. Character

| Параметр | Балл |
|---|---:|
| Premium | 9 |
| Technological | 8 |
| Trustworthy | 9 |
| Distinctive | 8 |
| Minimal | 7 |
| Emotional | 8 |
| Scalability | 8 |

### G. Риски

- Light mode может потерять характер материала.
- Слишком много bevel/shadow создаст скевоморфизм и визуальный вес.
- Лаймовый цвет нельзя использовать как постоянный декоративный акцент: он должен сохранять смысл действия или состояния.

## 3. Atmosphere

### A. Название

**Atmosphere**

### B. Основная идея

Приватность ощущается как тихая среда вокруг пользователя: дымчатые поверхности, мягкие поля цвета, много воздуха. Направление особенно хорошо раскрывается в light mode и делает технический продукт спокойным и бытовым. В отличие от типичного VPN, оно не демонстрирует инфраструктуру и не драматизирует угрозы.

### C. Visual language

- **Background:** молочно-серый или дымчато-графитовый, с мягким нерегулярным color field вокруг главного состояния.
- **Surfaces:** тонкие полупрозрачные слои только в верхнем chrome; content surfaces почти непрозрачные.
- **Cards:** мягкие секции без явной рамки, разделённые пространством.
- **Radius:** 12 / 18 / 26 / 34.
- **Shadows:** широкие рассеянные, 8–14% opacity.
- **Typography:** Inter Regular/Medium, увеличенный line-height.
- **Controls:** тихий tonal fill, крупные touch targets.
- **Graphics:** размытое поле или halo, форма которого меняется со статусом.
- **Motion:** дыхание поля с малой амплитудой; при Reduce Motion заменяется кроссфейдом.

### D. Color direction

| Роль | Dark | Light |
|---|---|---|
| Canvas | `#171A18` | `#F3F2ED` |
| Surface | `#222724` | `#FCFCF8` |
| Elevated | `#2D3530` | `#FFFFFF` |
| Primary text | `#F3F1EB` | `#222721` |
| Secondary text | `#B9B9B0` | `#626960` |
| Accent | `#AFCFBE` | `#357259` |
| Connected | `#9DD6AE` | `#2F7048` |
| Warning | `#E4BC7C` | `#82560F` |
| Error | `#EFA19B` | `#A23C37` |
| Border | `#3C4540` | `#D5D8D1` |

### E. Main VPN / Home

Disconnected — поле маленькое, нейтральное и асимметричное; Connecting — оно вытягивается по вертикали и медленно собирается; Connected — становится стабильным мягким овалом с зелёным подтоном. Connection control остаётся исходным элементом поверх поля. Selector и IP-информация получают воздух и простые разделители.

### F. Character

| Параметр | Балл |
|---|---:|
| Premium | 8 |
| Technological | 6 |
| Trustworthy | 8 |
| Distinctive | 7 |
| Minimal | 9 |
| Emotional | 8 |
| Scalability | 8 |

### G. Риски

- Может выглядеть как wellness-приложение и ослабить технологичность.
- Дымчатые поля требуют аккуратной оптимизации и могут полосить на некоторых экранах.
- В dark mode легко уйти в generic blur aesthetic.

## 4. Signal

### A. Название

**Signal**

### B. Основная идея

Строгий интерфейс строится вокруг одного цветового шва, который показывает состояние соединения. Основная выразительность создаётся типографикой, ритмом и точной геометрией. Это самое утилитарное направление: уверенное, быстрое и легко масштабируемое.

### C. Visual language

- **Background:** ровные нейтральные поверхности с едва заметным зелёным tint.
- **Surfaces:** плоские уровни luminance, минимум теней.
- **Cards:** редкие; преимущественно section rows и dividers.
- **Borders:** 1 pt, активный seam — 2 pt.
- **Radius:** 6 / 10 / 14 / 18.
- **Typography:** Inter Medium/Semibold, чёткая информационная иерархия.
- **Controls:** функциональные, компактные, почти без декоративной глубины.
- **Graphics:** цветовая линия проходит через исходный connection control и коротко меняет форму по статусу.
- **Motion:** sweep, crossfade и короткие opacity changes.

### D. Color direction

| Роль | Dark | Light |
|---|---|---|
| Canvas | `#121715` | `#F5F6F3` |
| Surface | `#1D2421` | `#FFFFFF` |
| Elevated | `#27302C` | `#E9EDE9` |
| Primary text | `#F2F5F2` | `#18201C` |
| Secondary text | `#AEB9B3` | `#58635D` |
| Accent | `#93C7A7` | `#2D6A49` |
| Warning | `#DBB46E` | `#7B510D` |
| Error | `#E9928B` | `#A33934` |
| Border | `#34413B` | `#CCD3CE` |

### E. Main VPN / Home

Disconnected — seam разорван; Connecting — сегмент проходит по линии; Connected — линия становится непрерывной. Исходные статус, selector и показатели остаются на прежних местах. Connection control получает вертикальный или угловой seam вместо круговой рамки.

### F. Character

| Параметр | Балл |
|---|---:|
| Premium | 8 |
| Technological | 8 |
| Trustworthy | 9 |
| Distinctive | 7 |
| Minimal | 10 |
| Emotional | 5 |
| Scalability | 10 |

### G. Риски

- Без точной типографики и spacing может выглядеть слишком generic.
- Один seam недостаточно выразителен на маркетинговых изображениях.
- Строгость может сделать продукт холодным и корпоративным.

---

# Part 2 — Recommendation

## Best overall: Contour

Contour лучше всего соединяет privacy, speed, calm и premium technology. Открытая рамка — метафора управляемой границы, а не буквальной защиты; поэтому она сохраняет смысл и избегает клише. Система хорошо живёт в light и dark mode, переносится с home на списки, sheets, loading и error states и остаётся узнаваемой без логотипа. Её легко масштабировать: цвет и материалы семантичны, а signature не требует изменения UX.

Через несколько лет Contour имеет больше шансов сохранить актуальность, потому что характер строится на пропорциях, контуре и движении, а не на модном градиенте. Liquid Glass работает как функциональный Apple-layer, а не как основной декоративный эффект.

## Alternative: Obsidian

Obsidian — сильная альтернатива, если нужен более тёмный, физический и выразительный характер. Он особенно хорош для dark mode и tactile interactions. Для основной системы он уступает Contour из-за большего риска перегрузить long-form settings и потерять характер в light mode.

Не следует смешивать направления поровну. Допустимый перенос из Obsidian в Contour — только тактильное pressed-состояние и направленный edge highlight.

---

# Part 3 — Visual DNA

Contour — это тихая технологичная среда на хвойно-графитовой основе, где данные живут на плотных спокойных поверхностях, а управление парит над ними в функциональном Liquid Glass. Связь выражается вложенными незамкнутыми рамками: в незащищённом состоянии они разведены, при подключении точно сходятся, а в защищённом образуют устойчивую структуру с намеренно сохранённым разрывом. Один акцентный зелёный спектр, контрастная типографика и короткое уверенное движение создают характер без неона, щитов, глобусов и power-кнопок.

## Design principles

1. **State before spectacle.** Каждый эффект сначала объясняет состояние и только потом создаёт характер.
2. **Dense content, light control.** Данные и настройки читаются на плотных поверхностях; glass закреплён за навигацией и действиями.
3. **One contour moment.** На одном экране только один выразительный кластер вложенных контуров.
4. **Calm precision.** Движение короткое, направленное и без bounce; геометрия аккуратная, но не стерильная.
5. **Meaning beyond color.** Статус всегда различается текстом, иконкой/формой и движением, а не только оттенком.
6. **Baseline is the contract.** Визуальный polish не меняет content hierarchy, навигацию или функциональность.

---

# Part 4 — Design tokens

## 4.1 Semantic color tokens

Значения — стартовые токены. Перед production handoff необходим автоматический contrast audit на реальных размерах текста и материалах.

| Token | Dark | Light | Назначение |
|---|---|---|---|
| `background/default` | `#101916` | `#F2F5EF` | основной canvas |
| `background/subtle` | `#14201B` | `#EAF0E9` | подложка секции, grouped area |
| `surface/primary` | `#192721` | `#FFFFFF` | основной content layer |
| `surface/secondary` | `#1E3028` | `#F7F9F5` | вложенная секция/row group |
| `surface/elevated` | `#23392E` | `#E6EEE5` | floating content, sheet body |
| `surface/glass-regular` | `#24392DE8` | `#F9FCF3E8` | статический visual fill только для nav/action chrome |
| `text/primary` | `#F3F6F2` | `#14231B` | заголовки и основной текст |
| `text/secondary` | `#B1C0B6` | `#50645A` | пояснения и metadata |
| `text/tertiary` | `#93A89B` | `#64756B` | необязательная подпись; не для мелкого текста на glass |
| `text/on-accent` | `#102318` | `#FFFFFF` | текст primary action |
| `border/default` | `#51685A` | `#A6B5AA` | интерактивная граница и section edge |
| `border/subtle` | `#304439` | `#D3DDD3` | разделитель |
| `border/glass-edge` | `#BBD9BD66` | `#FFFFFFCC` | оптическая кромка glass |
| `accent/default` | `#B8D8BA` | `#2D6847` | primary action и активное состояние |
| `accent/hover` | `#C6E3C7` | `#255B3E` | pointer hover |
| `accent/pressed` | `#A5C9A8` | `#1E4E34` | pressed |
| `accent/subtle` | `rgba(184,216,186,.14)` | `rgba(45,104,71,.10)` | hover, transient accent wash; не финальный selected fill |
| `selection/default` | `#314F3B` | `#DDEBDD` | фактический selected fill для row/item/navigation state |
| `status/connected` | `#91D5A3` | `#286843` | protected / connected |
| `status/connecting` | `#B8D8BA` | `#2D6847` | connecting / reconnecting |
| `status/warning` | `#E5BA72` | `#80540E` | no internet / warning |
| `status/error` | `#F19B94` | `#A63832` | connection error / destructive |
| `text/data-error` | `#F6AAA4` | `#A63832` | усиленный foreground для error latency/data на selected row |
| `focus/ring` | `#D8EFDA` | `#1F5E3D` | 2 pt focus indicator |

Контрастные пары для макета: `text/primary` на `background/default` и `surface/primary`, `text/secondary` на основных поверхностях, `text/on-accent` на `accent/default`. Общий семантический error остаётся `status/error`; для мелкого error latency/data foreground на выделенной строке используется отдельный `text/data-error`, потому что dark `#F19B94` на selected surface даёт около `4.26:1`, а `#F6AAA4` поднимает контраст выше целевого `4.5:1`. Текст на glass не следует считать проверенным только по fill: его нужно проверять на самом светлом и самом тёмном возможном контенте под материалом. При сомнении используется scrim или плотная surface.

## 4.2 Typography

### Гарнитуры

1. **Фактический шрифт копий: Inter Variable** — заменяет исходный Roboto, при этом размеры body из Baseline сохраняются без пересчёта.
2. **Native iOS option: SF Pro / SF Compact** — если приложение следует системной типографике Apple; решение должно приниматься для всего продукта, а не для отдельных экранов.
3. **Fallback: Noto Sans** — для окружений и языков, где Inter недоступен или не покрывает нужные символы.

JSON и logs используют **JetBrains Mono** с tabular figures. Моноширинный шрифт не распространяется на обычные labels, settings и navigation.

Не смешивать Inter и SF Pro внутри одного макета. Для копий Baseline используется Inter Variable. Исходные размеры body сохраняются; заголовки экранов фиксируются как `22/28`, weight `600`. Остальные значения ниже — системная шкала для сопоставления существующих размеров, а не разрешение массово менять typography metrics Baseline.

### Scale

| Style | Size / line | Weight | Tracking | Использование |
|---|---:|---:|---:|---|
| `display` | 36 / 40 | 600 | `-0.6px` | редкий ключевой статус Home, если размер уже допускает Baseline |
| `title/screen` | 22 / 28 | 600 | `-0.2px` | фактический заголовок экрана в копиях |
| `title/section` | исходный размер Baseline | 600 | `-0.1px` | секция или sheet без изменения структуры |
| `headline` | 17 / 22 | 600 | `-0.1px` | ключевая строка/CTA |
| `body` | 16 / 22 | 400 | `0` | основной текст |
| `body/medium` | 16 / 22 | 500 | `0` | интерактивная строка |
| `callout` | 15 / 20 | 500 | `0` | metadata/action |
| `caption` | 13 / 18 | 400 | `0.1px` | вспомогательная подпись |
| `micro` | 11 / 14 | 500 | `0.25px` | только некритичные метки, не на glass |
| `data/large` | 28 / 32 | 550 | `-0.3px` | скорость или время, если уже есть в Baseline |
| `data/body` | 15 / 20 | 500 | `0` | IP, latency, usage |

Для `data/*`: `font-variant-numeric: tabular-nums slashed-zero`. IP не переносится по произвольному символу; при недостатке ширины сохраняется текущий паттерн Baseline — shrink/truncate/copy affordance не изобретаются. Время подключения, скорость, latency, data usage используют единый baseline единиц измерения; единица на один уровень спокойнее значения.

## 4.3 Spacing

| Token | Значение |
|---|---:|
| `space/0` | 0 |
| `space/1` | 4 |
| `space/2` | 8 |
| `space/3` | 12 |
| `space/4` | 16 |
| `space/5` | 20 |
| `space/6` | 24 |
| `space/8` | 32 |
| `space/10` | 40 |
| `space/12` | 48 |
| `space/16` | 64 |

Правила: 8 px — внутренняя связь icon/text; 12–16 px — compact control; 16–20 px — row; 24 px — между смысловыми группами; 32–48 px — между крупными секциями. Вертикальный ритм сохраняет расположение Baseline; допустимо выровнять интервалы до ближайшего токена без перестановки блоков. Safe areas и minimum touch target следуют платформе.

## 4.4 Radius

| Token | Значение | Использование |
|---|---:|---|
| `radius/xs` | 6 | chip-like status, tiny inner element |
| `radius/sm` | 8 | field, compact button |
| `radius/md` | 12 | row group, button |
| `radius/lg` | 16 | content surface |
| `radius/profile` | 20 | profile surface |
| `radius/xl` | 22 | sheet / glass navigation |
| `radius/fab` | 28 | floating action button |
| `radius/2xl` | 30 | signature outer contour only |
| `radius/connection` | 44 | исходный connection control `148×130` |
| `radius/contour-1` | 62 | первый открытый периметр, offset `+18` |
| `radius/contour-2` | 82 | второй открытый периметр, offset `+38` |
| `radius/full` | 999 | toggle thumb, circular icon button only |

Одинаковый радиус на всех элементах запрещён. Editable input использует radius `12`, profile surface — `20`, FAB — `28`. Для connection signature действуют точные component overrides `44 / 62 / 82`, а не общая шкала content surfaces.

## 4.5 Surfaces

1. **Canvas:** `background/default`, без card chrome.
2. **Content group:** `surface/primary`; объединяет семантически связанные строки. Может не иметь внешней рамки, если достаточно luminance.
3. **Nested/selected:** `surface/secondary` или `accent/subtle`; используется для выбранного item, вложенного editor или раскрытой группы.
4. **Elevated content:** `surface/elevated`; dialog/sheet body, popover, критическое сообщение. Плотный, чтобы текст не зависел от фона.
5. **Functional glass:** `surface/glass-regular`; navigation, toolbar, floating action strip. Не используется для длинных текстов, логов и плотных таблиц.

## 4.6 Borders and shadows

- `stroke/subtle`: 1 px `border/subtle`, внутренние dividers.
- `stroke/default`: 1 px `border/default`, field/button edge.
- `stroke/focus`: 2 px `focus/ring` + 2 px offset.
- `stroke/signature`: 1–1.5 px, цвет зависит от state; непрозрачность не ниже уровня, различимого на canvas.
- Glass edge: 1 px inner highlight сверху/слева и 1 px lowlight снизу/справа; не обводить белым одинаково по всему периметру.
- `shadow/low`: `0 2 8 rgba(5,16,11,.14)` dark; `0 2 8 rgba(35,60,44,.08)` light.
- `shadow/medium`: `0 10 28 rgba(5,16,11,.22)` dark; `0 10 28 rgba(35,60,44,.12)` light.
- `shadow/glass`: `0 12 36 rgba(5,16,11,.24)` dark; `0 12 36 rgba(35,60,44,.14)` light + inner highlight.

Dark-mode elevation строится прежде всего разницей surface luminance и кромкой. Большой чёрный drop shadow без surface difference не используется.

---

# Part 5 — Component language

## 5.1 Buttons

| Variant | Height | Radius | Fill / border | Hover | Pressed | Disabled |
|---|---:|---:|---|---|---|---|
| Primary | 48; compact 40 | 12 | `accent/default`, без border | `accent/hover` | `accent/pressed`, scale `.98` или translateY `1px` | surface secondary, text tertiary, без shadow |
| Secondary | 48; compact 40 | 12 | `surface/secondary`, `border/default` | surface elevated | translateY `1px`, border stronger | 45% visual emphasis |
| Tertiary | 40 | 8 | transparent | `accent/subtle` | accent subtle stronger | text tertiary 45% |
| Destructive | 48 | 12 | `status/error`; либо tonal для менее опасного действия | темнее/плотнее на 6–8% | translateY `1px` | 45% emphasis |
| Icon button | 40×40 minimum visual, platform touch target | 12 или full только для круглого glyph | dense surface или glass в chrome | edge highlight | scale `.96` | 40% emphasis |
| FAB | сохраняет исходный размер | 28 | accent/dense surface по роли исходного действия | edge highlight | scale `.98` | 40% emphasis |

Label не заменяется иконкой, если Baseline использует текст. На мобильном pointer hover не требуется, но состояния hover сохраняются для desktop/tablet pointer. Pressed не должен двигать соседние элементы.

## 5.2 Inputs and controls

- **Text field:** min height 48, radius 12, `surface/secondary`, 1 px border. Focus — 2 px ring; error — error icon + исходный/существующий текст, не только красная рамка. Placeholder — `text/tertiary`, но реальное значение — `text/primary`.
- **Search:** тот же field, leading search glyph, clear action только если он уже есть в Baseline. В proxy list сохраняется текущее положение и поведение.
- **Toggle:** track 44×26 как стартовая метрика, thumb 22. Off: neutral track + видимая ручка; On: accent/connected fill + смещение. Строка и label остаются источником значения для accessibility.
- **Segmented control:** плотная общая surface; выбранный сегмент — raised/contrast fill и semibold text. Не использовать один цвет как единственный selected signal.
- **Checkbox:** 20×20, radius 6; selected — accent fill + check; mixed — horizontal mark. Не добавлять checkbox туда, где Baseline использует другой паттерн.
- **Radio:** 20×20; selected — inner dot + stronger outer border.
- **Slider:** track 4, thumb 22; active track accent, inactive border/default. Numeric value остаётся там, где оно уже есть.
- **Row disclosure:** chevron secondary; весь существующий tappable row сохраняет hit area. Divider начинается по текстовой оси, если текущая структура это допускает.

## 5.3 Navigation

- Top/bottom/navigation chrome следует исходной модели Baseline и не переезжает.
- Статическая геометрия сохраняет исходное место navigation: outer `393×90`; внутри capsule `361×66`, radius `33`, padding `6` по вертикали и `8` по горизонтали; chosen item `70×32`.
- Material: visual Regular Liquid Glass с fill `#F9FCF3E8` light / `#24392DE8` dark и edge `#FFFFFFCC` light / `#BBD9BD66` dark. Нативное адаптивное поведение остаётся proposed до реализации.
- Активный item: selected fill `#DDEBDD` light / `#314F3B` dark, более сильный glyph и label. Не полагаться только на зелёный.
- На scroll стеклянный chrome визуально отделяется edge highlight и системным поведением; в статическом макете показывается один репрезентативный state.
- При Reduce Transparency glass заменяется на `surface/elevated` 96–100% opacity с border.

## 5.4 Cards and lists

- Card существует только для семантической группы или elevation. Одиночная setting row не получает отдельную floating card.
- Proxy/profile/settings списки используют section surface + dividers, сохраняя исходные строки и порядок.
- Selected proxy/profile обозначается минимум двумя признаками: `selection/default` (`#DDEBDD` light / `#314F3B` dark) и glyph/check/исходный indicator.
- Logs используют максимально плотную непрозрачную поверхность, моноширинный шрифт только если он уже предусмотрен для содержимого. Glass, glow и signature за текстом логов исключены.

## 5.5 Dialogs and sheets

- Сохраняются исходный тип, размер, кнопки, порядок и dismiss behavior.
- Chrome/handle может использовать Liquid Glass; тело с input/error/help text — плотный `surface/elevated`.
- Import dialogs визуально выделяют drop/input area border, но не добавляют новый способ импорта.
- Destructive/cancel hierarchy совпадает с Baseline.

## 5.6 Accessibility modes

- **Reduce Transparency:** glass → плотная elevated surface, blur отсутствует.
- **Increase Contrast:** border/default становится сильнее; tertiary text не используется для необходимой информации.
- **Reduce Motion:** contour movement → 120–180 ms crossfade между статическими геометриями; бесконечное движение отключается.
- **Differentiate Without Color:** state label + icon/shape pattern обязательны; green/red не являются единственным каналом.
- Dynamic Type: текстовые компоненты должны расширяться и переноситься по правилам платформы; signature уступает место тексту, а не наоборот.

---

# Part 6 — VPN state language

Исходные названия статусов WIR сохраняются дословно. Ниже указана семантика; она не является разрешением переписать UI-copy.

| State | Color | Shape / icon | Motion | Surface treatment |
|---|---|---|---|---|
| Protected / Connected | `status/connected` | вложенные контуры совмещены, один фирменный разрыв; исходная success/status icon | короткая фиксация 220 ms, затем статично | очень слабый connected tint 6–10%, без постоянного glow |
| Connecting | `status/connecting` | контуры приближаются, разрывы ещё не совпали; progress indicator | segment travel 900–1200 ms, linear/standard loop | accent subtle field 8–12% |
| Disconnecting | neutral + secondary text | контуры расходятся на 2–4 px; исходный progress indicator | reverse settle 180–240 ms | connected tint быстро исчезает |
| Unprotected / Disconnected | neutral border + primary text | рамки разведены, два разрыва расположены несогласованно; исходная status icon | статично | canvas/surface без warning tint, если Baseline не считает это ошибкой |
| Connection error | `status/error` | один контур прерван дополнительным коротким gap; error icon | один короткий edge pulse 180 ms, затем статично | error tint 8–12% на плотной поверхности |
| No internet | `status/warning` | параллельные контуры смещены; warning icon | короткий lateral shift 160 ms, без loop | warning tint 8–12% |
| Reconnecting | `status/connecting` + warning context | рамки частично совмещены; reconnect/progress icon | два прохода segment, затем спокойный loop | accent/warning tint, но текст сохраняет точный state |

Правила:

- Любое состояние читается текстом до декоративного motif.
- Error не должен мерцать постоянно. Connected не пульсирует бесконечно.
- Connecting loop прекращается сразу после реального изменения state; декоративная анимация не имитирует прогресс во времени.
- Если Baseline различает дополнительные loading/error состояния, применяются ближайшие семантические токены без нового текста и действия.

---

# Part 7 — Signature visual

## 1. Nested open contour frames — выбранный вариант

**Вид:** исходный connection control `148×130`, radius `44`, окружён двумя вложенными открытыми периметрами. Первый построен с offset `+18` и radius `62`, второй — с offset `+38` и radius `82`. Оба имеют stroke `1`, проходят по верхней, правой и левой сторонам и открыты снизу; opacity внутреннего/внешнего периметра `0.60` / `0.25`. Геометрия не образует щит, круг, глобус или power glyph.

**State reaction:** disconnected — рамки немного разведены и разрывы не совпадают; connecting — разрывы движутся к одной оси; connected — рамки устойчиво совмещены, сохраняется один намеренный gap; error — появляется дополнительный короткий разрыв.

**Применение:** Home как полный motif; loading — один фрагмент контура; selected proxy/profile — короткий corner fragment; about/intro — статический крупный crop. В настройках не повторяется вокруг каждой секции.

**Сложность:** средняя. Нужны vector paths и state interpolation, но не shader.

**Узнаваемость:** высокая.

## 2. Offset boundary

**Вид:** две параллельные незамкнутые границы, слегка смещённые относительно друг друга.

**State reaction:** расстояние между ними уменьшается при подключении; warning показывает локальный сдвиг; error — разрыв оси.

**Применение:** разделители, sheet edge, selected row, intro illustration.

**Сложность:** низкая.

**Узнаваемость:** средняя: легко превратить в обычную рамку.

## 3. Routed notch

**Вид:** у контейнеров появляется асимметричный ступенчатый вырез, через который проходит короткая линия состояния.

**State reaction:** линия проходит notch при connecting, фиксируется внутри при connected, останавливается перед ним при error.

**Применение:** connection control, active server row, import progress, dialogs.

**Сложность:** средняя.

**Узнаваемость:** высокая, но форма может конфликтовать с platform chrome.

## 4. Quiet field lens

**Вид:** нерегулярное матовое поле с одним резким краем, словно lens фокусирует фон.

**State reaction:** поле сжимается/фокусируется при подключении; теряет фокус при disconnected; смещается при switching.

**Применение:** Home, intro, background loading state.

**Сложность:** высокая: blur/shader/performance и accessibility fallbacks.

**Узнаваемость:** высокая, но ближе к Atmosphere, чем к Contour.

## 5. Signal splice

**Вид:** тонкая линия с намеренным разрывом и короткой перпендикулярной вставкой.

**State reaction:** вставка выравнивается с основной линией при connected; проходит вдоль gap при connecting; отклоняется при error.

**Применение:** list selection, progress, navigation active state, chart-like data rows.

**Сложность:** низкая.

**Узнаваемость:** средняя.

## Сравнение

| Signature | Узнаваемость / 10 | Масштабируемость / 10 | Реализация: 1 просто, 5 сложно | A11y устойчивость / 10 | Риск клише |
|---|---:|---:|---:|---:|---:|
| Nested open contour frames | 9 | 9 | 3 | 9 | низкий |
| Offset boundary | 7 | 9 | 2 | 9 | средний |
| Routed notch | 8 | 8 | 3 | 8 | низкий |
| Quiet field lens | 8 | 6 | 5 | 6 | средний |
| Signal splice | 6 | 10 | 1 | 9 | средний |

**Выбор:** Nested open contour frames. Он лучше всего связывает состояние, бренд и главный control, работает статически при Reduce Motion и масштабируется до фрагмента без потери характера. Для Home фиксируется точная статическая геометрия `148×130 / r44`, два периметра `+18 / r62` и `+38 / r82`, stroke `1`, bottom opening, opacity `0.60 / 0.25`. Малый fragment на других экранах может масштабировать эти пропорции, но не добавляет третий периметр.

---

# Part 8 — Motion

> **Статус: proposed native behavior.** Эта часть не описывает реализованную анимацию статических копий. Durations, easing и transitions должны быть проверены в приложении на реальных state events.

## Principles

- Motion сообщает изменение state и пространственную связь.
- Основные переходы укладываются в 120–320 ms; loop используется только пока система действительно находится в connecting/loading.
- Не использовать overshoot, spring bounce, elastic easing и постоянный glow.
- Анимировать transform, opacity и path progress; layout не должен прыгать.
- Контентный текст обновляется синхронно с реальным state, а не с окончанием декоративной анимации.

## Timing and easing

| Token | Значение | Использование |
|---|---|---|
| `motion/instant` | 100 ms | icon feedback, small opacity |
| `motion/fast` | 160 ms | pressed, selection, error edge |
| `motion/base` | 220 ms | button, row, state settle |
| `motion/slow` | 320 ms | sheet, navigation, contour assembly |
| `motion/loop` | 900–1200 ms | connecting/loading segment only |
| `ease/standard` | cubic-bezier(.2,.8,.2,1) | большинство переходов |
| `ease/enter` | cubic-bezier(.16,1,.3,1) | появление layer |
| `ease/exit` | cubic-bezier(.4,0,1,1) | исчезновение |
| `ease/linear` | linear | progress along path only |

## Transitions

- **Connect:** pressed feedback 100 ms; outer contour begins assembly immediately; label/state updates по данным приложения; финальная фиксация 220 ms. Общая декоративная последовательность не дольше 500 ms после фактического connected.
- **Disconnect:** tint fades 160 ms; contours separate 220 ms; no reverse celebratory effect.
- **Connecting:** один segment движется по незамкнутому пути 900–1200 ms. Не вращать весь объект.
- **Server switch:** selected row crossfade 160 ms; на Home contour делает один короткий lateral alignment 220 ms. Не добавлять отдельный экран/шаг.
- **Navigation:** content crossfade + translate 4–8 px, 180–240 ms; glass chrome остаётся устойчивым, если так ведёт себя исходная модель.
- **Modal/sheet:** opacity + translateY 12–20 px, 280–320 ms enter, 180–220 ms exit. Background dim спокойный, без масштабирования всего экрана.
- **Success:** один edge highlight проходит 120–180 ms и исчезает; затем статичный status.
- **Error:** один короткий edge pulse 160–180 ms и error tint; никакой бесконечной тряски.
- **Loading:** skeleton/contour segment повторяет форму фактического контента. Spinner сохраняется, если он является частью исходного UX и замена изменила бы ожидания.

### Accessibility motion

При Reduce Motion path morph и segment travel отключаются. Используется crossfade 120–180 ms между заранее заданными статичными состояниями. Connecting остаётся различимым через системный progress indicator/текст Baseline. Нельзя оставлять статичный connected motif при продолжающемся connecting.

---

# Part 9 — Screen application

Все указания применяются к копии рядом с Baseline. Перед переносом дизайнер сравнивает frame-by-frame: количество элементов, тексты, порядок, bounds основных блоков, навигацию и действия.

| Existing screen | Keep unchanged | Visual changes | Components / tokens | Special treatment |
|---|---|---|---|---|
| Intro | количество шагов, тексты, CTA, порядок | canvas, typography, button style, decorative background | background, title/body, primary button | статический крупный crop contour; не добавлять onboarding step |
| Home | все блоки, status labels, selector, connect action, metrics | Contour motif, semantic state, surfaces, type | signature, state tokens, buttons, data styles | единственный полный signature cluster |
| Proxy list | поиск/фильтры, строки, порядок, selection, действия | grouped rows, selected tonal surface, glass nav | search, row, divider, active state | маленький corner-fragment только у selected item |
| Proxy profile | поля, значения, actions, hierarchy | плотные field groups, data typography, dividers | field, section, buttons, status | без декоративного motif за данными |
| Settings | секции, порядок, labels, navigation | grouped surfaces, typography, disclosure rows | content group, toggle, chevron, nav glass | не делать каждую row отдельной card |
| General | все настройки и controls | единые toggle/segmented/fields | controls, semantic surfaces | исходные значения и labels дословно |
| Routing | все правила, controls и порядок | чёткие groups, selection/focus states | row, segmented, fields, buttons | contour fragment только как active marker, если нужен |
| DNS | поля, switches, help text | dense content surface, accessible focus/error | field, toggle, caption, error | технические значения tabular; glass не использовать под текстом |
| Inbound | поля, switches, order | единый form language | fields, toggles, section surfaces | сохранить техническую плотность |
| TLS | все настройки, warning/error content | semantic warning/error, field hierarchy | fields, warning surface, buttons | warning включает icon + text + color |
| WARP | исходный state, controls и details | state treatment, selected surfaces | status, toggle/button, data | не добавлять новую связь с account/subscription |
| Logs | content, filters/actions, ordering | максимальная читаемость, плотный background | dense surface, mono/data style where present | никаких blur/gradient/glass за логами |
| About | тексты, version/build, links/actions | clean typography, subtle motif crop | title/body, tertiary actions | статичный contour fragment как brand mark, без новых ссылок |
| Import dialogs | способ импорта, fields, buttons, cancel/confirm | elevated dense body, glass chrome, focus/error | dialog, field, progress, buttons | не добавлять QR/file/url option, если его нет |
| Loading states | точки появления и реальная логика | skeleton/segment style под существующий layout | loading semantic, contour fragment | не имитировать прогресс процентами |
| Error states | исходные тексты, действия и placement | error tint, broken contour, icon/text hierarchy | status/error, alert surface, buttons | цвет всегда дублируется icon/shape/text |

## Подробности ключевых экранов

### Intro

Сохраняются исходные hero, текст и CTA. Background получает `background/default`, заголовок — `title/1` или фактический ближайший стиль, CTA — Primary. Декоративный contour может выходить за край frame, но не перекрывает текст и не создаёт новый swipe cue. В light mode motif строится `border/default` + accent segment; в dark — subtle border + один более светлый edge.

### Home

Верхняя навигация и все блоки остаются на исходных координатных отношениях. Контурная система обрамляет существующую область connection control; сам tap target не сужается и не раздваивается. Status label имеет наибольший semantic priority. Selector — плотная secondary surface с border; IP/protection data используют `data/body` и сохраняют исходную группировку. В connected state accent не заливает весь экран.

### Proxy list

Поиск получает единый field treatment. Список живёт на canvas или общей `surface/primary`; строки разделены subtle dividers. Выбранный proxy отличается tonal fill, более сильным текстом и существующим indicator. Флаги, latency, load и secondary metadata не изобретаются: стилизуются только если уже есть. Navigation/chrome — glass regular, content — плотный.

### Proxy profile

Заголовок, поля, действия и порядок остаются прежними. Profile surface использует radius `20`, editable inputs — radius `12`. Значения IP/port/ID используют data style; sensitive/technical values не декорируются blur. Секции различаются spacing и luminance, а не стопкой одинаковых карточек. Primary и destructive action сохраняют исходный hierarchy.

### Settings и вложенные экраны

Settings, General, Routing, DNS, Inbound, TLS и WARP используют общую строку: min touch target по платформе, leading icon только если он уже есть, label, value/description, trailing control. Секции отделены 24–32 px; внутри — dividers. Glass закреплён за navigation и floating actions. В warning/error блоках используются semantic surface + icon + текст.

### Logs

Приоритет — плотность и чтение. `surface/primary` непрозрачная; primary/secondary text контрастные. Фильтры, clear/share/copy и другие действия остаются только там, где уже присутствуют. Contour не анимируется на фоне логов.

### About

Сохраняются текущие version/build, тексты и действия. Малый статичный fragment signature допускается рядом с существующей brand area. Новые legal/support/social links не добавляются.

### Import dialogs

Dialog geometry и порядок кнопок не меняются. Тело — `surface/elevated`, chrome/handle может быть glass regular. Focus, loading и error состояния видимы; исходный input и способ импорта сохраняются. Progress не превращается в процент, если приложение его не предоставляет.

### Loading and error

Loading повторяет геометрию будущего контента и не показывает ложные данные. Error сохраняет исходный copy и recovery action. Broken contour — secondary cue; первым остаётся текст. Для no internet применяется warning palette, для connection failure — error palette, если Baseline действительно различает эти состояния.

## Отсутствующие экраны

Account, Subscription, Upgrade и самостоятельный Server details вне существующего proxy profile не создаются. Если они позже появятся в `WIR Baseline`, система применяется по тем же правилам после фиксации их исходной структуры.

## Visual consistency audit

| Проверка | Решение системы | Статус спецификации |
|---|---|---|
| Единая hierarchy | общая type scale, surfaces и spacing | заложено; проверить на копиях |
| Не слишком много accents | один зелёный accent + semantic warning/error | заложено |
| Cards не везде | grouped sections + dividers, cards только по смыслу | заложено |
| Interactive vs static | fill/border/focus/pressed для controls | заложено |
| Читаемость | плотный content layer, glass только chrome | заложено; нужен contrast audit на frames |
| Dark/light parity | обе semantic palettes определены | заложено; нужна визуальная проверка обеих тем |
| Узнаваемость без логотипа | nested open contour motif | заложено |
| Не VPN template | нет shield/lock/globe/tunnel/power, нет neon cyber | заложено |
| Mobile/tablet/desktop | semantic tokens и scalable motif | заложено; конкретные responsive frames не подтверждены |
| Premium consumer software | material restraint, type, motion, optical edges | заложено; требует нативной проверки |

Документ не утверждает, что экраны уже отрисованы, контраст автоматически проверен, motion реализован или нативное поведение Apple подтверждено.

---

# Part 10 — Implementation brief

## 10.1 Структура файла / pen.dev

1. Зафиксировать оригинальную группу `WIR Baseline` как read-only source of truth.
2. Создать рядом отдельную группу `WIR Reskin — Contour 2026-10-04`.
3. Копировать все существующие Baseline frames один к одному, сохраняя порядок и размер. Имена: `<Original name> — Contour`.
4. Не создавать отсутствующие Account/Subscription/Upgrade frames.
5. Добавить служебный style board вне пользовательских frames: palette light/dark, typography, surfaces, controls, states, signature geometry и motion notes.

## 10.2 Variables first

Создать коллекции:

- `Color / Light` и `Color / Dark` — все semantic tokens из Part 4.
- `Type` — Inter для UI с исходными body sizes, screen heading `22/28/600`; JetBrains Mono для JSON/logs; display, headline, callout, caption, micro и data styles.
- `Space` — 0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64.
- `Radius` — общие 6, 8, 12, 16, 22, 30, full; component overrides profile `20`, FAB `28`, connection `44`, contour `62/82`, navigation capsule `33`.
- `Stroke` — subtle, default, focus, signature.
- `Elevation` — low, medium, glass.
- `Motion` — instant, fast, base, slow, loop + easing notes.

## 10.3 Components first

Порядок сборки:

1. `Surface / Content`, `Surface / Elevated`, `Surface / Glass Regular` с light/dark и accessibility fallback.
2. `Button` variants: primary, secondary, tertiary, destructive, icon; states: default, hover, pressed, focus, disabled, loading.
3. `Field` variants: text, search; states: default, focus, filled, disabled, error.
4. `Control`: toggle, segmented, checkbox, radio, slider.
5. `Row`: navigation/disclosure, value, toggle, selected proxy/profile, warning/error.
6. `Navigation`: только существующие Baseline variants; outer `393×90`, capsule `361×66 / r33 / padding 6,8`, chosen item `70×32`; glass regular + Reduce Transparency fallback.
7. `Dialog/Sheet`: existing sizes/structures; dense body + optional glass chrome.
8. `Status`: connected, connecting, disconnecting, unprotected, error, no internet, reconnecting.
9. `Signature / Nested Contour`: size `hero`, `medium`, `fragment`; state variants; light/dark; reduced motion static states.
10. `Loading`: skeleton/segment, только для фактических Baseline layouts.

## 10.4 Frame pass

Применять систему в таком порядке: Home → proxy list/profile → settings и вложенные экраны → import dialogs → logs/about → intro → loading/error → light-mode parity. После каждого экрана делать overlay comparison с Baseline: UX/content/nav/action bounds должны совпадать; любое отклонение объясняется только spacing/radius/type optical polish.

## 10.5 Native handoff — proposed behavior

- На Apple-платформах навигационный и action chrome должны опираться на системный Liquid Glass согласно Apple HIG и WWDC25 guidance.
- Статические opacity/blur/shadow значения из макета описывают вид, а не служат рецептом ручной реализации нативного материала.
- Проверить Reduce Transparency, Increase Contrast, Reduce Motion, Differentiate Without Color и Dynamic Type.
- Проверить status transition на реальных состояниях подключения: декоративный state не должен опережать данные приложения.
- Проверить performance vector-path animation; fallback — crossfade статичных contour states.

## 10.6 Definition of done для дизайн-копии

- Все существующие `WIR Baseline` frames имеют отдельные соседние копии; оригиналы не изменены.
- Тексты, labels, функции, порядок и навигация совпадают с Baseline.
- Light и dark используют semantic variables, а не локальные цвета.
- Home показывает минимум disconnected, connecting, connected и error/relevant states только в объёме, который существует в Baseline.
- Glass ограничен navigation/action chrome; logs, forms и content остаются читаемыми на плотных поверхностях.
- Signature не образует shield, globe, lock, tunnel или power glyph.
- В каждом критическом state есть текст + форма/иконка + цвет.
- Выполнен contrast audit на реальных frames и visual diff/overlay с Baseline.
- Нативное соответствие Liquid Glass считается подтверждённым только после реализации и проверки в приложении, а не по статическому pen.dev-макету.
