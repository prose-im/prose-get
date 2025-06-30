#!/usr/bin/env bash

set -eu
set -o pipefail


# ===== Colors and style =====

C_OFF='\033[0m'

C_BLACK='\033[0;30m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_PURPLE='\033[0;35m'
C_CYAN='\033[0;36m'
C_WHITE='\033[0;37m'

S_DARK='\033[2m'
S_DARK_OFF='\033[22m'

S_UNDERLINE='\033[4m'
S_UNDERLINE_OFF='\033[24m'

log_trace() {
  if (( ${LOG_TRACE:-0} )); then
    printf "%b %s\n" "${C_PURPLE}T${C_OFF}" "$*" >&2
  fi
}
log_debug() {
  printf "%b %s\n" "${C_YELLOW}D${C_OFF}" "$*" >&2
}
log_info() {
  printf "%b %s\n" "${C_BLUE}i${C_OFF}" "$*"
}
log_warn() {
  printf "%b ${C_YELLOW}%s${C_OFF}\n" "${C_YELLOW}W${C_OFF}" "$*" >&2
}
log_error() {
  printf "%b ${C_RED}%s${C_OFF}\n" "${C_RED}E${C_OFF}" "$*" >&2
}

log_success() {
  printf "%b %s\n" "${C_GREEN}\u2713${C_OFF}" "$*"
}
log_task_success() {
  printf "%b ${S_DARK}%s${S_DARK_OFF}\n" "${C_GREEN}\u00B7${C_OFF}" "$*"
}
log_task_maybe() {
  printf "%b ${S_DARK}%s${S_DARK_OFF}\n" "${C_YELLOW}\u00B7${C_OFF}" "$*"
}
log_task_todo() {
  printf "%b ${S_DARK}%s${S_DARK_OFF}\n" "${C_RED}\u00B7${C_OFF}" "$*"
}
log_question() {
  printf "%b %s\n" "${C_CYAN}?${C_OFF}" "$*"
}
log_question_inline() {
  printf "%b %s " "${C_CYAN}?${C_OFF}" "$*"
}

format_code() {
  printf "${C_CYAN}${S_DARK}\`${S_DARK_OFF}%s${S_DARK}\`${S_DARK_OFF}${C_OFF}" "$*"
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
  echo
  log_trace "$@"
}
section_end() {
  log_success "$@"
}


# ===== Helper functions =====

edo() {
  bash -c "$*"
  status=$?
  return $status
}

dim() {
  printf "${S_DARK}"
  "$@"
  status=$?
  printf "${S_DARK_OFF}"
  return $status
}

# Asks a question, reads y or n and exits
# with code 0 or 1 depending on the answer.
ask_yes_no() {
  local question="${1:?}"
  local yes_no_default="${2:?}" answer

  choices() {
    case "$yes_no_default" in
      y|Y) echo 'Y|n' ;;
      n|N) echo 'y|N' ;;
      *) echo 'y|n' ;;
    esac
  }

  log_question_inline "$(printf '%s [%s]' "$question" "$(choices)")"
  # NOTE: Reading with `-s` then `echo`ing is a trick to avoid printing
  #   newlines when the user only hits [Enter]. `-s` hides user input,
  #   which doesn’t print the user-induced `\n`, but `read` doesn’t
  #   store trailing whitespaces in variables which means `$answer`
  #   will be empty. `echo` will print the value the user entered if
  #   any, plus a trailing `\n` which looks exactly like if we hadn’t
  #   used `-s` in the first place.
  read -n 1 -s answer
  echo "${answer}"
  case "${answer:-"$yes_no_default"}" in
    y|Y) return 0 ;;
    n|N|*) return 1 ;;
  esac
}

