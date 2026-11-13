# pi-Tool-Umgebung für Kubuntu

Diese Datei beschreibt, welche Programme der Agent **pi** zusammen mit dem Skill `plan` braucht, wofür sie da sind und wie sich die Umgebung auf einem neuen Rechner reproduzieren lässt. Alles wird mit einem einzigen Skript eingerichtet (`setup-pi-tools.sh`, am Ende dieser Datei vollständig abgedruckt).

Getestet unter Ubuntu 24.04 mit pi 1.5.0, ripgrep 14.1, Universal Ctags 5.9 und jq 1.7. Die tatsächlich installierten Versionen schreibt das Skript bei jedem Lauf in `tool-versions.txt`.

## Dateien

| Datei | Zweck | Wird installiert nach |
|---|---|---|
| `requirements.md` | diese Beschreibung | – |
| `setup-pi-tools.sh` | installiert und konfiguriert alles | – |
| `SKILL.md` | Plan-Skill (Planung, Snapshots, Arbeitslog) | `~/.pi/agent/skills/plan/SKILL.md` |
| `confirmation-dialog.ts` | pi-Extension: fragt vor Git-Schreibbefehlen und `rm -r` per Dialog nach | `~/.pi/agent/extensions/confirmation-dialog.ts` |
| `AGENTS.md` | globale Anweisungen: Sicherheitsregeln, Planung und Gedächtnis, Tool-Hinweise | `~/.pi/agent/AGENTS.md` (siehe „So kommt die AGENTS.md an ihren Platz“) |
| `tool-versions.txt` | wird vom Skript erzeugt: installierte Versionen | – |

## Schnellstart

```bash
cd /pfad/zum/ordner/mit/den/dateien
bash setup-pi-tools.sh      # ohne sudo starten, das Skript fragt selbst nach dem Passwort
```

Danach ein neues Terminal öffnen und pi von dort starten.

## Voraussetzungen

- Kubuntu oder Ubuntu mit `apt` und sudo-Rechten.
- pi selbst: Ist pi schon installiert, braucht das Skript nichts weiter. Fehlt pi, installiert das Skript es über npm; dafür ist Node.js **22.19 oder neuer** nötig. Node.js installiert das Skript bewusst nicht selbst. Alternative ist der offizielle Installer von pi: `curl -fsSL https://pi.dev/install.sh | sh`.

## Programme und ihre Funktion

| Programm | Befehl | Quelle | Funktion | Status |
|---|---|---|---|---|
| pi | `pi` | Installer von pi.dev oder npm `@earendil-works/pi-coding-agent` | der Agent selbst | Pflicht |
| ripgrep | `rg` | apt `ripgrep` | durchsucht Code und Text, liefert immer Datei und Zeilennummer; findet mit `-U` auch Muster über mehrere Zeilen (z. B. Funktionsaufrufe mit bestimmten Argumenten); `rg --files` listet Dateien auf | Pflicht, einziges Suchwerkzeug |
| Universal Ctags | `ctags` | apt `universal-ctags` | Gliederung einer Datei: alle Funktionen, Klassen und Methoden mit Startzeile, damit der Agent gezielt nur die nötigen Zeilen liest | Pflicht |
| jq | `jq` | apt `jq` | fragt JSON gezielt ab, z. B. Skripte und Abhängigkeiten aus `package.json`, statt die ganze Datei zu lesen | Pflicht |
| git | `git` | apt `git` | **nur lesend**: Status, Unterschiede und Historie in bereits bestehenden Repositories | Pflicht |
| diffutils | `diff`, `cmp` | apt `diffutils` (vorinstalliert) | Vergleich der Projektdateien mit dem Snapshot des Plans; das ist der Fortschrittsnachweis | Pflicht |
| coreutils, findutils | `cp --parents`, `date`, `wc`, `head`, `tail`, `sort`, `uniq`, `cut`, `find` | vorinstalliert | Snapshots anlegen, Zeitstempel, Dateilänge prüfen, Ausgaben kürzen | Pflicht |
| Node.js und npm | `node`, `npm` | z. B. nvm oder NodeSource | nur nötig, wenn pi über npm installiert wird | je nach Installationsweg |

Bewusst **nicht** verwendet:

