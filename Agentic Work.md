# Master-Playbook: Autonome Codebase-Steuerung mit Qwen 3.8 27B, LM Studio & Pi Agent (32 GB VRAM Edition)

Dieses Handbuch ist die technische Komplettreferenz für den Betrieb von **Qwen 3.8 27B** auf einer **32 GB VRAM GPU** unter **LM Studio** in Kombination mit dem **Pi Coding Agent (`pi`)**. Es ist speziell darauf ausgelegt, aus **nicht-technischen, menschlichen Anforderungen („Vibe-Specs“)** auf einer **großen Bestands-Codebase** zuverlässigen, produktionsreifen Code zu generieren – ohne in endlosen Auto-Compaction-Schleifen, VRAM-Overflows oder dem gefürchteten *Context Rot* unterzugehen.

---

## 1. Architektur- & Hardware-Fundament

Um das Maximum aus 32 GB VRAM herauszuholen, muss man verstehen, wie sich **Qwen 3.8 27B** unter der Haube von klassischen Transformern unterscheidet.

### 1.1 Die Hybrid-GDN-Architektur
Qwen 3.8 27B besitzt $64$ Layer, nutzt aber **keine** klassische Voll-Attention über alle Schichten. Stattdessen kommt ein hybrides Design im Verhältnis $3:1$ zum Einsatz:

$$\text{Architektur} = 16 \times \left(3 \times \text{Gated DeltaNet} \rightarrow 1 \times \text{Gated Attention}\right)$$

* **$48$ Layer sind Gated DeltaNet (Linear Attention / SSM-ähnlich):** Diese Schichten benötigen **keinen wachsenden KV-Cache**. Sie halten lediglich einen kompakten, rekurrenten Zustand (State) im Speicher, der unabhängig von der Kontextlänge konstant rund $72\text{ MiB}$ belegt.
* **$16$ Layer sind klassische Gated Attention:** Nur diese $16$ Schichten skalieren linear mit der Kontextlänge ($4$ KV-Heads, Head-Dimension $d_k = 256$).

### 1.2 Exakte KV-Cache-Mathematik für 32 GB VRAM
Der Speicherbedarf pro Token im KV-Cache berechnet sich nur über die $16$ Gated-Attention-Layer:

$$\text{Bytes pro Token (FP16)} = 16 \text{ Layer} \times 2 \text{ (K, V)} \times 4 \text{ Heads} \times 256 \text{ Dim} \times 2 \text{ Bytes} = 65\,536 \text{ Bytes} = 64\text{ KiB/Token}$$

Durch eine Quantisierung des KV-Caches auf **8-Bit (`Q8_0`)** halbiert sich der Wert auf **$32\text{ KiB/Token}$**, ohne dass die Perplexity oder die Präzision bei Zeilennummern und Code-Diffs messbar leidet.

| VRAM-Komponente | 125k @ `FP16` | 262k @ `FP16` | **262k @ `Q8_0` (Optimum)** | 262k @ `Q4_0` (Nicht empfohlen) |
| :--- | :--- | :--- | :--- | :--- |
| **Modellgewichte (`Q4_K_M` / `UD-Q4_K_XL`)** | $16{,}1\text{ GiB}$ | $16{,}1\text{ GiB}$ | **$16{,}1\text{ GiB}$** | $16{,}1\text{ GiB}$ |
| **MTP-Draft-Head (`Q4_0`) & Vision** | $2{,}1\text{ GiB}$ | $2{,}1\text{ GiB}$ | **$2{,}1\text{ GiB}$** | $2{,}1\text{ GiB}$ |
| **Gated DeltaNet State ($48$ Layer)** | $0{,}07\text{ GiB}$ | $0{,}07\text{ GiB}$ | **$0{,}07\text{ GiB}$** | $0{,}07\text{ GiB}$ |
| **KV-Cache ($16$ Layer)** | $7{,}8\text{ GiB}$ | $16{,}0\text{ GiB}$ | **$8{,}0\text{ GiB}$** | $4{,}0\text{ GiB}$ |
| **Compute Buffer & CUDA Context** | $2{,}0\text{ GiB}$ | $2{,}5\text{ GiB}$ | **$2{,}5\text{ GiB}$** | $2{,}5\text{ GiB}$ |
| **Gesamt-VRAM** | **$28{,}07\text{ GiB}$** | **$36{,}77\text{ GiB}$ (OOM)** | **$28{,}77\text{ GiB}$ (Sweetspot)** | **$24{,}77\text{ GiB}$ (Diff-Fehler!)** |

> **Wichtige Warnung zu 4-Bit KV-Cache (`Q4_0`):** Während der K-Cache notfalls `Q4_0` verträgt, führt ein auf 4-Bit quantisierter V-Cache bei Qwen 3.8 auf `xhigh` oder `high` zu leichtem Rauschen in der Token-Aufmerksamkeit. Beim `edit`-Tool von `pi` (welches exakte String-Ersetzungen im Quellcode verlangt) schlagen dadurch regelmäßig Patches wegen abweichender Einrückungen oder halluzinierter Variablennamen fehl. Bleibe zwingend bei **`Q8_0` für K und V**.

### 1.3 Multi-Token Prediction (MTP) & Der 5-Token-Cliff
Standardmäßige autoregressive Inferenz bei Batch-Size $1$ ist extrem **Memory-Bandwidth-bound**: Für jedes generierte Token müssen rund $17\text{ GB}$ Gewichte durch den Speicherbus geschleust werden. Der integrierte 1-Layer-MTP-Head von Qwen 3.8 rät $N$ zukünftige Tokens mit minimalem Aufwand voraus, die das Hauptmodell in **einem einzigen parallelen Forward-Pass** verifiziert.

Da die Trefferquote (Acceptance Rate $\alpha$) mit jedem weiteren geratenen Token exponentiell sinkt ($\alpha_k \approx \alpha_1^k$) und verworfene Draft-Tokens ein Zurückrollen (Rollback) der rekurrenten Gated-DeltaNet-States erfordern, ergibt sich in Benchmarks auf High-End-GPUs folgende Kurve:

* **$N = 0$ (Kein MTP):** ca. $46\text{--}48\text{ Tokens/s}$
* **$N = 2\text{ bis }3$:** ca. $75\text{--}85\text{ Tokens/s}$ (extrem stabil bei freiem Reasoning)
* **$N = 4\text{ bis }5$ (Sweetspot für Code):** ca. $88\text{--}96\text{ Tokens/s}$ ($\approx 2\times$ Speedup, da Code-Syntax, Einrückungen und JSON-Tool-Calls sehr gut vorhersehbar sind)
* **$N \ge 6$ (Der Performance-Cliff):** Der Verwaltungs- und Rollback-Overhead übersteigt den Gewinn; bei $N = 15$ bricht die Geschwindigkeit auf unter $9\text{ Tokens/s}$ ein.

---

## 2. LM Studio & System-Konfiguration

