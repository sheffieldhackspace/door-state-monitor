#!/bin/bash
# listen to MQTT topic and save files for states
# run as a daemon

source .env

echo "starting to listen…" >&2

# increment counter in a file, needs filename as arg 1
# file contains integer counter like this:
#   109
function increment_file_counter() {
  file="${STATE_FILE_ROOT}/${1:-broken}.txt"
  if [[ ! -f "${file}" ]]; then
    num=0
  else
    num=$(cat "${file}")
  fi
  num=$(( $num + 1 ))
  echo "  wrote new counter! ${num}" >&2
  printf "%s" "${num}" > "${file}"
}

# add fob event to fob event file
# arguments:
#   1: timestamp, or empty string where we just grab the current time
#   2: fob ID, or otherwise unique ID
# event file looks like this
#   1789303400 04356FD2AFF233
#   1789303426 04654ABAAFCC21
# also cleans up lines from the file older than 24 hours
update_fob_file() {
  timestamp="${1:-}"
  fobid="${2:-null}"
  [[ -z "${timestamp}" ]] && timestamp=$(date '+%s')
  file="${STATE_FILE_ROOT}/${STATE_FOB_FILE}"
  delete_older_than_ts=$(date --date="-24 hours" '+%s')
  if [[ ! -f "${file}" ]]; then
    contents=""
  else
    contents=$(cat "${file}")
  fi
  echo "  writing new line to fob file, ts ${timestamp} id ${fobid}"
  echo "${contents}" \
    | awk -F' ' -v min="${delete_older_than_ts}" \
      -v ts="${timestamp}" -v id="${fobid}" \
      '$1 > min {print} END {printf "%s %s\n", ts, id}' \
    > "${file}"
}

while read -u 10 -r message; do
  timestamp=$(date '+%s')
  echo "[${timestamp}] Got MQTT message!" >&2
  date | sed 's+^+  +' >&2
  echo "  mqtt: ${message}" >&2

  topic=$(echo "${message}" | cut -d' ' -f 1)
  message=$(echo "${message}" | cut -d' ' -f 2-)

  if [[ "${topic}" == "${MOSQUITTO_TOPIC_FOB}" ]]; then
    echo "  FOB scanned!" >&2
    fobid=$(echo "${message}" | jq -r '.id')
    datetime=$(echo "${message}" | jq -r '.ts')
    timestamp=$(date --date="${datetime}" '+%s')
    echo "  got fob scan, id ${fobid}, datetime ${datetime}, timestamp ${timestamp}"
    # do not send timestamp, just use server timestamp
    update_fob_file "" "${fobid}"

  elif [[ "${topic}" == "${MOSQUITTO_TOPIC_OPENSTATE}" ]]; then
    echo "  door opened/closed" >&2
    opened=$(echo "${message}" | jq -r '."Door Open"')
    if [[ "${opened}" == "true" ]]; then
      increment_file_counter door_opened
    elif [[ "${opened}" == "false" ]]; then
      increment_file_counter door_closed
    else
      echo "  warning: non-boolean bool" >&2
    fi

  elif [[ "${topic}" == "${MOSQUITTO_TOPIC_LOCKSTATE}" ]]; then
    echo "  door locking/unlocking" >&2
    state=$(echo "${message}" | jq -r '.state')
    if [[ "${state}" == "UNLOCKING" ]]; then increment_file_counter door_unlocking
    elif [[ "${state}" == "UNLOCKED" ]]; then increment_file_counter door_unlocked
    elif [[ "${state}" == "LOCKING" ]]; then increment_file_counter door_locking
    elif [[ "${state}" == "LOCKED" ]]; then increment_file_counter door_locked
    else echo "  warning: I do not know this state" >&2
    fi

  else
    echo "  warning: does not match event!" >&2
  fi
done 10< <(
  mosquitto_sub -h mosquitto.shhm.uk -v -R \
    -t "${MOSQUITTO_TOPIC_OPENSTATE}" \
    -t "${MOSQUITTO_TOPIC_LOCKSTATE}" \
    -t "${MOSQUITTO_TOPIC_FOB}" \
)
