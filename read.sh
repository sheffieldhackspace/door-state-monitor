#!/bin/bash
# read state and output how Prometheus wants it

source .env

echo "Content-type: text/plain"
echo ""

# space state
# echo "# got state: <${state}>" # can't have this as prometheus gets sad
echo "# TYPE space gauge"
echo "# HELP current state of space, as enums"
state=$(cat "${STATE_FILE_ROOT}/state.txt")
for state_enum in PRE_EXIT EXITING LOCKED ENTERING OCCUPIED; do
  if [[ "${state}" == "${state_enum}" ]]; then
    is_true=1
  else
    is_true=0
  fi
  echo 'space{state="'"${state_enum}"'"} '"${is_true}"
done

# door states
echo "# TYPE door_events_total counter"
echo "# HELP total number of door events seen"
for door in a c x; do
  for doorstate in closed opened unlocking unlocked locking locked; do
    file="${STATE_FILE_ROOT}/door${door}_${doorstate}.txt"
    if [[ ! -f "${file}" ]]; then
      num=0
    else
      num=$(cat "${file}")
    fi
    printf 'door_events_total{door="'"${door}"'", event="%s"} %s\n' "${doorstate}" "${num}"
  done
done

# non-unique fob reads
echo "# TYPE door_fob_reads gauge"
echo "# HELP number of fob reads"
for door in a c x all; do
  for r in 1 2 3 4 8 16; do
    FOB_RECENCY_H="${r}"
    min_ts=$(date --date="-${FOB_RECENCY_H} hour" '+%s')
    if [[ "${door}" == "all" ]]; then
      data=$(cat "${STATE_FILE_ROOT}/door"*"_fobs.txt")
    else
      data=$(cat "${STATE_FILE_ROOT}/door${door}_fobs.txt")
    fi
    fob_reads=$(
      echo "${data}" \
        | awk -v min_ts="${min_ts}" \
          'BEGIN {total=0} $1 > min_ts {total+=1} END {print total}'
    )
    printf 'door_fob_reads{door="'"${door}"'", last_h="%s"} %s\n' "${FOB_RECENCY_H}" "${fob_reads}"
  done
done

# unique fob reads
echo "# TYPE door_unique_fob_reads gauge"
echo "# HELP number of fob reads"
for door in a c x all; do
  for r in 1 2 3 4 8 16; do
    FOB_RECENCY_H="${r}"
    min_ts=$(date --date="-${FOB_RECENCY_H} hour" '+%s')
    if [[ "${door}" == "all" ]]; then
      data=$(cat "${STATE_FILE_ROOT}/door"*"_fobs.txt")
    else
      data=$(cat "${STATE_FILE_ROOT}/door${door}_fobs.txt")
    fi
    fob_reads=$(
      echo "${data}" \
        | awk -v min_ts="${min_ts}" \
          'BEGIN {delete fobs} $1 > min_ts {fobs[$2] = 1} END {print length(fobs)}'
    )
    printf 'door_unique_fob_reads{door="'"${door}"'", last_h="%s"} %s\n' "${FOB_RECENCY_H}" "${fob_reads}"
  done
done