### 2.1 Betriebssystem-Schutz: Shared GPU Memory Fallback deaktivieren
Auf Systemen mit $32\text{ GB}$ VRAM lauert bei $28{,}8\text{ GB}$ Belegung eine massive Falle: Wenn Windows oder ein Hintergrundprozess (Browser, IDE, Discord) kurzzeitig $2\text{ GB}$ VRAM anfordert, lagert der Grafiktreiber Teile des KV-Caches oder der Modell-Layer stillschweigend in den langsamen System-RAM ( über PCIe) aus. Das Modell stürzt nicht ab, aber die Geschwindigkeit fällt sofort von $90\text{ t/s}$ auf $4\text{ t/s}$.

* **Nvidia Systemsteuerung (Windows):** Gehe zu *3D-Einstellungen verwalten* $\rightarrow$ *CUDA - Sysmem-Fallback-Richtlinie* und stelle diese für `LM Studio.exe` (bzw. `llama-server`) auf **„Kein System-Speicher-Fallback bevorzugen“**.
* **Browser & IDE:** Falls du VS Code, Cursor oder Chrome parallel auf demselben Rechner nutzt, reduziere das Kontextfenster in LM Studio von $262\,144$ auf **$196\,608$ Tokens** (spart genau $2{,}0\text{ GiB}$ VRAM und hält dich sicher bei ca. $26{,}7\text{ GiB}$).

### 2.2 LM Studio Model Loader & Server Settings (Checkliste)

Stelle in LM Studio vor dem Laden des Modells (`Qwen3.8-27B-UD-Q4_K_XL.gguf` oder `Q4_K_M.gguf` inkl. `mtp`-Head) folgende Parameter ein:

| Kategorie | Parameter in LM Studio | Exakter Zielwert | Begründung |
| :--- | :--- | :--- | :--- |
| **Context** | Context Length (`n_ctx`) | `262144` (oder `196608`) | Volles natives Fenster als Sicherheits-Obergrenze gegen OOM. |
| **Memory** | GPU Offload (`n_gpu_layers`) | `64 / 64` (Max) | Alle $64$ Layer + Output-Head müssen im VRAM liegen. |
| **Memory** | K-Cache Quantization Type | `Q8_0` | Halbiert K-Cache-Speicher ohne Qualitätsverlust. |
| **Memory** | V-Cache Quantization Type | `Q8_0` | Halbiert V-Cache-Speicher (erfordert Flash Attention). |
| **Memory** | Offload KV Cache to GPU | `ON` (Aktiviert) | Zwingend nötig, sonst berechnet die CPU die Attention. |
| **Compute** | Flash Attention (`flash_attn`) | `ON` (Aktiviert) | Pflicht für `Q8_0` V-Cache und verhindert $O(n^2)$ Speicher-Spikes. |
| **Compute** | Evaluation Batch Size (`n_batch`) | `2048` (oder `4096`) | Beschleunigt das Einlesen großer Dateien (Prompt Processing). |
| **Compute** | Physical Batch Size (`n_ubatch`) | `512` (oder `1024`) | Verhindert Compute-Buffer-Spikes beim Prompt-Processing. |
| **MTP / Spec** | Draft Tokens Max (`spec-draft-n-max`) | `4` oder `5` | Optimaler Durchsatz für Code und strukturierte Tool-Calls. |
| **MTP / Spec** | Draft Minimum Probability (`p_min`) | `0.75` | Bricht den Draft-Baum frühzeitig ab, wenn der MTP-Head unsicher wird. |
| **Caching** | Keep Model in Memory | `ON` | Verhindert Entladen während längerer User-Denkpausen. |
| **Caching** | Cache Prompt / Slot Similarity | `ON` | Übernimmt den berechneten KV-Prefix zwischen aufeinanderfolgenden `pi`-Turns. |
| **Sampling** | Temperature | `0.6` | Verhindert deterministische Endlosschleifen bei fehlgeschlagenen Edits. |
| **Sampling** | Top-P / Min-P / Top-K | `0.95` / `0.05` / `20` | Offizielle Qwen-3.8-Empfehlung für präzises Reasoning & Coding. |
| **Reasoning** | Parse `<think>` Tags / History | **Exclude old `<think>` from History** | Alte Denk-Monologe vergangener Schritte dürfen den KV-Cache nicht aufblähen! |

### 2.3 Äquivalente `llama-server` / LM Studio Backend-Konfiguration (`config.json` / CLI)

Falls du den Server-Tab von LM Studio über die CLI (`lms`) oder direkt das darunterliegende `llama.cpp`-Backend steuerst, entspricht das folgendem Aufruf:

```bash
llama-server \
  --model Qwen3.8-27B-UD-Q4_K_XL.gguf \
  --model-draft Qwen3.8-27B-mtp-Q4_0.gguf \
  --ctx-size 262144 \
  --n-gpu-layers 99 \
  --flash-attn \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --batch-size 2048 \
  --ubatch-size 512 \
  --spec-type draft-mtp \
  --spec-draft-n-max 5 \
  --spec-draft-p-min 0.75 \
  --temp 0.6 \
  --top-p 0.95 \
  --min-p 0.05 \
  --top-k 20 \
  --parallel 1 \
  --cache-reuse 256 \
  --reasoning-format deepseek \
  --no-context-shift
```

> **Kritischer Parameter `--parallel 1`:** Setze die Anzahl paralleler Server-Slots zwingend auf $1$. Wenn LM Studio $4$ Slots reserviert, teilt es entweder deine $262\,144$ Tokens durch $4$ (sodass jeder Slot nur $65\text{k}$ hat) oder vervierfacht den KV-Cache-Bedarf!

---

## 3. Der 4-Phasen-Workflow für „Vibe-Specs“ auf großen Codebases

### 3.1 Warum das 27B-Modell ohne Struktur ab 120k Tokens versagt
Ein $27\text{B}$-Modell besitzt eine hervorragende lokale Logik, hat aber zwei physikalische Grenzen:
1. **Die Vokabular-Kluft (Domain Gap):** Du formulierst menschlich (*„Kunden sollen im Dashboard ihre Storno-Frist sehen“*). Im Code heißt das Modul aber `SubscriptionRetentionPolicyResolver.ts`. Ohne Übersetzungs-Phase liest der Agent $30$ falsche Dateien komplett ein, verbrennt $90\,000$ Tokens Kontext und rät am Ende.
2. **Die „Dumb Zone“ ab $100\text{k}\text{--}120\text{k}$ Tokens (*Context Rot*):** Obwohl das Modell technisch $262\text{k}$ Tokens unterstützt, sinkt die effektive Aufmerksamkeit in der Mitte des Kontexts (*Lost in the Middle*) jenseits von $120\text{k}$ deutlich ab. Das Modell vergisst subtile Randbedingungen aus deinem ersten Prompt.
3. **Destruktive Auto-Compaction:** Wenn `pi` mitten in einer Fehlersuche automatisch kompaktiert, fasst das $27\text{B}$-Modell den bisherigen Chat zusammen. Dabei gehen exakte Zeilennummern und vor allem **negatives Wissen** (*„Ansatz A haben wir schon probiert, der wirft einen Zirkelbezug“*) verloren. Nach der Compaction baut der Agent denselben Fehler erneut.

