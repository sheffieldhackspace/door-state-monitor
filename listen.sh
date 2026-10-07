#!/bin/bash
# listen to MQTT topic and save files for states
# run as a daemon

source .env

echo "starting to listen…" >&2

function slugify() {
  echo "${1}" | tr '[A-Z]' '[a-z]' | sed 's+ ++'
}

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
#   1: filename, i.e., "doorc"
#   2: timestamp, or empty string where we just grab the current time
#   3: fob ID, or otherwise unique ID
# event file looks like this
#   1789303400 04356FD2AFF233
#   1789303426 04654ABAAFCC21
# also cleans up lines from the file older than 24 hours
update_fob_file() {
  file="${STATE_FILE_ROOT}/${1:-broken}_fobs.txt"
  timestamp="${2:-}"
  fobid="${3:-null}"
  [[ -z "${timestamp}" ]] && timestamp=$(date '+%s')
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

update_state_file() {
  echo "${1:-UNKNOWN}" > "${STATE_FILE_ROOT}/state.txt"
}

while read -u 10 -r message; do
  timestamp=$(date '+%s')
  echo "[${timestamp}] Got MQTT message!" >&2
  date | sed 's+^+  +' >&2
  echo "  mqtt: ${message}" >&2

  topic=$(echo "${message}" | cut -d' ' -f 1)
  message=$(echo "${message}" | cut -d' ' -f 2-)

  if [[ "${topic}" == "${MOSQUITTO_TOPIC_DOORA_FOB}" ]] || [[ "${topic}" == "${MOSQUITTO_TOPIC_DOORC_FOB}" ]] || [[ "${topic}" == "${MOSQUITTO_TOPIC_DOORX_FOB}" ]]; then
    { read node; read fobid; read datetime; } <<< $(echo "${message}" | jq -r '.node, .id, .ts')
    timestamp=$(date --date="${datetime}" '+%s')
    door=$(slugify "${node}")
    echo "  got fob scan! node <${node}> id <${fobid}>, datetime <${datetime}>, timestamp <${timestamp}>"
    # do not send timestamp, just use server timestamp
    update_fob_file "${door}" "" "${fobid}"

  elif [[ "${topic}" == "${MOSQUITTO_TOPIC_DOORA_OPENSTATE}" ]] || [[ "${topic}" == "${MOSQUITTO_TOPIC_DOORC_OPENSTATE}" ]] || [[ "${topic}" == "${MOSQUITTO_TOPIC_DOORX_OPENSTATE}" ]]; then
    { read node; read opened; } <<< $(echo "${message}" | jq -r '.node, ."Door Open"')
    door=$(slugify "${node}")
    echo "  got door open/closed! node <${node}> opened <${opened}>"
    if [[ "${opened}" == "true" ]]; then
      increment_file_counter "${door}"_opened
    elif [[ "${opened}" == "false" ]]; then
      increment_file_counter "${door}"_closed
    else
      echo "  warning: non-boolean bool" >&2
    fi

  elif [[ "${topic}" == "${MOSQUITTO_TOPIC_DOORA_LOCKSTATE}" ]] || [[ "${topic}" == "${MOSQUITTO_TOPIC_DOORC_LOCKSTATE}" ]] || [[ "${topic}" == "${MOSQUITTO_TOPIC_DOORX_LOCKSTATE}" ]]; then
    { read node; read state; } <<< $(echo "${message}" | jq -r '.node, .state')
    door=$(slugify "${node}")
    echo "  got door locking/unlocking! node <${node}> state <${state}>" >&2
    if [[ "${state}" == "UNLOCKING" ]]; then increment_file_counter "${door}"_unlocking
    elif [[ "${state}" == "UNLOCKED" ]]; then increment_file_counter "${door}"_unlocked
    elif [[ "${state}" == "LOCKING" ]]; then increment_file_counter "${door}"_locking
    elif [[ "${state}" == "LOCKED" ]]; then increment_file_counter "${door}"_locked
    else echo "  warning: I do not know this state" >&2
    fi

  elif [[ "${topic}" == "${MOSQUITTO_TOPIC_STATE}" ]]; then
    if echo "${message}" | grep 'State\.' > /dev/null; then
      state=$(echo "${message}" | sed 's+State\.++')
      echo "  got state change to <${state}>"
      update_state_file "${state}"
    else
      echo "  ignore message"
    fi

  else
    echo "  warning: does not match event!" >&2
  fi
done 10< <(
  mosquitto_sub -h mosquitto.shhm.uk -v -R \
    -t "${MOSQUITTO_TOPIC_DOORA_OPENSTATE}" -t "${MOSQUITTO_TOPIC_DOORC_OPENSTATE}" -t "${MOSQUITTO_TOPIC_DOORX_OPENSTATE}" \
    -t "${MOSQUITTO_TOPIC_DOORA_LOCKSTATE}" -t "${MOSQUITTO_TOPIC_DOORC_LOCKSTATE}" -t "${MOSQUITTO_TOPIC_DOORX_LOCKSTATE}" \
    -t "${MOSQUITTO_TOPIC_DOORA_FOB}" -t "${MOSQUITTO_TOPIC_DOORC_FOB}" -t "${MOSQUITTO_TOPIC_DOORX_FOB}" \
    -t "${MOSQUITTO_TOPIC_STATE}"
)