- **fd** (Paket `fd-find`): Auf Ubuntu heißt der Befehl `fdfind`, und `rg --files` deckt denselben Zweck ab.
- **ast-grep**: sucht im Syntaxbaum statt im Text. Für die Erkundung im Plan-Skill reicht `rg` mit Code-Mustern und `-U`, weil der Agent jeden relevanten Treffer ohnehin mit `read` prüft. Ein Werkzeug weniger heißt weniger Fehlerquellen für ein lokales Modell. Ein früher installiertes ast-grep stört nicht; wer es entfernen möchte: `npm uninstall -g @ast-grep/cli`.

## Konfiguration, die das Skript anlegt

| Datei | Inhalt | Warum |
|---|---|---|
| `~/.ctags.d/tsx.ctags` | `--map-TypeScript=+.tsx` | ohne diese Zeile liefert ctags für `.tsx`-Dateien kommentarlos nichts |
| `~/.config/ripgrep/rgrc` und `RIPGREP_CONFIG_PATH` in `~/.bashrc` | `--no-require-git` | `rg` beachtet `.gitignore` sonst nur in Git-Repositories und durchsucht ohne Repo z. B. `node_modules/`. Gilt auch für dein eigenes `rg` im Terminal. |
| `~/.pi/agent/skills/plan/SKILL.md` | Plan-Skill | wird von pi bei passenden Aufgaben geladen, erzwingen mit `/skill:plan` |
| `~/.pi/agent/extensions/confirmation-dialog.ts` | Schutz-Extension mit Bestätigungsdialog | wird von pi beim Start automatisch geladen |
| `~/.pi/agent/AGENTS.md` | Sicherheitsregeln, Planung und Gedächtnis, Tool-Hinweise | steht in jedem Systemprompt und übersteht damit jede Compaction |

## So kommt die AGENTS.md an ihren Platz

Die mitgelieferte `AGENTS.md` ist eine Vorlage. Das Skript bringt ihren Inhalt nach `~/.pi/agent/AGENTS.md`, überschreibt dabei aber nie deine eigenen Zeilen.

Damit das geht, ist der Teil, der vom Skript stammt, mit zwei Markierungszeilen eingerahmt: oben `<!-- pi-env:start … -->`, unten `<!-- pi-env:end -->`. Alles dazwischen gehört dem Skript, alles außerhalb gehört dir:

```
# Global instructions                         <- deins, bleibt
- Antworte auf Deutsch.                       <- deins, bleibt

<!-- pi-env:start (managed by setup-pi-tools.sh) -->   -+
## Safety rules (all projects)                          |  gehört dem Skript:
...                                                     |  wird bei jedem Lauf
<!-- pi-env:end -->                                    -+  auf den neuesten Stand gebracht

- Meine eigene Regel                          <- deins, bleibt
```

Beim Ausführen gibt es drei Fälle:

1. **Es gibt noch keine `~/.pi/agent/AGENTS.md`:** Das Skript kopiert die Vorlage komplett dorthin.
2. **Es gibt sie schon, mit den Markierungszeilen:** Das Skript tauscht nur den Teil zwischen den Markierungen gegen die aktuelle Fassung aus. Alles darüber und darunter bleibt, wie es ist.
3. **Es gibt sie schon, aber ohne Markierungszeilen:** Das Skript hängt den markierten Teil unten an.

Daraus folgt eine einfache Regel: Eigene Regeln schreibst du über oder unter den markierten Teil, nie hinein. Was du innerhalb der Markierungen änderst, ersetzt das Skript beim nächsten Lauf (die alte Fassung liegt dann als Sicherung daneben). Willst du dort dauerhaft etwas ändern, änderst du es in der Vorlage `AGENTS.md` neben dem Skript.

Die Markierungszeilen sind HTML-Kommentare. pi gibt sie mit an das Modell weiter, sie stören aber nicht.

## Was das Skript tut und was nicht

Das Skript ist mehrfach ausführbar. Es installiert nur fehlende apt-Pakete und erkennt bereits vorhandene Einträge, statt sie doppelt anzulegen.

Es löscht nichts. Jede Datei, die es ändert, sichert es vorher als `<datei>.bak-<Zeitstempel>`. pi lädt diese Sicherungen nicht, weil sie nicht auf `.ts`, `.js` oder `.md` enden.