### 3.2 Die Lösung: Der 4-Phasen-Loop mit Festplatten-Gedächtnis

Verabschiede dich vom Gedanken, dass eine komplexe Anforderung in einer einzigen, endlosen Chat-Session durchlaufen muss. Dein echtes Gedächtnis ist nicht der KV-Cache, sondern die Datei **`.pi/SPEC.md`** auf deiner Festplatte!

```
[Menschlicher Prompt ("Vibe-Spec")]
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 1: SCOPED EXPLORATION (Reasoning: high)               │
│ • Haupt-Agent liest PROJECT_MAP.md                          │
│ • Delegiert Dateisuche an isolierten Sub-Agent (Scout)      │
│ • Scout stirbt -> gibt nur 500-Token-Zusammenfassung zurück │
│ • Agent stellt dir 2-3 gezielte Klärungsfragen              │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 2: SPEC-SYNTHESE (Reasoning: xhigh)                   │
│ • Agent übersetzt deinen Wunsch in Architektur              │
│ • Schreibt .pi/SPEC.md (Dateien, Zeilen, Checkliste, Tabus) │
│ • Noch KEINE Zeile Produktivcode geändert!                  │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 3: ATOMARE EXEKUTION (Reasoning: medium / high)       │
│ • Agent arbeitet .pi/SPEC.md Punkt für Punkt ab             │
│ • Surgical Reads (nur relevante Zeilen per Offset/Limit)    │
│ • Hakt erledigte Tasks direkt in .pi/SPEC.md ab `[x]`       │
└─────────────────────────────────────────────────────────────┘
         │
         ├──► Kontext > 110k Tokens? ──► Handover in .pi/SPEC.md ──► `/clear` (Frischer Kontext!)
         ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 4: QUIET VERIFICATION (Reasoning: medium)             │
│ • Führt gezielte Einzel-Tests mit Log-Filter (`tail -n 60`) │
│ • Prüft Linter/Typecheck nur für geänderte Dateien          │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 Dynamisches Reasoning-Level-Shifting in `pi`
Nutze `xhigh` niemals als Dauer-Einstellung für den gesamten Lauf:
* **Phase 1 & 2 (`xhigh`):** Hier lohnt sich tiefes Nachdenken. Das Modell muss deine menschliche Anforderung durchdringen, Edge-Cases antizipieren und einen wasserdichten Plan in `.pi/SPEC.md` entwerfen.
* **Phase 3 & 4 (`medium` oder `high`):** Beim eigentlichen Editieren von Dateien und Ausführen von Tests ist `xhigh` kontraproduktiv. Es erzeugt riesige Denk-Monologe für triviale Tool-Calls und führt häufiger zu „Overthinking“ (das Modell hinterfragt plötzlich seinen eigenen Plan und baut Dinge um, nach denen niemand gefragt hat).

### 3.4 Prompt-Cheat-Sheet: Wie du mit dem Agenten sprichst

* **Start einer neuen Anforderung (Phase 1 & 2):**
  > *„Ich möchte folgende Funktion aus Nutzersicht: [Deine menschliche Beschreibung]. Nutze deinen `vibe-to-spec`-Skill. Ändere noch keinen Code! Schick deinen Scout-Subagenten los, um die relevanten Stellen in der Codebase zu lokalisieren, stell mir maximal 3 Verständnisfragen und erstelle danach die `.pi/SPEC.md`.“*
* **Start der Umsetzung (Phase 3):**
  > *„Die `.pi/SPEC.md` passt. Schalte auf chirurgisches Arbeiten um (`surgical-reader`) und setze Punkt 1 bis 3 der Checkliste um. Hake jeden erledigten Punkt sofort in `.pi/SPEC.md` ab und prüfe nach jedem Schritt mit `quiet-verifier`.“*
* **Manueller Reset vor dem Context Rot (bei ca. $100\text{k}\text{--}120\text{k}$ Tokens):**
  > *„Stopp nach diesem Schritt. Führe den `context-handover`-Skill aus und aktualisiere `.pi/SPEC.md` mit deinem exakten Stand und allen verworfenen Ansätzen.“*
  *(Danach tippst du `/clear` in `pi` und startest frisch mit:)*
  > *„Lies `.pi/SPEC.md` und arbeite ab dem nächsten offenen `[ ]`-Punkt weiter.“*

---

## 4. Pi Agent Konfiguration & Basis-Dateien

### 4.1 Die optimale `~/.pi/agent/settings.json`

Mit dieser Konfiguration zwingst du `pi`, die Compaction nicht erst kurz vor dem VRAM-Crash bei $245\text{k}$ Tokens auszulösen, sondern bereits bei rund $130\text{k}$ Tokens – also genau an der Grenze, bevor Qwen 3.8 27B in die „Dumb Zone“ abrutscht. Gleichzeitig bleiben die vollen $262\text{k}$ Tokens in LM Studio als Puffer bestehen, falls ein Tool-Call versehentlich einen großen Output liefert.

```json
{
  "$schema": "https://pi.dev/schemas/settings.schema.json",
  "defaultProvider": "lmstudio",
  "defaultModel": "qwen3.8-27b",
  "defaultThinkingLevel": "high",
  "compaction": {
    "enabled": true,
    "reserveTokens": 130000,
    "keepRecentTokens": 24000
  },
  "retry": {
    "enabled": true,
    "maxRetries": 3,
    "baseDelayMs": 1500
  },
  "packages": [
    "npm:pi-subagents",
    "npm:pi-lsp-adapter",
    "npm:pi-tidy-tools",
    "npm:pi-fff",
    "npm:pi-dynamic-footer"
  ]
}
```

**Erklärung der Compaction-Mathematik:**
$$\text{Compaction-Trigger} = \text{ContextWindow } (262\,144) - \text{reserveTokens } (130\,000) = 132\,144 \text{ Tokens}$$
Sobald dein Kontext $132\,144$ Tokens überschreitet, räumt `pi` auf, behält die letzten $24\,000$ Tokens im Original (`keepRecentTokens`) und fasst den älteren Verlauf kompakt zusammen.

---

### 4.2 Globale Agenten-Verfassung: `AGENTS.md` (im Projekt-Root)

Lege diese Datei direkt im Hauptverzeichnis deiner Codebase ab. `pi` lädt sie automatisch in den System-Prompt, der **niemals** wegkompaktiert wird und bei jedem Turn im schnellen Prefix-Cache von LM Studio bleibt.

```md
# AGENTS.md — Operationshandbuch für Qwen 3.8 27B

Du bist ein autonomer Principal Software Architect & Surgical Coding Agent. Du arbeitest auf einer großen Bestands-Codebase. Der User gibt dir oft nicht-technische, fachliche Anforderungen aus menschlicher Perspektive („Vibe-Specs“).

