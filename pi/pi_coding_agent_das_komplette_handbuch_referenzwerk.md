# Pi Coding Agent (`pi`) — Das komplette Referenz-Handbuch & Master-Guide

Dieses Handbuch ist die vollständige technische Dokumentation, Bedienungsanleitung und Best-Practice-Referenz für den **Pi Coding Agent (`pi`)**. Es zeigt dir bis ins kleinste Detail, wie du `pi` als deinen primären Coding-Agenten einrichtest, steuerst, über Markdown-Hierarchien konditionierst und mit Prompt-Templates (Personas) sowie TypeScript-Extensions an deinen Workflow anpasst.

---

## 1. Architektur & Philosophie: Warum `pi` fundamental anders funktioniert

Während andere Coding-Agenten (wie Claude Code, Cursor oder Windsurf) auf riesige, versteckte System-Prompts, intransparente Sub-Agenten und starre „Plan-Modi“ setzen, verfolgt `pi` das Design-Prinzip **„Primitives, not Features“**:

1. **Der 150-Wörter-Kern & Die 4+3 Basis-Tools:**
   Standardmäßig besitzt `pi` den kürzesten System-Prompt aller bekannten Coding-Agenten. Das ist besonders für lokale Modelle wie **Qwen 3.8 27B** ein gewaltiger Vorteil: Deine wertvolle Attention-Spanne wird nicht schon ab Token 1 durch 8.000 Tokens an generischen Belehrungen verwässert, sondern gehört zu 100 % deinem Projekt.
   * **Die 4 Standard-Tools (Read/Write):**
     * `read`: Liest Textdateien (mit Zeilennummern sowie optionalem `offset` und `limit`) und lädt Bilder (`png`, `jpg`, `webp`) für Vision-fähige Modelle.
     * `write`: Erstellt neue Dateien oder überschreibt bestehende komplett.
     * `edit`: Führt chirurgische Suchen-und-Ersetzen-Patches (`oldText` $\rightarrow$ `newText`) durch.
     * `bash`: Führt beliebige Shell-Befehle im aktuellen Arbeitsverzeichnis aus (optional mit `timeout`).
   * **Die 3 zusätzlichen Read-Only-Tools (bei Bedarf zuschaltbar):**
     * `grep`, `find`, `ls`: Können über `--tools read,grep,find,ls` aktiviert werden, wenn du dem Agenten das Schreiben von Dateien und das Ausführen von `bash`-Befehlen für reine Code-Reviews oder Architektur-Analysen komplett verbieten willst.
2. **YOLO-Mode by Default:**
   `pi` fragt dich standardmäßig **nicht** um Erlaubnis, bevor es eine Datei editiert oder einen Shell-Befehl ausführt. Die Philosophie dahinter: Sobald ein Agent Code schreiben und Tests ausführen darf, sind Standard-Bestätigungs-Popups bloßes Sicherheits-Theater, das dich durch „Approval Fatigue“ (blindes Wegklicken) ermüdet. Wenn du echte Leitplanken für kritische Pfade oder Befehle willst, rüstest du diese gezielt über eine 20-zeilige TypeScript-Extension nach (siehe Kapitel 9).
3. **Konversationen sind Bäume (DAGs), keine linearen Listen:**
   Jede Session wird als gerichteter azyklischer Graph (Tree) in einer einzigen `.jsonl`-Datei unter `~/.pi/agent/sessions/` gespeichert. Jede Nachricht besitzt eine `id` und eine `parentId`. Wenn das Modell in eine Sackgasse läuft, diskutierst du nicht mit ihm, sondern springst per `/tree` in der Zeit zurück und zweigst einen neuen Ast ab.
4. **Self-Modifying Harness (Selbst-Erweiterung zur Laufzeit):**
   `pi` lädt Markdown-Prompts, Skills und TypeScript-Extensions (dank `jiti` komplett ohne Build- oder Compile-Schritt!) direkt aus deinem Projektordner. Du kannst dem laufenden Agenten sagen: *„Schreib mir eine Extension, die jeden `git push` blockiert, und ein `/review`-Template“*, tippst danach `/reload` und die neuen Funktionen sind in derselben Sekunde aktiv.

---

## 2. Das komplette CLI- & Slash-Command-Lexikon

### 2.1 Die 4 Betriebsmodi über die Kommandozeile (CLI)

| Start-Befehl | Modus & genaue Funktionsweise |
| :--- | :--- |
| `pi` | Startet die interaktive Terminal-UI (TUI) im aktuellen Projektverzeichnis. |
| `pi "Erkläre mir das Auth-Modul"` | Startet die interaktive TUI und schickt den übergebenen Text sofort als ersten Prompt ab. |
| `pi -c` *(oder `--continue`)* | Lädt nahtlos die **zuletzt genutzte Session** des aktuellen Projektordners (kann auch direkt mit einem neuen Prompt kombiniert werden: `pi -c "Mach bei Schritt 3 weiter"`). |
| `pi -r` *(oder `--resume`)* | Öffnet direkt beim Start den interaktiven **Session-Picker**, um aus allen bisherigen Sessions dieses Projekts auszuwählen. |
| `pi -p "Fixe den Build-Fehler"` | **Print-Mode (Headless One-Shot):** Führt den Prompt samt aller nötigen Tool-Calls nicht-interaktiv aus, gibt die finale Antwort auf `stdout` aus und beendet sich sofort (ideal für Skripte, Git-Hooks oder Sub-Prozesse). |
| `pi --tools read,grep,find,ls` | **Read-Only-Modus:** Beschränkt die Werkzeuge des Agenten strikt auf lesende Zugriffe. Er kann weder Dateien ändern (`edit`/`write` fehlen) noch beliebige Befehle über `bash` ausführen. |
| `pi --no-session` | **Ephemeral-Modus (Inkognito):** Startet eine Sitzung im Arbeitsspeicher, die nicht als `.jsonl`-Datei auf der Festplatte gespeichert wird. |
| `pi -n "Billing-Refactoring"` | Startet eine neue Session und vergibt sofort einen sprechenden Namen (`--name`), damit du sie später unter `/resume` sofort wiederfindest. |
| `pi --session <id-oder-pfad>` | Öffnet gezielt eine bestimmte `.jsonl`-Session anhand ihrer (Teil-)UUID oder ihres Dateipfads. |
| `pi --fork <id-oder-pfad>` | Klont eine bestehende Session vor dem Start in eine komplett neue Session-Datei, um gefahrlos zu experimentieren. |
| `pi --mode rpc` | Startet `pi` als Hintergrund-Prozess, der über striktes `LF`-getrenntes JSONL auf `stdin`/`stdout` ferngesteuert werden kann (genutzt von IDE-Integrationen wie Neovim oder Obsidian). |

### 2.2 Paket-Management über die CLI (`pi install`)

* `pi install npm:<paketname>` — Installiert ein `pi`-Paket global und trägt es in `~/.pi/agent/settings.json` ein.
* `pi install -l npm:<paketname>` — Installiert das Paket **nur lokal für das aktuelle Projekt** (Eintrag in `.pi/settings.json`).
* `pi install git:github.com/user/repo@v1` — Installiert direkt aus einem Git-Repository (optional auf einen Tag oder Commit gepinnt).
* `pi list` — Zeigt alle global und lokal installierten Pakete an.
* `pi config [-l]` — Öffnet eine interaktive TUI, in der du einzelne Extensions, Skills oder Prompts aus installierten Paketen per Leertaste an- und ausschalten kannst.
* `pi update` — Aktualisiert `pi` selbst sowie alle nicht-gepinnten Erweiterungspakete.