# Creates directories with the correct owner
# and mode then logs the created paths.
prose_create_dir() {
  local mode="${1:?"Expected a mode"}"
  shift 1
  install -o prose -g prose -m "$mode" -d "$@"
  for p in "$@"; do log_task_success "Created directory $(format_path "$p")."; done
}
# Creates fils with the correct owner
# and mode then logs the created paths.
prose_create_file() {
  local mode="${1:?"Expected a mode"}"
  shift 1
  install -o prose -g prose -m "$mode" -T /dev/null "$@"
  for p in "$@"; do log_task_success "Created file $(format_path "$p")."; done
}
# Retrieves a file from `prose-pod-system` then
# changes the owner and logs the created path.
prose_get_file() {
  local in_path="${1:?Expected a path in prose-pod-system}"
  local out_path="${2:?Expected a path on the file system}"

  curl -s -L "${PROSE_FILES:?}"/"$in_path" \
    | sed s/'{your_domain}'/"${APEX_DOMAIN:?}"/g \
    > "$out_path"

  chown prose:prose "$out_path"

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


# ===== Constants =====

PROSE_USER_NAME=prose
PROSE_UID=1001
PROSE_GROUP_NAME=prose
PROSE_GID=1001
PROSE_CONFIG_FILE=/etc/prose/prose.toml
PROSE_COMPOSE_FILE=/etc/prose/compose.yaml
PROSE_FILES=https://raw.githubusercontent.com/prose-im/prose-pod-system/refs/heads/master


# ===== Main logic =====


# === Greeting ===

# Welcome message
log_info "Hello and welcome to the $(format_hyperlink "Prose" "https://prose.org/") installer script."
echo


# === Checks ===

step_checks() {
  log_trace 'Checking if your architecture is supported…'
  case $(uname -m) in
    x86_64|aarch64) ;;
    *) die "Your architecture is unsupported. Only $(format_code x86_64) and $(format_code aarch64) are." ;;
  esac

  log_trace "Checking if user is $(format_code root)…"
  if [ "$EUID" -ne 0 ]; then
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

  if (( ${LOG_TRACE:-0} )); then echo; fi
}
if ! (( ${SKIP_CHECKS:-0} )); then step_checks; fi


# === User inputs ===

step_questions() {
  # Ask company name.
  log_question_inline 'What is the name of your company?'
  read -r COMPANY_NAME

  # Ask company apex domain.
  log_question_inline 'What is your apex domain?'
  read -r APEX_DOMAIN

  # Ask desired Prose Pod address.
  PROSE_POD_DOMAIN_DEFAULT=prose."${APEX_DOMAIN:?}"
  log_question_inline "Where do you want to host Prose? (${PROSE_POD_DOMAIN_DEFAULT:?})"
  read -r PROSE_POD_DOMAIN
  PROSE_POD_DOMAIN="${PROSE_POD_DOMAIN:-"${PROSE_POD_DOMAIN_DEFAULT:?}"}"

  # Ask SMTP server info.
  if ask_yes_no 'Do you have a SMTP server Prose could use (e.g. to send invitations)?' y; then
    log_question_inline "  - SMTP host (${APEX_DOMAIN:?}):"
    read -r SMTP_HOST
    SMTP_HOST="${SMTP_HOST:-"${APEX_DOMAIN:?}"}"

    SMTP_PORT_DEFAULT=587
    log_question_inline "  - SMTP port: (${SMTP_PORT_DEFAULT:?})"
    read -r SMTP_PORT
    SMTP_PORT="${SMTP_PORT:-"${SMTP_PORT_DEFAULT:?}"}"

    log_question_inline '  - SMTP username:'
    read -r SMTP_USER

    log_question_inline '  - SMTP password:'
    read -r -s SMTP_PASS
    echo # Print empty line because `read -s` doesn’t.

    ask_yes_no '  - Force SMTP encryption?' y && SMTP_ENCRYPT=true || SMTP_ENCRYPT=false
  else
    log_warn "Prose can start without access to a SMTP server, but you will have to"
    log_warn "configure it in $(format_path "${PROSE_CONFIG_FILE:?}") in order to send invitations."
  fi
}
if ! (( ${SKIP_QUESTIONS:-0} )); then step_questions; fi