## 1. EISERNE GRUNDREGELN (NIEMALS BRECHEN!)

1. **Verbot blinder Code-Änderungen:** Wenn der User eine neue fachliche Anforderung stellt, darfst du NIEMALS sofort Produktivdateien editieren. Du musst zwingend zuerst `.pi/PROJECT_MAP.md` prüfen und eine technische Spezifikation in `.pi/SPEC.md` anlegen oder aktualisieren.
2. **Verbot kompletter Datei-Reads (>150 Zeilen):** Unser Kontextfenster ist kostbar. Es ist STRENG VERBOTEN, `read` ohne `offset` und `limit` auf Dateien anzuwenden, die mehr als 150 Zeilen haben. Nutze immer zuerst `rg -n` (ripgrep), `ast-grep` oder LSP-Tools, um die exakten Zeilennummern zu finden, und lies dann nur das relevante Fenster (z. B. 80 Zeilen rund um den Treffer).
3. **Sub-Agent-Pflicht für Suchaufgaben:** Wenn du noch nicht weißt, in welchen Dateien sich eine Logik befindet, suche NICHT im Hauptkontext. Delegiere die Suche an einen Sub-Agenten (sequenziell, niemals parallel!), der dir nur Dateipfade, Zeilennummern und Funktionssignaturen zurückgibt.
4. **Log-Hygiene bei Bash-Befehlen:** Führe niemals ungefilterte Test-Suites, Builds oder Git-Logs aus. Hänge an jeden potenziell langen Shell-Befehl immer `| tail -n 60` oder `| head -n 80` an.
5. **Gedächtnis-Anker nach Compaction:** Wenn du am Anfang des Kontexts eine `<summary>` einer Compaction siehst, ist dein ALLERERSTER Schritt: Lies sofort `.pi/SPEC.md` und `.pi/PROJECT_MAP.md`, bevor du irgendeine andere Aktion ausführst!

## 2. ARBEITSRHYTHMUS (DER 4-PHASEN-LOOP)

- **Phase 1 (Explore):** Übersetze die menschlichen Begriffe des Users mithilfe von `.pi/PROJECT_MAP.md` in technische Module. Schicke bei Unklarheiten einen Scout-Subagenten los.
- **Phase 2 (Spec):** Schreibe das Ziel, die betroffenen Dateien (mit Zeilenbereichen), die Architektur-Entscheidung und eine atomare `[ ]`-Checkliste in `.pi/SPEC.md`.
- **Phase 3 (Execute):** Arbeite immer nur EINEN `[ ]`-Punkt aus `.pi/SPEC.md` ab. Prüfe den Edit sofort. Markiere den Punkt in `.pi/SPEC.md` als `[x]`.
- **Phase 4 (Verify & Handover):** Führe gezielte Einzel-Tests aus. Dokumentiere verworfene Lösungswege sofort unter `## Negative Knowledge (Was NICHT funktioniert hat)` in `.pi/SPEC.md`.
```

---

### 4.3 Das Domänen-Wörterbuch: `.pi/PROJECT_MAP.md` (Vorlage)

Dies ist deine wichtigste Waffe, wenn du als Mensch nicht-technische Aufgaben formulierst. Lass den Agenten diese Datei einmalig für dein Projekt generieren und pflegen. Sie übersetzt deine „Menschensprache“ in „Code-Sprache“.

```md
# PROJECT_MAP.md — Fachliches & Technisches Domänen-Mapping

## 1. Tech-Stack & Befehle (Kurzreferenz)
- **Sprache / Framework:** [z. B. TypeScript 5.x, Next.js App Router, Prisma ORM, PostgreSQL]
- **Einzel-Test ausführen (Quiet):** `npx vitest run <pfad/zur/datei.test.ts> --reporter=dot | tail -n 50`
- **Typecheck (Nur Fehler):** `npx tsc --noEmit --pretty false | head -n 60`
- **Linter (Gezielt):** `npx eslint <pfad/zur/datei.ts> --quiet`

## 2. Wörterbuch: Menschlicher Begriff -> Technische Code-Entität
*(Immer hier nachschlagen, wenn der User fachliche Begriffe verwendet!)*

| Was der User sagt (Menschlich) | Wie es im Code heißt (Klassen / Tabellen / Module) | Primärer Ort im Repo |
| :--- | :--- | :--- |
| „Kunde“ / „Firma“ / „Account“ | `Tenant`, `OrganizationProfile` | `src/domain/tenant/` |
| „Abo“ / „Tarif“ / „Rechnung“ | `SubscriptionTier`, `BillingCycleInvoice` | `src/modules/billing/services/` |
| „Storno“ / „Kündigung“ | `ChurnWorkflow`, `RetentionPolicyResolver` | `src/modules/billing/retention/` |
| „Berechtigungen“ / „Wer darf was“ | `RBACGuard`, `PermissionPolicyMatrix` | `src/core/auth/rbac/` |
| „Startseite nach dem Login“ | `WorkspaceOverviewView` | `src/app/(dashboard)/overview/` |
| „E-Mail-Benachrichtigung“ | `TransactionalDispatchQueue` | `src/infra/mailer/` |

## 3. Architektur-Grenzen & Tabuzonen
- **Datenbank-Schema:** Liegt in `prisma/schema.prisma`. Niemals Migrationen ohne Rückfrage ausführen!
- **UI-Komponenten:** Basis-Komponenten in `src/components/ui/` dürfen nicht fachlich verändert werden; Fach-Komponenten gehören in `src/features/<feature>/components/`.
- **API-Routen:** Nutzen alle den `withAuthAndValidation()`-Wrapper aus `src/core/http/middleware.ts`.
```

---

### 4.4 Das persistente Arbeitsgedächtnis: `.pi/SPEC.md` (Vorlage)

Diese Datei überlebt jede Auto-Compaction und jeden Neustart von `pi`.

```md
# SPEC.md — Aktiver Task-State & Gedächtnis-Anker

## 1. Menschliche Anforderung (Original-Wunsch)
> „[Hier steht in 2-3 Sätzen, was der User sich aus Nutzersicht wünscht]“

## 2. Technische Übersetzung & Zielbild
- **Fachliche Logik:** [Kurze technische Zusammenfassung]
- **Datenfluss:** `[UI Component] -> [API Endpoint] -> [Service Method] -> [DB Model]`
- **Akzeptanzkriterien:**
  1. [Kriterium 1]
  2. [Kriterium 2]

## 3. Chirurgische Datei-Karte (Nur diese Bereiche anfassen!)
- `src/modules/billing/retention/RetentionService.ts` (Zeilen 112–185: Methode `calculateGracePeriod`)
- `src/app/api/billing/cancel/route.ts` (Zeilen 20–65: POST-Handler)
- `src/features/billing/CancelModal.tsx` (Zeilen 40–110: State-Handling & UI-Hinweis)