---

### 2.3 Alle Slash-Commands in der interaktiven TUI

Tippe im Eingabefeld `/`, um das Autocomplete-Menü zu öffnen. Hier sind alle eingebauten Kern-Kommandos:

#### A. Session-Steuerung & Zeitreisen (DAG-Navigation)
* `/new` — Startet eine komplett leere Konversation in einer neuen Session-Datei.
* `/resume` — Öffnet die Liste aller vergangenen Sessions dieses Projekts zum Wechseln.
* `/name <Name>` — Gibt der aktuellen Session einen klaren Titel (wird in `/resume` und im Header angezeigt).
* `/session` — Zeigt detaillierte Statistiken zur laufenden Sitzung: Dateipfad der `.jsonl`, Session-ID, Nachrichtenanzahl, exakter Token-Verbrauch (Input/Output/Cache) und berechnete Kosten.
* `/tree` — **Das mächtigste Werkzeug in `pi`!** Öffnet die visuelle Baum-Ansicht der aktuellen Session (siehe Kapitel 4 für alle Tasten in dieser Ansicht).
* `/fork` — Öffnet eine Liste deiner bisherigen User-Nachrichten; wählst du eine aus, wird der Pfad bis zu diesem Punkt in eine **neue `.jsonl`-Session-Datei** kopiert und dort fortgesetzt.
* `/clone` — Kopiert den kompletten aktuell aktiven Ast der Sitzung in eine neue `.jsonl`-Datei.
* `/compact [Optionale Fokus-Anweisung]` — Löst manuell sofort eine Kontext-Kompaktierung aus. **Profi-Tipp:** Übergib dahinter immer einen Satz wie `/compact Behalte alle Dateipfade aus src/billing, den aktuellen Datenbank-Schema-Stand und alle fehlgeschlagenen Test-Ursachen im Klartext bei`.

#### B. Modell, Thinking & Einstellungen
* `/model [provider/model-id]` — Öffnet den interaktiven Model-Picker (wie `Ctrl+L`) oder wechselt direkt zum angegebenen Modell (z. B. `/model lmstudio/qwen3.8-27b`).
* `/scoped-models` — Wählt aus deiner Gesamtliste an Modellen diejenigen Favoriten aus (und legt deren Reihenfolge fest), durch die du im Arbeitsalltag blitzschnell mit `Ctrl+P` durchschalten willst.
* `/thinking [level]` — Öffnet das Auswahlmenü für die Denktiefe (`off`, `minimal`, `low`, `medium`, `high`, `xhigh`) oder setzt den Wert direkt (äquivalent zu `Shift+Tab`).
* `/settings` — Öffnet das interaktive Einstellungsmenü direkt im Terminal (für Auto-Compaction, Themes, Thinking-Defaults, Tool-Sichtbarkeit).
* `/llama` — Eingebauter Manager für lokale `llama.cpp`-Router-Setups (Modelle entdecken, laden und entladen).
* `/login` & `/logout` — Authentifizierung für Cloud-Provider oder Abos (OAuth / API-Keys in `~/.pi/agent/auth.json`).

#### C. Export, Zwischenablage & System-Befehle
* `/copy` — Kopiert die komplette letzte Antwort des Assistenten sauber in deine System-Zwischenablage.
* `/export [dateiname.html]` — Exportiert die gesamte Session inklusive aufklappbarer `<think>`-Blöcke, Tool-Calls und Branch-Historie in eine eigenständige, interaktive HTML-Datei (perfekt zur Dokumentation!).
* `/share` — Lädt den HTML-Export als privates GitHub Gist hoch und gibt dir eine teilbare URL zurück.
* `/reload` — **Unverzichtbar beim Anpassen des Setups:** Lädt `AGENTS.md`, `SYSTEM.md`, `APPEND_SYSTEM.md`, alle Prompt-Templates, Skills, Themes, `keybindings.json` und TypeScript-Extensions sofort im laufenden Betrieb neu, ohne die Session zu beenden!
* `/trust` — Markiert das aktuelle Projektverzeichnis als vertrauenswürdig, damit projektlokale `.pi/extensions/` und `.pi/settings.json` geladen werden dürfen.
* `/hotkeys` — Zeigt eine Übersicht aller aktuell aktiven Tastenkombinationen an.
* `/quit` — Beendet `pi`.

#### D. Dynamisch generierte Slash-Commands
* `/<template-name> [Argumente]` — Jede Datei `.pi/prompts/<name>.md` wird automatisch zum Befehl `/<name>`.
* `/skill:<skill-name> [Aufgabe]` — Lädt und aktiviert gezielt einen bestimmten Skill aus `.pi/skills/<skill-name>/SKILL.md` für den nächsten Turn.

---

## 3. TUI-Meisterschaft: Live-Steering, `!` vs. `!!` & Tastenkürzel

Wer `pi` wie einen gewöhnlichen Chat bedient (warten bis das Modell fertig ist, dann antworten), verschenkt 50 % der Produktivität. Die Terminal-Oberfläche von `pi` erlaubt es dir, **während das Modell rechnet und Tools ausführt**, aktiv in den Prozess einzugreifen.

### 3.1 Live-Steering: Die Nachrichten-Warteschlange (`Enter` vs. `Alt+Enter`)

Während Qwen 3.8 27B mitten in einer Kette von Tool-Calls steckt, ist dein Text-Editor unten **nicht gesperrt**. Du kannst jederzeit tippen und entscheidest mit der Bestätigungstaste, wann deine Nachricht einschlägt:

| Taste während der Agent läuft | Name der Aktion | Was passiert exakt im Agent-Loop? | Wann nutzt du das? |
| :--- | :--- | :--- | :--- |
| **`Enter`** | **Steering Message (Sofort-Kurskorrektur)** | `pi` lässt den *gerade laufenden* Tool-Call noch sauber zu Ende laufen, **unterbricht danach aber weitere geplante Schritte** und injiziert deine Nachricht sofort vor dem nächsten LLM-Aufruf! | Du siehst live, dass der Agent in den falschen Ordner abbiegt oder eine falsche Bibliothek nutzen will: Tippe *„Stopp, nutze dafür `axios` statt `fetch`!“* + `Enter`. |
| **`Alt+Enter`** | **Follow-up Message (Anschluss-Auftrag)** | Deine Nachricht wird in die Warteschlange gelegt und **erst dann abgeschickt, wenn der Agent seine aktuelle Aufgabe zu 100 % beendet hat** und sonst auf deine Eingabe warten würde. | Während der Agent noch Schritt 1 implementiert, tippst du schon: *„Schreib danach direkt den Unit-Test dafür“* + `Alt+Enter` und holst dir einen Kaffee. |
| **`Escape`** | **Abort & Restore** | Bricht den laufenden Turn sofort ab und legt alle noch nicht abgearbeiteten Steering-/Follow-up-Nachrichten zurück in deinen Text-Editor, damit nichts verloren geht. | Das Modell halluziniert komplett oder ein Befehl hängt fest. |
| **`Alt+Pfeil-Hoch`** | **Retrieve Queued** | Holt eine bereits mit `Enter` oder `Alt+Enter` eingereihte Nachricht wieder zurück in dein Eingabefeld, falls du dich vertippt hast oder es dir anders überlegst. | Du willst deine eingereihte Nachricht noch einmal umformulieren. |

