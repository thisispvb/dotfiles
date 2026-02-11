#!/usr/bin/env bash

# Claude Code status line script
# Git status format matches p10k my_git_formatter (see dot_p10k.zsh)

input=$(cat)
model=$(echo "$input" | jq -r '.model.display_name // .model.id')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Shorten directory path (e.g., ~/.l/s/chezmoi) when longer than 40 chars
dir=$(echo "$PWD" | sed "s|^$HOME|~|")
if [ ${#dir} -gt 40 ]; then
  IFS="/" read -ra parts <<< "$dir"
  if [ ${#parts[@]} -gt 3 ]; then
    result="${parts[0]}"
    for ((i = 1; i < ${#parts[@]} - 1; i++)); do
      result="$result/${parts[i]:0:1}"
    done
    result="$result/${parts[-1]}"
    dir="$result"
  fi
fi

# Directory (blue)
printf "\033[34m%s\033[0m" "$dir"

# Git status — format matches p10k my_git_formatter
if git rev-parse --git-dir >/dev/null 2>&1; then
  GIT="git -c core.useBuiltinFSMonitor=false"
  git_dir=$($GIT rev-parse --git-dir 2>/dev/null)

  # Branch, tag, or commit (matching p10k fallback order)
  branch=$($GIT rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$branch" = "HEAD" ]; then
    tag=$($GIT describe --tags --exact-match HEAD 2>/dev/null)
    if [ -n "$tag" ]; then
      [ ${#tag} -gt 32 ] && tag="${tag:0:12}…${tag: -12}"
      ref="#${tag}"
    else
      ref="@$($GIT rev-parse --short=8 HEAD 2>/dev/null)"
    fi
  else
    [ ${#branch} -gt 32 ] && branch="${branch:0:12}…${branch: -12}"
    ref="$branch"
  fi

  # WIP detection
  wip=""
  summary=$($GIT log -1 --format=%s 2>/dev/null)
  if [[ "$summary" =~ (^|[^[:alnum:]])(wip|WIP)($|[^[:alnum:]]) ]]; then
    wip=" wip"
  fi

  # Ahead/behind remote
  ahead=$($GIT rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  behind=$($GIT rev-list --count HEAD..@{u} 2>/dev/null || echo 0)

  # Ahead/behind push remote
  push_ahead=$($GIT rev-list --count @{push}..HEAD 2>/dev/null || echo 0)
  push_behind=$($GIT rev-list --count HEAD..@{push} 2>/dev/null || echo 0)

  # Stashes
  stashes=$($GIT stash list 2>/dev/null | wc -l | tr -d " ")

  # Action (merge/rebase/cherry-pick/revert/bisect)
  action=""
  if [ -f "$git_dir/MERGE_HEAD" ]; then
    action="merge"
  elif [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
    action="rebase"
  elif [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
    action="cherry-pick"
  elif [ -f "$git_dir/REVERT_HEAD" ]; then
    action="revert"
  elif [ -f "$git_dir/BISECT_LOG" ]; then
    action="bisect"
  fi

  # Parse git status --porcelain for file counts
  conflicted=0 staged=0 unstaged=0 untracked=0
  while IFS= read -r line; do
    x="${line:0:1}" y="${line:1:1}"
    case "$x$y" in
      "??") ((untracked++)) ;;
      U?|?U|DD|AA) ((conflicted++)) ;;
      *)
        [[ "$x" =~ [MADRC] ]] && ((staged++))
        [[ "$y" =~ [MADRC] ]] && ((unstaged++))
        ;;
    esac
  done < <($GIT status --porcelain 2>/dev/null)

  # Color: green if clean, yellow if dirty
  if [ "$staged" -eq 0 ] && [ "$unstaged" -eq 0 ] && [ "$untracked" -eq 0 ] && [ "$conflicted" -eq 0 ]; then
    color="\033[32m"
  else
    color="\033[33m"
  fi

  # Build indicators in p10k order: wip ⇣N⇡N ⇠N⇢N *N action ~N +N !N ?N
  indicators=""
  indicators+="$wip"
  # ⇣N⇡N (grouped when both present)
  [ "$behind" -gt 0 ] 2>/dev/null && indicators+=" ⇣${behind}"
  if [ "$ahead" -gt 0 ] 2>/dev/null; then
    [ "$behind" -le 0 ] 2>/dev/null && indicators+=" "
    indicators+="⇡${ahead}"
  fi
  # ⇠N⇢N (grouped when both present)
  [ "$push_behind" -gt 0 ] 2>/dev/null && indicators+=" ⇠${push_behind}"
  if [ "$push_ahead" -gt 0 ] 2>/dev/null; then
    [ "$push_behind" -le 0 ] 2>/dev/null && indicators+=" "
    indicators+="⇢${push_ahead}"
  fi
  # *N stashes
  [ "$stashes" -gt 0 ] && indicators+=" *${stashes}"
  # action
  [ -n "$action" ] && indicators+=" ${action}"
  # ~N conflicts
  [ "$conflicted" -gt 0 ] && indicators+=" ~${conflicted}"
  # +N staged
  [ "$staged" -gt 0 ] && indicators+=" +${staged}"
  # !N unstaged
  [ "$unstaged" -gt 0 ] && indicators+=" !${unstaged}"
  # ?N untracked
  [ "$untracked" -gt 0 ] && indicators+=" ?${untracked}"

  printf "  %b%s%s\033[0m" "$color" "$ref" "$indicators"
fi

# Context window remaining (cyan)
if [ -n "$remaining" ]; then
  printf "  \033[36m%.0f%%\033[0m" "$remaining"
fi

# Model name (magenta)
printf "  \033[35m%s\033[0m" "$model"
