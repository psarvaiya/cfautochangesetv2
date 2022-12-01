#!/bin/bash

function quit_execution(){
  print_color 'red' "Script Exited"
  exit

}

function fetch_active_stack(){
    print_color 'green' "\nFetching active stack"
    aws cloudformation  list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query StackSummaries[*].[StackName,StackStatus] --output table
    
    if [[ $? != 0 ]]; then
        print_color 'red' 'Unable to fetch stacks, some issue with roles and permission'
        quit_execution
    fi

}


function execute_change_set(){
        aws cloudformation execute-change-set  --change-set-name $CHANGESET --stack-name $STACKNAME
        aws cloudformation wait stack-update-complete --stack-name $STACKNAME

}

function get_stack_events(){
        aws cloudformation describe-stack-events --stack-name $STACKNAME  --query StackEvents[*].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason] --output table

        aws cloudformation describe-stack-events --stack-name $STACKNAME  --query StackEvents[*].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason] --output table > get_stack_events.txt 
}


function get_change_sets(){
        print_color 'green' "Fetching change sets"
        aws cloudformation  describe-change-set --change-set-name $CHANGESET --stack-name $STACKNAME --query ExecutionStatus --query Changes[*].ResourceChange.[Action,LogicalResourceId,PhysicalResourceId] --output table

        aws cloudformation  describe-change-set --change-set-name $CHANGESET --stack-name $STACKNAME --query ExecutionStatus --query Changes[*].ResourceChange.[Action,LogicalResourceId,PhysicalResourceId] --output table > get_change_sets.txt


}

function list_stack_resources(){
        aws cloudformation list-stack-resources --stack-name $STACKNAME --query StackResourceSummaries[*].[LogicalResourceId,PhysicalResourceId,ResourceType] --output table

        aws cloudformation list-stack-resources --stack-name $STACKNAME --query StackResourceSummaries[*].[LogicalResourceId,PhysicalResourceId,ResourceType] --output table > list_stack_resources.txt

}


function display_output(){
        aws cloudformation describe-stacks --stack-name $STACKNAME --query Stacks[*].Outputs[*] --output table

        aws cloudformation describe-stacks --stack-name $STACKNAME --query Stacks[*].Outputs[*] --output table > output.txt

}


function check_changeset_available(){
        check_available=$(aws cloudformation  describe-change-set --change-set-name $CHANGESET --stack-name $STACKNAME --query ExecutionStatus --output text)

}


function validate_user_input_stack(){
        validate_user_stack=$(aws cloudformation describe-stacks --stack-name $STACKNAME --query Stacks[*].StackName --output text)

}

function loop_parameters(){
        count_iteration=$(aws cloudformation validate-template --query 'length(Parameters[*].ParameterKey)' --template-body file://$FILENAME)

}


function create_change_set(){
        aws cloudformation create-change-set --stack-name $STACKNAME --change-set-name $CHANGESET --parameters $s_parameters --template-body file://$FILENAME

        if [[ $? -eq 255 ]]; then
                print_color 'red' 'PARAMETERS passed are incorrect, exiting the script'
                quit_execution

        fi

        aws cloudformation create-change-set --stack-name $STACKNAME --change-set-name $CHANGESET --parameters $s_parameters --template-body file://$FILENAME > create_change_set.txt

cat > create_change_set_command.txt <<-EOF
aws cloudformation create-change-set --stack-name $STACKNAME --change-set-name $CHANGESET --parameters $s_parameters --template-body file://$FILENAME
EOF

}

function artifacts(){
        print_color 'green' '\n Logging the stack events to get_stack_events.txt'
        print_color 'green' '\n Logging the change set events to get_change_sets.txt'
        print_color 'green' '\n Logging the resources created by cloudformation to list_stack_resources.txt'
        print_color 'green' '\n Logging the output to output.txt'
        print_color 'green' '\n Logging the change set output.txt and command.txt'

        mkdir artifacts-$(date -d "today" +"%Y%m%d%H%M%S") && cp -r *.txt $_
        rm -rf *.txt

}

function print_color(){
  NC='\033[0m' 
  case $1 in

            "green") COLOR='\033[0;32m' 
                ;;
            "red") COLOR='\033[0;31m' 
                ;;
            "*") COLOR='\033[0m' 
                ;;
  esac
  echo -e "${COLOR} $2 ${NC}"

}

function assume_role(){

OUT=$(aws sts assume-role --role-arn $ROLEARN --role-session-name $ROLESESSION)
if [[ $? != 0 ]]; then
        print_color 'red' 'Configuration was unsucessful, some issue with role/session/permission'
        quit_execution
fi

export AWS_ACCESS_KEY_ID=$(echo $OUT | jq -r '.Credentials''.AccessKeyId');\
export AWS_SECRET_ACCESS_KEY=$(echo $OUT | jq -r '.Credentials''.SecretAccessKey');\
export AWS_SESSION_TOKEN=$(echo $OUT | jq -r '.Credentials''.SessionToken');
export AWS_DEFAULT_REGION=$REGION

}