---

### 3.2 Der `!` vs. `!!` Shell-Trick (Direkte Befehle aus dem Editor)

Du musst in `pi` niemals das Terminal wechseln, um selbst einen Git-Befehl, einen Build oder eine Suche auszuführen. Wenn dein Eingabetext mit einem Ausrufezeichen beginnt, führt `pi` ihn direkt in seiner Shell aus – mit einem entscheidenden Unterschied zwischen einem (`!`) und zwei (`!!`) Ausrufezeichen:

1. **`!<befehl>` (Sichtbarer Shell-Befehl $\rightarrow$ geht in den LLM-Kontext!):**
   * *Beispiel:* `!git diff src/auth.ts` oder `!npx tsc --noEmit | head -n 40`
   * **Wirkung:** `pi` führt den Befehl sofort aus, zeigt dir die Ausgabe im Terminal an **und fügt Befehl + Ausgabe als Nachricht in den Kontext der Konversation ein**.
   * **Warum das genial für Qwen 3.8 27B ist:** Statt dem Agenten zu sagen *„Schau mal nach, welche Typfehler wir haben“* (woraufhin das Modell erst nachdenkt, einen Tool-Call generiert und vielleicht das `| head -n 40` vergisst), feuerst du kurz `!npx tsc --noEmit | head -n 40` ab und schreibst im nächsten Satz: *„Behebe die beiden Fehler oben.“* Du sparst einen kompletten Agent-Turn und behältst die 100%ige Kontrolle über die Token-Menge!
2. **`!!<befehl>` (Versteckter Shell-Befehl $\rightarrow$ 0 Tokens im LLM-Kontext!):**
   * *Beispiel:* `!!git status`, `!!git log -n 5`, `!!npm test`
   * **Wirkung:** `pi` führt den Befehl aus und zeigt dir das Ergebnis auf dem Bildschirm, **schickt davon aber kein einziges Byte an das Sprachmodell!**
   * **Warum du das ständig nutzen solltest:** Immer wenn *du selbst* kurz prüfen willst, was der Agent geändert hat (`!!git diff`), oder ob ein Server läuft, nutzt du `!!`. So bleibt dein kostbares Kontextfenster komplett frei von deinen eigenen Kontroll-Abfragen.

---

### 3.3 Die wichtigsten Tastenkürzel (Hotkeys) im Alltag

* **`@` (im Text-Editor tippen):** Öffnet sofort eine **Fuzzy-Dateisuche** über dein gesamtes Projekt. Tippe `@userServ`, wähle mit `Tab`/`Enter` die Datei `src/services/userService.ts` aus und der exakte Pfad steht im Prompt.
* **`Ctrl+G`:** Öffnet deinen aktuellen Prompt-Entwurf in deinem **externen Standard-Editor** (`$VISUAL` oder `$EDITOR`, z. B. Neovim, Vim oder `code --wait`). Ideal, wenn du eine längere Anforderung mit mehreren Absätzen oder Code-Snippets sauber vorschreiben willst. Sobald du im Editor speicherst und schließt, landet der Text direkt im `pi`-Eingabefeld.
* **`Ctrl+O`:** Klappt lange Tool-Outputs (z. B. Datei-Reads, Diffs oder Bash-Ausgaben) sowie `<think>`-Blöcke in der TUI auf und wieder zu.
* **`Shift+Tab`:** Schaltet das **Thinking-Level** (`off` $\rightarrow$ `minimal` $\rightarrow$ `low` $\rightarrow$ `medium` $\rightarrow$ `high` $\rightarrow$ `xhigh`) live im laufenden Betrieb weiter.
* **`Ctrl+L`:** Öffnet den interaktiven **Model-Selector**.
* **`Ctrl+P` / `Shift+Ctrl+P`:** Schaltet vorwärts/rückwärts durch deine in `/scoped-models` definierten Lieblingsmodelle.
* **`Shift+Enter` (oder `Alt+Enter` im leeren Lauf):** Fügt einen Zeilenumbruch im Editor ein, ohne die Nachricht abzuschicken.

---

## 4. Der Session-Baum (DAG) als Zeitmaschine (`/tree`, `/fork`, `/clone`)

### 4.1 Warum du bei lokalen 27B-Modellen niemals „gegen Fehler anreden“ darfst
Das größte Anti-Pattern beim Arbeiten mit lokalen Coding-Agenten ist der Versuch, einen verirrten Agenten durch Diskussionen zu korrigieren.
Wenn Qwen 3.8 27B in Turn 12 drei Dateien falsch editiert hat und ein Test fehlschlägt, liegen die fehlerhaften Code-Blöcke und die falschen Annahmen des Modells im Kontext. Wenn du in Turn 13 schreibst: *„Nein, das war falsch, mach es lieber anders“*, leidet das Modell unter **Context Poisoning** (es orientiert sich weiterhin stark an den fehlerhaften Mustern, die kurz zuvor im Kontext stehen).

**Die richtige Reaktion in `pi`:**
Sobald ein Ansatz nach maximal 2 Versuchen scheitert:
1. Setze die geänderten Dateien kurz zurück (`!!git checkout -- .`).
2. Tippe **`/tree`**.
3. Springe auf den Knoten **vor** dem fehlgeschlagenen Versuch zurück, formuliere deinen Prompt an dieser Stelle präziser und zweige einen frischen, unverschmutzten Ast ab!

### 4.2 Entscheidungs-Matrix: `/new` vs. `/compact` vs. `/tree` vs. `/fork` vs. `/clone`

| Befehl | Erzeugt neue `.jsonl`-Datei? | Startpunkt des neuen Laufs | Wann ist das die richtige Wahl? |
| :--- | :--- | :--- | :--- |
| **`/new`** | **Ja** | Komplett leer (Token 0) | Du beginnst ein neues Feature, das nichts mit der aktuellen Aufgabe zu tun hat. |
| **`/compact`** | **Nein** | Am aktuellen Ende (mit Zusammenfassung davor) | Dein Weg war erfolgreich, ein Meilenstein ist fertig, aber der Kontext nähert sich den 100k Tokens. |
| **`/tree`** | **Nein** (In-Place Branching) | Jeder beliebige frühere Punkt derselben Session | Du willst eine Sackgasse verwerfen, einen Prompt besser formulieren oder zwei Lösungswege in derselben Session vergleichen. |
| **`/fork`** | **Ja** | Eine beliebige frühere User-Nachricht | Du hast in den ersten 5 Turns die Codebase analysiert und willst aus dieser Basis heraus zwei völlig getrennte Features in separaten Sessions entwickeln. |
| **`/clone`** | **Ja** | Kopie des kompletten aktuellen Astes | Du willst vor einem hochriskanten Refactoring ein komplettes Backup der bisherigen Session-Datei anlegen. |

