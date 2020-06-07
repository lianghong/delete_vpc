# delete_vpc

A shell script to delete AWS VPC with its dependancies (ec2 instance, NAT Gateway,VPN connection, VPN Gateway, VPC Peering, Delete Endpoints, egress only internet gateway, Network ACLs, Security Group , Elastic IP, Internet Gateway, Network Interface , Subnet and RouteTable).

Note: The script requires AWSCLI and does not depend on any other tools。

Modified on Jun 7 2020 :` Solved the issue of Security Group deleting failed when Security Group Attachedt to ENI

``
Usage :
./delete_vpc.sh <region-id> <vpc-id> # Delete a apecific VPC
./delete_vpc.sh <region-id> # List all of VPC in the specific Region

For example:
./delete_vpc.sh us-east-1
./delete_vpc.sh us-east-1 vpc-xxxxxxxxxx

```

```