Es legt keine Git-Repositories an, installiert kein Node.js und aktualisiert ein vorhandenes pi nicht (dafür gibt es `pi update`). Fehlt pi und ist Node.js aktuell genug, installiert es pi über npm mit `--ignore-scripts`, wie es die pi-Dokumentation empfiehlt. Liegt das npm-Programmverzeichnis danach nicht im `PATH`, weist es darauf hin.

Liegt noch die frühere Version der Extension unter dem alten Namen `data-guard.ts` im Extension-Ordner, benennt das Skript sie in `data-guard.ts.bak-<Zeitstempel>` um. So zeigt pi nicht zwei Dialoge, und die Datei bleibt trotzdem erhalten.

Findet es in `~/.pi/agent/AGENTS.md` einen älteren Abschnitt „Safety rules“ ohne Markierungszeilen (aus einer früheren Anleitung), ändert es nichts und bittet darum, diesen Abschnitt zuerst von Hand zu entfernen.

## Prüfen nach der Installation

1. Neues Terminal öffnen und pi starten. Im Startbereich müssen `AGENTS.md`, der Skill `plan` und die Extension `confirmation-dialog` erscheinen.
2. pi bitten, in `/tmp/test` ein Git-Repository anzulegen. Der Dialog `confirmation-dialog` muss erscheinen. Bei „Nein“ wird der Befehl blockiert. Einen Timer gibt es nicht: Solange du nicht antwortest, wartet der Agent, und es läuft nichts.
3. `cat tool-versions.txt` zeigt die installierten Versionen.

## Installationsskript

Das Skript liegt zusätzlich als eigene Datei `setup-pi-tools.sh` bei und ist identisch mit diesem Abdruck.