### 4.3 Navigation und Geheimtricks in der `/tree`-Ansicht

Wenn du `/tree` öffnest, befindest du dich in einem vollwertigen Baum-Navigator:
* **Einfach drauflostippen:** Startet sofort eine Volltextsuche über alle Knoten im Baum.
* **`Pfeil-Hoch` / `Pfeil-Runter`:** Bewegt sich chronologisch durch den Baum.
* **`Ctrl+Links` / `Ctrl+Rechts` (oder `Alt+Links` / `Alt+Rechts`):** Springt direkt zwischen Verzweigungs-Knoten (Branches) hin und her oder faltet Äste ein/aus.
* **`Ctrl+O` (Filter-Modus durchschalten):** Ein extrem wichtiges Feature bei langen Sessions! Drücke in `/tree` mehrfach `Ctrl+O`, um die Ansicht zu filtern:
  `default` $\rightarrow$ `no-tools` (blendet alle Tool-Calls aus!) $\rightarrow$ `user-only` (zeigt nur deine eigenen Prompts!) $\rightarrow$ `labeled-only` (zeigt nur deine Lesezeichen!) $\rightarrow$ `all`.
* **`Shift+L` (Lesezeichen / Bookmark setzen):** Markiere wichtige Meilensteine im Baum (z. B. `Baseline nach Exploration` oder `Tests grün vor Refactoring`) mit einem Label. Später drückst du in `/tree` einfach `Ctrl+O` bis `labeled-only` und kannst sofort zu jedem gesicherten Meilenstein zurückspringen!
* **`Shift+T`:** Blendet Zeitstempel neben den Knoten ein oder aus.

> **Wichtiger Hinweis beim Zurückspringen in `/tree`:** Wenn du von einem abgebrochenen Ast zu einem früheren Knoten wechselst, fragt `pi` dich optional, ob es den verlassenen Irrweg kurz zusammenfassen und als Notiz an den neuen Ast anhängen soll. Das ist Gold wert, weil der neue Ast dadurch sofort weiß: *„Im vorherigen Versuch sind wir in Datei X gescheitert, weil Y fehlte“*, ohne die 30.000 Tokens des Irrwegs mitschleppen zu müssen!

---

## 5. Die Markdown-Architektur: Welche Dateien `pi` wann liest

`pi` besitzt eine glasklare, hierarchische Dateistruktur für System-Prompts, Projekt-Kontext, Slash-Command-Vorlagen und Skills.

### 5.1 Übersichtstabelle aller Markdown-Steuerdateien

| Dateiname & Pfad | Geladen wann? | Ersetzt oder ergänzt? | Wofür du diese Datei nutzt |
| :--- | :--- | :--- | :--- |
| **`SYSTEM.md`**<br>`~/.pi/agent/SYSTEM.md` *(Global)*<br>`.pi/SYSTEM.md` *(Projekt)* | Beim Session-Start (und `/reload`) | **Ersetzt** den eingebauten Standard-System-Prompt von `pi` komplett. | **Vorsicht:** Nur nutzen, wenn du den kompletten Prompt von Grund auf selbst schreiben willst. Meistens ist `APPEND_SYSTEM.md` besser! |
| **`APPEND_SYSTEM.md`**<br>`~/.pi/agent/APPEND_SYSTEM.md`<br>`.pi/APPEND_SYSTEM.md` | Beim Session-Start (und `/reload`) | **Hängt an** den originalen `pi`-System-Prompt an (Projekt überschreibt Global). | **Der perfekte Ort für Modell-Spezifika!** Hier gehören Regeln für Qwen 3.8 hinein (z. B. knappe `<think>`-Blöcke bei Datei-Reads, chirurgisches Lesen mit `offset`/`limit`). |
| **`AGENTS.md`** *(oder `CLAUDE.md`)*<br>1. `~/.pi/agent/AGENTS.md`<br>2. Alle Eltern-Ordner bis `cwd`<br>3. `./AGENTS.md` im Projekt | Beim Session-Start (und `/reload`) | **Alle gefundenen Dateien werden verkettet** (von Global $\rightarrow$ Root $\rightarrow$ Unterordner) ans Ende des System-Prompts gehängt! | **Projekt- & Architektur-Wissen:** Coding-Conventions, Build-/Test-Befehle, Ordnerstruktur, Domänen-Begriffe und der 4-Phasen-Workflow. |
| **Prompt Templates**<br>`~/.pi/agent/prompts/*.md`<br>`.pi/prompts/*.md` | Erst **bei Aufruf** von `/<dateiname>` im Editor | Expandiert den Markdown-Text (inkl. `$1`, `$ARGUMENTS`) als deine nächste User-Nachricht. | **Personas & Workflows:** `/architect`, `/surgeon`, `/challenger`, `/review`, `/handover`. |
| **Agent Skills**<br>`~/.pi/agent/skills/<name>/SKILL.md`<br>`.pi/skills/<name>/SKILL.md`<br>`.agents/skills/<name>/SKILL.md` | **On-Demand!** Beim Start sieht das Modell nur Name + `description` aus dem YAML-Header. | Der volle Inhalt wird erst in den Kontext geladen, wenn das Modell den Skill braucht oder du `/skill:<name>` tippst. | **Schwere Spezial-Anleitungen:** Datenbank-Migrations-Regeln, komplexe API-Spezifikationen oder Design-System-Richtlinien, die nicht bei *jedem* Turn den System-Prompt belasten sollen. |

### 5.2 Der Monorepo-Trick mit hierarchischen `AGENTS.md`-Dateien
Weil `pi` beim Start vom aktuellen Arbeitsverzeichnis (`cwd`) aus den Verzeichnisbaum nach oben wandert und **jede gefundene `AGENTS.md` einsammelt**, kannst du große Projekte extrem sauber strukturieren:
* `~/.pi/agent/AGENTS.md`: Deine persönlichen globalen Vorlieben (z. B. *„Antworte mir auf Deutsch, schreibe Kommentare im Code auf Englisch, nutze immer `rg` statt `grep`“*).
* `/mein-projekt/AGENTS.md`: Übergreifende Architektur des Projekts, Domänen-Glossar und Git-Regeln.
* `/mein-projekt/packages/frontend/AGENTS.md`: Spezifische React/Tailwind-Regeln (wird nur geladen, wenn du `pi` im `frontend`-Ordner startest).

---

## 6. Die 3 zentralen JSON-Konfigurationsdateien (Kopierfertig)

Alle globalen Einstellungen liegen unter `~/.pi/agent/`. Projektspezifische Überschreibungen legst du in `.pi/settings.json` im jeweiligen Repository ab.

### 6.1 `~/.pi/agent/models.json` (Optimiert für LM Studio + Qwen 3.8 27B)
Hier definierst du deinen lokalen LM Studio Server mit unserem ermittelten **160k-Kontext-Sweetspot** (`163840` Tokens), Kosten-Tracking auf `0` und aktiviertem Reasoning- sowie Vision-Support (damit du auch Screenshots von UI-Fehlern in `pi` hineinziehen kannst!).

