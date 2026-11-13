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
