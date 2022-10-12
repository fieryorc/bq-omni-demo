#!/bin/bash

# echocolor [options] <color> <stuff> ... <stuff>
echocolor ()
{
    # Parse color code
    color_code=7
    case $1 in
        --black) color_code="\033[0;30m"; shift;;
        --red) color_code="\033[0;31m"; shift;;
        --green) color_code="\033[0;32m"; shift;;
        --yellow) color_code="\033[0;33m"; shift;;
        --blue) color_code="\033[0;34m"; shift;;
        --magenta) color_code="\033[0;35m"; shift;;
        --cyan) color_code="\033[0;36m"; shift;;
        --white) color_code="\033[0;37m"; shift;;
        # Lighter colors
        --lblack) color_code="\033[1;30m"; shift;;
        --lred) color_code="\033[1;31m"; shift;;
        --lgreen) color_code="\033[1;32m"; shift;;
        --lyellow) color_code="\033[1;33m"; shift;;
        --lblue) color_code="\033[1;34m"; shift;;
        --lmagenta) color_code="\033[1;35m"; shift;;
        --lcyan) color_code="\033[1;36m"; shift;;
        --lwhite) color_code="\033[1;37m"; shift;;
    esac

    # Parse any options
    options="-e"
    _option=$1
    if [ "${_option:0:1}" == "-" ]
    then
        options="${options} $_option"
        shift
    fi
    echo $options "${color_code}$@\033[0;0m"
}

function mycmd() {
  myecho --green "Running: $@"
  "$@"
  local err=$?
  if [ $err -ne 0 ]; then
    echo "Failed running $@"
  fi
  return $err
}

function log()
{
    echocolor --green "[$(date +%H:%M:%S)] $@"
}

function log_warning()
{
    echocolor --warning "[$(date +%H:%M:%S)] $@"
}

function log_error()
{
    echocolor --error "[$(date +%H:%M:%S)] $@"
}

function status() {
    echocolor --lcyan "[$(date +%H:%M:%S)] $@"
}

# Runs the command and exits the current shell if the command failed.
function exec_cmd()
{
    log "Running: $@"
    exec_cmd_quiet "$@"
}

# Runs the command and exits the current shell if the command failed.
# Doesn't print the command it runs.
function exec_cmd_quiet()
{
    "$@"
    local error_code=$?
    if [ $error_code -ne 0 ]; then
        log_error "Failed running command $@" 1>&2
        exit $error_code
    fi
}

# Runs the command and ignores exit code.
function exec_cmd_ignore()
{
    log "Running: $@"
    "$@"
}

function exec_cmd_suppress()
{
    log "Running (output suppressed): $@"
    "$@" >/dev/null
}

function error_exit()
{
    log_error "Failed: $@" 1>&2
    exit 2
}

# ------------------------------------------------
# Script starts here.
# ------------------------------------------------

save_file=$PWD/omni-quickstart.info

aws_key=
aws_secret=
aws_session_token=
aws_account_id=
aws_policy=omni-quickstart
aws_role=omni-quickstart
aws_s3_bucket=
aws_s3_path=
aws_s3_file_format=

gcp_project=
gcp_connection=
gcp_connection_name=
gcp_connection_identity=
gcp_dataset=
gcp_location=aws-us-east-1
gcp_external_table=

init_defaults()
{
    db_put gcp_location "aws-us-east-1"
    if [ -z "$(db_get gcp_connection)" ]; then
        db_put gcp_connection omni-quickstart-conn
    fi
    if [ -z "$(db_get gcp_dataset)" ]; then
        db_put gcp_dataset omni_quickstart
    fi
    if [ -z "$(db_get gcp_external_table)" ]; then
        db_put gcp_external_table quickstart_table
    fi
    if [ -z "$(db_get aws_s3_file_format)" ]; then
        db_put aws_s3_file_format "PARQUET"
    fi
}

