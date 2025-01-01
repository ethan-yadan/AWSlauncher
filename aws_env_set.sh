#!/bin/bash

############### Start of Secure Header ###############
# Created by: Eitan Yadan                            #
# Purpose: creates aws environment for ec2           #
# Version: 1.1.5                                     #
# Date: 17.12.2024                                   #
set -o errexit                                       #
set -o pipefail                                      #
set -o nounset                                       #
set -x                                               #
############### End of Secure Header #################


# AWS Predefined Environment Variables Setup 
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_SUBNET_CIDR="10.0.1.0/24"
DEFAULT_REGION="us-east-1"
DEFAULT_TAG_KEY="Name"
DEFAULT_TAG_VALUE="MyProjectVPC"
DEFAULT_SECURITY_GROUP_NAME="my-project-security-group"
DEFAULT_SECURITY_GROUP_DESC="Project security group for my VPC"


# Display Current Values of Variables 
echo "----------------------------------------------------------------------"
echo "Current (Predefined) AWS Environment Variables:" 
echo " Default VPC CIDR: $DEFAULT_VPC_CIDR"
echo " Default Subnet CIDR: $DEFAULT_SUBNET_CIDR"
echo " Default AWS Region: $DEFAULT_REGION"
echo " Default Tag Key: $DEFAULT_TAG_KEY"
echo " Default Tag Value: $DEFAULT_TAG_VALUE"
echo " Default Security Group Name: $DEFAULT_SECURITY_GROUP_NAME"
echo " Default Security Group Description: $DEFAULT_SECURITY_GROUP_DESC"
echo "----------------------------------------------------------------------"


# Ask User to Override Variables 
read -p "Enter a new VPC CIDR (To keep default: $DEFAULT_VPC_CIDR ,Press Enter): " VPC_CIDR
read -p "Enter a new Subnet CIDR (To keep default: $DEFAULT_SUBNET_CIDR ,Press Enter): " SUBNET_CIDR
read -p "Enter a new AWS Region (To keep default: $DEFAULT_REGION ,Press Enter): " REGION 
read -p "Enter a new Tag Key (To keep default: $DEFAULT_TAG_KEY ,Press Enter): " TAG_KEY 
read -P "Enter a new Tag Value (To keep default: $DEFAULT_TAG_VALUE ,Press Enter): " TAG_VALUE
read -p "Enter a new Security Group Name (To keep default: $DEFAULT_SECURITY_GROUP_NAME ,Press Enter): " SECURITY_GROUP_NAME
read -p "Enter a new Security Group Description (To keep default: $DEFAULT_SECURITY_GROUP_DESC ,Press Enter): " SECURITY_GROUP_DESC


# Use Default Values if Input is Empty 
VPC_CIDR=${VPC_CIDR:-$DEFAULT_VPC_CIDR}
SUBNET_CIDR=${SUBNET_CIDR:-$DEFAULT_SUBNET_CIDR}
REGION=${REGION:-$DEFAULT_REGION}
TAG_KEY=${TAG_KEY:-$DEFAULT_TAG_KEY}
TAG_VALUE=${TAG_VALUE:-$DEFAULT_TAG_VALUE}
SECURITY_GROUP_NAME=${SECURITY_GROUP_NAME:-$DEFAULT_SECURITY_GROUP_NAME}
SECURITY_GROUP_DESC=${SECURITY_GROUP_DESC:-$DEFAULT_SECURITY_GROUP_DESC}


# 1. AWS VPC Cretaion and Tags
VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" --region "$REGION" --query 'Vpc.VpcId' --output text)
echo "VPC created with ID: $VPC_ID"

aws ec2 create-tags --resources "$VPC_ID" --tags Key="$TAG_KEY",Value="$TAG_VALUE" --region "$REGION"
echo "VPC tagged with $TAG_KEY=$TAG_VALUE"


# 2. AWS Subnet Creation and Tagging
SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_CIDR" --region "$REGION" --query 'Subnet.SubnetId' --output text) 
echo "Subnet created with ID: $SUBNET_ID"

