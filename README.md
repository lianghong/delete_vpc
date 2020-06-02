# delete_vpc

A shell script to delete AWS VPC with its dependancies (ec2 instance, NAT Gateway,VPN connection, VPN Gateway, VPC Peering, Delete Endpoints, egress only internet gateway, Network ACLs, Security Group , Elastic IP, Internet Gateway, Network Interface , Subnet and RouteTable).

Note: The script requires AWSCLI and does not depend on any other tools。

```
Usage      : ./delete_vpc.sh <region-id> <vpc-id>
For example: ./delete_vpc.sh us-east-1 vpc-xxxxxxxxxx
```
