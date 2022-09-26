#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Prject description : Delete a specific AWS VPC
# author      : Lianghong Fei
# e-mail      : feilianghong@gmail.com
# create date : May 23, 2020
# modify date : Aug 22, 2021
# modify date : Jun 16, 2022
# modify date : Jul 10, 2022, support china refion
# modify date : Sep 26, 2022, add 'Delete Security Group(s) IpPermissions'

set -e

function print_usage_and_exit {
    echo "Usage   : $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Display this message."
    echo "  --region             AWS Region (eg. us-east-1)"
    echo "  --vpc-id             The ID of VPC (eg. vpc-xxxxxxxxxx)"
    echo "  --non-interactive    Run with no interactive"
    echo "  --list-vpc           List all VPCs in the specific region"
    echo "Example:"
    echo "    $0 --region us-east-1 --vpc-id vpc-xxxxxxxxxx"
    echo "    $0 --region us-east-1 --vpvid vpc-xxxxxxxxxx --non-interactive"
    echo "    $0 --region us-east-1 --list-vpc"
    exit $1
}
function list_vpc {
    if [ -z $1 ] ; then
        echo "AWS resion is required."
        exit 1
    fi
    aws ec2 describe-vpcs \
        --query 'Vpcs[].{vpcid:VpcId,name:Tags[?Key==`Name`].Value[]}' \
        --region $1 \
        --output table
    exit 1
}

if ! command -v aws &>/dev/null; then
    echo "awscli is not installed. Please install it and re-run this script."
    exit 1
fi

if [ "$#" -eq 0 ]; then
   print_usage_and_exit 1
fi

AWS_REGION=""
VPC_ID=""
NON_INTERACTIVE=0
CHINA_REGION="cn-northwest-1|cn-north-1"

while [ $# -gt 0 ]
do
  case $1 in
    --region )
        AWS_REGION=$2
          ;;
    --vpc-id )
        VPC_ID=$2
        ;;
    --non-interactive )
        NON_INTERACTIVE=1
        ;;
    --list-vpc )
        list_vpc "${AWS_REGION}"
        ;;
    -h | --help )
        print_usage_and_exit 0
        ;;
      esac
      shift
done

[ -z "${AWS_REGION}" ] && print_usage_and_exit 0
[ -z "${VPC_ID}" ] && print_usage_and_exit 0

# Check VPC status, available or not
state=$(aws ec2 describe-vpcs \
    --vpc-ids "${VPC_ID}" \
    --query 'Vpcs[].State' \
    --region "${AWS_REGION}" \
    --output text)

if [ "${state}" != 'available' ]; then
    echo "The VPC of ${VPC_ID} is NOT available now!"
    exit 1
fi

if [ ${NON_INTERACTIVE} -eq 0 ]  ;then
  echo -n "*** Are you sure to delete the VPC of ${VPC_ID} in ${AWS_REGION} (y/n)? "
  read answer
  if [ "$answer" != "${answer#[Nn]}" ] ;then
      exit 1
  fi
fi

# Delete ELB
echo "Process of ELB ..."
all_elbs=$(aws elbv2 describe-load-balancers \
        --query 'LoadBalancers[*].{ARN:LoadBalancerArn,VPCID:VpcId}' \
        --region "${AWS_REGION}" \
        --output text \
        | grep "${VPC_ID}" \
        | xargs -n1 | sed -n 'p;n')

for elb in ${all_elbs}; do
    # get all listenners under the elb
    listeners=$(aws elbv2 describe-listeners \
        --load-balancer-arn "${elb}" \
        --query 'Listeners[].{ARN:ListenerArn}' \
        --region "${AWS_REGION}" \
        --output text)

    for lis in ${listeners}; do
        echo "    delete listenner of ${lis}"
        aws elbv2 delete-listener \
            --listener-arn "${lis}" \
            --region "${AWS_REGION}" \
            --output text
    done

    echo "    delete elb of ${elb}"
    aws elbv2 delete-load-balancer \
        --load-balancer-arn "${elb}" \
        --region "${AWS_REGION}" \
        --output text
done

