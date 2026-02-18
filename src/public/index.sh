#!/usr/bin/env sh

##
# Prose Pod installation script
#
# /!\ This script should be ran from your server to setup your own Prose Pod, \
#     with this command: `curl -L https://get.prose.org | sh`
#
# Copyright 2025–2026, Prose Foundation
##


set -eu


# ===== Colors and style =====

# Reset all attributes
A_RESET='\033[0m'

# Color
C_BLACK='\033[30m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_PURPLE='\033[35m'
C_CYAN='\033[36m'
C_WHITE='\033[37m'
C_RESET='\033[39m'

# Intensity
I_BOLD='\033[1m'
I_DIM='\033[2m'
I_RESET='\033[22m'

# Style
S_UNDERLINE='\033[4m'
S_UNDERLINE_OFF='\033[24m'

ANSI_ESC='\x1b\['
ANSI_ESC_ESC='\\\033\['
ANSI_NO_DECOLOR='(4|24)m'

# Removes ANSI color-related escape codes from the input.
# Note that it doesn’t remove underline style.
decolor() {
  sed -r 's/('"${ANSI_ESC}|${ANSI_ESC_ESC}"')('"${ANSI_NO_DECOLOR}"')/\1%%%\2/g' \
    | sed -r 's/'"(${ANSI_ESC}|${ANSI_ESC_ESC})"'[0-9;]+m//g' \
    | sed -r 's/('"${ANSI_ESC}|${ANSI_ESC_ESC}"')%%%('"${ANSI_NO_DECOLOR}"')/\1\2/g'
}

log_trace() {
  if [ "${LOG_TRACE:-0}" -ne 0 ]; then
    printf_tty "%b ${I_DIM}%s${I_RESET}\n" "${C_PURPLE}T${C_RESET}" "$(printf "%s" "$*" | decolor)" >&2
  fi
}
log_dry_run() {
  printf_tty "${I_DIM}%b %s${I_RESET}\n" "${C_YELLOW}dry_run:${C_RESET}" "$(printf "%s" "$*" | decolor)" >&2
}
log_debug() {
  printf_tty "%b %s\n" "${C_YELLOW}D${C_RESET}" "$*" >&2
}
log_info() {
  printf_tty "${I_BOLD}%b %s${I_RESET}\n" "${C_BLUE}i${C_RESET}" "$*"
}
log_warn() {
  printf_tty "${I_BOLD}%b ${C_YELLOW}%s${C_RESET}${I_RESET}\n" "${C_YELLOW}W${C_RESET}" "$(printf "%s" "$*" | decolor)" >&2
}
log_error() {
  printf_tty "${I_BOLD}%b ${C_RED}%s${C_RESET}${I_RESET}\n" "${C_RED}E${C_RESET}" "$(printf "%s" "$*" | decolor)" >&2
}

log_success() {
  printf_tty "${I_BOLD}%b ${C_GREEN}%s${C_RESET}${I_RESET}\n" "${C_GREEN}\u2713${C_RESET}" "$(printf "%s" "$*" | decolor)"
}
log_task_success() {
  printf_tty "%b %s\n" "${C_GREEN}\u00B7${C_RESET}" "$*"
}
log_task_maybe() {
  printf_tty "%b %s\n" "${C_YELLOW}\u00B7${C_RESET}" "$*"
}
log_task_todo() {
  printf_tty "%b %s\n" "${C_RED}\u00B7${C_RESET}" "$*"
}
log_question() {
  printf_tty "%b %s\n" "${C_CYAN}?${C_RESET}" "$*"
}
log_question_inline() {
  printf_tty "%b %s " "${C_CYAN}?${C_RESET}" "$*"
}

format_code() {
  printf "${C_CYAN}${I_DIM}\`${I_RESET}%s${I_DIM}\`${I_RESET}${C_RESET}" "$(printf "%s" "$*" | decolor)"
}
format_hyperlink() {
  local text="${1:?"Expected hyperlink text"}"
  local href="${2:?"Expected hyperlink href"}"
  printf "\033]8;;%s\033\\%s\033]8;;\033\\" "${href}" "${text}"
}
format_path() {
  printf "${S_UNDERLINE}%s${S_UNDERLINE_OFF}" "$*"
}

section_start() {
  echo_tty
  log_trace "$@"
}
section_end() {
  log_success "$@"
}
section_end_todo() {
  printf_tty "${I_BOLD}%b ${C_YELLOW}%s${C_RESET}${I_RESET}\n" "${C_YELLOW}\u2717${C_RESET}" "$*"
}


# ===== Helper functions =====

description() {
  cat <<EOF
${I_BOLD}Prose Pod installation script.${I_RESET}
EOF
}

usage() {
  cat <<EOF
Usage:
  You want to install the latest released version:
    curl -L https://get.prose.org | sh
  You want to run the script with arguments:
    curl -L https://get.prose.org | sh -s -- [arg...]

Options:
  Miscellaneous options:
    --help
      Explains what the command does and how to use it.
    --dry-run
      Do a dry run (i.e. print what would be executed instead of running it).
    --trace
      Log tracing messages when running the script.
EOF
}

help() {
  printf_tty "$(description)\n"
  echo_tty ''
  printf_tty "$(usage)\n"
  exit 0
}

read_tty() {
  read "$@" < /dev/tty
}

printf_tty() {
  printf "$@" > /dev/tty
}

echo_tty() {
  echo "$@" > /dev/tty
}

# Allows passing a pipe as argument.
REGEX_ALLOW_PIPES='s#\\|#|#'
# Allows passing redirects (e.g. `2>&1`) as argument.
REGEX_ALLOW_REDIRECTS='s#([[:digit:]]*)\\>(\\&[[:digit:]]+)?#\1>\2#'
edo() {
  if [ "${DRY_RUN:-0}" -ne 0 ]; then
    log_dry_run "$*"
  else
    log_trace "$*"
    # NOTE: `$@`, `"$@"` or `eval $@` would break spaces in arguments.
    eval $(printf '%q ' "$@" | sed "${REGEX_ALLOW_PIPES:?}" | sed -E "${REGEX_ALLOW_REDIRECTS:?}") < /dev/tty > /dev/tty
  fi
  status=$?
  return $status
}

dim() {
  # NOTE: Do not dim in dry runs because commands will not be ran (thus output)
  #   anyway. They will be logged as traces and colors would be incorrect in
  #   this case (for the log line).
  [ "${DRY_RUN:-0}" -ne 0 ] || printf_tty "${I_DIM}"
  "$@"
  status=$?
  [ "${DRY_RUN:-0}" -ne 0 ] || printf_tty "${I_RESET}"
  return $status
}

# Asks a question, reads y or n and exits
# with code 0 or 1 depending on the answer.
ask_yes_no() {
  local question="${1:?}"
  local yes_no_default="${2:?}" answer

  choices() {
    case "$yes_no_default" in
      y|Y) printf '%s' 'Y|n' ;;
      n|N) printf '%s' 'y|N' ;;
      *) printf '%s' 'y|n' ;;
    esac
  }

  log_question_inline "$(printf '%s [%s]' "$question" "$(choices)")"
  read_tty -r answer
  case "${answer:-"$yes_no_default"}" in
    y|Y) return 0 ;;
    n|N|*) return 1 ;;
  esac
}

