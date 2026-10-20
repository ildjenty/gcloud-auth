# gcloud-auth.zsh
# zsh functions to switch Google Cloud accounts (gcloud CLI and Application
# Default Credentials) per terminal session, plus a chpwd hook that applies the
# account mapped to the current folder.
# Load it from .zshrc: source ~/.gcloud-accounts/gcloud-auth.zsh
#
# How it works:
#   - each account uses $GCLOUD_ACCOUNTS_DIR/<name>/ as its CLOUDSDK_CONFIG
#   - GOOGLE_APPLICATION_CREDENTIALS points at that account's ADC file, for
#     client libraries that ignore CLOUDSDK_CONFIG (never overrides a value
#     you set yourself)
#   - $GCLOUD_ACCOUNTS_DIR/dirs maps folders to accounts (tab separated)
#   - when no folder matches and nothing is pinned, both variables are unset
#     and gcloud behaves as if this tool were not installed (~/.config/gcloud)
#   - gcloud-auth <name> pins the account for this shell; cd no longer changes it

: ${GCLOUD_ACCOUNTS_DIR:=$HOME/.gcloud-accounts}

# ---------------------------------------------------------------- internals

_gcloud_auth_apply() {
  local name=$1

  # drop GOOGLE_APPLICATION_CREDENTIALS only if this tool set it
  if [[ -n $_GCLOUD_AUTH_ADC && $GOOGLE_APPLICATION_CREDENTIALS == $_GCLOUD_AUTH_ADC ]]; then
    unset GOOGLE_APPLICATION_CREDENTIALS
  fi
  unset _GCLOUD_AUTH_ADC

  if [[ -z $name ]]; then
    unset CLOUDSDK_CONFIG GCLOUD_AUTH_NAME
    return
  fi

  export CLOUDSDK_CONFIG="$GCLOUD_ACCOUNTS_DIR/$name"
  export GCLOUD_AUTH_NAME=$name

  local adc=$CLOUDSDK_CONFIG/application_default_credentials.json
  if [[ -z $GOOGLE_APPLICATION_CREDENTIALS && -r $adc ]]; then
    export GOOGLE_APPLICATION_CREDENTIALS=$adc
    typeset -g _GCLOUD_AUTH_ADC=$adc
  fi
}

_gcloud_auth_exists() {
  [[ -n $1 && -d $GCLOUD_ACCOUNTS_DIR/$1 ]]
}

_gcloud_auth_names() {
  local d
  for d in "$GCLOUD_ACCOUNTS_DIR"/*(N/); do
    print -r -- "${d:t}"
  done
}

# Account mapped to the current folder (longest match, empty if none).
_gcloud_auth_dir_account() {
  local file=$GCLOUD_ACCOUNTS_DIR/dirs
  local best= bestlen=0 p name
  if [[ -r $file ]]; then
    while IFS=$'\t' read -r p name; do
      [[ -z $p || $p == \#* || -z $name ]] && continue
      p=${p/#\~/$HOME}
      p=${p%/}
      if [[ $PWD == "$p" || ${PWD:0:$((${#p}+1))} == "$p/" ]] && (( ${#p} > bestlen )); then
        best=$name
        bestlen=${#p}
      fi
    done < "$file"
  fi
  print -r -- "$best"
}

# Value of a [core] property in an account's active gcloud configuration.
# Reads the files directly because running gcloud takes about a second.
_gcloud_auth_core_prop() {
  emulate -L zsh -o extendedglob
  local name=$1 key=$2
  local dir=$GCLOUD_ACCOUNTS_DIR/$name
  local config=default line section=
  [[ -r $dir/active_config ]] && config=$(<"$dir/active_config")
  local file=$dir/configurations/config_$config
  [[ -r $file ]] || return
  while IFS= read -r line; do
    line=${line##[[:space:]]#}
    if [[ $line == \[*\] ]]; then
      section=${${line#\[}%\]}
    elif [[ $section == core && $line == ${~key}[[:space:]]#=* ]]; then
      line=${line#*=}
      print -r -- "${${line##[[:space:]]#}%%[[:space:]]#}"
      return
    fi
  done < "$file"
}

# quota_project_id in an account's ADC file (empty if none).
_gcloud_auth_adc_quota_project() {
  local file=$GCLOUD_ACCOUNTS_DIR/$1/application_default_credentials.json
  [[ -r $file ]] || return
  sed -n 's/.*"quota_project_id": *"\([^"]*\)".*/\1/p' "$file" | head -1
}