## 4. Atomarer Umsetzungs-Plan (Checkliste)
- [x] **Schritt 1:** Typ-Definition in `src/modules/billing/types.ts` (Zeile 45) um `gracePeriodDays` erweitern.
- [x] **Schritt 2:** `calculateGracePeriod` in `RetentionService.ts` (Zeile 112–185) anpassen und Unit-Test schreiben.
- [ ] **Schritt 3 (AKTUELL):** API-Response in `route.ts` (Zeile 48) erweitern und Typecheck prüfen.
- [ ] **Schritt 4:** UI-Banner in `CancelModal.tsx` einbinden.
- [ ] **Schritt 5:** End-to-End-Verifikation über Einzel-Tests.

## 5. Negative Knowledge (Was bereits probiert wurde & NICHT funktioniert!)
*(KRITISCH: Niemals diese Ansätze wiederholen!)*
- **Verworfen 1:** Direktes Laden von `TenantSettings` in `CancelModal.tsx` schlägt fehl, weil es eine Client-Komponente ist und keinen DB-Zugriff hat. Daten müssen zwingend über den API-Endpoint `/api/billing/cancel` kommen.
- **Verworfen 2:** `date-fns/addBusinessDays` berücksichtigt keine Feiertage; stattdessen muss der interne Helper `src/core/utils/dateCalc.ts` (`addWorkingDays`) genutzt werden.

## 6. Letzter bekannter Status vor Compaction / Handover
- **Zuletzt geänderte Datei:** `src/modules/billing/retention/RetentionService.ts`
- **Test-Status:** `RetentionService.test.ts` ist GRÜN (4/4 Tests).
- **Exakter nächster Befehl:** Lies `src/app/api/billing/cancel/route.ts` mit `offset: 1, limit: 70` und setze Schritt 3 um.
```

---

## 5. Essenzielle Werkzeuge & Pi Extensions

### 5.1 System-CLI-Tools (Pflicht-Installation auf deinem Rechner)
Ein $27\text{B}$-Modell ist nur so schlau wie die Werkzeuge, die es über das `bash`-Tool aufrufen kann. Installiere diese 4 ultraschnellen CLI-Tools global auf deinem System (über `winget`, `scoop`, `brew` oder `apt`), damit Qwen Dateien nicht mehr blind einlesen muss:

1. **`ripgrep` (`rg`):** Findet Textmuster und Zeilennummern in Millisekunden unter Beachtung der `.gitignore`.
2. **`ast-grep` (`sg`):** Sucht nach syntaktischen Code-Strukturen (AST) statt bloßem Text (z. B. *„Finde alle Funktionen, die `async` sind und `Invoice` zurückgeben“*).
3. **`fd` (`fd-find`):** Viel schneller und kompakter als `find` für Dateinamen-Suchen.
4. **`jq`:** Erlaubt dem Agenten, aus riesigen `package.json`-, OpenAPI- oder Config-Dateien gezielt nur einen Schlüssel auszulesen, statt $5\,000$ Zeilen JSON in den Kontext zu laden.

### 5.2 Die wichtigsten `pi` Extensions im Detail

| Extension | Aufgabe & Nutzen für Qwen 3.8 27B | Wichtiger Konfigurations-Hinweis für 32 GB VRAM |
| :--- | :--- | :--- |
| **`pi-subagents`** | Erlaubt das Spawnen isolierter Kind-Agenten (`subagent`) für Codebase-Suchen und Analysen. | **WICHTIG:** Auf `maxConcurrency: 1` (sequenziell) stellen! Parallele Sub-Agenten würden in LM Studio entweder blockieren oder den VRAM sprengen. |
| **`pi-lsp-adapter`** | Gibt dem Agenten echte IDE-Fähigkeiten (`lsp_definition`, `lsp_references`, `lsp_diagnostics`, `lsp_symbols`). | Spart ca. $70\,\%$ aller Such-Tokens, weil Qwen sofort zur exakten Zeile springt, statt mit `grep` 20 Dateien abzuklappern. |
| **`pi-tidy-tools` / `cprune`** | Schneidet überlange Tool-Ausgaben ab und bereinigt veraltete Datei-Reads aus der laufenden Historie. | Verhindert, dass ein einziger unvorsichtiger `bash`-Aufruf $50\,000$ Tokens auf einmal frisst. |
| **`pi-fff`** | Stellt extrem kompakte Fuzzy-File-Finder bereit. | Ideal, wenn du in menschlichen Prompts unscharfe Begriffe nennst. |
| **`pi-dynamic-footer`** | Zeigt im Terminal live die Kontext-Füllung, Token-Geschwindigkeit (t/s) und den Compaction-Abstand. | Dein Frühwarnsystem: Ab $100\text{k}$ Tokens bereitest du den `/handover` vor. |

---

## 6. Die 5 fertigen Pi Skills (Copy-Paste-bereit)

Lege für jeden dieser Skills einen eigenen Ordner unter `.pi/skills/<skill-name>/SKILL.md` (oder global unter `~/.pi/agent/skills/`) an. `pi` erkennt sie beim Start automatisch über das YAML-Frontmatter und lädt sie bei Bedarf in den Kontext.

### Skill 1: `.pi/skills/vibe-to-spec/SKILL.md`
Übersetzt deine menschlichen, nicht-technischen Anforderungen zuverlässig in Software-Architektur.

```md
---
name: vibe-to-spec
description: Übersetzt nicht-technische, menschliche Anforderungen („Vibe-Specs“) in eine präzise technische Spezifikation (.pi/SPEC.md). MUSS immer ausgeführt werden, wenn der User ein neues Feature, eine Änderung oder ein fachliches Problem in Alltagssprache beschreibt.
---

# Skill: Vibe-to-Spec (Anforderungs-Übersetzer)

Wenn der User eine Anforderung aus menschlicher/fachlicher Sicht formuliert, befolge strikt dieses Protokoll. **Es ist verboten, während dieses Skills Produktivcode zu ändern!**

## Schritt 1: Domänen-Übersetzung
1. Lies `.pi/PROJECT_MAP.md` komplett ein.
2. Identifiziere alle menschlichen Begriffe aus dem Prompt des Users und ordne sie den exakten technischen Klassen, Modulen und Ordnern aus der `PROJECT_MAP.md` zu.

## Schritt 2: Chirurgische Bestandsaufnahme (Exploration)
1. Falls unklar ist, welche Dateien exakt betroffen sind, starte **einen einzelnen** Scout-Subagenten (oder nutze `rg -l` / `lsp_symbols`), um die beteiligten Dateien und Zeilennummern zu ermitteln.
2. Lies von den gefundenen Dateien **nur die relevanten Ausschnitte** (Signaturen, Interfaces, betroffene Methoden mit `offset` und `limit`, maximal 100 Zeilen pro Datei).
3. Prüfe, wie ähnliche Features in dieser Codebase bereits gebaut wurden (Pattern-Matching: Wie werden Fehler behandelt? Wie sieht die Validierung aus? Welche Helper werden genutzt?).