run_step_if_not_skipped() {
  local step="${1:?Expected a step name (with no `step_` prefix)}"
  case " ${PROSE_INSTALL_SKIP_STEPS-} " in
    *" ${step} "*)
      log_warn "Step $(format_code "${step}") skipped. Remove it from $(format_code 'PROSE_INSTALL_SKIP_STEPS') to run the step."
      ;;
    *) step_"${step}" ;;
  esac
}

# Creates directories with the correct owner
# and mode then logs the created paths.
prose_create_dir() {
  local mode="${1:?"Expected a mode"}"
  shift 1
  dim edo install -o prose -g prose -m "$mode" -d "$@"
  for p in "$@"; do log_task_success "Created directory $(format_path "$p")."; done
}
# Creates fils with the correct owner
# and mode then logs the created paths.
prose_create_file() {
  local mode="${1:?"Expected a mode"}"
  shift 1
  dim edo install -o prose -g prose -m "$mode" -T /dev/null "$@"
  for p in "$@"; do log_task_success "Created file $(format_path "$p")."; done
}
# Retrieves a file from `prose-pod-system` then
# changes the owner and logs the created path.
prose_get_file() {
  local in_path="${1:?Expected a path in prose-pod-system}"
  local out_path="${2:?Expected a path on the file system}"

  dim edo curl -s -L "${PROSE_FILES:?}"/"$in_path" \
    \| sed s/'{your_domain}'/"${APEX_DOMAIN:?}"/g \
    \> "$out_path"

  dim edo chown prose:prose "$out_path"

  log_task_success "Created file $(format_path "$out_path")."
}