# === Install Prose ===

TODO_LIST=()

step_create_user_and_group() {
  section_start "Creating the user and group…"

  # Create group.
  if [ "$(getent passwd "${PROSE_GID:?}" | cut -d: -f1)" == "${PROSE_GROUP_NAME:?}" ]; then
    log_trace "Group $(format_code "${PROSE_GROUP_NAME:?}(${PROSE_GID:?})") already exists."
  else
    edo addgroup --gid "${PROSE_GID:?}" "${PROSE_GROUP_NAME:?}" >/dev/null
  fi

  # Create user.
  if [ "$(getent passwd "${PROSE_UID:?}" | cut -d: -f1)" == "${PROSE_USER_NAME:?}" ]; then
    log_trace "User $(format_code "${PROSE_USER_NAME:?}(${PROSE_UID:?})") already exists."
  else
    edo adduser --uid "${PROSE_UID:?}" --gid "${PROSE_GID:?}" --disabled-password --no-create-home --gecos 'Prose' "${PROSE_USER_NAME:?}" >/dev/null
  fi

  section_end "User $(format_code "${PROSE_USER_NAME:?}(${PROSE_UID:?})") and group $(format_code "${PROSE_GROUP_NAME:?}(${PROSE_GID:?})") created (if needed)."
}
step_create_user_and_group

