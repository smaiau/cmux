#!/bin/zsh
# cmux-team — Lance plusieurs Claude en team mode sur des worktrees séparés dans tmux
#
# Usage:
#   cmux-team <branch1> [branch2] [branch3] ...   — Lance une fenêtre tmux par branche
#   cmux-team --attach                             — Se rattacher à une session existante
#   cmux-team --kill                               — Ferme les fenêtres team (conserve les worktrees)
#   cmux-team --clean                              — Supprime les worktrees propres
#   cmux-team --list                               — Liste les branches actives
#   cmux-team --help                               — Aide

CMUX_TEAM_SESSION="cmux-team"
CMUX_TEAM_WIN_PREFIX="team:"
CLAUDE_CMD="claude --dangerously-skip-permissions --teammate-mode tmux"

_cmux_team_repo_root() {
  local git_common_dir
  git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  (cd "$(dirname "$git_common_dir")" && pwd)
}

_cmux_team_safe_name() {
  echo "${1//\//-}"
}

_cmux_team_setup() {
  local worktree_dir="$1"
  local repo_root="$2"

  if [[ -x "$worktree_dir/.cmux/setup" ]]; then
    "$worktree_dir/.cmux/setup"
  elif [[ -x "$repo_root/.cmux/setup" ]]; then
    "$repo_root/.cmux/setup"
  fi
}

# Check if team windows exist in the current tmux session (inline mode)
_cmux_team_has_inline_windows() {
  [[ -n "$TMUX" ]] || return 1
  tmux list-windows -F '#{window_name}' 2>/dev/null | grep -q "^${CMUX_TEAM_WIN_PREFIX}"
}

# List inline team window indices
_cmux_team_inline_indices() {
  tmux list-windows -F '#{window_index} #{window_name}' 2>/dev/null \
    | awk -v prefix="$CMUX_TEAM_WIN_PREFIX" '$2 ~ "^"prefix {print $1}'
}