log_contact_assistance() {
  log_info "Please contact our technical support team at $(format_hyperlink "https://prose.org/contact/" "https://prose.org/contact/") for further assistance."
}
die() {
  if [ $# -gt 0 ]; then
    log_error "$@"
  fi
  exit 1
}

link_docs_deploy() {
  format_hyperlink "docs.prose.org/guides/operating/deploy" "https://docs.prose.org/guides/operating/deploy/"
}
link_app_web() {
  format_hyperlink "${PROSE_POD_DOMAIN:?}" "https://${PROSE_POD_DOMAIN:?}"
}
link_dashboard() {
  format_hyperlink "admin.${PROSE_POD_DOMAIN:?}" "https://admin.${PROSE_POD_DOMAIN:?}"
}


# === POSIX-compliant fake arrays ===

# POSIX shells don’t have arrays, therefore we have to craft them ourselves.
# The trick is to create a long string with a custom separator, then split on
# it later for iteration.
# NOTE: I (RemiBardon) wish I could just use Bash arrays…

# Use ASCII Unit Separator (`0x1F`) as separator because it is very unlikely
# to appear in normal strings.
ARRAY_SEP="$(printf '\037')"

# Adds a string to a “pseudo-array” string.
# Usage: `result=$(posix_array_push "$existing_array" "new_item")`.
posix_array_push() {
  existing_array="${1-}"
  new_item="${2:?}"

  if [ -z "${existing_array-}" ]; then
    # First item: no separator needed.
    printf '%s' "${new_item-}"
  else
    # Append with separator.
    printf '%s%s%s' "${existing_array:?}" "${ARRAY_SEP:?}" "${new_item-}"
  fi
}

# Splits a “pseudo-array” string for use in `for` loops.
# Usage: `posix_array_split "$array_string" | while read -r item; do ... done`.
# See tests in <https://gist.github.com/RemiBardon/c7b9db54dca1c7e8d819b4f9267b9991>.
posix_array_split() {
  array_string="$1"

  if [ -z "${array_string-}" ]; then
    return 0
  fi

  # Use parameter expansion to replace `$ARRAY_SEP` by `\n`.
  # This creates one item per line, preserving spaces within items.
  # NOTE: We can’t just use `IFS=$ARRAY_SEP printf` because `printf`
  #   is a builtin and do not get the special treatment `read` does.
  oldIFS=$IFS IFS="${ARRAY_SEP:?}"
  printf '%s\n' ${array_string:?}
  IFS=$oldIFS
}


# ===== Constants =====

PROSE_USER_NAME=prose
PROSE_UID=1001
PROSE_GROUP_NAME=prose
PROSE_GID=1001
PROSE_CONFIG_FILE=/etc/prose/prose.toml
PROSE_COMPOSE_FILE=/etc/prose/compose.yaml
PROSE_FILES=https://raw.githubusercontent.com/prose-im/prose-pod-system/refs/heads/master


# ===== Main logic =====


# === Argument parsing ===
for arg in "$@"; do
  case $arg in
    --help) help ;;
    --dry-run) export DRY_RUN=1 ;;
    --trace) export LOG_TRACE=1 ;;
    *) log_error "Unknown argument: $(format_code $arg)."; log_info "$(usage)"; die ;;
  esac
done


# === Greeting ===

# Welcome message
log_info "Hello and welcome to the $(format_hyperlink "Prose" "https://prose.org/") installer script."
echo_tty

# Dry run warning
if [ "${DRY_RUN:-0}" -ne 0 ]; then
  log_warn 'Dry run is enabled, actions will be logged instead of being performed.'
  echo_tty
fi


# === Checks ===