step_create_dirs_and_files() {
  section_start 'Creating required files and directories…'

  # Directories
  prose_create_dir 750 \
    /var/lib/{prose-pod-api,prosody} \
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
step_create_dirs_and_files

step_prose_config() {
  section_start 'Creating the Prose configuration file…'

  # Get the template.
  prose_get_file templates/prose-scripting.toml "${PROSE_CONFIG_FILE:?}"
  local replacements
  replacements=()

  # Fill the file with answers from the user.
  if [ -n "${SMTP_HOST-}" ]; then
    set_config() {
      local key="${1:?Expected a config name}"
      local value="${2:?Expected a value}"
      replacements+=(-e "s~\{${key}\}~${value}~g")
    }

    set_config_opt() {
      local key="${1:?Expected a config name}"
      local value="${2?Expected a value}"
      if [ -n "${value-}" ]; then
        replacements+=(-e "s~\{${key}\}~${value}~g")
      else
        replacements+=(-e 's~^(.*\{'"${key}"'\}.*)$~#\1~g')
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
    replacements+=( \
      -e 's/^(smtp_\w+ =)/#\1/g' \
      -e 's/(\[notifiers.email\])/#\1/' \
    )
  fi

  sed -i -E "${replacements[@]}" "${PROSE_CONFIG_FILE:?}"

  section_end "Created the Prose configuration file at $(format_path "${PROSE_CONFIG_FILE:?}")."
}
if ! (( ${SKIP_PROSE_CONFIG:-0} )); then step_prose_config; fi

step_ssl_certificates_prosody() {
  section_start 'Installing SSL certificates for the Server…'

  if ! command -v certbot >/dev/null; then
    log_info "Updating the apt index…"
    dim edo apt-get -q update

    log_info "Installing $(format_code certbot)…"
    dim edo apt-get -q install -y certbot
  fi

  certbot certonly --standalone -d "${APEX_DOMAIN:?}" -d groups."${APEX_DOMAIN:?}"

  rsync -aL --chown=prose:prose /etc/{letsencrypt/live,prosody/certs}/"${APEX_DOMAIN:?}"/

  local cert_renewal_conf_file="/etc/letsencrypt/renewal/${APEX_DOMAIN:?}.conf"
  if grep -q 'post_hook' "${cert_renewal_conf_file:?}"; then
    if grep -q 'prosody/certs' "${cert_renewal_conf_file:?}"; then
      log_task_maybe "$(format_code post_hook) already configured in $(format_path "${cert_renewal_conf_file:?}"). Assuming it’s correct."
    else
      TODO_LIST+=("Add $(format_code "/bin/bash -c 'rsync -aL --chown=prose:prose /etc/{letsencrypt/live,prosody/certs}/\"${APEX_DOMAIN:?}\"/'") your $(format_code post_hook) in $(format_path "${cert_renewal_conf_file:?}").")
      log_task_todo "$(format_code post_hook) already configured in $(format_path "${cert_renewal_conf_file:?}"). Manual action required."
    fi
  else
    sed -i '/^\[renewalparams\]$/a post_hook = "'"/bin/bash -c 'rsync -aL --chown=prose:prose /etc/{letsencrypt/live,prosody/certs}/\"${APEX_DOMAIN:?}\"/'"'"' "${cert_renewal_conf_file:?}"
  fi

  section_end 'Installed SSL certificates for the Server.'
}
step_ssl_certificates_prosody

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

  usermod -aG docker "${PROSE_USER_NAME:?}"
  log_task_success "User $(format_code "${PROSE_USER_NAME:?}") added to group $(format_code docker)."

  prose_get_file compose.yaml "${PROSE_COMPOSE_FILE:?}"

  section_end 'Prose is ready to run.'
}
step_docker_compose

step_run_prose() {
  section_start 'Running Prose…'

  prose_get_file templates/prose.service /etc/systemd/system/prose.service
  systemctl daemon-reload
  systemctl enable prose
  log_task_success "$(format_code systemd) service $(format_code prose) enabled."
  systemctl start prose
  log_task_success "$(format_code systemd) service $(format_code prose) started."

  section_end 'Prose is running.'
}
step_run_prose

step_reverse_proxy() {
  section_start 'Configuring NGINX to serve Prose web apps…'

  dim edo apt-get -q install -y nginx python3-certbot-nginx
  certbot certonly --nginx -d "prose.${APEX_DOMAIN:?}" -d "admin.prose.${APEX_DOMAIN:?}"

  prose_get_file templates/nginx.conf /etc/nginx/sites-available/"prose.${APEX_DOMAIN:?}"

  ln -s /etc/nginx/sites-{available,enabled}/"prose.${APEX_DOMAIN:?}" >/dev/null

  systemctl reload nginx

  local well_known_dir="$(find /var/www -type d -name *well-known)"
  if [ -n "${well_known_dir-}" ]; then
    prose_get_file templates/host-meta "${well_known_dir:?}"/host-meta
    prose_get_file templates/host-meta.json "${well_known_dir:?}"/host-meta.json
  else
    well_known_dir=/var/www/default/.well-known
    mkdir -p "${well_known_dir:?}"
    prose_get_file templates/host-meta "${well_known_dir:?}"/host-meta
    prose_get_file templates/host-meta.json "${well_known_dir:?}"/host-meta.json
    prose_get_file templates/nginx-well-known.conf /etc/nginx/sites-available/"${APEX_DOMAIN:?}"
    ln -s /etc/nginx/sites-{available,enabled}/"${APEX_DOMAIN:?}"
    systemctl reload nginx
  fi
  : ${well_known_dir:=/var/www/default/.well-known}

  section_end "NGINX is serving $(format_hyperlink "prose.${APEX_DOMAIN:?}" "https://prose.${APEX_DOMAIN:?}") and $(format_hyperlink "admin.prose.${APEX_DOMAIN:?}" "https://admin.prose.${APEX_DOMAIN:?}")."
}
step_reverse_proxy

echo
if [ ${#TODO_LIST[@]} -eq 0 ]; then
  log_success Installation finished!
  # TODO: Link / instructions to next steps / docs.
else
  log_warn 'Installation is finished, but a few things couldn’t be automated and require manual actions:'
  for item in "${TODO_LIST[@]}"; do
    log_warn "- ${item-}"
  done
fi
