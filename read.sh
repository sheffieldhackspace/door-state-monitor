#!/bin/bash
# read state and output how Prometheus wants it

source .env

echo "Content-type: text/plain"
echo ""

# door states
echo "# TYPE door_events_total counter"
echo "# HELP total number of door events seen"
for doorstate in closed opened unlocking unlocked locking locked; do
  file="${STATE_FILE_ROOT}/door_${doorstate}.txt"
  if [[ ! -f "${file}" ]]; then
    num=0
  else
    num=$(cat "${file}")
  fi
  printf 'door_events_total{door="a", event="%s"} %s\n' "${doorstate}" "${num}"
done

# non-unique fob reads
echo "# HELP number of fob reads"
echo "# TYPE door_fob_reads gauge"
for r in 1 2 3 4 8 16; do
  FOB_RECENCY_H="${r}"
  min_ts=$(date --date="-${FOB_RECENCY_H} hour" '+%s')
  fob_reads=$(
    cat "${STATE_FILE_ROOT}/${STATE_FOB_FILE}" \
      | awk -v min_ts="${min_ts}" \
        'BEGIN {total=0} $1 > min_ts {total+=1} END {print total}'
  )
  printf 'door_fob_reads{door="a", last_h="%s"} %s\n' "${FOB_RECENCY_H}" "${fob_reads}"
done

# unique fob reads
echo "# HELP number of fob reads"
echo "# TYPE door_unique_fob_reads gauge"
for r in 1 2 3 4 8 16; do
  FOB_RECENCY_H="${r}"
  min_ts=$(date --date="-${FOB_RECENCY_H} hour" '+%s')
  fob_reads=$(
    cat "${STATE_FILE_ROOT}/${STATE_FOB_FILE}" \
      | awk -v min_ts="${min_ts}" \
        'BEGIN {delete fobs} $1 > min_ts {fobs[$2] = 1} END {print length(fobs)}'
  )
  printf 'door_unique_fob_reads{door="a", last_h="%s"} %s\n' "${FOB_RECENCY_H}" "${fob_reads}"
done