step_checks() {
  log_trace 'Checking if your architecture is supported…'
  case $(uname -m) in
    x86_64|aarch64) ;;
    *) die "Your architecture is unsupported. Only $(format_code x86_64) and $(format_code aarch64) are." ;;
  esac

  log_trace "Checking if user is $(format_code root)…"
  if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be ran as root."
    log_contact_assistance
    die
  fi

  log_trace "Checking if user and group $(format_code prose) can be created…"
  if getent passwd "${PROSE_UID:?}" > /dev/null && [ "$(getent passwd "${PROSE_UID:?}" | cut -d: -f1)" != "${PROSE_USER_NAME:?}" ]; then
    # TODO: Add link to a tracking issue.
    log_error 'A user with UID 1001 already exists. For security reasons, we won’t reuse it.'
    log_error 'Because of how Docker works, we can’t easily use a different UID.'
    log_contact_assistance
    die
  fi
  if getent group "${PROSE_GID:?}" > /dev/null && [ "$(getent passwd "${PROSE_GID:?}" | cut -d: -f1)" != "${PROSE_GROUP_NAME:?}" ]; then
    # TODO: Add link to a tracking issue.
    log_error 'A group with GID 1001 already exists. For security reasons, we won’t reuse it.'
    log_error 'Because of how Docker works, we can’t easily use a different GID.'
    log_contact_assistance
    die
  fi

  if [ "${LOG_TRACE:-0}" -ne 0 ]; then echo_tty; fi
}
run_step_if_not_skipped checks


# === User inputs ===

step_questions() {
  # Ask company name.
  log_question_inline 'What is the name of your company?'
  read_tty -r COMPANY_NAME

  # Ask company apex domain.
  log_question_inline 'What is your apex domain?'
  read_tty -r APEX_DOMAIN

  # Ask desired Prose Pod address.
  PROSE_POD_DOMAIN_DEFAULT="prose.${APEX_DOMAIN:?}"
  log_question_inline "Where do you want to host Prose? (${PROSE_POD_DOMAIN_DEFAULT:?})"
  read_tty -r PROSE_POD_DOMAIN
  PROSE_POD_DOMAIN="${PROSE_POD_DOMAIN:-"${PROSE_POD_DOMAIN_DEFAULT:?}"}"

  # Ask SMTP server info.
  if ask_yes_no 'Do you have a SMTP server Prose could use (e.g. to send invitations)?' y; then
    log_question_inline "  - SMTP host: (${APEX_DOMAIN:?})"
    read_tty -r SMTP_HOST
    SMTP_HOST="${SMTP_HOST:-"${APEX_DOMAIN:?}"}"

    SMTP_PORT_DEFAULT=587
    log_question_inline "  - SMTP port: (${SMTP_PORT_DEFAULT:?})"
    read_tty -r SMTP_PORT
    SMTP_PORT="${SMTP_PORT:-"${SMTP_PORT_DEFAULT:?}"}"

    log_question_inline '  - SMTP username:'
    read_tty -r SMTP_USER

    log_question_inline '  - SMTP password:'
    read_tty -r SMTP_PASS

    ask_yes_no '  - Force SMTP encryption?' y && SMTP_ENCRYPT=true || SMTP_ENCRYPT=false
  else
    log_warn "Prose can start without access to a SMTP server, but you will have to"
    log_warn "configure it in $(format_path "${PROSE_CONFIG_FILE:?}") in order to send invitations."
  fi
}
run_step_if_not_skipped questions


# === Install Prose ===

TODO_LIST=""

step_create_user_and_group() {
  section_start "Creating the user and group…"

  # Create group.
  if [ "$(getent passwd "${PROSE_GID:?}" | cut -d: -f1)" = "${PROSE_GROUP_NAME:?}" ]; then
    log_trace "Group $(format_code "${PROSE_GROUP_NAME:?}(${PROSE_GID:?})") already exists."
  else
    dim edo addgroup --gid "${PROSE_GID:?}" "${PROSE_GROUP_NAME:?}" >/dev/null
  fi

  # Create user.
  if [ "$(getent passwd "${PROSE_UID:?}" | cut -d: -f1)" = "${PROSE_USER_NAME:?}" ]; then
    log_trace "User $(format_code "${PROSE_USER_NAME:?}(${PROSE_UID:?})") already exists."
  else
    dim edo adduser --uid "${PROSE_UID:?}" --gid "${PROSE_GID:?}" --disabled-password --no-create-home --gecos 'Prose' "${PROSE_USER_NAME:?}" >/dev/null
  fi

  section_end "User $(format_code "${PROSE_USER_NAME:?}(${PROSE_UID:?})") and group $(format_code "${PROSE_GROUP_NAME:?}(${PROSE_GID:?})") created (if needed)."
}
run_step_if_not_skipped create_user_and_group

