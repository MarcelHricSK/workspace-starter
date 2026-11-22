#!/usr/bin/env bash
# Shared by the hooks in this directory; not a hook itself.
#
#   hook_setting <name> <default> [bool|int]
#
# Looks a setting up in this order and prints the first value found:
#   1. per-clone git config       git config hooks.<name> <value>
#   2. the tracked .hooksconfig   shared by everyone who clones the repository
#   3. the built-in default
#
# Only "not set" falls through to the next source. A value that cannot be read
# (malformed file, bad boolean) makes the lookup fail, and with it the hook, so
# a broken setting can never silently switch a check off.
#
# The caller must already be in the repository's top-level directory.
hook_setting() {
  local name=$1 default=$2 type=${3:-} where value rc
  for where in clone tracked; do
    rc=0
    if [ "$where" = clone ]; then
      value=$(git config ${type:+"--type=$type"} --get "hooks.$name" 2>&1) || rc=$?
    else
      # --no-includes: a tracked file must not be able to pull in other files.
      value=$(git config --no-includes --file .hooksconfig ${type:+"--type=$type"} --get "hooks.$name" 2>&1) || rc=$?
    fi
    case "$rc" in
      0)
        printf '%s\n' "$value"
        return 0
        ;;
      1) ;; # not set here; try the next source
      *)
        printf 'hooks: cannot read setting hooks.%s: %s\n' "$name" "$value" >&2
        return 1
        ;;
    esac
  done
  printf '%s\n' "$default"
}

# in_list <word> <space-separated list>: exact match, no globbing.
in_list() {
  local word=$1 item
  local -a items=()
  read -r -a items <<<"$2"
  for item in ${items[@]+"${items[@]}"}; do
    [ "$item" = "$word" ] && return 0
  done
  return 1
}
