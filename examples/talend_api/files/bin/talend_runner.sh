#!/usr/bin/env bash
## Original script taken from SUV project to make generic to work for mtt shared project.
# Script to run talend jobs
set -o pipefail

# Get the directory containing the current script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "$SCRIPT_DIR/../lib/shared-utils.sh"

# Check if required programs are installed
for cmd in curl jq awk base64; do
    if ! command -v "$cmd" &>/dev/null; then
        printf '%s\n' 'Error: %s is not installed.' "$cmd" >&2
        exit 1
    fi
done

#-----------#
# Functions #
#-----------#

## \brief Checks if the script arguments are valid.
## \desc This code requires two arguemtns with the first one being mandatory, otherwise, it prints an error message and exits.
##  "--timeout" argument default is set to 30.
## \example Use `exec` command instead of `bash` when running from JobScheduler
## \example-code bash
##   bash bin/talend-run-task.sh -n job_adr_000_processWrapper -t 30
check_arguments() {
TIMEOUT=
    while [[ $# -gt 0 ]]; do
        case $1 in
        ## \option -n, --task-name
        ## Assigns the Task name as seen in Job Conductor in TAC.
        -n | --task-name)
            TASK_NAME=$2
            shift 2
            ;;
        ## \option -p, --project
        ## optional project name
        -p | --project)
            PROJECT_NAME=$2
            shift 2
            ;;
        ## \option -t, --timeout
        ## Assigns the Task runtime. If not provided, defaults to 30.
        -t | --timeout)
            TIMEOUT=$2
            shift 2
            ;;
        ## \option -h, --help
        ## Prints the help and exits.
        -h | --help)
            show_usage
            ;;
        *)
            printf "%s\n" "Error: Invalid argument $1" >&2
            exit 1
            ;;
        esac
    done

    # Set default value for TIMEOUT if not provided
    if [[ -z "$TIMEOUT" ]]; then
        TIMEOUT=30
    fi

    # Check if TASK_NAME is provided, if not, print error and exit
    if [[ -z "$TASK_NAME" ]]; then
        printf '%s\n' 'Error: Task name is required.' >&2
        exit 1
    fi

}

