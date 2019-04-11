#!/bin/bash

clear

## Global VAR ##
aws_stack_name=''
aws_profile=''

usage="Usage:
  # Creating resources (VPC, ECR, ECS, FARGATE, ...)
	./AppBuilder.sh create-stacks
  
  # Inventory of stacks contains $aws_stack_name
  ./AppBuilder.sh inventory-stacks
	
  # Deleting resources (VPC, ECR, ECS, FARGATE, ...)
  ./AppBuilder.sh delete-stacks

  # Updating resources on a stack
  ./AppBuilder.sh update-stack <name> <file in templates folder>
"

if [ "$aws_stack_name" == "" ] || [ "aws_profile" == "" ] ; then
  echo "You must enter the variables aws_stack_name and aws_profile in AppBuilder.sh file"
  exit 1 || return 1
fi

if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ] || [ "$1" == "usage" ] ; then
  echo "$usage"
  exit 1 || return 1
fi

function waitOnCompletion() {
	STATUS=IN_PROGRESS
	while expr "$STATUS" : '^.*PROGRESS' > /dev/null ; do
		if STATUS=$(aws cloudformation describe-stacks --stack-name $1 --profile=$2 | jq -r '.Stacks[0].StackStatus'); then
      echo "|-- Status: "$STATUS
     sleep 10
    fi
	done
}

## Program ##
if [ $# -gt 0 ]; then

  option="${1}"

  case "$option" in
     "create-stacks")
        start=`date +%M`

        echo "|- Create stack (VPC 3 AZs)"
        aws cloudformation create-stack --stack-name $aws_stack_name'-VPC' --template-body file://'$PWD/templates/vpc-3azs.yml' --parameters file://'$PWD/parameters/vpc-3azs.json' --profile=$aws_profile
				waitOnCompletion $aws_stack_name'-VPC' $aws_profile

        echo "|- Create stack (ECR Repository)"
        aws cloudformation create-stack --stack-name $aws_stack_name'-ECR' --template-body file://'$PWD/templates/ecr-repo.yml' --parameters file://'$PWD/parameters/ecr-repo.json' --profile=$aws_profile
        waitOnCompletion $aws_stack_name'-ECR' $aws_profile
        
        echo "|- Build Docker img"
        docker build -t appli-demo ./app-demo/
        sleep 5
        
        echo "|- Push img to ECR repository"
        aws ecr get-login --no-include-email --profile=$aws_profile | sh
        IMAGE_REPO=$(aws ecr describe-repositories --repository-names repo-paris-meetup --query 'repositories[0].repositoryUri' --output text --profile=$aws_profile)
        docker tag appli-demo:latest $IMAGE_REPO:latest
        docker push $IMAGE_REPO:latest

        echo "|- Create stack (ECS Cluster)"
        aws cloudformation create-stack --stack-name $aws_stack_name'-ECS-Cluster' --template-body file://'$PWD/templates/ecs.yml' --parameters file://'$PWD/parameters/ecs-cluster.json' --profile=$aws_profile
        waitOnCompletion $aws_stack_name'-ECS-Cluster' $aws_profile

        echo "|- Create stack (Fargate task)"
        aws cloudformation create-stack --stack-name $aws_stack_name'-ECS-Task' --template-body file://'$PWD/templates/fargate.yml' --profile=$aws_profile  --capabilities CAPABILITY_IAM
        waitOnCompletion $aws_stack_name'-ECS-Task' $aws_profile

        echo "|- Create Handling Events for ECS (Lambda + DynamoDB)"
        aws cloudformation create-stack --stack-name $aws_stack_name'-ECS-Event-Handling' --template-body file://'$PWD/templates/event-handling.yml' --profile=$aws_profile  --capabilities CAPABILITY_IAM  
        waitOnCompletion $aws_stack_name'-ECS-Event-Handling' $aws_profile

        echo ""
        aws cloudformation describe-stacks --stack-name $aws_stack_name'-ECS-Cluster' --profile=$aws_profile

        end=`date +%M`
        runtime=$((end-start))
        echo "|- Total elapsed time: $runtime (min)"
     ;;
     
     "inventory-stacks")
        start=`date +%M`

        echo "|- Inventory of stacks contains $aws_stack_name"
        aws cloudformation describe-stacks --query "Stacks[?contains(StackName,'$aws_stack_name')].{\"Name\":StackName,\"Status\":StackStatus,\"CreationTime\":CreationTime,\"Description\":Description}" --profile=$aws_profile

        end=`date +%M`
        runtime=$((end-start))
        echo "|- Total elapsed time: $runtime (min)"
     ;;

     "update-stack")
        start=`date +%M`

        if [ "$2" == "" ] || [ "$3" == "" ] ; then
          echo "You must enter the name of the stack ans template file as a parameter"
          exit 1 || return 1
        fi

        echo "|- Updating of stack $2"
        aws cloudformation update-stack --stack-name $2 --capabilities CAPABILITY_IAM  --template-body file://'$PWD/templates/'$3 --profile=$aws_profile
        waitOnCompletion $2 $aws_profile

        end=`date +%M`
        runtime=$((end-start))
        echo "|- Total elapsed time: $runtime (min)"
     ;;

     "delete-stacks")
        start=`date +%M`

        echo "|- Delete stack Handling Events for ECS (Lambda + DynamoDB)..."
        aws cloudformation delete-stack --stack-name $aws_stack_name'-ECS-Event-Handling' --profile=$aws_profile
        waitOnCompletion $aws_stack_name'-ECS-Event-Handling' $aws_profile

        echo "|- Delete stack Fargate task..."
        aws cloudformation delete-stack --stack-name $aws_stack_name'-ECS-Task' --profile=$aws_profile
        waitOnCompletion $aws_stack_name'-ECS-Task' $aws_profile

        echo "|- Delete stack ECS Cluster..."
        aws cloudformation delete-stack --stack-name $aws_stack_name'-ECS-Cluster' --profile=$aws_profile
        waitOnCompletion $aws_stack_name'-ECS-Cluster' $aws_profile

        echo "|- Delete stack ECR..."
        aws ecr get-login --no-include-email --profile=$aws_profile | sh
        aws ecr delete-repository --force --repository-name 'repo-paris-meetup' --profile=$aws_profile
        sleep 5
        aws cloudformation delete-stack --stack-name $aws_stack_name'-ECR' --profile=$aws_profile
        waitOnCompletion $aws_stack_name'-ECR' $aws_profile

        echo "|- Delete stack VPC..."
        aws cloudformation delete-stack --stack-name $aws_stack_name'-VPC' --profile=$aws_profile
        waitOnCompletion $aws_stack_name'-VPC' $aws_profile
    
        end=`date +%M`
        runtime=$((end-start))
        echo "|- Total elapsed time: $runtime (min)"
     ;;

  esac

else
  echo "Your command line contains no arguments"
  echo ""
  echo "$usage" 
  exit 1 || return 1
fi