~~~json
{
  "providers": {
    "lmstudio": {
      "baseUrl": "http://127.0.0.1:1234/v1",
      "api": "openai-completions",
      "apiKey": "lm-studio",
      "models": [
        {
          "id": "qwen3.8-27b",
          "name": "Qwen 3.8 27B (LM Studio 160k Q8_0)",
          "reasoning": true,
          "input": ["text", "image"],
          "contextWindow": 163840,
          "maxTokens": 16384,
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        }
      ]
    }
  }
}
~~~

### 6.2 `~/.pi/agent/settings.json` (Mit Anti-Context-Rot Compaction)
Durch `reserveTokens: 60000` bei einem `163840`er Fenster zwingst du `pi`, proaktiv bei rund **103.000 Tokens** zu kompaktieren (bevor Qwen 3.8 den roten Faden verliert), während gleichzeitig 60.000 Tokens Sicherheits-Airbag in LM Studio bereitstehen, damit große Tool-Outputs niemals einen Context-Overflow-Absturz verursachen.

~~~json
{
  "$schema": "https://pi.dev/schemas/settings.schema.json",
  "defaultProvider": "lmstudio",
  "defaultModel": "qwen3.8-27b",
  "defaultThinkingLevel": "medium",
  "compaction": {
    "enabled": true,
    "reserveTokens": 60000,
    "keepRecentTokens": 20000
  },
  "retry": {
    "enabled": true,
    "maxRetries": 3,
    "baseDelayMs": 1500
  }
}
~~~

### 6.3 `~/.pi/agent/keybindings.json` (Ergonomische Tastenbelegung)
Falls du eigene Hotkeys bevorzugst oder Konflikte mit deinem Terminal/tmux lösen willst, kannst du jede Aktion in dieser Datei umbelegen:

~~~json
{
  "cycleThinkingLevel": "shift+tab",
  "selectModel": "ctrl+l",
  "cycleModelForward": "ctrl+p",
  "cycleModelBackward": "shift+ctrl+p",
  "toggleToolOutput": "ctrl+o",
  "openExternalEditor": "ctrl+g",
  "retrieveQueuedMessages": "alt+up"
}
~~~

---

## 7. Kopierfertige Basis-Markdown-Dateien (`APPEND_SYSTEM.md` & `AGENTS.md`)

### 7.1 Globale Modell-Disziplin: `~/.pi/agent/APPEND_SYSTEM.md`
Diese Datei wird an den System-Prompt angehängt und bügelt die typischen Schwächen eines 27B-Modells im Tool-Gebrauch glatt:

~~~markdown
# Zusätzliche Ausführungs-Disziplin für Qwen 3.8 27B

1. **Thinking-Budget-Kontrolle:** Halte deine `<think>`-Blöcke bei simplen Routine-Aktionen (wie `read`, `rg` oder einfachen `edit`-Calls) extrem knapp (maximal 3–5 Sätze). Nutze tiefes, langes Nachdenken nur bei Architektur-Entscheidungen, komplexen Algorithmen oder unklaren Fehlermeldungen.
2. **Chirurgisches Lesen (`read`):** Lies niemals Dateien mit mehr als 150 Zeilen komplett auf einmal ein. Ermittle zuerst per `rg -n` die exakten Zeilennummern und nutze dann `read` zwingend mit den Parametern `offset` und `limit`.
3. **Sichere Bash-Ausgaben (`bash`):** Begrenze jeden Test-, Build-, Linter- oder Log-Befehl im `bash`-Tool immer mit `2>&1 | tail -n 60` oder `2>&1 | head -n 60`, damit große Konsolen-Ausgaben nicht das Kontextfenster fluten.
4. **Exakte Edits (`edit`):** Rufe niemals `edit` auf einer Datei auf, deren relevanten Zeilenbereich du in den letzten Turns nicht frisch mit `read` gesehen hast. Übernimm Einrückungen und Leerzeichen für `oldText` 1:1.
~~~

### 7.2 Projekt-Verfassung: `./AGENTS.md` (im Projekt-Root)

~~~markdown
# Projekt-Handbuch & Architektur-Regeln (AGENTS.md)

## 1. Projekt-Kontext & Domänen-Mapping
- Lies vor dem Bearbeiten fachlicher Anforderungen immer `.pi/PROJECT_MAP.md`, um die menschlichen Begriffe des Users den exakten technischen Modulen und Klassennamen zuzuordnen.
- Unser persistentes Arbeitsgedächtnis liegt in `.pi/SPEC.md`. Wenn du zu Beginn der Sitzung eine Compaction-Summary (`<summary>`) siehst, lies als allerersten Schritt `.pi/SPEC.md` ein!

## 2. Arbeitsweise bei neuen Anforderungen
1. **Keine blinden Code-Änderungen:** Wenn der User ein neues Feature oder Verhalten in Alltagssprache beschreibt, editiere noch keinen Produktivcode. Analysiere zuerst die betroffenen Stellen und aktualisiere `.pi/SPEC.md` (Ziel, betroffene Dateien + Zeilenbereiche, `[ ]`-Checkliste).
2. **Schrittweise Umsetzung:** Arbeite `.pi/SPEC.md` Punkt für Punkt ab. Prüfe nach jedem Schritt gezielt die geänderte Datei auf Typ-/Syntaxfehler und hake erledigte Punkte sofort mit `[x]` in `.pi/SPEC.md` ab.
3. **Negatives Wissen sichern:** Wenn ein Lösungsansatz fehlschlägt, dokumentiere ihn sofort in einem Satz unter `## Negative Knowledge` in `.pi/SPEC.md`, damit er nach einer Compaction niemals wiederholt wird.
~~~

---

## 8. Das Persona-System: 5 fertige Prompt-Templates (`.pi/prompts/*.md`)

In `pi` brauchst du kein kompliziertes Multi-Agent-Framework, um dem Modell verschiedene Rollen („Hüte“) aufzusetzen. Jede Markdown-Datei in **`.pi/prompts/`** (projektlokal) oder **`~/.pi/agent/prompts/`** (global) wird automatisch zu einem **Slash-Command** mit Autocomplete, Argument-Übergabe (`$1`, `$2`, `$ARGUMENTS`) und – dank unseres angepassten Jinja-Templates in LM Studio – **automatischer Steuerung des Qwen-3.8-Effort-Levels (`[effort:xhigh]`, `[effort:medium]`, `[effort:low]`)**!

Lege diese 5 Dateien unter `~/.pi/agent/prompts/` an und führe einmal `/reload` in `pi` aus:

### Persona 1: Der Produkt-Architekt (`~/.pi/agent/prompts/architect.md`)
* **Aufruf in `pi`:** `/architect Kunden sollen im Dashboard sehen können, warum eine Zahlung fehlgeschlagen ist`
* **Schaltet Qwen automatisch auf:** `xhigh`

~~~markdown
---
description: Übersetzt menschliche Anforderungen („Vibe-Specs“) mit maximaler Denktiefe (xhigh) in Architektur & .pi/SPEC.md
argument-hint: "<menschliche Anforderung oder Feature-Wunsch>"
---
[effort:xhigh]
Du agierst jetzt in der Persona **PRINCIPAL PRODUCT ARCHITECT**.
Deine Aufgabe ist es, folgende menschliche, nicht-technische Anforderung des Users in eine wasserdichte technische Spezifikation zu übersetzen:

> **Anforderung des Users:**
> $ARGUMENTS

### Dein striktes Protokoll (SCHREIBE NOCH KEINEN PRODUKTIVCODE!):
1. **Domänen-Mapping:** Prüfe `.pi/PROJECT_MAP.md` (oder nutze gezielte `rg -l`-Suchen), um herauszufinden, welche bestehenden Module, Services, Datenbank-Modelle und UI-Komponenten für diesen fachlichen Wunsch zuständig sind.
2. **Chirurgische Code-Inspektion:** Lies nur die relevanten Signaturen und Schnittstellen (mit `offset` und `limit`). Kopiere bestehende Architektur-Muster dieses Repositories, statt neue Paradigmen zu erfinden.
3. **Klärung oder Spezifikation:**
   - Falls kritische fachliche Randfälle unklar sind, stelle mir jetzt **maximal 3 präzise, leicht verständliche Fragen** (mit deiner jeweiligen Empfehlung als Standard).
   - Falls alles technisch klar ableitbar ist, schreibe sofort den vollständigen Plan in `.pi/SPEC.md` (inkl. exakter Dateipfade, Zeilennummern-Bereiche, Datenfluss und einer atomaren `[ ]`-Checkliste).
~~~

---

### Persona 2: Der Code-Chirurg (`~/.pi/agent/prompts/surgeon.md`)
* **Aufruf in `pi`:** `/surgeon Setze den nächsten offenen Punkt aus .pi/SPEC.md um` *(oder einfach `/surgeon`)*
* **Schaltet Qwen automatisch auf:** `low` (Ultraschnelle Ausführung ohne langes Grübeln!)

~~~markdown
---
description: Ultraschneller Implementierungs-Modus (low effort) für präzise Code-Edits nach Plan ohne Geschwafel
argument-hint: "[optional: konkreter Punkt oder Datei]"
---
[effort:low]
Du agierst jetzt in der Persona **SURGICAL CODE EXECUTOR**.
Die Architektur-Entscheidungen sind bereits getroffen. Hinterfrage den Plan nicht mehr und halte deine `<think>`-Blöcke minimal!

> **Fokus / Anweisung:**
> $ARGUMENTS

### Dein Ausführungs-Protokoll:
1. Lies `.pi/SPEC.md` (falls noch nicht im aktuellen Kontext sichtbar) und identifiziere den nächsten offenen `[ ]`-Schritt.
2. Lies den exakten Zielbereich der betroffenen Datei frisch mit `read` (`offset` & `limit`) ein.
3. Führe die Änderung präzise mit `edit` durch. Ändere keinen umliegenden Code, der nicht zur Aufgabe gehört.
4. Prüfe deine Änderung mit einem gezielten, per `| tail -n 50` gefilterten Test- oder Typecheck-Befehl.
5. Markiere den erledigten Punkt in `.pi/SPEC.md` als `[x]` und gib mir nur eine extrem knappe 3-Zeilen-Rückmeldung.
~~~

---

### Persona 3: Der schonungslose Kritiker / Red-Teamer (`~/.pi/agent/prompts/challenge.md`)
* **Aufruf in `pi`:** `/challenge Prüfe unsere aktuellen Änderungen auf Edge-Cases und Race-Conditions`
* **Schaltet Qwen automatisch auf:** `xhigh`

~~~markdown
---
description: Kritischer Staff-Engineer & Red-Teamer (xhigh) – zerlegt Pläne oder aktuelle Git-Diffs auf Fehler & Risiken
argument-hint: "[Fokus der Kritik oder leer für aktuellen git diff]"
---
[effort:xhigh]
Du agierst jetzt in der Persona **ADVERSARIAL STAFF REVIEWER (RED TEAM)**.
Sei direkt, unbestechlich und kritisch. Keine Höflichkeitsfloskeln, kein Schulterklopfen!

> **Zu prüfender Bereich / Fokus:**
> $ARGUMENTS

### Dein Prüf-Auftrag:
1. Inspiziere den aktuellen Stand über `git diff` (oder `.pi/SPEC.md`, falls wir noch in der Planung sind).
2. Suche gezielt nach:
   - Logikfehlern, Off-by-One-Errors, Null/Undefined-Fallen und unbehandelten Exceptions.
   - Gebrochenen Verträgen zu bestehenden Aufrufern im Rest der Codebase (prüfe Aufrufer mit `rg`).
   - Sicherheitslücken, fehlender Berechtigungsprüfung oder Performance-Flaschenhälsen (z. B. N+1 Queries).
   - Abweichungen von der ursprünglichen menschlichen Anforderung des Users.
3. Liste nur **echte, handfeste Befunde** nach Schweregrad (`KRITISCH`, `WARNUNG`, `ARCHITEKTUR-RISIKO`) mit exaktem Dateipfad, Zeilennummer und konkretem Fix-Vorschlag auf. **Ändere selbst noch keinen Code!**
~~~

---

### Persona 4: Der Forensik-Debugger (`~/.pi/agent/prompts/forensic.md`)
* **Aufruf in `pi`:** `/forensic Beim Klick auf Speichern kommt ein 500er Fehler in der Konsole`
* **Schaltet Qwen automatisch auf:** `medium`

~~~markdown
---
description: Systematische Root-Cause-Analyse (medium) bei Bugs – verbietet blindes Raten und Trial-and-Error-Edits
argument-hint: "<Fehlerbeschreibung oder Symptom>"
---
[effort:medium]
Du agierst jetzt in der Persona **FORENSIC ROOT-CAUSE DEBUGGER**.
Es ist dir STRENG VERBOTEN, auf Verdacht Code zu ändern („Shotgun Debugging“), bevor die Ursache bewiesen ist!

> **Gemeldetes Symptom / Problem:**
> $ARGUMENTS

### Deine 4 Schritte zur Diagnose:
1. **Spurensicherung:** Reproduziere den Fehler oder verfolge den exakten Aufrufpfad im Code rückwärts vom Symptom bis zur Quelle (nutze `rg -n` und chirurgische `read`-Aufrufe).
2. **Hypothesen-Bildung:** Formuliere die 2 wahrscheinlichsten technischen Ursachen und prüfe anhand des tatsächlichen Codes, welche davon zutrifft.
3. **Beweis:** Zeige mir die exakte Datei und Zeilennummer, in der der fehlerhafte Zustand entsteht, und erkläre in 3 Sätzen das *Warum*.
4. **Minimal-invasiver Fix:** Schlage den kleinstmöglichen, saubersten Fix vor (oder wende ihn direkt an, wenn der Beweis zu 100 % eindeutig ist) und verifiziere ihn mit einem Einzel-Test.
~~~

---

### Persona 5: Der State-Saver vor Compaction (`~/.pi/agent/prompts/handover.md`)
* **Aufruf in `pi`:** `/handover`
* **Schaltet Qwen automatisch auf:** `low`

~~~markdown
---
description: Sichert den kompletten Arbeitsstand inkl. verworfener Ansätze in .pi/SPEC.md für ein verlustfreies /compact oder /new
---
[effort:low]
Führe sofort ein **verlustfreies Context-Handover** durch, damit wir die Session kompaktieren oder bereinigen können:

1. Prüfe kurz per `git status -s` und `git diff --stat`, welche Dateien aktuell modifiziert sind.
2. Aktualisiere `.pi/SPEC.md` mit folgenden Pflicht-Angaben:
   - Hake alle erledigten Schritte der Checkliste mit `[x]` ab und markiere den unmittelbar nächsten Schritt mit **`(AKTUELL)`**.
   - **KRITISCH (`## Negative Knowledge`):** Trage jeden Lösungsansatz, der in dieser Sitzung fehlgeschlagen ist oder verworfen wurde, mit kurzer Begründung ein, damit er nach der Compaction niemals wiederholt wird.
   - Trage unter `## Letzter bekannter Status` den exakten Dateipfad, die Zeilennummern und den ersten Befehl für die Fortsetzung ein.
3. Antworte mir danach nur mit dem Satz: *„Handover in .pi/SPEC.md abgeschlossen – bereit für `/compact` oder `/new`.“*
~~~

---

## 9. Best Practices für den Profi-Alltag (Jenseits von Isolation)

Wenn `pi` dein tägliches Hauptwerkzeug ist, entscheiden diese 6 Gewohnheiten darüber, ob das 27B-Modell wie ein Senior-Entwickler abliefert oder sich verzettelt:

### 1. „Context Feeding“ mit `!` statt Such-Aufträgen
Jedes Mal, wenn du Qwen selbst nach dem aktuellen Git-Status, den letzten Commits oder einer bekannten Fehlermeldung suchen lässt, verbraucht das Modell einen kompletten Denk- und Tool-Turn.
* **Schlecht:** *„Schau mal nach, was sich in den letzten 2 Commits geändert hat und welche Tests gerade fehlschlagen.“*
* **Profi-Workflow in `pi`:**
  1. Du tippst `!git log -n 2 --stat` (`Enter`)
  2. Du tippst `!npx vitest run src/billing/ --reporter=dot | tail -n 40` (`Enter`)
  3. Du tippst: *„Hier sind die letzten Commits und der aktuelle Testfehler. Behebe die Ursache.“*
  Das Modell hat sofort alle Fakten im Prompt und startet bei Turn 1 direkt mit der Lösung!

### 2. Gezielte Compaction am Meilenstein (Niemals mitten im Bugfix!)
Lass es im Idealfall gar nicht erst zum ungesteuerten Auto-Compact mitten in einer Debugging-Schleife kommen.
* Behalte die Token-Anzeige unten im Footer im Auge.
* Sobald ein Teil-Feature oder ein Checklisten-Punkt aus `.pi/SPEC.md` abgeschlossen ist und der Kontext zwischen **75.000 und 95.000 Tokens** liegt:
  1. Tippe `/handover` (aktualisiert `.pi/SPEC.md`).
  2. Tippe `/compact Behalte den Verweis auf .pi/SPEC.md, alle geänderten Dateipfade und alle verworfenen Ansätze im Klartext bei`.
* So gehst du mit schlanken ~22.000 Tokens und 100 % frischer Modell-Aufmerksamkeit in den nächsten Abschnitt.

### 3. Die „2-Strike-Regel“ mit `/tree`
Wenn das Modell versucht, einen Bug oder Compiler-Fehler zu beheben, und der zweite Reparaturversuch ebenfalls fehlschlägt: **Stopp!**
Diskutiere keinen dritten und vierten Versuch herbei.
* Drücke `Escape`, führe `!!git checkout -- <datei>` aus, um den verpfuschten Versuch auf der Festplatte zurückzusetzen.
* Öffne `/tree`, wähle den Knoten direkt vor dem ersten Fehlversuch aus und lass `pi` beim Wechsel des Astes eine kurze Branch-Summary des fehlgeschlagenen Versuchs mitnehmen.

### 4. Prefix-Cache-Disziplin wahren (Keine Live-Änderungen an `AGENTS.md` mitten im Run)
In deinem lokalen LM-Studio-Setup auf 32 GB VRAM ist der **Prompt-Prefix-Cache** deine Lebensversicherung für schnelle Antwortzeiten (0,2 Sekunden statt 30 Sekunden Wartezeit bei 90k Kontext).
* Der System-Prompt und die `AGENTS.md`-Dateien stehen ganz am Anfang des Kontexts (bei Token 0 bis 2.000).
* Wenn du mitten in einer 90.000-Token-Session eine Zeile in `AGENTS.md` änderst und `/reload` tippst, verändert sich der Prompt ganz oben bei Token 500. Die Folge: LM Studio muss die gesamten nachfolgenden 89.500 Tokens komplett neu berechnen!
* **Regel:** Änderungen an `AGENTS.md`, `APPEND_SYSTEM.md` oder das Umschalten aktiver Tool-Sets immer genau dann durchführen, wenn du ohnehin `/new` oder `/compact` ausführst.

### 5. Visuelles Debugging per Drag & Drop nutzen
Da dein Qwen 3.8 27B in LM Studio ein nativ multimodales Vision-Modell ist und das `read`-Tool von `pi` Bilder unterstützt:
Wenn im Frontend ein Layout verschoben ist oder ein komplexes Architektur-Diagramm vorliegt, beschreibe es nicht mühsam in 500 Wörtern. Ziehe den Screenshot einfach per Drag & Drop in das `pi`-Terminal (oder gib den Dateipfad `@screenshot.png` an) und sage: *„Das Modal überlappt hier auf mobilen Bildschirmen die Navigation – korrigiere die Tailwind-Klassen in `@src/components/Modal.tsx`.“*

### 6. Den Agenten seine eigenen Werkzeuge bauen lassen
Wenn du merkst, dass du in einem Projekt immer wieder denselben Prüfschritt machst (z. B. prüfen, ob neue Übersetzungs-Keys in `de.json` und `en.json` synchron sind):
Sag einfach zu `pi`: *„Schreib mir eine lokale `pi`-Extension in `.pi/extensions/i18n-check.ts`, die den Befehl `/i18n` registriert und prüft, ob alle Keys in `locales/` synchron sind.“* Danach `/reload` tippen – fertig.

---

## 10. Drei unverzichtbare TypeScript-Extensions zum direkten Einbau

Da `pi` im YOLO-Mode läuft, kannst du dir mit wenigen Zeilen TypeScript in `.pi/extensions/` (oder global in `~/.pi/agent/extensions/`) maßgeschneiderte Sicherheitsnetze und Automatisierungen bauen. `pi` lädt `.ts`-Dateien direkt beim Start über `jiti` – du musst nichts kompilieren!

### Extension 1: Schutzschild gegen zerstörerische Befehle & sensible Dateien (`~/.pi/agent/extensions/safe-guard.ts`)
Verhindert, dass Qwen 3.8 versehentlich `git reset --hard`, `rm -rf` oder Datenbank-Drops ohne deine explizite Zustimmung ausführt oder `.env`-Dateien überschreibt.

~~~typescript
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const DANGEROUS_BASH_PATTERNS = [
  /\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|--recursive)\b/,
  /\bgit\s+(reset\s+--hard|clean\s+-[a-zA-Z]*f|push\s+--force|checkout\s+--\s+\.)\b/,
  /\b(drop\s+table|drop\s+database|truncate\s+table)\b/i,
  /\b(prisma\s+migrate\s+reset|db\s+push\s+--force-reset)\b/
];