step_create_dirs_and_files() {
  section_start 'Creating required files and directories…'

  # Directories
  prose_create_dir 750 \
    /var/lib/{prose-pod-server,prose-pod-api,prosody} \
    /etc/{prose,prosody} \
    /etc/prosody/certs

  # Database
  prose_create_file 640 \
    /var/lib/prose-pod-api/database.sqlite

  # Environment
  prose_create_file 600 \
    /etc/prose/prose.env

  section_end 'Created required files and directories.'
}
run_step_if_not_skipped create_dirs_and_files

step_prose_config() {
  section_start 'Creating the Prose configuration file…'

  # Get the template.
  prose_get_file templates/prose-scripting.toml "${PROSE_CONFIG_FILE:?}"

  # Fill the file with answers from the user.
  if [ -n "${SMTP_HOST-}" ]; then
    set_config() {
      local key="${1:?Expected a config name}"
      local value="${2:?Expected a value}"
      dim edo sed -i -E -e "s~\{${key}\}~${value}~g" "${PROSE_CONFIG_FILE:?}"
    }

    set_config_opt() {
      local key="${1:?Expected a config name}"
      local value="${2?Expected a value}"
      if [ -n "${value-}" ]; then
        dim edo sed -i -E -e "s~\{${key}\}~${value}~g" "${PROSE_CONFIG_FILE:?}"
      else
        dim edo sed -i -E -e 's~^(.*\{'"${key}"'\}.*)$~#\1~g' "${PROSE_CONFIG_FILE:?}"
      fi
    }

    set_config company_name "${COMPANY_NAME:?}"

    set_config pod_domain "${PROSE_POD_DOMAIN:?}"

    set_config smtp_host "${SMTP_HOST:?}"

    set_config_opt smtp_port "${SMTP_PORT-}"

    set_config_opt smtp_username "${SMTP_USER-}"
    # WARN: Passwords containing a `~` will break but let’s ignore it.
    set_config_opt smtp_password "${SMTP_PASS-}"

    set_config_opt smtp_encrypt "${SMTP_ENCRYPT-}"
  else
    dim edo sed -i -E -e 's/^(smtp_\w+ =)/#\1/g' "${PROSE_CONFIG_FILE:?}"
    dim edo sed -i -E -e 's/(\[notifiers.email\])/#\1/' "${PROSE_CONFIG_FILE:?}"
  fi

  section_end "Created the Prose configuration file at $(format_path "${PROSE_CONFIG_FILE:?}")."
}
run_step_if_not_skipped prose_config

step_ssl_certificates_prosody() {
  section_start 'Installing SSL certificates for the Server…'

  if ! command -v certbot >/dev/null; then
    log_info "Updating the apt index…"
    dim edo apt-get -q update

    log_info "Installing $(format_code certbot)…"
    dim edo apt-get -q install -y certbot
  fi

  local cert_renewal_conf_file="/etc/letsencrypt/renewal/${APEX_DOMAIN:?}.conf"
  local post_hook="/bin/bash -c 'rsync -aL --chown=prose:prose /etc/{letsencrypt/live,prosody/certs}/\"${APEX_DOMAIN:?}\"/'"
  if edo certbot certonly --standalone -d "${APEX_DOMAIN:?}" -d groups."${APEX_DOMAIN:?}"; then
    dim edo rsync -aL --chown=prose:prose /etc/{letsencrypt/live,prosody/certs}/"${APEX_DOMAIN:?}"/

    if grep -q 'post_hook' "${cert_renewal_conf_file:?}"; then
      if grep -q 'prosody/certs' "${cert_renewal_conf_file:?}"; then
        log_task_maybe "$(format_code post_hook) already configured in $(format_path "${cert_renewal_conf_file:?}"). Assuming it’s correct."
      else
        TODO_LIST="$(posix_array_push "${TODO_LIST-}" "Add $(format_code "${post_hook}") to your $(format_code post_hook) in $(format_path "${cert_renewal_conf_file:?}").")"
        log_task_todo "$(format_code post_hook) already configured in $(format_path "${cert_renewal_conf_file:?}"). Manual action required."
      fi
    else
      dim edo sed -i '/^\[renewalparams\]$/a post_hook = "'"${post_hook}"'"' "${cert_renewal_conf_file:?}"
    fi

    section_end 'Installed SSL certificates for the Server.'
  else
    TODO_LIST="$(posix_array_push "${TODO_LIST-}" "Generate certificates for $(format_code "${APEX_DOMAIN:?}") and $(format_code "groups.${APEX_DOMAIN:?}") then put them in $(format_path "/etc/letsencrypt/live/${APEX_DOMAIN:?}").")"
    TODO_LIST="$(posix_array_push "${TODO_LIST-}" "Add $(format_code "${post_hook}") to your $(format_code post_hook) in $(format_path "${cert_renewal_conf_file:?}").")"
    log_task_todo "Certificates for $(format_code "${APEX_DOMAIN:?}") and $(format_code "groups.${APEX_DOMAIN:?}") not generated. Manual action required."

    section_end_todo 'SSL certificates for the Server not installed.'
  fi
}
run_step_if_not_skipped ssl_certificates_prosody

