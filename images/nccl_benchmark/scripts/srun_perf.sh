#!/bin/bash

set -e

while getopts ":b:e:f:g:t:l:d:u:h:p:n:s:m:w:c:q:" opt; do
  case ${opt} in
    b )
      min_bytes=$OPTARG
      ;;
    e )
      max_bytes=$OPTARG
      ;;
    f )
      step_factor=$OPTARG
      ;;
    g )
      num_gpus=$OPTARG
      ;;
    t )
      bench_timout=$OPTARG
      ;;
    l )
      limit=$OPTARG
      ;;
    d )
      drain_state=$OPTARG
      ;;
    u )
      use_infiniband=$OPTARG
      ;;
    h )
      kubernetes_service_host=$OPTARG
      ;;
    p )
      kubernetes_service_port=$OPTARG
      ;;
    n )
      namespace=$OPTARG
      ;;
    s )
      push_events=$OPTARG
      ;;
    m )
      push_metrics_grpc=$OPTARG
      ;;
    w )
      push_metrics_http=$OPTARG
      ;;
    c )
      exporter_endpoint=$OPTARG
      ;;
    q )
      push_metrics_path=$OPTARG
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      exit 1
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# If num_gpus not set, get it from sinfo (min gpu on host)
if [ -z "$num_gpus" ]; then
  num_gpus=$(sinfo -N -o "%G" | awk -F '[:,=()]' '/gpu/ {for (i=1; i<=NF; i++) if ($i == "gpu") {print $(i+2)}}' | sort -n | head -1)
  echo "$num_gpus GPUs on each node are going to be benchmarked"
fi

if [ -z "$min_bytes" ] || [ -z "$max_bytes" ] || [ -z "$step_factor" ] || [ -z "$bench_timout" ] || [ -z "$limit" ] || [ -z "$drain_state" ] || [ -z "$use_infiniband" ]; then
    echo "Usage: $0 -b <min_bytes> -e <max_bytes> -f <step_factor> -t <bench_timout> -l <limit> -d <drain_state> -u <use_infiniband>" >&2
    exit 1
fi

job_name="nccl_test"
ntasks_per_node=1
# Get only responding nodes uniq for all slurm partitions
ready_nodes=$(sinfo --Node -h -o "%N" -r | uniq)

run_job_on_node() {
  local node=$1
  local job_name=$2
  local ntasks_per_node=$3
  local num_gpus=$4
  local bench_timout=$5
  local min_bytes=$6
  local max_bytes=$7
  local step_factor=$8
  local limit=$9
  local drain_state=${10}
  local use_infiniband=${11}
  local namespace=${12}
  local kubernetes_service_host=${13}
  local kubernetes_service_port=${14}
  local push_events=${15}
  local push_metrics_grpc=${16}
  local push_metrics_http=${17}
  local exporter_endpoint=${18}
  local push_metrics_path=${19}

  job_exists=$(squeue --name="$job_name" -O "ReqNodes" --noheader | grep -w "$node")

  if [ -n "$job_exists" ]; then
    echo "Job '$job_name' is already running on node '$node'."
    return 0
  else
    echo "Starting perf test at $(date) on '$node'"
    srun --ntasks-per-node="$ntasks_per_node" \
         --job-name="$job_name" \
         --nodelist="$node" \
         --gpus="$num_gpus" \
         --cpus-per-task=16 \
         --mem-per-cpu="12GB" \
         --time="$bench_timout" \
         /usr/bin/gpubench -debug=true -min_bytes="$min_bytes" -step_factor="$step_factor" -limit="$limit" -drain_state=$drain_state -max_bytes="$max_bytes" -namespace="$namespace" -kube_service_host="$kubernetes_service_host" -kube_service_port="$kubernetes_service_port" -exporter_endpoint="$exporter_endpoint" -use_infiniband=$use_infiniband -push_events=$push_events -push_metrics_grpc="$push_metrics_grpc" -push_metrics_http="$push_metrics_http" -push_metrics_path="$push_metrics_path"
    echo "exit_code $?"
  fi
}

export -f run_job_on_node

# Run jobs in parallel and capture exit codes
output=$(parallel --no-notice -j 0 run_job_on_node ::: "$ready_nodes" ::: "$job_name" ::: "$ntasks_per_node" ::: "$num_gpus" ::: "$bench_timout" ::: "$min_bytes" ::: "$max_bytes" ::: "$step_factor" ::: "$limit" ::: "$drain_state" ::: "$use_infiniband" ::: "$namespace" ::: "$kubernetes_service_host" ::: "$kubernetes_service_port" ::: "$push_events" ::: "$push_metrics_grpc" ::: "$push_metrics_http" ::: "$exporter_endpoint" ::: "$push_metrics_path")

exit_codes=$(echo "$output" | grep 'exit_code' | awk '{print $2}')

for code in $exit_codes; do
  if [[ $code -ne 0 ]]; then
    echo "All exit codes not 0 - $exit_codes"
    exit 1
  fi
done

echo "All jobs completed successfully."