# get <var>
db_get () {
   key=$(echo -n "$1" | base64 -w 0);
   sed -nr "s/^$key\ (.*$)/\1/p" $save_file | base64 -d
}

# db_put var value ..
db_put () {
   local key=$(echo -n "$1" | base64 -w 0);
   shift
   local value=$(echo -n "$@" | base64 -w 0);

   if [ ! -f "$save_file" ]; then touch "$save_file"; fi;
   if [[ $(grep "^"$key"\ " $save_file) == "" ]]; then
      echo "$key $value" >> $save_file
   else
      # Replace the value
      sed -i "s/^$key\ .*/$key $value/g" $save_file
   fi;
}

# read_var <var_name> <description>
function read_var() 
{
    local key="$1"
    local description="$2"
    local val=$(db_get $key)
    read -e -p "Enter $description: " -i "$val" val
    db_put "$key" "$val"
    eval "$key=\"$val\""
}

function install_aws_cli() {
    if which aws; then
        echo 'aws cli already installed. skipping.'
        return
    fi
    
    exec_cmd pushd /tmp
    exec_cmd curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    exec_cmd_suppress unzip awscliv2.zip
    exec_cmd_suppress sudo ./aws/install
}

function get_aws_credentials() 
{
    read_var aws_account_id "AWS account id"
    read_var aws_key "Aws Key"
    read_var aws_secret "Aws Secret"
    read_var aws_session_token "Session Token (enter if none)"

    # log "account_id: ${aws_account_id}, key: ${aws_key}, secret: ${aws_secret}, session_token: ${aws_session_token}"
    export AWS_ACCESS_KEY_ID=$aws_key
    export AWS_SECRET_ACCESS_KEY=$aws_secret
    export AWS_SESSION_TOKEN=$aws_session_token
}

function get_s3_bucket_info()
{
    read_var aws_s3_bucket "S3 bucket name"
    read_var aws_s3_path "S3 object path (ex., foo/baz/*)"
    read_var aws_s3_file_format "File format (Supported: PARQUET, JSON, AVRO)"

    exec_cmd_suppress aws s3 ls "$aws_s3_bucket/${aws_s3_path%%\*}"
    status "s3 credentials verified"
}

function get_gcp_info()
{
    read_var gcp_project "GCP Project"
    read_var gcp_dataset "Dataset name"
    read_var gcp_connection "Connection name"
    read_var gcp_external_table "External table name"

    status "project: ${gcp_project}, dataset: ${gcp_dataset}, connection: ${gcp_connection}"
}

function create_gcp_resources()
{
    # Enable bigquery API
    exec_cmd gcloud services enable --project "$gcp_project" bigquery.googleapis.com

    local output=
    output=$(bq --format=prettyjson show --connection --project_id=$gcp_project --location=$gcp_location $gcp_connection)
    if [ $? -ne 0 ]; then
        exec_cmd bq mk --connection --connection_type='AWS' \
            --iam_role_id=arn:aws:iam::$aws_account_id:role/$aws_role \
            --location=aws-us-east-1 \
            $gcp_connection
        output=$(bq --format=prettyjson show --connection --project_id=$gcp_project --location=$gcp_location $gcp_connection)
    fi

    gcp_connection_identity=$(echo "$output" | awk '/"identity":/{print substr($2,2,length($2)-2)}')
    gcp_connection_name=$(echo "$output" | awk '/"name":/{print substr($2,2,length($2)-2)}')
    if [ -z "$gcp_connection_identity" ]; then
        error_exit "unable to get identity for connection"
    fi
    status "connection created. identity id: ${gcp_connection_identity}, connection: ${gcp_connection_name}"
}

