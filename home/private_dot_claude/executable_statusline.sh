#!/usr/bin/env bash

# Claude Code status line script
# Called by Claude Code with JSON input on stdin containing model and context info

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

# Git status
if git rev-parse --git-dir >/dev/null 2>&1; then
  GIT="git -c core.useBuiltinFSMonitor=false"

  branch=$($GIT rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ ${#branch} -gt 32 ]; then
    branch="${branch:0:12}…${branch: -12}"
  fi

  indicators=""
  [ -n "$($GIT ls-files --others --exclude-standard)" ] && indicators+="?"
  $GIT diff-files --quiet 2>/dev/null || indicators+="!"
  $GIT diff-index --quiet --cached HEAD 2>/dev/null || indicators+="+"

  ahead=$($GIT rev-list --count @{u}..HEAD 2>/dev/null)
  behind=$($GIT rev-list --count HEAD..@{u} 2>/dev/null)
  [ -n "$ahead" ] && [ "$ahead" -gt 0 ] && indicators+="⇡"
  [ -n "$behind" ] && [ "$behind" -gt 0 ] && indicators+="⇣"

  stashes=$($GIT stash list 2>/dev/null | wc -l | tr -d " ")
  [ "$stashes" -gt 0 ] && indicators+="*"

  # Green if clean, yellow if dirty
  if $GIT diff-index --quiet HEAD 2>/dev/null && [ -z "$($GIT ls-files --others --exclude-standard)" ]; then
    color="\033[32m"
  else
    color="\033[33m"
  fi

  printf "  %b%s%s\033[0m" "$color" "$branch" "$indicators"
fi

# Context window remaining (cyan)
if [ -n "$remaining" ]; then
  printf "  \033[36m%.0f%%\033[0m" "$remaining"
fi

# Model name (magenta)
printf "  \033[35m%s\033[0m" "$model"
