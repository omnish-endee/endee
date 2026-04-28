#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Configurable parameters — edit these as needed
# =============================================================================

# Sweep arrays
FILTER_BOOST_PERCENTAGES=(0)
LABEL_PERCENTAGES=(0.5 0.2 0.1 0.05 0.02 0.01 0.002 0.001)
#LABEL_PERCENTAGES=(0.5)
NUM_CONCURRENCIES=(16)
#NUM_CONCURRENCIES=(8)

# Number of times to repeat each experiment
NUM_REPETITIONS=3

# Fixed parameters
TOKEN="YOUR_TOKEN"
REGION="YOUR_REGION"
BASE_URL="http://198.244.140.12:8080/api/v1"
#BASE_URL="http://10.5.0.150:8080/api/v1"
INDEX_NAME="test_shaleen_10M"
TASK_LABEL="10m_int16_filter"
M=16
EF_CON=128
EF_SEARCH=128
SPACE_TYPE="cosine"
PRECISION="int16"
VERSION=1
PREFILTER_CARDINALITY_THRESHOLD=10000
CASE_TYPE="LabelFilterPerformanceCase"
DATASET="Large Cohere (768dim, 10M)"
K=30
CONCURRENCY_DURATION=30
CONCURRENCY_TIMEOUT=3600
NUM_PER_BATCH=1000
DATASET_LOCAL_DIR="/home/debian/VectorDBBench/vectordataset"

# =============================================================================
# Output directory for raw logs (named after TASK_LABEL)
# =============================================================================

LOG_DIR="./${TASK_LABEL}_logs"
mkdir -p "$LOG_DIR"

# =============================================================================
# Results collection
# =============================================================================

declare -a RESULTS=()

total=$(( ${#FILTER_BOOST_PERCENTAGES[@]} * ${#LABEL_PERCENTAGES[@]} * ${#NUM_CONCURRENCIES[@]} * NUM_REPETITIONS ))
current=0

export NUM_PER_BATCH DATASET_LOCAL_DIR

for fbp in "${FILTER_BOOST_PERCENTAGES[@]}"; do
  for lp in "${LABEL_PERCENTAGES[@]}"; do
    for nc in "${NUM_CONCURRENCIES[@]}"; do
      for rep in $(seq 1 "$NUM_REPETITIONS"); do
        current=$((current + 1))
        test_label="test_${rep}"
        echo ">>> [$current/$total] filter-boost=$fbp  label-pct=$lp  concurrency=$nc  ${test_label}"

        log_file="${LOG_DIR}/fbp${fbp}_lp${lp}_nc${nc}_${test_label}.log"

        # Build args array — single source of truth for the command
        args=(
          vectordbbench endee
          --token "$TOKEN"
          --region "$REGION"
          --base-url "$BASE_URL"
          --index-name "$INDEX_NAME"
          --task-label "$TASK_LABEL"
          --m "$M"
          --ef-con "$EF_CON"
          --ef-search "$EF_SEARCH"
          --space-type "$SPACE_TYPE"
          --precision "$PRECISION"
          --version "$VERSION"
          --prefilter-cardinality-threshold "$PREFILTER_CARDINALITY_THRESHOLD"
          --filter-boost-percentage "$fbp"
          --case-type "$CASE_TYPE"
          --dataset-with-size-type "$DATASET"
          --label-percentage "$lp"
          --k "$K"
          --num-concurrency "$nc"
          --concurrency-duration "$CONCURRENCY_DURATION"
          --concurrency-timeout "$CONCURRENCY_TIMEOUT"
          --skip-drop-old
          --skip-load
          --search-concurrent
          --search-serial
        )

        #echo ""
        #echo "    COMMAND:"
        #printf '    NUM_PER_BATCH=%q DATASET_LOCAL_DIR=%q' "$NUM_PER_BATCH" "$DATASET_LOCAL_DIR"
        #printf ' %q' "${args[@]}"
        #printf '\n\n'

        output=$("${args[@]}" 2>&1) || true

        # Save raw output to log file
        echo "$output" > "$log_file"
        echo "    saved raw output -> $log_file"

        # Parse the Endee results line. Pipe-delimited fields are:
        #   $1=timestamp | $2=INFO | $3=Endee | $4=case description | $5=metrics | $6=label
        # Inside $5: load_dur  qps  p99  p95  recall  max_load_count
        parsed=$(echo "$output" | grep '|Endee' | tail -1 | \
          awk -F'|' '{
            n = split($5, a, " ");
            if (n >= 5)
              printf "%s %s %s %s", a[2], a[3], a[4], a[5];
            else
              printf "N/A N/A N/A N/A";
          }')

        qps=$(echo "$parsed" | awk '{print $1}')
        p99=$(echo "$parsed" | awk '{print $2}')
        p95=$(echo "$parsed" | awk '{print $3}')
        recall=$(echo "$parsed" | awk '{print $4}')

        RESULTS+=("${fbp}|${lp}|${nc}|${test_label}|${qps}|${p99}|${p95}|${recall}")
      done
    done
  done
done

# =============================================================================
# Print ASCII table
# =============================================================================

printf "\n"
printf "%-18s %-16s %-14s %-10s %12s %12s %12s %12s\n" \
  "FilterBoost(%)" "LabelPct" "Concurrency" "Test" "QPS" "P99(s)" "P95(s)" "Recall"
printf "%-18s %-16s %-14s %-10s %12s %12s %12s %12s\n" \
  "------------------" "----------------" "--------------" "----------" "------------" "------------" "------------" "------------"

for row in "${RESULTS[@]}"; do
  IFS='|' read -r fbp lp nc test_label qps p99 p95 recall <<< "$row"
  printf "%-18s %-16s %-14s %-10s %12s %12s %12s %12s\n" \
    "$fbp" "$lp" "$nc" "$test_label" "$qps" "$p99" "$p95" "$recall"
done

printf "\nTotal runs: %d\n" "${#RESULTS[@]}"
printf "Raw logs saved in: %s/\n" "$LOG_DIR"