#Disclaimer

while true
do

print_color 'green' 'To execute the automation script, we are going to assume IAM role. If you dont have it, please create it from AWS console'

print_color 'green'     '\nYou may also chose to continue with your personal AWS secret and access keys, but that is not recommended approach for security reason. \nWe expect you to configure this'

read -p 'Chose your workflow press 1 or 2
1. STS assume role
2. AWS configure CLI
' workflow

case $workflow in

        1)  	read -p 'Please provide the complete role arn : ' ROLEARN 
                echo -e '\n'
                read -p 'Please provide the name of session role : ' ROLESESSION
                echo -e '\n'
                read -p 'Please provide the region : ' REGION
                assume_role
                break

        ;;

        2) print_color 'green' 'Continuing with personal AWS secret and access keys'
                break
        ;;

        *) print_color 'red' '\nInvalid input, try again.'
           continue
            ;;

        esac
done

#Get Stacks

while true
do
        fetch_active_stack
        read -p "Which stack you want to update. Press q or Q to exit? " STACKNAME
        case $STACKNAME in
            q|Q)
                quit_execution
                ;;

          #   *)
                        # print_color 'red' "\n Invalid Input please try again."
          #       continue
          #       ;;

            $STACKNAME)  

                        validate_user_input_stack
                if [[ $validate_user_stack = $STACKNAME ]]; then
                        print_color 'green' "\nStack selected: $STACKNAME"
                        break
                else 
                        print_color 'red' "Stack does not exist, please try again"
                        continue
                fi
                ;;
        esac
done

echo -e '\n'

read -p 'Please provide complete path to AWS CF template including file name i.e. /path/to/cf.yaml : ' FILENAME


#Check if file exist

if [[ -e $FILENAME ]]; then
    print_color 'green' 'Cloudformation template file exist'
else
    print_color 'red' 'Cloudformation template file not present'
    quit_execution
fi


#Get the parameters from user

declare -A parameters

loop_parameters

echo -e '\n\nUsage example:

-----------------------------------
There are "X" parameters
 
Please provide Parameter Key : S3BucketName
Please provide Parameter value : my-s3-bucket
Please provide Parameter Key : SelectStage
Please provide Parameter value : dev
------------------------------------
'

print_color 'green' '\nThere are '$count_iteration' parameters\n'

for (( i = 0; i < $count_iteration; i++ )); do
        #statements
        read -p 'Please provide Parameter Key : ' key
        read -p 'Please provide Parameter value : ' value
        parameters[$key]=$value

done


#Concatenate the parameters

s_parameters=''
for j in "${!parameters[@]}"
do
        s_parameters=$s_parameters' '$(printf "ParameterKey=%s,ParameterValue=%s" $j ${parameters[${j}]})
done


#Create Change set

echo -e '\n'

read -p 'Please provide name of Change Set: ' CHANGESET

create_change_set


#Check if Change set becomes available state in 30 secs

print_color 'green' '\n\nWaiting for change set to become available'

n=1
until [[ $n -ge 6 ]]; do

   check_changeset_available

   if [[ $check_available != "AVAILABLE" ]]; then
                print_color 'red' "\n\nChange set didn't become available in $n attempt"
   
                if [[ $n -eq 5 ]]; then
                        #statements
                        print_color 'red' "\n\nChange set didn't become available state within given time, exiting now"
                        quit_execution
                fi

   else
                print_color 'green' "\n\nChange set is now available after $n retries"
                break
   fi
   sleep 5s
  
   n=$((n+1)) 

done


#Prompt user if they want to execute the change set  -> If no then exit 

echo -e '\n'

while true
do
        get_change_sets

        read -p 'Do you want to execute the above change set? Press Y to continue, N to exit : ' execute

        case $execute in
            y|Y)
                        #Execute the changeset 
                print_color 'green' "\n\nExecute the change set. \nPlease wait while the resources are getting updated/created."
                execute_change_set
                break
                ;;
            n|N)
                        print_color 'red' '\nExiting the script'
                quit_execution
                ;;
            *)
                        print_color 'red' '\nInvalid input, try again.'
                continue
                ;;
        esac

done

#Show events

print_color 'green' "\n----Getting the deployment events----"
get_stack_events


#list the resources that are created

print_color 'green' "\n----List Stack resources----"
list_stack_resources


#show the output

print_color 'green' "\n----Display output----"
display_output


#save the artifacts for reference

print_color 'green' "\n----Copy the artifacts----"

artifacts
print_color 'green' "\n----You can find the artifacts in the same directory----"

#Complete
print_color 'green' "\n----Cloudformation template update was successfull!----"