cmux-team() {
  local cmd="$1"

  case "$cmd" in
    --help|-h|"")
      echo "Usage: cmux-team <branch1> [branch2] [branch3] ..."
      echo ""
      echo "  Lance une fenêtre tmux par branche."
      echo "  Chaque fenêtre a son worktree + Claude en team mode."
      echo ""
      echo "Options:"
      echo "  --attach    Se rattacher à la session existante"
      echo "  --kill      Ferme les fenêtres team (conserve les worktrees)"
      echo "  --clean     Supprime les worktrees propres (refuse si changements non commités)"
      echo "  --list      Liste les branches actives"
      echo "  --help      Aide"
      return 0
      ;;
    --attach)
      if _cmux_team_has_inline_windows; then
        local first_win
        first_win="$(_cmux_team_inline_indices | head -1)"
        tmux select-window -t ":$first_win"
      elif tmux has-session -t "$CMUX_TEAM_SESSION" 2>/dev/null; then
        if [[ -n "$TMUX" ]]; then
          tmux switch-client -t "$CMUX_TEAM_SESSION"
        else
          tmux attach -t "$CMUX_TEAM_SESSION"
        fi
      else
        echo "Pas de session cmux-team active."
        return 1
      fi
      return 0
      ;;
    --kill)
      _cmux_team_kill
      return $?
      ;;
    --clean)
      _cmux_team_clean
      return $?
      ;;
    --list)
      _cmux_team_list
      return $?
      ;;
  esac

  # Vérifier qu'on est dans un repo git
  local repo_root
  repo_root="$(_cmux_team_repo_root)" || { echo "Pas dans un repo git."; return 1; }

  # Vérifier que tmux est dispo
  if ! command -v tmux &>/dev/null; then
    echo "tmux n'est pas installé. brew install tmux"
    return 1
  fi

  # Team déjà active → revenir dessus
  if _cmux_team_has_inline_windows; then
    local first_win
    first_win="$(_cmux_team_inline_indices | head -1)"
    tmux select-window -t ":$first_win"
    return 0
  fi
  if tmux has-session -t "$CMUX_TEAM_SESSION" 2>/dev/null; then
    if [[ -n "$TMUX" ]]; then
      tmux switch-client -t "$CMUX_TEAM_SESSION"
    else
      tmux attach -t "$CMUX_TEAM_SESSION"
    fi
    return 0
  fi

  local branches=("$@")
  local count=${#branches[@]}

  if [[ "$count" -eq 0 ]]; then
    echo "Usage: cmux-team <branch1> [branch2] ..."
    return 1
  fi

  echo "Création de $count worktrees..."

  # Créer les worktrees
  local worktree_dirs=()
  for branch in "${branches[@]}"; do
    local safe_name
    safe_name="$(_cmux_team_safe_name "$branch")"
    local worktree_dir="$repo_root/.worktrees/$safe_name"

    if [[ -d "$worktree_dir" ]]; then
      echo "  [$branch] worktree existe déjà"
    else
      mkdir -p "$repo_root/.worktrees"
      if ! git -C "$repo_root" worktree add "$worktree_dir" -b "$branch" 2>/dev/null; then
        # Branche existe déjà, essayer sans -b
        if ! git -C "$repo_root" worktree add "$worktree_dir" "$branch" 2>/dev/null; then
          echo "  [$branch] erreur création worktree"
          continue
        fi
      fi
      echo "  [$branch] worktree créé"
    fi

    # Setup
    _cmux_team_setup "$worktree_dir" "$repo_root"

    worktree_dirs+=("$worktree_dir|$branch")
  done

  if [[ ${#worktree_dirs[@]} -eq 0 ]]; then
    echo "Aucun worktree créé. Abandon."
    return 1
  fi

  echo ""
  echo "Lancement des fenêtres tmux..."

  if [[ -n "$TMUX" ]]; then
    # ── Déjà dans tmux → créer des fenêtres dans la session courante ──
    for ((i = 0; i < ${#worktree_dirs[@]}; i++)); do
      local entry="${worktree_dirs[$i]}"
      local dir="${entry%%|*}"
      local branch="${entry##*|}"

      tmux new-window -n "${CMUX_TEAM_WIN_PREFIX}${branch}" -c "$dir"
      tmux send-keys "$CLAUDE_CMD" C-m
    done

    # Activer les titres de panes (pour les sub-agents)
    tmux set-option pane-border-status top
    tmux set-option pane-border-format " #{pane_title} "

    # Sélectionner la première fenêtre team
    local first_win
    first_win="$(_cmux_team_inline_indices | head -1)"
    [[ -n "$first_win" ]] && tmux select-window -t ":$first_win"

  else
    # ── Pas dans tmux → créer une session séparée ──
    local first_entry="${worktree_dirs[0]}"
    local first_dir="${first_entry%%|*}"
    local first_branch="${first_entry##*|}"

    tmux new-session -d -s "$CMUX_TEAM_SESSION" -c "$first_dir" \
      -x "$(tput cols)" -y "$(tput lines)"
    tmux send-keys -t "$CMUX_TEAM_SESSION" "$CLAUDE_CMD" C-m
    tmux rename-window -t "$CMUX_TEAM_SESSION" "$first_branch"

    for ((i = 1; i < ${#worktree_dirs[@]}; i++)); do
      local entry="${worktree_dirs[$i]}"
      local dir="${entry%%|*}"
      local branch="${entry##*|}"

      tmux new-window -t "$CMUX_TEAM_SESSION" -n "$branch" -c "$dir"
      tmux send-keys -t "$CMUX_TEAM_SESSION" "$CLAUDE_CMD" C-m
    done

    tmux set-option -t "$CMUX_TEAM_SESSION" pane-border-status top
    tmux set-option -t "$CMUX_TEAM_SESSION" pane-border-format " #{pane_title} "
    tmux select-window -t "$CMUX_TEAM_SESSION:0"
  fi

  echo ""
  echo "cmux-team lancé avec ${#worktree_dirs[@]} agents :"
  for entry in "${worktree_dirs[@]}"; do
    local branch="${entry##*|}"
    echo "  - $branch"
  done
  echo ""

  if [[ -z "$TMUX" ]]; then
    if [[ -t 0 ]]; then
      echo "Attaching..."
      tmux attach -t "$CMUX_TEAM_SESSION"
    else
      echo "Pas de TTY. Pour te rattacher :"
      echo "  cmux-team --attach"
    fi
  fi
}

_cmux_team_kill() {
  local killed=false

  # Mode inline : fermer les fenêtres team: dans la session courante
  if _cmux_team_has_inline_windows; then
    echo "Fermeture des fenêtres team..."
    local indices
    indices="$(_cmux_team_inline_indices)"
    # Supprimer en ordre inverse pour ne pas décaler les indices
    for win_idx in $(echo "$indices" | sort -rn); do
      tmux kill-window -t ":$win_idx" 2>/dev/null
    done
    killed=true
  fi

  # Mode session séparée
  if tmux has-session -t "$CMUX_TEAM_SESSION" 2>/dev/null; then
    tmux kill-session -t "$CMUX_TEAM_SESSION"
    killed=true
  fi

  if [[ "$killed" == true ]]; then
    echo "Team fermée."
    echo ""
    echo "Les worktrees sont conservés. Pour les nettoyer :"
    echo "  cmux-team --clean"
  else
    echo "Pas de session cmux-team active."
    return 1
  fi
}

_cmux_team_clean() {
  local repo_root
  repo_root="$(_cmux_team_repo_root 2>/dev/null)"
  if [[ -z "$repo_root" || ! -d "$repo_root/.worktrees" ]]; then
    echo "Aucun worktree à nettoyer."
    return 0
  fi

  local wt_count
  wt_count="$(ls -d "$repo_root/.worktrees"/*/ 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$wt_count" -eq 0 ]]; then
    echo "Aucun worktree à nettoyer."
    return 0
  fi

  echo "$wt_count worktree(s) trouvé(s) :"
  for dir in "$repo_root/.worktrees"/*/; do
    [[ -d "$dir" ]] || continue
    local name="${dir%/}"
    name="${name##*/}"
    if git -C "${dir%/}" diff --quiet 2>/dev/null && git -C "${dir%/}" diff --cached --quiet 2>/dev/null; then
      echo "  $name (propre)"
    else
      echo "  $name ⚠ changements non commités"
    fi
  done

  echo ""
  printf "Supprimer les worktrees propres ? (y/N) "
  read -r reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Annulé."
    return 0
  fi

  local removed=0
  local skipped=0
  for dir in "$repo_root/.worktrees"/*/; do
    [[ -d "$dir" ]] || continue
    local branch
    branch="$(git -C "$repo_root" worktree list --porcelain \
      | grep -A2 "^worktree ${dir%/}\$" \
      | grep '^branch ' \
      | sed 's|^branch refs/heads/||')"

    if git -C "$repo_root" worktree remove "${dir%/}" 2>/dev/null; then
      [[ -n "$branch" ]] && git -C "$repo_root" branch -d "$branch" 2>/dev/null
      echo "  Supprimé: ${dir%/}"
      ((removed++))
    else
      echo "  Conservé (changements non commités): ${dir%/}"
      ((skipped++))
    fi
  done

  echo ""
  echo "$removed supprimé(s), $skipped conservé(s)."
  if [[ "$skipped" -gt 0 ]]; then
    echo "Pour forcer : commit ou stash les changements, puis relance --clean."
  fi
}

_cmux_team_list() {
  local found=false

  # Mode inline
  if _cmux_team_has_inline_windows; then
    echo "Fenêtres team (session courante) :"
    tmux list-windows -F "  #{window_index}: #{window_name} (#{pane_current_path})" \
      | grep "  [0-9]*: ${CMUX_TEAM_WIN_PREFIX}"
    found=true
  fi

  # Mode session séparée
  if tmux has-session -t "$CMUX_TEAM_SESSION" 2>/dev/null; then
    echo "Session '$CMUX_TEAM_SESSION' :"
    tmux list-windows -t "$CMUX_TEAM_SESSION" \
      -F "  #{window_index}: #{window_name} (#{pane_current_path})"
    found=true
  fi

  if [[ "$found" == false ]]; then
    echo "Pas de session cmux-team active."
    return 1
  fi
}

# Completions zsh
if [[ -n "$ZSH_VERSION" ]]; then
  _cmux_team_complete() {
    if (( CURRENT == 2 )); then
      local -a opts=('--attach:Rattacher à la session' '--kill:Fermer les fenêtres team' '--clean:Supprimer les worktrees propres' '--list:Lister les branches' '--help:Aide')
      _describe 'options' opts
      local -a branches
      branches=(${(f)"$(git branch --format='%(refname:short)' 2>/dev/null)"})
      compadd -a branches
    else
      local -a branches
      branches=(${(f)"$(git branch --format='%(refname:short)' 2>/dev/null)"})
      compadd -a branches
    fi
  }
  compdef _cmux_team_complete cmux-team
fi