```bash
#!/usr/bin/env bash
# setup-pi-tools.sh
# Richtet die CLI-Tool-Umgebung für pi und den plan-Skill ein (Kubuntu/Ubuntu).
#
#  - Mehrfach ausführbar: Vorhandenes wird erkannt und nicht doppelt eingerichtet.
#  - Löscht nichts: Jede Datei, die geändert wird, wird vorher als *.bak-<Zeitstempel> gesichert.
#  - Legt keine Git-Repositories an, installiert kein Node.js und aktualisiert pi nicht.
#  - Deinstalliert nichts: Ein früher installiertes ast-grep bleibt, wird aber nicht mehr gebraucht.
#
# Aufruf (ohne sudo; das Skript fragt bei Bedarf selbst nach dem Passwort):
#   bash setup-pi-tools.sh
# SKILL.md, confirmation-dialog.ts und AGENTS.md müssen im selben Ordner wie dieses Skript liegen.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
NODE_MIN="22.19.0"                               # Mindestversion für pi über npm
STAMP="$(date +%Y%m%d-%H%M%S)"
MARK_START="<!-- pi-env:start (managed by setup-pi-tools.sh) -->"
MARK_END="<!-- pi-env:end -->"

info() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[1;33mwarn\033[0m  %s\n' "$*"; }
fail() { printf '\033[1;31mFehler:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- Hilfsfunktionen

# version_ge A B  ->  wahr, wenn Version A >= Version B
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# backup FILE  ->  Kopie FILE.bak-<Zeitstempel>, falls FILE existiert
backup() { if [ -e "$1" ]; then cp -p "$1" "$1.bak-$STAMP"; warn "Backup: $1.bak-$STAMP"; fi; }

# install_file SRC DST  ->  identisch: nichts tun; abweichend: Backup, dann kopieren
install_file() {
  local src="$1" dst="$2"
  if [ ! -f "$src" ]; then warn "Quelle fehlt, übersprungen: $src"; return 0; fi
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then ok "unverändert: $dst"; return 0; fi
  backup "$dst"
  cp "$src" "$dst"
  ok "installiert: $dst"
}

# ensure_line FILE LINE  ->  hängt LINE an, falls sie fehlt (mit Backup)
ensure_line() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ] && grep -qxF -- "$line" "$file"; then ok "vorhanden in $file: $line"; return 0; fi
  backup "$file"
  printf '%s\n' "$line" >> "$file"
  ok "ergänzt in $file: $line"
}

# npm_global_install ARGS...  ->  npm install -g, mit sudo nur wenn das npm-Verzeichnis nicht beschreibbar ist
npm_global_install() {
  local prefix; prefix="$(npm prefix -g)"
  if [ -w "$prefix/lib" ] || { [ ! -e "$prefix/lib" ] && [ -w "$prefix" ]; }; then
    npm install -g "$@"
  else
    warn "npm-Verzeichnis $prefix ist nicht beschreibbar, verwende sudo"
    $SUDO npm install -g "$@"
  fi
}

# ---------------------------------------------------------------- 0. Grundprüfungen

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  fail "Bitte ohne sudo starten, sonst landen die Dateien in /root. Das Skript fragt selbst nach dem Passwort."
fi
SUDO=""; if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi
command -v apt-get >/dev/null || fail "apt-get nicht gefunden. Das Skript ist für Kubuntu/Ubuntu gedacht."

# ---------------------------------------------------------------- 1. Systempakete

info "1/4 Systempakete (apt)"
APT_PKGS=(ripgrep universal-ctags jq git diffutils findutils coreutils)
missing=()
for p in "${APT_PKGS[@]}"; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
  info "Installiere: ${missing[*]}"
  $SUDO apt-get update
  $SUDO apt-get install -y "${missing[@]}"
else
  ok "alle vorhanden: ${APT_PKGS[*]}"
fi

# ---------------------------------------------------------------- 2. pi (und Node.js, falls pi fehlt)

info "2/4 pi"
if command -v pi >/dev/null; then
  ok "pi vorhanden: $(pi --version 2>/dev/null | head -n1). Wird nicht verändert (Update: pi update)."
elif command -v node >/dev/null && command -v npm >/dev/null && version_ge "$(node --version | sed 's/^v//')" "$NODE_MIN"; then
  npm_global_install --ignore-scripts @earendil-works/pi-coding-agent
  if command -v pi >/dev/null; then
    ok "pi installiert: $(pi --version 2>/dev/null | head -n1)"
  else
    warn "pi installiert, aber $(npm prefix -g)/bin steht nicht im PATH. Trage es in ~/.bashrc ein."
  fi
else
  warn "pi fehlt, und Node.js $NODE_MIN oder neuer ist nicht vorhanden. Das Skript installiert Node.js bewusst nicht."
  warn "Alternative: der offizielle Installer von pi: curl -fsSL https://pi.dev/install.sh | sh"
fi

# ---------------------------------------------------------------- 3. Konfiguration

info "3/4 Konfiguration"

# ctags: .tsx-Dateien als TypeScript erkennen (sonst bleibt die Ausgabe für .tsx leer)
ensure_line "$HOME/.ctags.d/tsx.ctags" "--map-TypeScript=+.tsx"

# ripgrep: .gitignore auch außerhalb von Git-Repositories beachten
RGRC="$HOME/.config/ripgrep/rgrc"
if [ -n "${RIPGREP_CONFIG_PATH:-}" ] && [ "$RIPGREP_CONFIG_PATH" != "$RGRC" ]; then
  warn "RIPGREP_CONFIG_PATH zeigt bereits auf $RIPGREP_CONFIG_PATH. Nicht verändert; ergänze dort ggf. --no-require-git."
else
  ensure_line "$RGRC" "--no-require-git"
  if grep -qF "RIPGREP_CONFIG_PATH" "$HOME/.bashrc" 2>/dev/null; then
    ok "RIPGREP_CONFIG_PATH steht bereits in ~/.bashrc"
  else
    backup "$HOME/.bashrc"
    printf '\n# ripgrep-Konfiguration (setup-pi-tools.sh)\nexport RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/rgrc"\n' >> "$HOME/.bashrc"
    ok "RIPGREP_CONFIG_PATH in ~/.bashrc eingetragen (wirkt in neuen Terminals)"
  fi
fi

# ---------------------------------------------------------------- 4. pi-Ressourcen

info "4/4 pi-Ressourcen in $AGENT_DIR"
install_file "$SCRIPT_DIR/SKILL.md"               "$AGENT_DIR/skills/plan/SKILL.md"
install_file "$SCRIPT_DIR/confirmation-dialog.ts" "$AGENT_DIR/extensions/confirmation-dialog.ts"

# Alte Version der Extension (früherer Name data-guard.ts) deaktivieren, damit pi nicht zwei
# Dialoge zeigt. Sie wird nur umbenannt, nicht gelöscht; pi lädt nur Dateien auf .ts/.js.
OLD_EXT="$AGENT_DIR/extensions/data-guard.ts"
if [ -f "$OLD_EXT" ] && [ -f "$AGENT_DIR/extensions/confirmation-dialog.ts" ]; then
  mv "$OLD_EXT" "$OLD_EXT.bak-$STAMP"
  warn "alte Extension deaktiviert: $OLD_EXT -> $OLD_EXT.bak-$STAMP"
fi

# Globale AGENTS.md: Quelle ist die AGENTS.md neben diesem Skript.
# - Ziel fehlt:               die ganze Datei wird kopiert.
# - Ziel hat den Marker-Block: nur dieser Block wird ersetzt, der Rest der Datei bleibt unberührt.
# - Ziel ohne Marker:          der Block wird angehängt.
AGENTS_SRC="$SCRIPT_DIR/AGENTS.md"
AGENTS_FILE="$AGENT_DIR/AGENTS.md"
if [ ! -f "$AGENTS_SRC" ]; then
  warn "Quelle fehlt, übersprungen: $AGENTS_SRC"
elif ! grep -qxF "$MARK_START" "$AGENTS_SRC" || ! grep -qxF "$MARK_END" "$AGENTS_SRC"; then
  warn "$AGENTS_SRC enthält keinen Block zwischen den pi-env-Markern, übersprungen."
else
  BLOCK_FILE="$(mktemp)"
  awk -v s="$MARK_START" -v e="$MARK_END" '$0==s{p=1} p{print} $0==e{p=0}' "$AGENTS_SRC" > "$BLOCK_FILE"
  mkdir -p "$AGENT_DIR"
  if [ ! -f "$AGENTS_FILE" ]; then
    cp "$AGENTS_SRC" "$AGENTS_FILE"
    ok "AGENTS.md angelegt: $AGENTS_FILE"
  elif grep -qxF "$MARK_START" "$AGENTS_FILE"; then
    current="$(awk -v s="$MARK_START" -v e="$MARK_END" '$0==s{p=1} p{print} $0==e{p=0}' "$AGENTS_FILE")"
    if [ "$current" = "$(cat "$BLOCK_FILE")" ]; then
      ok "AGENTS.md-Block ist aktuell: $AGENTS_FILE"
    else
      backup "$AGENTS_FILE"
      awk -v s="$MARK_START" -v e="$MARK_END" -v bf="$BLOCK_FILE" '
        $0==s { while ((getline l < bf) > 0) print l; skip=1; next }
        $0==e { skip=0; next }
        !skip { print }' "$AGENTS_FILE.bak-$STAMP" > "$AGENTS_FILE"
      ok "AGENTS.md-Block aktualisiert: $AGENTS_FILE"
    fi
  elif grep -qF "## Safety rules (all projects)" "$AGENTS_FILE"; then
    warn "$AGENTS_FILE enthält einen älteren Abschnitt 'Safety rules' ohne Marker."
    warn "Nichts geändert. Entferne diesen Abschnitt von Hand und starte das Skript erneut."
  else
    backup "$AGENTS_FILE"
    { if [ -s "$AGENTS_FILE" ]; then echo; fi; cat "$BLOCK_FILE"; } >> "$AGENTS_FILE"
    ok "AGENTS.md-Block ergänzt: $AGENTS_FILE"
  fi
  rm -f "$BLOCK_FILE"
fi

# ---------------------------------------------------------------- Zusammenfassung

info "Installierte Versionen (gespeichert in $SCRIPT_DIR/tool-versions.txt)"
{
  echo "# Tool-Versionen, erstellt $(date '+%Y-%m-%d %H:%M') auf $( . /etc/os-release && echo "$PRETTY_NAME" )"
  for t in pi node npm rg ctags jq git; do
    if command -v "$t" >/dev/null; then
      printf '%-9s %s\n' "$t" "$("$t" --version 2>/dev/null | head -n1)"
    else
      printf '%-9s MISSING\n' "$t"
    fi
  done
} | tee "$SCRIPT_DIR/tool-versions.txt"

cat <<'DONE'

Fertig. Nächste Schritte:
  1. Neues Terminal öffnen (damit RIPGREP_CONFIG_PATH gilt) und pi von dort starten.
  2. Im Startbereich von pi müssen AGENTS.md, der Skill "plan" und die Extension "confirmation-dialog" erscheinen.
  3. Test: pi bitten, in /tmp/test ein Git-Repository anzulegen. Der Dialog "confirmation-dialog" muss erscheinen.
DONE
```