## Schritt 3: Rückfragen-Filter (Nur wenn kritisch!)
- Wenn eine fachliche Mehrdeutigkeit besteht, die zu komplett unterschiedlicher Architektur führen würde (z. B. „Soll das Löschen ein Hard-Delete in der DB oder ein Soft-Delete über `deletedAt` sein?“), stelle dem User **maximal 3 kurze, nicht-technische Fragen** mit einer klaren Standard-Empfehlung.
- Wenn alles aus dem bestehenden Code ableitbar ist, gehe direkt zu Schritt 4.

## Schritt 4: `.pi/SPEC.md` generieren
Schreibe die vollständige Datei `.pi/SPEC.md` mit:
1. Original-Wunsch des Users.
2. Technischem Datenfluss und Akzeptanzkriterien.
3. Exakter Datei-Karte inklusive **Zeilennummern-Bereichen**.
4. Einer kleinschrittigen `[ ]`-Checkliste (maximal 1–2 Dateien pro Schritt).
5. Bekannten Fallstricken unter `## Negative Knowledge`.

Melde dem User danach kurz: *„Die technische Spezifikation steht in `.pi/SPEC.md`. Soll ich mit der Umsetzung ab Schritt 1 starten?“*
```

---

### Skill 2: `.pi/skills/surgical-reader/SKILL.md`
Gewöhnt dem Modell das verschwenderische Einlesen kompletter Quellcode-Dateien ab.

```md
---
name: surgical-reader
description: Erzwingt token-sparendes, chirurgisches Lesen und Navigieren in großen Codebases. Verhindert das Einlesen kompletter Dateien und schützt das Kontextfenster vor dem Volllaufen.
---

# Skill: Surgical Reader (Kontext-Schutz-Protokoll)

Große Dateien im Ganzen einzulesen zerstört deine Aufmerksamkeitsspanne und löst unnötige Auto-Compactions aus. Halte dich bei JEDEM Dateizugriff an diese 4 Gesetze:

## Gesetz 1: Die 150-Zeilen-Grenze
- Prüfe vor dem Lesen einer unbekannten Datei immer zuerst ihre Länge oder Struktur:
  `wc -l <datei>` oder nutze ein Outline-Kommando.
- Wenn eine Datei **mehr als 150 Zeilen** hat, darfst du das `read`-Tool **NIEMALS** ohne `offset` und `limit` aufrufen!

## Gesetz 2: Erst Röntgenbild, dann Skalpell
Bevor du `read` auf einer großen Datei ausführst, hole dir über `bash` oder LSP das Inhaltsverzeichnis der Datei (kostet nur ~100 Tokens statt 15.000 Tokens):

- **Für TypeScript / JavaScript / Python / Rust / Go / C#:**
  ```bash
  rg -n "^(export |async |public |private |protected |static )?(class|interface|type|function|def|fn|struct|impl|const [A-Za-z0-9_]+ =)" <pfad/zur/datei>
  ```
- **Für gezielte Begriffe innerhalb einer Datei:**
  ```bash
  rg -n -C 3 "Suchbegriff" <pfad/zur/datei>
  ```
- **Für strukturelle AST-Suche (falls `ast-grep` installiert ist):**
  ```bash
  sg --pattern 'function $NAME($$$) { $$$ }' <pfad/zur/datei>
  ```

## Gesetz 3: Gezielter Fenster-Read (`offset` + `limit`)
Sobald du aus Gesetz 2 weißt, dass die gesuchte Funktion z. B. in Zeile 340 beginnt:
- Rufe `read` mit `offset: 330` und `limit: 90` auf.
- Lies immer nur genau den Block, den du verstehen oder mit `edit` bearbeiten musst, plus 10 Zeilen Kontext darüber und darunter.

## Gesetz 4: Präzises Editieren
- Kopiere den `oldText` für das `edit`-Tool exakt aus deinem letzten `read`-Ausschnitt.
- Halte den `oldText`-Block so kompakt wie möglich (nur die zu ändernden Zeilen plus 2–3 eindeutige Anker-Zeilen), um Token im Tool-Call zu sparen.
```

---

### Skill 3: `.pi/skills/subagent-orchestrator/SKILL.md`
Steuert Sub-Agenten so, dass der Hauptkontext sauber bleibt, aber deine 32 GB GPU nicht durch parallele Anfragen überlastet wird.

```md
---
name: subagent-orchestrator
description: Regelt den Einsatz von isolierten Sub-Agenten für Codebase-Exploration, Impact-Analysen und Refactoring-Suchen auf einem lokalen Single-GPU-Setup (LM Studio).
---

# Skill: Sub-Agent Orchestrator (Single-GPU Edition)

Du läufst auf einer lokalen 32 GB GPU mit einem einzigen aktiven KV-Cache-Slot in LM Studio. Sub-Agenten sind dein wichtigstes Werkzeug, um deinen eigenen Kontext sauber zu halten – aber sie müssen strikt nach diesen Regeln aufgerufen werden:

## 1. Striktes Parallelitäts-Verbot (Sequenzieller Modus)
- Starte **NIEMALS** mehrere Sub-Agenten gleichzeitig in einem einzigen Turn!
- Rufe immer nur **genau einen** Sub-Agenten auf, warte auf sein Ergebnis und entscheide erst danach über den nächsten Schritt. Parallele Sub-Agenten führen auf lokalem VRAM zu Queue-Staus und zerstören das Prefix-Caching von LM Studio.

## 2. Wann musst du einen Sub-Agenten spawnen?
Spawne immer dann einen Sub-Agenten, wenn eine Aufgabe mehr als 3 Datei-Suchen oder das Durchkämmen unbekannter Ordner erfordert:
- *„Finde heraus, wo überall in der Codebase das Event `USER_DOWNGRADED` ausgelöst und verarbeitet wird.“*
- *„Analysiere alle Aufrufer der Funktion `calculateTax` und prüfe, ob eine Änderung der Signatur bestehende Aufrufe bricht.“*
- *„Durchsuche die Test-Dateien und finde heraus, wie wir in diesem Projekt Datenbank-Mocks aufsetzen.“*

## 3. Das Prompt-Format für den Sub-Agenten
Gib dem Sub-Agenten immer einen extrem klaren Rückgabe-Vertrag mit, damit er dir keinen riesigen Text-Dump zurückschickt:

> **Auftrag an Sub-Agent:**
> „Untersuche [Fragestellung]. Nutze `rg` und `read` mit Zeilenlimits.
> **WICHTIG für deine Antwort:** Gib mir KEINEN kompletten Quellcode zurück! Antworte ausschließlich im folgenden Kurzformat (maximal 400 Wörter):
> 1. **Relevante Dateien & Zeilennummern:** (`pfad/datei.ts:120-165`)
> 2. **Funktions-/Klassen-Signaturen:** (Nur die Köpfe/Typen)
> 3. **Kurze Architektur-Erkenntnis:** (Wie hängen die Teile zusammen?)“
```

---

### Skill 4: `.pi/skills/quiet-verifier/SKILL.md`
Verhindert, dass Compiler-, Test- oder Linter-Ausgaben mit zehntausenden Tokens deinen Kontext sprengen.

```md
---
name: quiet-verifier
description: Führt Tests, Typechecks, Linter und Builds mit strenger Output-Filterung aus, damit große Log-Ausgaben oder Stacktraces niemals das Kontextfenster fluten.
---