aws ec2 create-tags --resources "$SUBNET_ID" --tags Key="$TAG_KEY",Value="Subnet-$TAG_VALUE" --region "$REGION"
echo "Subnet tagged with $TAG_KEY=Subnet-$TAG_VALUE"


# 3. AWS Internet Gateway Creation and Tagging
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" --query 'InternetGateway.InternetGatewayId' --output text)
echo "Internet Gateway created successfully in region "$REGION" with ID: "$IGW_ID" "
    
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION" 
echo "Internet Gateway $IGW_ID successfully attached to VPC "$VPC_ID" in region "$REGION"."
    

# 4. AWS Route Table and Associate to Subnet 
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" --query 'RouteTable.RouteTableId' --output text)
echo "Route Table created with ID: "$ROUTE_TABLE_ID""
   
aws ec2 create-route --route-table-id "$ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$REGION" 
echo "Route successfully added to Route Table "$ROUTE_TABLE_ID" "
    
aws ec2 associate-route-table --route-table-id "$ROUTE_TABLE_ID" --subnet-id "$SUBNET_ID" --region "$REGION" 
echo "Subnet "$SUBNET_ID" successfully associated with Route Table "$ROUTE_TABLE_ID" "


# 5. AWS Security Group Creation and Ingress Roles 
SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name "$SECURITY_GROUP_NAME" --description "$SECURITY_GROUP_DESC" --vpc-id "$VPC_ID" --region "$REGION" --query 'GroupId' --output text)
echo "Security Group created successfully with ID: "$SECURITY_GROUP_ID" "
aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "$REGION"
aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 --region "$REGION"


# 6. Summary 
echo " **** AWS Environment Creation Status **** "
echo "-------------------------------------------"
echo "VPC ID: "$VPC_ID" "
echo "Subnet ID: "$SUBNET_ID" "
echo "Internet Gateway ID: "$IGW_ID" "
echo "Route Table ID: "$ROUTE_TABLE_ID" "
echo "Security Group ID: "$SECURITY_GROUP_ID" "
echo "-------------------------------------------"


# 7. AWS Key Pair Creation and Permissions
KEY_NAME="my-project-keypair"
KEY_FILE="${KEY_NAME}.pem"

aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --output text > "$KEY_FILE" 
echo "Key pair "$KEY_NAME" created successfully and saved as "$KEY_FILE" "
chmod 400 "$KEY_FILE"


# 8. AWS EC2 Instances Creation and Launching 
AMI_ID="ami-0e2c8caa4b6378d8c"
INSTANCE_TYPE="t2.micro" 
TAG_KEY_EC2="Name"
TAG_VALUE_EC2="Jenkins_EC2"
TAG_VALUE_EC2w="Nginx_EC2"

INSTANCE_ID1=$(aws ec2 run-instances --image-id "$AMI_ID" --count 1 --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" --subnet-id "$SUBNET_ID" --security-group-ids "$SECURITY_GROUP_ID" --associate-public-ip-address --tag-specifications "ResourceType=instance,Tags=[{Key="$TAG_KEY_EC2",Value="$TAG_VALUE_EC2"}]" --query 'Instances[0].InstanceId' --output text)

INSTANCE_ID2=$(aws ec2 run-instances --image-id "$AMI_ID" --count 1 --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" --subnet-id "$SUBNET_ID" --security-group-ids "$SECURITY_GROUP_ID" --associate-public-ip-address --tag-specifications "ResourceType=instance,Tags=[{Key="$TAG_KEY_EC2",Value="$TAG_VALUE_EC2w"}]" --query 'Instances[0].InstanceId' --output text)

echo "EC2 instance launched successfully with ID: "$INSTANCE_ID1" "
echo "EC2 instance launched successfully with ID: "$INSTANCE_ID2" "

INSTANCE_DETAILS1=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID1" --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]' --output table )
INSTANCE_DETAILS2=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID2" --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]' --output table )

echo "$INSTANCE_DETAILS1"
echo "$INSTANCE_DETAILS2"


# 9. Check EC2 Instances Status 
aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{InstanceId: InstanceId, PublicIpAddress: PublicIpAddress, PrivateIpAddress: PrivateIpAddress, State: State.Name, InstanceType: InstanceType}' --output table
