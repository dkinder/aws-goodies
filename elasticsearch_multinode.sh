#!/usr/bin/env bash
# Requirements
# * AMI must have cloud-init support
# * CentOS
# *AWS CLI (tested with aws-cli/1.10.34 Python/2.7.5 Darwin/13.4.0 botocore/1.4.24)
# * configured cedentials for AWS CLI
# run the following to configure awscli
# aws configure

#################
# Configuration #
#################
ACCESS_KEY='CHANGE_ME'
SECRET_KEY='CHANGE_ME'
ADMIN_PASS="CHANGE_ME" #used to access elasticsearch

INSTANCE_COUNT=3
CLUSTER_NAME="MY_CLUSTER" #elasticsearch cluster name to be used by all nodes

IMAGE_ID="ami-CHANGEME" #cloud init supported centos
INSTANCE_TYPE="t1.micro"
SUBNET_IDS="CHANGE_ME" #comma delimited list
PRIV_KEY_FILE_NAME="./priv.$$.pem"
SECURITY_GROUP="CHANGE_ME"
SSH_ALLOWED_IPS="10.10.0.0/16" #Space delimited
ES_ALLOWED_IPS="10.10.10.0/24 10.10.10.4/32" #Space delimited
NOOP=""

#############################################################

clear
echo "You are about to deploy a ${INSTANCE_COUNT} node Elasticsearch cluster to EC2 in its own VPC."
echo "Checking for existing security group..."
aws ec2 describe-security-groups ${NOOP} --group-names ${SECURITY_GROUP} 2>&1 > /dev/null
if [ $? -eq 0 ]
then
    echo "Security group already exists"
    secgroupid=$(aws ec2 describe-security-groups ${NOOP} --group-names ${SECURITY_GROUP}  --query SecurityGroups[*].{ID:GroupId})
else
    echo "Creating security group"
    secgroupid=$(aws ec2 create-security-group ${NOOP} --group-name ${SECURITY_GROUP} --description "Default security group for elasticsearch clusters")
    aws ec2 authorize-security-group-ingress --group-id ${secgroupid} --protocol tcp --port 9300 --source-group ${secgroupid}
    for iprange in ${SSH_ALLOWED_IPS}
    do
        aws ec2 authorize-security-group-ingress --group-name ${SECURITY_GROUP} --protocol tcp --port 22 --cidr $iprange
    done
    for iprange in ${ES_ALLOWED_IPS}
    do
        aws ec2 authorize-security-group-ingress --group-name ${SECURITY_GROUP} --protocol tcp --port 9200 --cidr $iprange
    done
fi

echo -n "Do you have an existing pub/priv key pair to use? [y/N]: "
read answer

answer=$(echo $answer | tr [:upper:] [:lower:])
if [ ${answer}X == 'yX' ] || [ ${answer}X == 'yesX' ]
then
    while [  -z $keyName  ];
    do 
        echo "Keypair Names:"
        echo $(aws ec2 describe-key-pairs | cut -f3)
        echo
        echo -n "Enter existing name for key pair: "
        read keyName
    done
else
    while [  -z $keyName  ];
    do 
        echo -n "Enter name for key pair: "
        read keyName
    done
    aws ec2 create-key-pair ${NOOP} --key-name ${keyName} --query 'KeyMaterial' --output text  > ${PRIV_KEY_FILE_NAME}
    echo "Your private key is located at ${PRIV_KEY_FILE_NAME}"
    echo "username: centos"
fi

while [  -z $clusterName ];
do 
    echo -n "Enter a name for this cluster: "
    read clusterName
done
#####
# Script
########
USERDATA=$(cat <<SETVAR
#!/bin/bash
setenforce 0
chkconfig iptables off
service iptables stop
yum install java-1.8.0-openjdk wget  -y
yum -y upgrade nss
cd /tmp/
wget https://download.elastic.co/elasticsearch/release/org/elasticsearch/distribution/rpm/elasticsearch/2.3.3/elasticsearch-2.3.3.rpm
yum localinstall elasticsearch-2.3.3.rpm -y


cat <<END >> /etc/elasticsearch/elasticsearch.yml
cluster.name: ${CLUSTERNAME}
node.name: \$(hostname)
network.host: 0.0.0.0
cloud:
    aws:
        access_key: ${ACCESS_KEY}
        secret_key: ${SECRET_KEY}
discovery:
    type: ec2
END


cd /usr/share/elasticsearch
bin/plugin install mobz/elasticsearch-head
bin/plugin install lmenezes/elasticsearch-kopf
bin/plugin install license
bin/plugin install shield # authentication
bin/plugin install cloud-aws -b
bin/shield/esusers useradd es_admin -r admin -p ${ADMIN_PASS}
chkconfig elasticsearch on
service elasticsearch start

SETVAR
)

#################
# Launch Config #
#################
echo "Creating Launch Configuration"
aws autoscaling create-launch-configuration --launch-configuration-name ${clusterName} --image-id ${IMAGE_ID} --key-name ${keyName} --security-groups ${secgroupid} --instance-type ${INSTANCE_TYPE} --instance-monitoring Enabled=false --user-data "${USERDATA}" 

##############
# Launch ASG #
##############
echo "Creating Autoscaling group"
aws autoscaling create-auto-scaling-group --launch-configuration-name ${clusterName} --min-size ${INSTANCE_COUNT} --max-size ${INSTANCE_COUNT} --desired-capacity ${INSTANCE_COUNT}  --vpc-zone-identifier ${SUBNET_IDS} --auto-scaling-group-name ${clusterName}
echo "DONE"
