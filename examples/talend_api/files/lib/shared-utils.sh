#!/usr/bin/env bash
# taken from SUV project shared libs.
## \Original author Andrey Zaharov / @7896959 / andrey.zaharov@capgemini.com
## \brief This is a common code library.

## \function print_variables
## \function-brief Prints formatted variables.
## \function-arg var_name - Variable Name.
## \function-arg var_value - Variable Value.
## \function-seealso When `$PRINT_TYPE` environment variable is set to "html" then no formatting is applied!
print_variables() {
    while [ "$#" -gt 0 ]; do
        local var_name="$1"
        local var_value="$2"
        local print_type="${PRINT_TYPE:-ansi}"

        if [ "$print_type" = "html" ]; then
            printf "%s: %s\n" "$var_name" "$var_value"
        else
            local bold='\033[1m'
            local blue='\033[34m'
            local reset='\033[0m'
            printf "${bold}${blue}%s:${reset} %s\n" "$var_name" "$var_value"
        fi
        shift 2
    done
}

## \function print_message
## \function-brief Prints formatted messages to stdout.
## \function-arg message - The message.
## \function-arg message_type - The type of the message. Can be 'error', 'warning', or 'info'.
## \function-seealso When `$PRINT_TYPE` environment variable is set to "html" then no formatting is applied!
print_message() {
    local message="$1"
    local message_type="$2"
    local print_type="${PRINT_TYPE:-ansi}"
    local color
    local prefix

    case "$message_type" in
        error)
            color='\033[31m'  # Red
            if [ "$print_type" = "html" ]; then
                prefix="[ERROR] "
            else
                prefix="Error: "
            fi
            ;;
        warning)
            color='\033[33m'  # Amber
            if [ "$print_type" = "html" ]; then
                prefix="[WARN] "
            else
                prefix="Warning: "
            fi
            ;;
        info)
            color='\033[32m'  # Green
            if [ "$print_type" = "html" ]; then
                prefix="[INFO] "
            else
                prefix=""
            fi
            ;;
        *)
            echo "Invalid message type: $message_type"
            return 1
            ;;
    esac

    if [ "$print_type" = "html" ]; then
        printf "%s%s\n" "$prefix" "$message"
    else
        local reset='\033[0m'
        printf "${color}%s%s${reset}\n" "$prefix" "$message"
    fi
}

show_usage_js(){
    echo "$0 -s <fqdn>"
    exit 0
}
show_usage(){
    echo "$0 -n <task_name> [-t timeout]"
    exit 0
}

## \function get_vault_token
## \function-brief Retrieves the vault token. Returs VAULT_TOKEN as variable.
get_vault_token() {
    VAULT_TOKEN=$(vault login -method=aws -token-only -namespace="$VAULT_NAMESPACE" header_value="$VAULT_HEADER")
    if [[ -z "$VAULT_TOKEN" ]]; then
        echo "Error: Unable to retrieve Vault token."
        return 1
    else
        declare -g VAULT_TOKEN="$VAULT_TOKEN"
    fi
}

## \function get_auth
## \function-brief Retrieves Talend authentication credentials to be used with metaservlet API.
##  Returns TALEND_AWHUSER as variable.
##  Returns TALEND_AWHPASS as variable.
get_auth() {
    local vault_data
    vault_data=$(vault kv get --format=json kv/shared/talend/auth)
    if [[ -z "$vault_data" ]]; then
        echo "Error: Unable to retrieve Talend authentication data."
        return 1
    fi
    TALEND_AWHUSER=$(printf '%s\n' "$vault_data" | jq -r '.data.data.api_admin_user')
    if [[ -z "$TALEND_AWHUSER" ]]; then
        echo "Error: Unable to retrieve Talend user."
        return 1
    fi

    TALEND_AWHPASS=$(printf '%s\n' "$vault_data" | jq -r '.data.data.api_admin_pass')
    if [[ -z "$TALEND_AWHPASS" ]]; then
        echo "Error: Unable to retrieve Talend password."
        return 1
    fi

    declare -g TALEND_AWHUSER="$TALEND_AWHUSER"
    declare -g TALEND_AWHPASS="$TALEND_AWHPASS"
}