# Skill: Quiet Verifier (Token-sparendes Testen & Prüfen)

Ein einziger ungefilterter `npm test`-, `pytest`- oder `cargo test`-Aufruf kann 40.000 Tokens an Konsolen-Output erzeugen und sofort eine zerstörerische Auto-Compaction auslösen.

## 1. Die 3 Filter-Regeln für JEDEN `bash`-Aufruf
1. **Keine globalen Test-Runs während der Entwicklung:** Führe niemals die gesamte Test-Suite aus, wenn du nur an einem Modul arbeitest. Übergib immer den konkreten Dateipfad des betroffenen Tests.
2. **Fail-Fast & Quiet Flags nutzen:** Übergib immer Flags, die Erfolgs-Logs unterdrücken und beim ersten Fehler abbrechen.
3. **Harte Pipe-Begrenzung (Pflicht):** Jeder Build-, Test- oder Check-Befehl MUSS mit `2>&1 | head -n 70` oder `2>&1 | tail -n 70` begrenzt werden!

## 2. Referenz-Befehle nach Sprache

### TypeScript / JavaScript (Node / Vitest / Jest)
- **Typecheck (nur die ersten 50 Fehlerzeilen):**
  `npx tsc --noEmit --pretty false 2>&1 | head -n 50`
- **Vitest (Einzeltest, kompakt):**
  `npx vitest run <pfad/zum/test.ts> --reporter=dot --bail=1 2>&1 | tail -n 60`
- **Jest (Einzeltest, leise):**
  `npx jest <pfad/zum/test.ts> --silent --bail 2>&1 | tail -n 60`

### Python (Pytest / Ruff / Mypy)
- **Pytest (kurzer Traceback, Abbruch beim 1. Fehler):**
  `pytest <pfad/test_file.py> -q -x --tb=short --no-header 2>&1 | tail -n 60`
- **Typecheck / Linter:**
  `ruff check <pfad/datei.py> --quiet 2>&1 | head -n 50`

### Rust / Go / C#
- **Rust Cargo:**
  `cargo check --message-format=short 2>&1 | head -n 60`
  `cargo test <test_name> -- --nocapture 2>&1 | tail -n 60`
- **Go:**
  `go test -v -run <TestName> ./pfad/zum/paket 2>&1 | tail -n 60`
- **C# (.NET):**
  `dotnet build --no-restore -v q /clp:ErrorsOnly 2>&1 | head -n 60`
```

---

### Skill 5: `.pi/skills/context-handover/SKILL.md`
Dein Rettungsanker, um vor dem Einsetzen von *Context Rot* (oder vor einer Compaction) den kompletten Denk-Zustand verlustfrei auf die Festplatte zu sichern.

```md
---
name: context-handover
description: Sichert den kompletten Arbeitsstand, geänderte Dateien, offene Schritte und verworfene Lösungsansätze in .pi/SPEC.md, damit die Session verlustfrei kompaktieren oder per /clear neu gestartet werden kann.
---

# Skill: Context Handover (Anti-Compaction State-Dump)

Führe diesen Skill sofort aus, wenn:
- der User dich zum Handover / Zwischenspeichern auffordert,
- ein größerer Meilenstein aus `.pi/SPEC.md` abgeschlossen ist, oder
- du merkst, dass die Session bereits viele Tool-Calls angesammelt hat.

## Protokoll für den State-Dump

1. **Git-Status abfragen (kompakt):**
   Führe `git status -s` und `git diff --stat` aus, um exakt zu sehen, welche Dateien im Arbeitsverzeichnis modifiziert wurden.
2. **`.pi/SPEC.md` aktualisieren:**
   Aktualisiere die Datei `.pi/SPEC.md` präzise in folgenden Sektionen:
   - **Sektion 4 (Checkliste):** Markiere alle abgeschlossenen Punkte mit `[x]`. Falls neue Teilaufgaben entdeckt wurden, füge sie als `[ ]` hinzu und markiere den exakt nächsten Schritt fett mit **`(AKTUELL)`**.
   - **Sektion 5 (Negative Knowledge):** Schreibe JEDE Sackgasse, jeden fehlgeschlagenen Test-Ansatz und jede verworfene Idee der aktuellen Session hier hinein. Formuliere klar, *warum* es nicht funktioniert hat, damit dein zukünftiges Ich nach einem `/clear` oder einer Compaction diesen Fehler nicht wiederholt!
   - **Sektion 6 (Letzter bekannter Status):** Trage den exakten Dateipfad, die Zeilennummern und den konkreten nächsten Befehl ein, mit dem die nächste Session sofort starten soll.
3. **Kurze Bestätigung an den User:**
   Antworte dem User:
   *„Handover in `.pi/SPEC.md` ist gesichert. Du kannst jetzt gefahrlos `/clear` oder `/compact` ausführen und mich danach mit: `Lies .pi/SPEC.md und mach beim aktuellen Punkt weiter` neu starten.“*