## \function stop_task_execution
## \function-brief Stops the execution of a task.
## This function stops the execution of a task by making a curl request with the necessary data. The data is base64 encoded and includes the action name, authentication details, and the task ID. The response from the curl request is then echoed.
stop_task_execution() {
    local base64_data
    local response
    local execRequestId
    if [ "$TALEND_TASK_ID" != 'null' ]; then
        base64_data=$(printf '%s' '{"actionName":"stopTask","authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'","taskId":"'"$TALEND_TASK_ID"'"}' | base64 -i | tr -d '[:space:]')
        response=$(make_curl_request "$base64_data")
        echo "$response"
    fi
}

## \function js_trap
## \function-brief This function is a trap handler for the signals `EXIT`, `TERM`, and `INT`.
## It captures the return code of the script, prints a message indicating that the job execution has been terminated, and then calls the `stop_task_execution` function to perform cleanup tasks.
## \example Trap signals and call js_trap function
## \example-code bash
##   trap 'js_trap EXIT' EXIT
##   trap 'js_trap TERM' TERM
##   trap 'js_trap INT' INT
js_trap() {
    return_code=$?
    if [[ $return_code -ne 0 ]]; then
        printf "%s\n" "Cleaning up..."
        stop_task_execution
    fi
    echo $return_code
    exit $return_code
}
## \function start_task_execution
## \function-brief Takes the Task id as an argument. Return value is set as TALEND_EXEC_REQUEST_ID variable.
start_task_execution() {
    local base64_data
    local response
    local execRequestId
    CONTEXT=$CONTEXT_NAME
    if [ -z $CONTEXT ]; then
        CONTEXT="Default"
    fi
    base64_data=$(printf '%s' '{"actionName":"runTask","authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'","taskId":"'"$TALEND_TASK_ID"'","mode":"asynchronous","contextName":"'"$CONTEXT"'"}' | base64 -i | tr -d '[:space:]')
    response=$(make_curl_request "$base64_data")
    execRequestId=$(echo "$response" | jq --raw-output '.execRequestId // empty')
    if [[ -z "$execRequestId" ]]; then
        print_message "exec_request_id is empty. The job is probably still running. Check TAC and try again." error
        exit 0 # so no need clean up, otherwise tries stop job.
    fi
    echo "Job Request id: $execRequestId"
    declare -g TALEND_EXEC_REQUEST_ID="$execRequestId"
}

## \function get_task_execution_status
## \function-brief This function is used to get the execution status of a task. Returns the response from the server.
## \function-arguments $1 Execution Request Id.
get_task_execution_status() {
    local exec_request_id=$1
    local base64_data
    local response

    base64_data=$(printf '%s' '{"actionName":"getTaskExecutionStatus","authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'","execRequestId":"'"${exec_request_id}"'"}' | base64 -i | tr -d '[:space:]')
    response=$(make_curl_request "$base64_data")
    handle_return_code "$response"
    echo "$response"
}

## \function retrieve_and_print_task_logs
## \function-brief This function is used to get the log of a task. Prints the Task logs to stdout.
retrieve_and_print_task_logs() {
    local base64_data
    local response
    local log_content

    base64_data=$(printf '%s' '{"actionName":"taskLog","authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'","taskId":"'"$TALEND_TASK_ID"'","execRequestId":"'"$TALEND_EXEC_REQUEST_ID"'"}' | base64 -i | tr -d '[:space:]')
    response=$(make_curl_request "$base64_data")
    handle_return_code "$response"

    log_content=$(printf '%s\n' "$response" | jq --raw-output '.result')

    if [[ -z "$log_content" ]]; then
        printf '%s\n' "No logs available for TASK NAME: $TASK_NAME"
        return
    fi

    print_message "==Started LOG process==" info
    printf '%b\n' "$log_content"
    print_message "==Completed LOG process==" info
}

## \function wait_for_task_completion
## \function-brief waits for a task to complete within a specified time limit.
## It checks the execution status of the task at regular intervals and takes different actions based on the status.
## \function-arguments exec_request_id The execution request ID of the task.
## \function-arguments timeout_minutes The timeout duration in minutes.
wait_for_task_completion() {
    local exec_request_id=$1
    local timeout_minutes=$2
    local timeout_seconds=$((timeout_minutes * 60))
    local job_exit_code
    local exec_detailed_status
    local start_time
    local time_elapsed=0

    start_time=$(date +%s)
    while ((time_elapsed < timeout_seconds)); do
        response=$(get_task_execution_status "$exec_request_id")
        job_exit_code=$(printf '%s\n' "$response" | jq --raw-output '.jobExitCode // empty')
        exec_detailed_status=$(printf '%s\n' "$response" | jq --raw-output '.execDetailedStatus // empty')

        if [[ "$exec_detailed_status" == "ENDED_OK" ]]; then
            print_message "Job run complete. Detailed Status: $exec_detailed_status" info
            retrieve_and_print_task_logs
            exit "$job_exit_code"
        elif [[ "$job_exit_code" -ne 0 ]]; then
            print_message "Job ended with error. Detailed Status: $exec_detailed_status" warning
            retrieve_and_print_task_logs
            exit "$job_exit_code"
        fi

        printf '%s\n' "Current task status: $exec_detailed_status. Time elapsed: ${time_elapsed}s"
        sleep 30
        time_elapsed=$(($(date +%s) - start_time))
    done

    if [[ "$exec_detailed_status" != "ENDED_OK" ]]; then
        print_message "Timeout reached. Task did not complete within the specified time limit." warning
        printf '%s\n' "Attempting to retrieve task log."
        retrieve_and_print_task_logs
        exit 1
    fi
}

## \function load_default_config
# ## \function-brief Loads default config for vault and any other environment specfic config
load_default_config(){
    if [ -f "$SCRIPT_DIR/../etc/config" ]; then
        source "$SCRIPT_DIR/../etc/config"
    fi
}

#------------#
# Define Run #
#------------#

## \function pre
## \function-brief Executes the preparation parts of the script.
pre() {
    ## - `check_arguments` Check script input arguments
    check_arguments "$@"

    # source default config or project config.
    # if project name is defined, it will use project config.
    if [ -z "$PROJECT_NAME" ]; then 
        load_default_config
    else
        if [ -f "$SCRIPT_DIR/../etc/$PROJECT_NAME" ]; then
            source "$SCRIPT_DIR/../etc/$PROJECT_NAME"
        else
            print_message "no project specific config in $SCRIPT_DIR/../etc/$PROJECT_NAME, using default" info
            load_default_config
        fi
    fi

    ## - `set_ec2_tag_value_as_vars` Sets necessary ec2 tag values as variables.
    set_ec2_tag_value_as_vars
    ## - `set_vault_vars` Sets Vault variables.
    set_vault_vars
    ## - `get_config_file` Load project related variables from config file.
    # get_config_file
    ## - unset and export `VAULT_TOKEN`
    export VAULT_ADDR
    export VAULT_NAMESPACE
    export VAULT_NAMESPACE
    unset VAULT_TOKEN
    get_vault_token
    export VAULT_TOKEN
    ## - `set_tac_url_vars` Sets TAC URL variables.
    set_tac_url_vars
}

## \function main
## \function-brief Executes the main part of the script.
main() {
    print_message "==Started GET TALEND VAULT CREDENTIALS process==" info

    ## - `get_auth` Get TAC Metaservlet API credentials.
    print_message "Authenticate with vault (get auth)" info
    get_auth || exit 1
    print_variables TAC_URL "$TAC_URL_BASE" VAULT_ADDR "$VAULT_ADDR" VAULT_HEADER "$VAULT_HEADER" VAULT_NAMESPACE "$VAULT_NAMESPACE" TALEND_AWHUSER "$TALEND_AWHUSER"

    print_message "==Completed TALEND VAULT GET CREDENTIALS process==" info
    print_message "==Started TASK DEPLOYMENT process==" info

    ## - `get_task_id_by_name` "$TASK_NAME" Get Task id.
    get_task_id_by_name "$TASK_NAME"
    print_variables "TASK_NAME" "$TASK_NAME" "TASK_ID" "$TALEND_TASK_ID"
    if [ $TALEND_TASK_ID == 'null' ]; then
       print_message "$TALEND_TASK_ID_RESPONSE" error
       exit 1
    fi
    ## - `start_task_execution` Start task execution.
    start_task_execution

    ## - `wait_for_task_completion` Wait for task completion. [Details](#wait_for_task_completion)
    wait_for_task_completion "$TALEND_EXEC_REQUEST_ID" "$TIMEOUT"
    print_message "==Completed TASK RUN process==" info

    ## - `retrieve_and_print_task_logs` Get task execution log.
    retrieve_and_print_task_logs
}

#-----#
# Run #
#-----#

trap 'js_trap EXIT' EXIT
trap 'js_trap TERM' TERM # 15+128
trap 'js_trap INT' INT

# Only run if direct execution - added to support unit testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    pre "$@"
    main
fi