const PROTECTED_FILE_PATTERNS = [
  /\.env(\..+)?$/,
  /package-lock\.json$/,
  /pnpm-lock\.yaml$/,
  /yarn\.lock$/
];

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    // 1. Gefährliche Bash-Befehle abfangen
    if (event.toolName === "bash") {
      const cmd = String(event.input.command || "");
      const isDangerous = DANGEROUS_BASH_PATTERNS.some((regex) => regex.test(cmd));

      if (isDangerous && ctx.hasUI) {
        const approved = await ctx.ui.confirm(
          "⚠️ Kritischer Shell-Befehl erkannt!",
          `Das Modell möchte folgenden Befehl ausführen:\n\n${cmd}\n\nWirklich zulassen?`
        );
        if (!approved) {
          return {
            block: true,
            reason: "Vom User abgelehnt: Dieser Befehl ist potenziell destruktiv. Suche einen sicheren Weg ohne Datenverlust."
          };
        }
      }
    }

    // 2. Schreibzugriffe auf geschützte Dateien (.env, Lockfiles) abfangen
    if (event.toolName === "write" || event.toolName === "edit") {
      const filePath = String(event.input.path || "");
      const isProtected = PROTECTED_FILE_PATTERNS.some((regex) => regex.test(filePath));

      if (isProtected && ctx.hasUI) {
        const approved = await ctx.ui.confirm(
          "🔒 Geschützte Datei!",
          `Das Modell möchte die geschützte Datei "${filePath}" verändern. Zulassen?`
        );
        if (!approved) {
          return {
            block: true,
            reason: `Zugriff auf ${filePath} verweigert. Diese Datei ist geschützt und darf nicht direkt editiert werden.`
          };
        }
      }
    }
  });
}
~~~

---

### Extension 2: Chirurgische Auto-Compaction (`~/.pi/agent/extensions/surgical-compaction.ts`)
Zwingt das Modell bei jeder automatischen oder manuellen Compaction dazu, exakte Dateipfade, Zeilennummern, das Domänen-Wissen aus `.pi/SPEC.md` und alle fehlgeschlagenen Ansätze („Negative Knowledge“) zu bewahren.

~~~typescript
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("session_before_compact", async (event) => {
    const userHint = event.customInstructions ? `\nZusätzlicher Fokus des Users: ${event.customInstructions}\n` : "";

    event.customInstructions = `
DU FÜHRST EINE CHIRURGISCHE KONTEXT-KOMPAKTIERUNG DURCH.
Verliere NIEMALS technische Details, Dateipfade oder Zeilennummern!${userHint}
Gliedere deine Zusammenfassung zwingend in exakt diese 5 Sektionen:

1. **PFLICHT-ANKER (.pi/SPEC.md):** Beginne mit der expliziten Anweisung: "Lies als allerersten Schritt nach dieser Zusammenfassung die Datei .pi/SPEC.md ein, um den vollen Plan wiederherzustellen."
2. **MODIFIZIERTE & ANALYSIERTE DATEIEN:** Liste jeden relevanten Dateipfad inkl. Zeilennummern und der dort gemachten Änderung oder Erkenntnis auf (z. B. \`src/services/auth.ts:120-165\`).
3. **AKTUELLER TEST- & BUILD-STATUS:** Welche Tests/Checks liefen bereits erfolgreich durch, welche schlagen noch mit welcher exakten Fehlermeldung fehl?
4. **NEGATIVE KNOWLEDGE (VERBOTENE SACKGASSEN):** Liste jeden Ansatz, jede Bibliothek und jeden Edit auf, der in den bisherigen Turns ausprobiert wurde und NICHT funktioniert hat (inkl. Grund), damit dieser Fehler nicht wiederholt wird!
5. **EXAKTER NÄCHSTER SCHRITT:** Welche Datei und welche Zeile muss im nächsten Turn als Erstes gelesen oder bearbeitet werden?
`;
  });
}
~~~

---

### Extension 3: Automatischer Bash-Output-Begrenzer (`~/.pi/agent/extensions/output-guard.ts`)
Falls Qwen 3.8 trotz deiner Anweisung in `APPEND_SYSTEM.md` einmal vergisst, einen langen Test- oder Build-Befehl mit `| tail -n 60` zu begrenzen, schneidet diese Extension überlange Ausgaben von `bash`-Calls automatisch intelligent zu (behält die ersten 30 und die letzten 50 Zeilen), bevor ein 40.000-Token-Stacktrace deinen gesamten Kontext sprengt!

~~~typescript
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const MAX_LINES = 100;
const HEAD_LINES = 30;
const TAIL_LINES = 50;

export default function (pi: ExtensionAPI) {
  pi.on("tool_result", async (event) => {
    if (event.toolName !== "bash" || !Array.isArray(event.content)) return;

    const modifiedContent = event.content.map((item) => {
      if (item.type !== "text" || typeof item.text !== "string") return item;

      const lines = item.text.split("\n");
      if (lines.length <= MAX_LINES) return item;

      const head = lines.slice(0, HEAD_LINES).join("\n");
      const tail = lines.slice(-TAIL_LINES).join("\n");
      const omitted = lines.length - (HEAD_LINES + TAIL_LINES);

      return {
        ...item,
        text: `${head}\n\n... [OUTPUT-GUARD: ${omitted} Zeilen in der Mitte ausgeblendet, um den Kontext zu schützen! Nutze gezielte Filter wie 'rg' oder 'tail', falls du Details dazwischen brauchst] ...\n\n${tail}`
      };
    });

    return { content: modifiedContent };
  });
}
~~~

---

## 11. Spickzettel für deinen täglichen Workflow (Zusammenfassung)

1. **Neues Feature starten:**
   Tippe `/architect <Deine menschliche Beschreibung was passieren soll>` $\rightarrow$ Qwen schaltet auf `xhigh`, prüft `PROJECT_MAP.md`, stellt dir max. 3 Rückfragen und schreibt `.pi/SPEC.md`.
2. **Plan abarbeiten:**
   Tippe `/surgeon` $\rightarrow$ Qwen schaltet auf `low`, liest chirurgisch mit `offset`/`limit`, baut den ersten Punkt aus `.pi/SPEC.md` und hakt ihn ab.
3. **Schnell selbst etwas prüfen (ohne Kontext-Verbrauch):**
   Tippe `!!git diff` oder `!!npm test`.
4. **Dem Modell gezielt einen Fehler vorwerfen:**
   Tippe `!npx tsc --noEmit | head -n 30` und danach: *„Fixe diese Fehler.“*
5. **Kurs während der Fahrt korrigieren:**
   Einfach drauflostippen und mit **`Enter`** direkt nach dem laufenden Tool-Call reingrätschen.
6. **Sackgasse rückgängig machen:**
   `!!git checkout -- .` $\rightarrow$ `/tree` $\rightarrow$ zum sauberen Knoten vor dem Fehler springen (`Shift+L` für Lesezeichen nutzen!).
7. **Vor der 100k-Token-Marke aufräumen:**
   Tippe `/handover` $\rightarrow$ und danach `/compact Behalte .pi/SPEC.md und alle Dateipfade bei`.