```

---

## 7. Prompt-Cache-Optimierung & Custom Compaction

### 7.1 Warum dein KV-Cache in LM Studio manchmal komplett neu berechnet wird
Bei $120\,000$ Tokens im Kontext dauert ein komplettes Neuberechnen des Prompts (Prompt Processing) selbst auf einer starken $32\text{ GB}$ GPU rund $25\text{ bis }45\text{ Sekunden}$, bevor das erste Antwort-Token erscheint. Wenn das **Prefix-Caching** von LM Studio greift, dauert es hingegen nur **$0{,}2\text{ Sekunden}$**.

Damit LM Studio den KV-Cache zu $99\,\%$ wiederverwenden kann, muss der Anfang des Prompts (Prefix) zwischen zwei Turns **Bit für Bit identisch** bleiben. Vermeide diese 3 Cache-Killer:
1. **Dynamische Zeitstempel oder wechselnde System-Prompts:** Wenn eine Extension in `pi` bei jedem Turn die aktuelle Uhrzeit auf Sekundenbasis ganz oben in den System-Prompt injiziert, wird ab Token $50$ der gesamte $120\text{k}$-Cache ungültig!
2. **Parallele Sub-Agenten:** Wenn ein Sub-Agent denselben LM-Studio-Slot (`--parallel 1`) mit seinem eigenen System-Prompt überschreibt, löscht er den KV-Cache des Haupt-Agenten. *(Tipp: Deshalb Sub-Agenten nur in Phase 1 am Anfang einer Session nutzen, wenn der Hauptkontext nur $3\,000$ Tokens groß ist! Sobald du in Phase 3 bei $80\text{k}$ Tokens bist, nutzt der Haupt-Agent statt Sub-Agenten den `surgical-reader`-Skill.)*
3. **Veränderung alter Nachrichten in der Mitte der Historie:** Wenn eine Pruning-Extension nach *jedem einzelnen* Turn eine Nachricht bei Token $2\,000$ kürzt, muss LM Studio alles ab Token $2\,000$ neu berechnen. Konfiguriere Pruning-Tools so, dass sie erst ab einem Schwellenwert (z. B. alle $30\text{k}$ Tokens) gebündelt eingreifen.

### 7.2 Eigene Compaction-Extension (`.pi/extensions/surgical-compaction.ts`)
Standardmäßig nutzt `pi` beim Auto-Compact einen allgemeinen Zusammenfassungs-Prompt. Mit dieser kleinen lokalen Extension (einfach unter `.pi/extensions/surgical-compaction.ts` im Projekt ablegen) überschreibst du das Verhalten bei einer Compaction so, dass Qwen 3.8 27B zwingend alle Dateipfade, Zeilennummern und verworfenen Ansätze rettet:

```typescript
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("session_before_compact", async (event, ctx) => {
    // Zusätzliche Instruktionen in die Compaction-Anfrage injizieren
    event.customInstructions = `
KRITISCHE ANWEISUNG FÜR DIE KOMPAKTIERUNG (SURGICAL COMPACTION):
Du fasst eine laufende Coding-Session zusammen. Verliere NIEMALS technische Präzision!
Erstelle die Zusammenfassung zwingend in genau diesen 5 Blöcken:

1. **Verweis auf .pi/SPEC.md:** Erinnere den Agenten im allerersten Satz daran, sofort nach dieser Zusammenfassung die Datei \`.pi/SPEC.md\` einzulesen.
2. **Exakte Datei- & Zeilen-Historie:** Liste jede gelesene oder bearbeitete Datei mit ihrem exakten Pfad und den relevanten Zeilennummern auf (z. B. \`src/auth/login.ts:45-110\`).
3. **Bereits durchgeführte Code-Änderungen:** Was wurde konkret mit \`edit\` oder \`write\` verändert und welche Tests sind bereits grün?
4. **NEGATIVE KNOWLEDGE (Verbotene Sackgassen):** Liste detailliert alle Ansätze, Befehle oder Code-Änderungen auf, die in dieser Session fehlgeschlagen sind, inklusive der genauen Fehlermeldung.
5. **Unmittelbar nächster Schritt:** Welche exakte Datei und Zeile muss als Nächstes bearbeitet oder getestet werden?
`;
  });
}
```

---

## 8. Troubleshooting & Notfall-Playbook

| Symptom im Betrieb | Ursache | Sofort-Lösung |
| :--- | :--- | :--- |
| **Geschwindigkeit bricht plötzlich von ~90 t/s auf <10 t/s ein** | 1. VRAM ist über $32\text{ GB}$ geschwappt (Shared RAM Fallback aktiv).<br>2. MTP-Draft-Max ist zu hoch eingestellt und verwirft bei komplexem `xhigh`-Reasoning alle Draft-Tokens. | 1. Im Task-Manager / `nvidia-smi` prüfen, ob VRAM $>31\text{ GB}$ ist $\rightarrow$ Context in LM Studio auf `196608` senken.<br>2. `--spec-draft-n-max` von `5` auf `3` reduzieren. |
| **`edit`-Tool schlägt ständig fehl (*„Could not find exact match for oldText“*)** | 1. V-Cache wurde auf `Q4_0` statt `Q8_0` gestellt.<br>2. Das Modell rät den Dateiinhalt aus dem Gedächtnis vor 60k Tokens, statt frisch zu lesen. | 1. V-Cache in LM Studio zwingend auf `Q8_0` stellen.<br>2. Dem Agenten befehlen: *„Lies die 40 relevanten Zeilen mit `read` (`offset`/`limit`) frisch ein, bevor du `edit` aufrufst.“* |
| **Agent dreht sich auf `xhigh` in einer endlosen `<think>`-Schleife (4.000+ Denk-Tokens ohne Tool-Call)** | Typisches „Overthinking“-Phänomen von Reasoning-Modellen bei Temperature `0.0` oder nach einem widersprüchlichen Test-Fehler. | Generation abbrechen (`ESC`), Thinking-Level in `pi` für den aktuellen Schritt von `xhigh` auf `medium` schalten, Temperature in LM Studio auf `0.6` prüfen. |
| **Agent baut nach dem Auto-Compact genau den Fehler wieder ein, den er vor 20 Minuten behoben hatte** | Negatives Wissen wurde bei der Standard-Compaction wegrationalisiert. | 1. `.pi/extensions/surgical-compaction.ts` aktivieren.<br>2. Den Agenten anweisen, jeden Fehlschlag sofort in Sektion 5 von `.pi/SPEC.md` (`Negative Knowledge`) einzutragen. |
| **Agent versteht menschliche Begriffe falsch und ändert das falsche Modul** | Die Vokabular-Kluft zwischen deiner Alltagssprache und den Klassennamen im Code ist zu groß. | Nimm dir 3 Minuten Zeit und ergänze den missverstandenen Begriff in der Tabelle von `.pi/PROJECT_MAP.md`. Danach passiert der Fehler nie wieder. |

---

## 9. Schnellstart-Checkliste (In 10 Minuten einsatzbereit)

1. [ ] **System-Tools prüfen:** Sind `rg` (ripgrep), `fd` und `ast-grep` im Terminal verfügbar?
2. [ ] **LM Studio konfigurieren:** Qwen 3.8 27B (`Q4_K_XL` oder `Q4_K_M`) laden $\rightarrow$ Context auf `262144` (oder `196608`) $\rightarrow$ K-Cache & V-Cache auf `Q8_0` $\rightarrow$ Flash Attention `ON` $\rightarrow$ MTP Draft Max auf `4` oder `5` $\rightarrow$ Temp `0.6` $\rightarrow$ Alte `<think>`-Blöcke aus der Chat-Historie ausschließen.
3. [ ] **`~/.pi/agent/settings.json` anpassen:** `reserveTokens` auf `130000` und `keepRecentTokens` auf `24000` setzen.
4. [ ] **Projekt-Struktur anlegen:** Im Root deiner Codebase die Datei `AGENTS.md` sowie den Ordner `.pi/` mit `PROJECT_MAP.md`, `SPEC.md`, `.pi/extensions/surgical-compaction.ts` und den 5 Skills unter `.pi/skills/` erstellen.
5. [ ] **Initialisierungs-Run starten:** Starte `pi` und gib diesen ersten Befehl ein:
   > *„Scanne die Ordnerstruktur und die wichtigsten Konfigurationsdateien dieses Projekts (nutze `fd` und `rg`, lies keine großen Dateien komplett!) und fülle mir die Vorlage in `.pi/PROJECT_MAP.md` mit unserem exakten Tech-Stack, den Test-Befehlen und den 15 wichtigsten Fach-Modulen aus.“*