function create_aws_policy()
{
    # Create aws role policy
    if aws iam get-policy --policy-arn "arn:aws:iam::$aws_account_id:policy/$aws_policy" >/dev/null 2>&1; then
        status "aws policy '$aws_policy' already exists"
        return
    fi
    cat >/tmp/$aws_policy.json <<EOF
{
 "Version": "2012-10-17",
 "Statement": [{
       "Effect": "Allow",
       "Action": ["s3:ListBucket"],
       "Resource": ["arn:aws:s3:::$aws_s3_bucket"]
   },
   {
       "Effect": "Allow",
       "Action": ["s3:GetObject"],
       "Resource": [
           "arn:aws:s3:::$aws_s3_bucket",
           "arn:aws:s3:::$aws_s3_bucket/*"
           ]
   }]
 }
EOF

    log "creating aws iam policy $aws_policy with $(cat /tmp/$aws_policy.json)"
    exec_cmd aws iam create-policy --policy-name "$aws_policy" \
        --policy-document file:///tmp/"$aws_policy.json" \
        --description "access to s3 bucket - created by omni quickstart script"
    exec_cmd rm -f /tmp/$aws_policy.json
    status "aws iam policy $aws_policy created"
}

function create_aws_role()
{
    if aws iam get-role --role-name "$aws_role" >/dev/null 2>&1; then
        status "aws role '$aws_role' already exists"
        return
    fi
    cat >/tmp/${aws_role}-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "accounts.google.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "accounts.google.com:sub": "$gcp_connection_identity"
        }
      }
    }]
}
EOF

    log "creating aws iam role $aws_role with $(cat /tmp/${aws_role}-trust-policy.json)"
    exec_cmd aws iam create-role --role-name "$aws_role" \
        --assume-role-policy-document file:///tmp/${aws_role}-trust-policy.json \
        --max-session-duration 43200 \
        --description "Omni quickstart role to access s3 bucket - created by omni-quickstart script"
    status "aws iam role $aws_role created"
}

function attach_role_policy()
{
    exec_cmd aws iam attach-role-policy --role-name "$aws_role" \
        --policy-arn "arn:aws:iam::$aws_account_id:policy/$aws_policy"
}

function gcp_create_dataset()
{
    if bq --project_id=$gcp_project show --dataset $gcp_dataset >/dev/null 2>&1; then
        log "dataset '$gcp_dataset' already exists"
        return
    fi

    log "creating dataset $gcp_dataset"
    exec_cmd bq --project_id=$gcp_project --location=$gcp_location mk --dataset \
        --default_table_expiration 86400 \
        --description "created by omni quickstart script" \
        "$gcp_project:$gcp_dataset"
    status "dataset '$gcp_dataset' created"
}

function gcp_create_external_table()
{
    if bq --project_id=$gcp_project show $gcp_dataset.$gcp_external_table >/dev/null 2>&1; then
        status "external table '$gcp_dataset.$gcp_external_table' already exists"
        return
    fi

    bq mkdef --source_format=$aws_s3_file_format --connection_id=$gcp_location.$gcp_connection \
        "s3://$aws_s3_bucket/$aws_s3_path" >/tmp/$gcp_external_table.def
    
    if [ $? -ne 0 ]; then
        error_exit "unable to create table def"
    fi

    log "creating external table from table def: /tmp/$gcp_external_table.def"
    exec_cmd bq mk --external_table_definition=/tmp/$gcp_external_table.def $gcp_dataset.$gcp_external_table
    status "external table '$gcp_dataset.$gcp_external_table' created"
}

function gcp_query_external_table()
{
    local query="SELECT COUNT(*) FROM \`$gcp_project.$gcp_dataset.$gcp_external_table\`"
    exec_cmd bq --project_id=$gcp_project query --use_legacy_sql=false "$query"
    status "successfully ran query: $query"
}

function main()
{
    init_defaults
    install_aws_cli
    get_aws_credentials
    get_s3_bucket_info
    get_gcp_info
    create_gcp_resources
    create_aws_policy
    create_aws_role
    attach_role_policy
    gcp_create_dataset
    gcp_create_external_table
    gcp_query_external_table
    status "congratulations! all done!"
}

main