_gcloud_auth_chpwd() {
  emulate -L zsh
  [[ -n $GCLOUD_AUTH_PINNED ]] && return
  _gcloud_auth_apply "$(_gcloud_auth_dir_account)"
}

# ---------------------------------------------------------------- subcommands

_gcloud_auth_cmd_list() {
  local -a names
  names=(${(f)"$(_gcloud_auth_names)"})
  if (( ${#names} == 0 )); then
    print -u2 "No accounts registered. Run: gcloud-auth add-account <name>"
    return 1
  fi

  local i=1 name account project mark
  for name in $names; do
    account=$(_gcloud_auth_core_prop "$name" account)
    project=$(_gcloud_auth_core_prop "$name" project)
    mark=" "
    [[ $name == $GCLOUD_AUTH_NAME ]] && mark="*"
    printf '%s %2d) %-12s %s%s\n' "$mark" $i "$name" "${account:-(not logged in)}" "${project:+  [$project]}"
    (( i++ ))
  done

  local n
  read -r "n?Number (Enter to cancel): "
  [[ -z $n ]] && return 0
  if [[ $n != <1-> ]] || (( n > ${#names} )); then
    print -u2 "Invalid number: $n"
    return 1
  fi
  _gcloud_auth_cmd_use "${names[$n]}"
}

_gcloud_auth_cmd_use() {
  local name=$1
  if ! _gcloud_auth_exists "$name"; then
    print -u2 "Account '$name' is not registered. Run: gcloud-auth add-account $name"
    return 1
  fi
  _gcloud_auth_apply "$name"
  export GCLOUD_AUTH_PINNED=1
  print "Using '$name' in this terminal."
}

_gcloud_auth_cmd_add_account() {
  local name=$1 project=$2
  if [[ -z $name ]]; then
    print -u2 "Usage: gcloud-auth add-account <name> [project-id]"
    return 1
  fi
  if [[ ! $name =~ '^[A-Za-z0-9_-]+$' ]]; then
    print -u2 "Name may only contain letters, digits, hyphen and underscore: $name"
    return 1
  fi
  local dir=$GCLOUD_ACCOUNTS_DIR/$name
  if [[ -e $dir ]]; then
    print -u2 "'$name' already exists: $dir"
    return 1
  fi

  mkdir -p "$dir"
  chmod 700 "$dir"

  print "Log in to gcloud via the browser..."
  if ! CLOUDSDK_CONFIG=$dir gcloud auth login; then
    print -u2 "Login failed. The directory was left in place: $dir"
    return 1
  fi

  # set before the ADC login so it is also recorded as the ADC quota project
  if [[ -n $project ]] && ! CLOUDSDK_CONFIG=$dir gcloud config set project "$project"; then
    print -u2 "Could not set project '$project'. Continuing without it."
    project=
  fi

  print
  print "Log in for Application Default Credentials..."
  # unset so the ADC login is not confused by another account's file
  if ! CLOUDSDK_CONFIG=$dir GOOGLE_APPLICATION_CREDENTIALS= gcloud auth application-default login; then
    print -u2 "ADC login failed. gcloud itself is set up; retry with:"
    print -u2 "  CLOUDSDK_CONFIG=$dir gcloud auth application-default login"
    return 1
  fi

  local account
  account=$(_gcloud_auth_core_prop "$name" account)
  print
  print "Registered account '$name'${account:+ ($account)}${project:+, project $project}."
  print "Switch to it with: gcloud-auth $name"
  [[ -z $project ]] && print "Then set its project with: gcloud-auth set-project <project-id>"

  # re-apply in case the current folder or pin already points at this name
  if [[ $GCLOUD_AUTH_NAME == $name ]]; then
    _gcloud_auth_apply "$name"
  else
    _gcloud_auth_chpwd
  fi
}

_gcloud_auth_cmd_add_dir() {
  local name=$1
  if [[ -z $name ]]; then
    print -u2 "Usage: gcloud-auth add-dir <name>   (use this account in the current folder)"
    return 1
  fi
  if ! _gcloud_auth_exists "$name"; then
    print -u2 "Account '$name' is not registered."
    return 1
  fi
  local file=$GCLOUD_ACCOUNTS_DIR/dirs
  mkdir -p "$GCLOUD_ACCOUNTS_DIR"
  touch "$file"

  # replace an existing entry for the same folder
  local tmp=$file.tmp.$$ p n
  : > "$tmp"
  while IFS=$'\t' read -r p n; do
    [[ ${${p/#\~/$HOME}%/} == "$PWD" ]] && continue
    printf '%s\t%s\n' "$p" "$n" >> "$tmp"
  done < "$file"
  printf '%s\t%s\n' "$PWD" "$name" >> "$tmp"
  mv "$tmp" "$file"

  print "Folder $PWD now uses '$name'."
  _gcloud_auth_chpwd
}

_gcloud_auth_cmd_set_project() {
  local project=$1
  if [[ -z $project ]]; then
    print -u2 "Usage: gcloud-auth set-project <project-id>"
    return 1
  fi
  if [[ -z $GCLOUD_AUTH_NAME ]]; then
    print -u2 "No account selected. Run: gcloud-auth <name>"
    return 1
  fi

  gcloud config set project "$project" || return 1

  if [[ -r $CLOUDSDK_CONFIG/application_default_credentials.json ]]; then
    # unset so gcloud edits this account's ADC file, not one set outside gcloud-auth
    GOOGLE_APPLICATION_CREDENTIALS= gcloud auth application-default set-quota-project "$project" || return 1
  else
    print "No ADC file for '$GCLOUD_AUTH_NAME' yet; only the gcloud project was set."
  fi
}

_gcloud_auth_cmd_status() {
  if [[ -z $GCLOUD_AUTH_NAME ]]; then
    print "account    : (none, using ~/.config/gcloud as if gcloud-auth were not installed)"
    print "config dir : ${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}"
    print "ADC        : ${GOOGLE_APPLICATION_CREDENTIALS:-(default location)}"
    return
  fi
  local account project quota
  account=$(_gcloud_auth_core_prop "$GCLOUD_AUTH_NAME" account)
  project=$(_gcloud_auth_core_prop "$GCLOUD_AUTH_NAME" project)
  quota=$(_gcloud_auth_adc_quota_project "$GCLOUD_AUTH_NAME")
  print "account    : $GCLOUD_AUTH_NAME${account:+ ($account)}"
  print "project    : ${project:-(not set)}"
  print "config dir : $CLOUDSDK_CONFIG"
  if [[ -n $_GCLOUD_AUTH_ADC ]]; then
    print "ADC        : $GOOGLE_APPLICATION_CREDENTIALS"
    if [[ -z $quota ]]; then
      print "quota proj : (not set; run: gcloud-auth set-project <project-id>)"
    elif [[ -n $project && $quota != $project ]]; then
      print "quota proj : $quota (differs from project; run: gcloud-auth set-project $project)"
    else
      print "quota proj : $quota"
    fi
  elif [[ -n $GOOGLE_APPLICATION_CREDENTIALS ]]; then
    print "ADC        : $GOOGLE_APPLICATION_CREDENTIALS (set outside gcloud-auth, takes precedence)"
  else
    print "ADC        : (not logged in; run: gcloud auth application-default login)"
  fi
  if [[ -n $GCLOUD_AUTH_PINNED ]]; then
    print "selected by: manual (pinned for this terminal)"
  else
    print "selected by: folder mapping"
  fi
}

_gcloud_auth_cmd_help() {
  cat <<'HELP'
Usage:
  gcloud-auth                      pick an account from a list (pinned for this terminal)
  gcloud-auth <name>               switch to the given account (pinned for this terminal)
  gcloud-auth add-account <name> [project-id]
                                   register an account and log in (gcloud and ADC)
  gcloud-auth add-dir <name>       use the given account in the current folder
  gcloud-auth set-project <id>     set the project and ADC quota project of the current account
  gcloud-auth status               show the current account
  gcloud-auth help                 show this help

Data lives in $GCLOUD_ACCOUNTS_DIR (default ~/.gcloud-accounts):
  <name>/     CLOUDSDK_CONFIG of each account
  dirs        folder -> account mapping (tab separated, longest match wins)
HELP
}

# ---------------------------------------------------------------- entry point

gcloud-auth() {
  emulate -L zsh
  local cmd=$1
  case $cmd in
    "")            _gcloud_auth_cmd_list ;;
    add-account)   _gcloud_auth_cmd_add_account "$2" "$3" ;;
    add-dir)       _gcloud_auth_cmd_add_dir "$2" ;;
    set-project)   _gcloud_auth_cmd_set_project "$2" ;;
    status)        _gcloud_auth_cmd_status ;;
    help|-h|--help) _gcloud_auth_cmd_help ;;
    *)             _gcloud_auth_cmd_use "$cmd" ;;
  esac
}

# ---------------------------------------------------------------- hook

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _gcloud_auth_chpwd
_gcloud_auth_chpwd