check_docker_compose_installed() {
  command -v docker >/dev/null && docker compose version >/dev/null 2>&1
}
install_docker() {
  log_info 'Installing Docker Compose…'
  dim edo curl -s -L https://get.docker.com \| sh
}
step_docker_compose() {
  section_start 'Installing Prose using Docker Compose…'

  check_docker_compose_installed || install_docker

  dim edo usermod -aG docker "${PROSE_USER_NAME:?}"
  log_task_success "User $(format_code "${PROSE_USER_NAME:?}") added to group $(format_code docker)."

  prose_get_file compose.yaml "${PROSE_COMPOSE_FILE:?}"

  section_end 'Prose is ready to run.'
}
run_step_if_not_skipped docker_compose

step_run_prose() {
  section_start 'Running Prose…'

  prose_get_file templates/prose.service /etc/systemd/system/prose.service
  dim edo systemctl -q daemon-reload
  dim edo systemctl -q enable prose
  log_task_success "$(format_code systemd) service $(format_code prose) enabled."
  dim edo systemctl -q start prose
  log_task_success "$(format_code systemd) service $(format_code prose) started."

  section_end 'Prose is running.'
}
run_step_if_not_skipped run_prose

step_reverse_proxy() {
  section_start 'Configuring NGINX to serve Prose web apps…'

  dim edo apt-get -q install -y nginx python3-certbot-nginx
  edo certbot certonly --nginx -d "${PROSE_POD_DOMAIN:?}" -d "admin.${PROSE_POD_DOMAIN:?}"

  prose_get_file templates/nginx.conf /etc/nginx/sites-available/"${PROSE_POD_DOMAIN:?}"

  dim edo ln -s /etc/nginx/sites-{available,enabled}/"${PROSE_POD_DOMAIN:?}" >/dev/null

  dim edo systemctl -q reload nginx

  local well_known_dir="$(find /var/www -type d -name *well-known)"
  if [ -n "${well_known_dir-}" ]; then
    prose_get_file templates/host-meta "${well_known_dir:?}"/host-meta
    prose_get_file templates/host-meta.json "${well_known_dir:?}"/host-meta.json
  else
    well_known_dir=/var/www/default/.well-known
    dim edo mkdir -p "${well_known_dir:?}"
    prose_get_file templates/host-meta "${well_known_dir:?}"/host-meta
    prose_get_file templates/host-meta.json "${well_known_dir:?}"/host-meta.json
    prose_get_file templates/nginx-well-known.conf /etc/nginx/sites-available/"${APEX_DOMAIN:?}"
    dim edo ln -s /etc/nginx/sites-{available,enabled}/"${APEX_DOMAIN:?}" >/dev/null
    dim edo systemctl -q reload nginx
  fi
  : ${well_known_dir:=/var/www/default/.well-known}

  section_end "NGINX is serving $(link_app_web) and $(link_dashboard)."
}
run_step_if_not_skipped reverse_proxy

echo_tty
if [ -z "${TODO_LIST-}" ]; then
  log_success 'Installation finished!'
  log_info "You can now open $(link_dashboard) and continue setting up your Prose Pod there."
else
  log_warn 'Installation is finished, but a few things couldn’t be automated and require manual actions:'
  posix_array_split "${TODO_LIST:?}" | while read -r item; do
    log_warn "- ${item-}"
  done
  log_info "After it’s done, open $(link_dashboard) and continue setting up your Prose Pod there."
fi
log_info "For more information, read $(link_docs_deploy)."