# Get all of target-group under the VPC
all_target_groups=$(aws elbv2 describe-target-groups \
    --query 'TargetGroups[].{ARN:TargetGroupArn,VPC:VpcId}' \
    --region "${AWS_REGION}" \
    --output text \
    | grep "${VPC_ID}" \
    | xargs -n1 | sed -n 'p;n')

for tg in ${all_target_groups}; do
    echo "    delete target group of ${tg}"
    aws elbv2 delete-target-group \
        --target-group-arn "${tg}" \
        --region "${AWS_REGION}" \
        --output text
done

# Stop EC2 instance
echo "Process of EC2 instance(s) ..."
for instance in $(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' \
    --region "${AWS_REGION}" \
    --output text)
do

    echo "    enable api to stop of ${instance}"
    aws ec2 modify-instance-attribute \
        --no-disable-api-stop \
        --instance-id "${instance}" \
        --region "${AWS_REGION}" > /dev/null

    echo "    stop instance of ${instance}"
    aws ec2 stop-instances \
        --instance-ids "${instance}" \
        --region "${AWS_REGION}" > /dev/null

    # Wait until instance stopped
    echo "    wait until instance stopped"
    aws ec2 wait instance-stopped \
        --instance-ids "${instance}" \
        --region "${AWS_REGION}"
done

# Terminate instance
for instance in $(aws ec2 describe-instances \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'Reservations[].Instances[].InstanceId' \
    --region "${AWS_REGION}" \
    --output text)
do

        echo "    enable api termination of ${instance}"
    aws ec2 modify-instance-attribute \
        --no-disable-api-termination \
        --instance-id "${instance}" \
        --region "${AWS_REGION}" > /dev/null

    echo "    terminate instance of ${instance}"
    aws ec2 terminate-instances \
        --instance-ids "${instance}" \
        --region "${AWS_REGION}" > /dev/null

    # Wait until instance terminated
    echo "    wait until instance terminated"
    aws ec2 wait instance-terminated \
        --instance-ids "${instance}" \
        --region "${AWS_REGION}"
done

# Delete NAT Gateway
echo "Process of NAT Gateway ..."
for natgateway in $(aws ec2 describe-nat-gateways \
    --filter 'Name=vpc-id,Values='${VPC_ID} \
    --query 'NatGateways[].NatGatewayId' \
    --region "${AWS_REGION}" \
    --output text)
do
    echo "    delete NAT Gateway of ${natgateway}"
    aws ec2 delete-nat-gateway \
        --nat-gateway-id "${natgateway}" \
        --region "${AWS_REGION}" > /dev/null
done

echo "    waiting for state of deleted"
while :
do
    state=$(aws ec2 describe-nat-gateways \
        --filter 'Name=vpc-id,Values='${VPC_ID} \
                 'Name=state,Values=pending,available,deleting' \
        --query 'NatGateways[].State' \
        --region "${AWS_REGION}" \
        --output text)
    if [ -z "${state}" ]; then
        break
    fi
    sleep 3
done

if  ! [[ ${AWS_REGION} = @(${CHINA_REGION}) ]]; then
    # Delete VPN connection
    echo "Process of VPN connection ..."
    for vpn in $(aws ec2 describe-vpn-connections \
        --filters 'Name=vpc-id,Values='${VPC_ID} \
        --query 'VpnConnections[].VpnConnectionId' \
        --region "${AWS_REGION}" \
        --output text)
    do
        echo "    delete VPN Connection of ${vpn}"
        aws ec2 delete-vpn-connection \
            --vpn-connection-id "${vpn}" \
            --region "${AWS_REGION}" > /dev/null
        # Wait until deleted
        echo "    wait until deleted"
        aws ec2 wait vpn-connection-deleted \
            --vpn-connection-ids "${vpn}" \
            --region "${AWS_REGION}"
    done

    # Delete VPN Gateway
    echo "Process of VPN Gateway ..."
    for vpngateway in $(aws ec2 describe-vpn-gateways \
        --filters 'Name=attachment.vpc-id,Values='${VPC_ID} \
        --query 'VpnGateways[].VpnGatewayId' \
        --region "${AWS_REGION}" \
        --output text)
    do
        echo "    delete VPN Gateway of $vpngateway"
        aws ec2 delete-vpn-gateway \
            --vpn-gateway-id "${vpngateway}" \
            --region "${AWS_REGION}" > /dev/null
    done
fi

# Delete VPC Peering
echo "Process of VPC Peering ..."
for peering in $(aws ec2 describe-vpc-peering-connections \
    --filters 'Name=requester-vpc-info.vpc-id,Values='${VPC_ID} \
    --query 'VpcPeeringConnections[].VpcPeeringConnectionId' \
    --region "${AWS_REGION}" \
    --output text)
do
    echo "    delete VPC Peering of $peering"
    aws ec2 delete-vpc-peering-connection \
        --vpc-peering-connection-id "${peering}" \
        --region "${AWS_REGION}" > /dev/null

    # Wait until deleted
    echo "    wait until deleted"
    aws ec2 wait vpc-peering-connection-deleted \
        --vpc-peering-connection-ids "${peering}" \
        --region "${AWS_REGION}"
done

# Delete Endpoints
echo "Process of VPC endpoints ..."
for endpoints in $(aws ec2 describe-vpc-endpoints \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'VpcEndpoints[].VpcEndpointId' \
    --region "${AWS_REGION}" \
    --output text)
do
    echo "    delete endpoint of $endpoints"
    aws ec2 delete-vpc-endpoints \
        --vpc-endpoint-ids "${endpoints}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete Egress Only Internet Gateway
echo "Process of Egress Only Internet Gateway ..."
for egress in $(aws ec2 describe-egress-only-internet-gateways \
    --filters 'Name=attachment.vpc-id,Values='${VPC_ID} \
    --query 'EgressOnlyInternetGateways[].EgressOnlyInternetGatewayId' \
    --region "${AWS_REGION}" \
    --output text)
do
    echo "    delete Egress Only Internet Gateway of $egress"
    aws ec2 delete-egress-only-internet-gateway \
        --egress-only-internet-gateway-id "${egress}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete ACLs
echo "Process of Network ACLs ..."
for acl in $(aws ec2 describe-network-acls \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'NetworkAcls[].NetworkAclId' \
    --region "${AWS_REGION}" \
    --output text)
do
    # Check it's default acl
    acl_default=$(aws ec2 describe-network-acls \
        --network-acl-ids "${acl}" \
        --query 'NetworkAcls[].IsDefault' \
        --region "${AWS_REGION}" \
        --output text)

    # Ignore default acl
    if [ "$acl_default" = 'true' ] || [ "$acl_default" = 'True' ]; then
        continue
    fi

    echo "    delete ACL of ${acl}"
    aws ec2 delete-network-acl \
        --network-acl-id "${acl}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete EIP
echo "Process of Elastic IP ..."
for associationid in $(aws ec2 describe-network-interfaces \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'NetworkInterfaces[].Association[].AssociationId' \
    --region "${AWS_REGION}" \
    --output text)
do
    echo "    disassociate EIP association-id of ${associationid}"
    aws ec2 disassociate-address \
        --association-id "${associationid}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete NIC
echo "Process of Network Interface ..."
for nic in $(aws ec2 describe-network-interfaces \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'NetworkInterfaces[].NetworkInterfaceId' \
    --region "${AWS_REGION}" \
    --output text)
do
    echo "    detach Network Interface of $nic"
    attachment=$(aws ec2 describe-network-interfaces \
        --filters 'Name=vpc-id,Values='${VPC_ID} \
                  'Name=network-interface-id,Values='${nic} \
        --query 'NetworkInterfaces[].Attachment.AttachmentId' \
        --region "${AWS_REGION}" \
        --output text)

    if [ ! -z ${attachment} ]; then
        echo "    network attachment is ${attachment}"
        aws ec2 detach-network-interface \
            --attachment-id "${attachment}" \
            --region "${AWS_REGION}" >/dev/null

        # we need a waiter here
        sleep 3
    fi

    echo "    delete Network Interface of ${nic}"
    aws ec2 delete-network-interface \
        --network-interface-id "${nic}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete Security Group(s) IpPermissions
sgs=$(aws ec2 describe-security-groups \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'SecurityGroups[].GroupId' \
    --region "${AWS_REGION}" \
    --output text)

echo "Delete Security Group(s) IpPermissions ..."
for sg in ${sgs} ; do
    # Check it's default security group
    sg_name=$(aws ec2 describe-security-groups \
        --group-ids "${sg}" \
        --query 'SecurityGroups[].GroupName' \
        --region "${AWS_REGION}" \
        --output text)
    # Ignore default security group
    if [ "$sg_name" = 'default' ] || [ "$sg_name" = 'Default' ]; then
        continue
    fi

    for type in "in" "e" ; do
        IP_PERMISSION_TYPE=""
        if [ "${type}" == "in" ]; then
            IP_PERMISSION_TYPE='SecurityGroups[].IpPermissions[]'
            echo "    delete IpPermissions of Security group of ${sg}"
        else
            IP_PERMISSION_TYPE='SecurityGroups[].IpPermissionsEgress[]'
            echo "    delete IpPermissionsEgress of Security groups of ${sg}"
        fi

        IP_PERMISSION=$(aws ec2 describe-security-groups \
            --group-ids "${sg}" \
            --query "${IP_PERMISSION_TYPE}" \
            --region "${AWS_REGION}" \
            --output json)

        if [[ -z "${IP_PERMISSION}" ]] || [[ "${IP_PERMISSION}" == '[]' ]]; then
            echo "    going forward..."
            continue
        fi
        echo "    revoke sg's ${type}gress"
        aws ec2 revoke-security-group-${type}gress \
            --group-id "${sg}" \
            --ip-permissions "${IP_PERMISSION}" \
            --region "${AWS_REGION}" >/dev/null
    done
done

# Delete Security Group(s)
echo "Process of Security Group ..."
for sg in ${sgs}; do
    # Check it's default security group
    sg_name=$(aws ec2 describe-security-groups \
        --group-ids "${sg}" \
        --query 'SecurityGroups[].GroupName' \
        --region "${AWS_REGION}" \
        --output text)
    # Ignore default security group
    if [ "$sg_name" = 'default' ] || [ "$sg_name" = 'Default' ]; then
        continue
    fi

    echo "    delete Security group of ${sg}"
    aws ec2 delete-security-group \
        --region "${AWS_REGION}" \
        --group-id "${sg}" >/dev/null
done

# Delete IGW(s)
echo "Process of Internet Gateway ..."
for igw in $(aws ec2 describe-internet-gateways \
    --filters 'Name=attachment.vpc-id,Values='${VPC_ID} \
    --query 'InternetGateways[].InternetGatewayId' \
    --region "${AWS_REGION}" \
    --output text)
do
    echo "    detach IGW of $igw"
    aws ec2 detach-internet-gateway \
        --internet-gateway-id "${igw}" \
        --vpc-id "${VPC_ID}" \
        --region "${AWS_REGION}" > /dev/null

    # we need a waiter here
    sleep 3

    echo "    delete IGW of ${igw}"
    aws ec2 delete-internet-gateway \
        --internet-gateway-id "${igw}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete Subnet(s)
echo "Process of Subnet ..."
for subnet in $(aws ec2 describe-subnets \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'Subnets[].SubnetId' \
    --region "${AWS_REGION}" \
    --output text)
do
    echo "    delete Subnet of $subnet"
    aws ec2 delete-subnet \
        --subnet-id "${subnet}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete Route Table
echo "Process of Route Table ..."
for routetable in $(aws ec2 describe-route-tables \
    --filters 'Name=vpc-id,Values='${VPC_ID} \
    --query 'RouteTables[].RouteTableId' \
    --region "${AWS_REGION}" \
    --output text)
do
    # Check it's main route table
    main_table=$(aws ec2 describe-route-tables \
        --route-table-ids "${routetable}" \
        --query 'RouteTables[].Associations[].Main' \
        --region "${AWS_REGION}" \
        --output text)

    # Ignore main route table
    if [ "$main_table" = 'True' ] || [ "$main_table" = 'true' ]; then
        continue
    fi

    echo "    delete Route Table of ${routetable}"
    aws ec2 delete-route-table \
        --route-table-id "${routetable}" \
        --region "${AWS_REGION}" > /dev/null
done

# Delete VPC
echo -n "Finally, delete the VPC of ${VPC_ID}"
aws ec2 delete-vpc \
    --vpc-id "${VPC_ID}" \
    --region "${AWS_REGION}" \
    --output text

echo ""
echo "Done."