## \function get_config_file
## \function-brief Read the INI file and store key-value pairs as variables.
get_config_file() {
    while IFS=' = ' read -r key value; do
        if [[ "$key" == \[*] ]]; then
            current_section=${key//[\[\]]/}
            continue
        fi
        [[ -z "$key" || "$key" == \#* ]] && continue
        current_section=${current_section^^}
        key=${key^^}
        value=$(eval echo "$value")  # Resolve variables in value
        declare -g "${current_section}_${key// /}=$value"
    done <"$ini_file"
}

## \function handle_return_code
## \function-brief Handles error codes returned by curl.
## \function-argument JSON API response.
handle_return_code() {
    local api_response=$1
    local error_message
    local return_code
    local regex='\{.*?\}'

    # Extract JSON from the response
    [[ "$api_response" =~ $regex ]] && api_response="${BASH_REMATCH[0]}"

    # Check if api_response is a valid JSON string
    if ! echo "$api_response" | jq empty >/dev/null 2>&1; then
        echo "Invalid JSON string: $api_response"
        return 1
    fi

    return_code=$(printf '%s\n' "$api_response" | jq --raw-output '.returnCode // empty')

    if [[ "$return_code" != "0" ]]; then
        error_message=$(printf '%s\n' "$api_response" | jq --raw-output '.error // empty')
        printf '%s\n' "Return code: $return_code, Error message: $error_message"
    fi
}

## \function check_api_status
## \function-brief Function make a call to api to make sure its up.
check_api_status(){
    local status
    local response
    status=$(curl  -sS -k -o /dev/null -w "%{http_code}" ${TAC_META_SERVLET_URL})
    response=$(curl -s -k -H "Accept: application/json" "${TAC_META_SERVLET_URL}")
    printf '%s' "$response"
    if [ $status == 502 ]; then
        print_message "Error connecting to talend api" error
        exit 1
    fi
}
## \function make_curl_request
## \function-brief Function to make a curl request to a specified URL with the given base64 encoded data.
## \function-argument $1 The base64 encoded data to be sent in the curl request.
make_curl_request() {
    local base64_data=$1
    local response

    response=$(curl -s -k -H "Accept: application/json" "${TAC_META_SERVLET_URL}${base64_data}")
    printf '%s' "$response"
}

## \function get_task_id_by_name
## \function-brief Retrieves Talend task ID by task name.
## \function-argumment $1 Task name.
get_task_id_by_name() {
    local task_name=$1
    local base64_data
    local response
    local task_id
    local return_code

    base64_data=$(printf '%s' '{"actionName":"getTaskIdByName","authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'","taskName":"'"$task_name"'"}' | base64 -i | tr -d '[:space:]')
    response=$(make_curl_request "$base64_data")
    task_id=$(printf '%s\n' "$response" | jq --raw-output '.taskId')
    return_code=$(printf '%s\n' "$response" | jq --raw-output '.returnCode')

    declare -g TALEND_TASK_ID_RESPONSE="$response"
    declare -g TALEND_TASK_ID="$task_id"
    declare -g TALEND_TASK_ID_RETURN_CODE="$return_code"
}

## \function get_server_name
## \function-brief List all servers available to user.set all labels as TALEND_SERVER_NAMES variable.
get_server_name() {
    local base64_data
    local response
    local label

    base64_data=$(printf '%s' '{"actionName":"listServer","authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'"}' | base64 -i | tr -d '[:space:]')
    response=$(make_curl_request "$base64_data")
    handle_return_code "$response"
    label=$(echo "$response" | jq --raw-output '.result[] | select(.active == true) | .label')
    declare -g TALEND_SERVER_NAMES="$label"
}

## \function set_server_label
## \function-brief sets TALEND_SERVER_LABEL using project_name_stage convention.
## \function-argumment $1 server fqdn
set_server_label(){
    local server_name=$1
    local name
    # extract the hostname from fqdn
    name=$(echo $server_name | cut -d. -f1)
    # use PROJECT and ENVIRONMENT to construct the server label
    label="${EC2_TAG_PROJECT}_${name}_${EC2_TAG_ENVIRONMENT}"
    declare -g TALEND_SERVER_LABEL="$label"
}

## \function set_virtual_server_label
## \function-brief sets TALEND_VSERVER_NAME. by looking at server fqdn
## \function-argumment $1 server fqdn
set_virtual_server_label(){
    local server_name=$1
    local label
    local project
    local programme
    project=$(echo $server_name| cut -d. -f3)
    programme=$(echo $server_name| cut -d. -f4)
    label="vs_${project}_${programme}"
    # use auto generatined naming convention vs_<project>_<programne> if TALEND_VS_NAME is not defined.
    if [ -z $TALEND_VS_NAME ]; then
        declare -g TALEND_VSERVER_NAME="$label"
    else
         declare -g TALEND_VSERVER_NAME="$TALEND_VS_NAME"
    fi

}

## \function get_server_id
## \function-brief Get server id using TALEND_SERVER_LABEL, sets TALEND_SERVER_ID
get_server_id() {
    local base64_data
    local response

    print_message "Find server label: $TALEND_SERVER_LABEL" info

    base64_data=$(printf '%s' '{"actionName":"listServer","authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'"}' | base64 -i | tr -d '[:space:]')
    response=$(make_curl_request "$base64_data")
    handle_return_code "$response"
    id=$(echo "$response" | jq --raw-output ".result[] | select(.label == \"$TALEND_SERVER_LABEL\") |.id")
    declare -g TALEND_SERVER_ID="$id"
}

## \function remove_server
## \function-brief remove server from talend
## \function-argumment $1 the talend server_id to remove.
remove_server(){
    local id=$1
    local base64_data
    local response
    local label

    base64_data=$(printf '%s' '{"actionName":"removeServer", "serverId" : "'"$id"'", "authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'"}' | base64 -i | tr -d '[:space:]')
    response=$(make_curl_request "$base64_data")
    handle_return_code "$response"
}

## \function get_vserver_id
## \function-brief Gets virtual server id using LABEL
get_vserver_id(){
    local base64_data
    local response
    local label

    base64_data=$(printf '%s' '{"actionName":"listVirtualServers","authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'"}' | base64 -i | tr -d '[:space:]')
    response=$(make_curl_request "$base64_data")
    handle_return_code "$response"
    id=$(echo "$response" | jq --raw-output ".result[] | select(.label == \"$TALEND_VSERVER_NAME\") |.id")
    server_list=$(echo "$response" | jq --raw-output ".result[] | select(.label == \"$TALEND_VSERVER_NAME\") |.servers")
    declare -g TALEND_VSERVER_ID="$id"
    declare -g TALEND_VSERVER_SERVER_LIST="$server_list"
}

## \function register_server
## \function-brief Add server to talend.
## \function-argumment $1 server fqdn, $2 state, to set active or not. defualt Active
register_server(){
    local servername=$1
    local state=$2
    local base64_data
    local response
    local label
    [[ -z $state ]] && state=true
    base64_data=$(printf '%s' '{"actionName":"addServer","authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'","label":"'"$TALEND_SERVER_LABEL"'","host":"'"$servername"'","commandPort":"'"$COMMAND_PORT"'","monitoringPort":"'"$MONITORING_PORT"'","filePort":"'"$FILE_PORT"'","processMessagePort":"'"$MESSAGE_PORT"'","timeOutUnknownState":"'"$TIMEOUT_UNKNOWN_STATE"'","timezoneId":"'"$TIMEZONE"'","useSSL":"'true'","active":"'$state'"}' | base64 -i | tr -d '[:space:]')
    response=$(make_curl_request "$base64_data")
    handle_return_code "$response"
}

## \function add_js_to_vs
## \fucntrion-brief Adds a jobserver to virtual server using the TALEND_SERVER_ID and TALEND_VSERVER_ID
add_js_to_vs(){
    local base64_data
    local response
    print_message "Add jobserver to virtual server" info
    get_server_id $SERVER_NAME
    base64_data=$(printf '%s' '{"actionName":"addServersToVirtualServer","authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'","virtualServerId":"'"$TALEND_VSERVER_ID"'","servers":['{"serverId": "$TALEND_SERVER_ID"}']}' | base64 -i | tr -d '[:space:]')
    response=$(make_curl_request "$base64_data")
    handle_return_code "$response"
}

## \function get_project_name
## \fucntrion-brief Returns list of all projects available to user. Reruns project name as TALEND_PROJECT_NAME variable.
## \function-seealso Talend user should only have one project name visible.
get_project_name() {
    local base64_data
    local response
    local label

    base64_data=$(printf '%s' '{"actionName":"listProjects","authPass":"'"$TALEND_AWHPASS"'","authUser":"'"$TALEND_AWHUSER"'","onlyActive":true,"onlyGit":true,"onlySvn":false,"withReference":false}' | base64 -i | tr -d '[:space:]')
    response=$(make_curl_request "$base64_data")
    handle_return_code "$response"
    label=$(echo "$response" | jq --raw-output '.projects[] | select(.branch == "master") | .label')
    declare -g TALEND_PROJECT_NAME="$label"
}

## \function get_all_ec2_tags
## \function-brief Retrieves all EC2 tags for the current instance as JSON.
get_all_ec2_tags() {
    local instance_id
    local tags

    instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    if [[ -z "$instance_id" ]]; then
        echo "Error: Unable to retrieve instance ID."
        return 1
    fi

    tags=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$instance_id")
    if [[ -z "$tags" ]]; then
        echo "Error: Unable to retrieve EC2 tags."
        return 1
    fi

    echo "$tags"
}

## \function set_ec2_tag_values_as_vars
## \function-brief Set ec2 tag values as variables.
set_ec2_tag_value_as_vars() {
    local tags
    tags=$(get_all_ec2_tags)

    ## - Returns VPC tag value as variable
    EC2_VPC_TAG=$(echo "$tags" | jq -r ".Tags[] | select(.Key==\"VPC\") | .Value")
    if [[ -z "$EC2_VPC_TAG" ]]; then
        echo "Error: Unable to retrieve VPC tag."
        return 1
    else
        declare -g EC2_VPC_TAG
    fi

    ## - Returns environment tag value as variable
    EC2_ENV_TAG=$(echo "$tags" | jq -r ".Tags[] | select(.Key==\"Environment\") | .Value")
    if [[ -z "$EC2_ENV_TAG" ]]; then
        echo "Error: Unable to retrieve Environment tag."
        return 1
    else
        declare -g EC2_ENV_TAG
    fi

    ## - Returns project tag value as variable
    EC2_PROJECT_TAG=$(echo "$tags" | jq -r ".Tags[] | select(.Key==\"Project\") | .Value")
    if [[ -z "$EC2_PROJECT_TAG" ]]; then
        echo "Error: Unable to retrieve Project tag."
        return 1
    else
        declare -g EC2_PROJECT_TAG
    fi

    ## - Returns programme tag value as variable
    EC2_PROGRAMME_TAG=$(echo "$tags" | jq -r ".Tags[] | select(.Key==\"Programme\") | .Value")
    if [[ -z "$EC2_PROGRAMME_TAG" ]]; then
        echo "Error: Unable to retrieve Programme tag."
        return 1
    else
        declare -g EC2_PROGRAMME_TAG
    fi
}

## \function set_vault_vars
## \function-brief Sets the Vault variables based on the EC2 VPC tag.
##  Returns VAULT_HEADER as variable.
##  Returns VAULT_ADDR as variable.
set_vault_vars() {
    local vault_value
    local result

    vault_value=$([[ "$EC2_VPC_TAG" == "live" ]] && echo "vault" || echo "vaultnp")
    result="${vault_value}.exmaple.com"
    declare -g VAULT_HEADER="$result"
    declare -g VAULT_ADDR="https://$VAULT_HEADER"
}

## \function set_tac_url_vars
## \function-brief Sets the TAC variables base based on the EC2 VPC tag.
##  Returns TAC_URL_BASE as variable.
##  Returns TAC_META_SERVLET_URL as variable.
set_tac_url_vars() {
    local tac_value
    local result
    declare -g TAC_META_SERVLET_URL="https://$TAC_URL_BASE/metaServlet?"
}
