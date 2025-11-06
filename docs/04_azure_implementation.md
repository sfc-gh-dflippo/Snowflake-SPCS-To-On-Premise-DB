## Chapter 4: Solution Implementation for Snowflake on Azure

This Chapter provides a parallel, detailed guide for customers whose Snowflake account is hosted on Microsoft Azure and who are connecting to an on-premise data center via Azure networking services. The architectural principles are analogous to the AWS solution, but the specific service names and configurations differ.

### Part 4.1: Establishing the Azure Hybrid Network Foundation if not already configured

This phase builds the private connection from the customer's Azure Virtual Network (VNet) to their on-premise data center.

#### 4.1.1. Step-by-Step: Configuring Azure ExpressRoute if not already in place

Azure ExpressRoute provides the dedicated private connectivity from on-premise to the Azure cloud[^10]
1. **Provision an ExpressRoute Circuit**: In the Azure Portal, create a new ExpressRoute circuit. This requires selecting a provider, a peering location, and a bandwidth SKU. The provider will then provision the Layer 2/Layer 3 connection between your on-premise network and the Microsoft Enterprise Edge (MSEE) routers[^10]
2. **Configure Azure Private Peering**: Once the circuit is provisioned, configure "Azure private peering." This involves setting up a Border Gateway Protocol (BGP) session between your on-premise edge routers and the MSEE routers. You will need to provide a primary and secondary /30 subnet for the peering links and your public BGP ASN[^11]
3. **Create a Virtual Network Gateway**: In your designated "hub" VNet, you must create a special subnet named GatewaySubnet. This subnet must be /27 or larger[^21]. Then, create a new Virtual Network Gateway resource, specifying the Gateway type as
   ExpressRoute and selecting an appropriate SKU[^21]
4. **Create a Connection**: Create a "Connection" resource in Azure that links your Virtual Network Gateway to your ExpressRoute circuit. This final step establishes the routing path between your VNet and the on-premise networks advertised over the ExpressRoute circuit's BGP session[^11]

#### 4.1.2. Step-by-Step: Deploying Azure Private DNS Resolver if not already configured

Azure Private DNS Resolver provides the necessary conditional forwarding capability to resolve on-premise DNS names from within Azure[^15]
1. **Create Dedicated Subnets**: Azure requires dedicated subnets for the resolver's endpoints. In your hub VNet, create two new subnets: one for the inbound endpoint and one for the outbound endpoint. These subnets must be delegated to the Microsoft.Network/dnsResolvers service. This delegation prevents any other resources from being deployed into these subnets, a strict platform requirement with operational impact on VNet planning and IP address management[^15]
2. **Create a DNS Private Resolver**: Deploy the DNS Private Resolver resource into your hub VNet.
3. **Configure an Outbound Endpoint**: Within the resolver resource, create an outbound endpoint and associate it with the dedicated outbound subnet you created[^15]
4. **Create a DNS Forwarding Ruleset**: Create a new DNS forwarding ruleset. Within this ruleset, add a rule for your on-premise domain (e.g., corp.local). Set the destination for this rule to the private IP addresses of your on-premise DNS servers[^44]
5. **Link the Ruleset**: Link the DNS forwarding ruleset to your hub VNet. This activates the rule, causing any DNS queries from resources in that VNet for \*.corp.local to be forwarded via the outbound endpoint to your on-premise DNS servers for resolution[^43]

### Part 4.2: Configuring Snowflake for Outbound Private Connectivity to Azure

This phase mirrors the AWS process, involving a consent-based handshake between Snowflake and the customer's Azure subscription.

#### 4.2.1. Architectural Prerequisite: The Azure Standard Load Balancer and Private Link Service

Similar to the AWS scenario, Snowflake's outbound private link must connect to a service within the customer's VNet, not directly to an on-premise IP. The Azure pattern for this involves an Azure Standard Load Balancer (SLB) and an Azure Private Link Service.

1. **Create a Standard Load Balancer**: Deploy an internal SLB in your hub VNet.
2. **Configure Backend Pool**: Create a backend pool for the SLB. Add the private IP address of the on-premise SQL Server to this pool.
3. **Configure Health Probe and Load Balancing Rule**: Create a health probe to check the availability of the SQL Server port (e.g., TCP 1433). Create a load balancing rule that listens on TCP 1433 on the SLB's frontend IP and forwards traffic to the backend pool.
4. **Create a Private Link Service**: Create a Private Link Service and associate it with the frontend IP configuration of the Standard Load Balancer. This service is what exposes your internal endpoint for private connections from other Azure tenants, such as Snowflake. Note the Resource ID and Alias of the Private Link Service.

#### 4.2.2. Step-by-Step: Provisioning and Approving the Private Endpoint

Provision Endpoint from Snowflake: As the Snowflake ACCOUNTADMIN, execute the SYSTEM$PROVISION\_PRIVATELINK\_ENDPOINT function. The first argument is the full Resource ID of the Azure Private Link Service you created. The second is the FQDN of the private link service, and the third is the sub-resource[^3]. For a custom service, such as an on-premise Oracle database, the sub-resource is a groupId you configured when you set up the private link service.

```sql
USE ROLE ACCOUNTADMIN;SELECT SYSTEM$PROVISION_PRIVATELINK_ENDPOINT(    '/subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.Network/privateLinkServices/<private-link-service-name>', -- Resource ID    'private-link-service-dns',    'groupId');
```

1. **Approve Connection in Azure**: In the Azure Portal, navigate to your Private Link Service. Under "Private endpoint connections," you will find the pending connection request from Snowflake. Approve this request. This action creates a private endpoint network interface in the designated subnet of your hub VNet and establishes the secure link[^7]

#### 4.2.3. Step-by-Step: Creating Snowflake Security and Integration Objects

This process is identical to the AWS scenario from a Snowflake SQL perspective.

Create Snowflake Secret:

```sql
CREATE OR REPLACE SECRET sql_server_creds  TYPE = PASSWORD  USERNAME = 'your_sql_server_user'  PASSWORD = 'your_sql_server_password';
```

Create Snowflake Network Rule but for Azure, the DNS is actually the DNS of the private-link-service, not the Standard Load Balancer. On Azure the Azure Private Link Service acts as the direct entry point and abstraction layer, so you only need to provide its custom DNS name. By using port 0, we are allowing any port and providing flexibility for adding additional databases to the Azure PrivatelinkServer on different port numbers. Azure will still block any ports that have not been specifically authorized.

```sql
CREATE NETWORK RULE IF NOT EXISTS onprem_sql_server_rule_azure  MODE = EGRESS  TYPE = PRIVATE_HOST_PORT  VALUE_LIST = ('private-link-service-dns:0');
```

Create External Access Integration:

```sql
CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS azure_onprem_eai  ALLOWED_NETWORK_RULES = (onprem_sql_server_rule_azure)  ALLOWED_AUTHENTICATION_SECRETS = all  ENABLED = TRUE;
```

### Part 4.3: End-to-End Routing, Security, and Validation on Azure

The final steps involve configuring Azure's network routing and security to permit the traffic flow.

#### 4.3.1. Configuring Azure User-Defined Routes (UDRs)

Azure automatically learns routes from the ExpressRoute gateway. However, it is a best practice to create a Route Table and associate it with the subnet hosting the private endpoint. This route table should have a route for the on-premise CIDR block with the next hop type set to Virtual network gateway. This explicitly directs traffic destined for on-premise to the ExpressRoute connection, ensuring predictable routing behavior[^46]

#### 4.3.2. Defining Network Security Group (NSG) Rules

Network Security Groups are Azure's primary mechanism for stateful packet filtering[^23]
1. Create or modify the NSG associated with the subnet hosting the private endpoint from Snowflake.
2. Add a new **inbound security rule** with the following properties:
   * **Source**: IP Addresses
   * **Source IP addresses/CIDR ranges**: The source IP address range of the Snowflake VNet (obtainable from Snowflake documentation or support).
   * **Source port ranges**: \*
   * **Destination**: IP Addresses
   * **Destination IP addresses/CIDR ranges**: The private IP address of the private endpoint's network interface.
   * **Destination port ranges**: The port for SQL Server (e.g., 1433).
   * **Protocol**: TCP
   * **Action**: Allow
   * **Priority**: A number lower than the default deny rule (e.g., 100).
3. Since NSGs are stateful, a corresponding outbound rule for the return traffic is not required. The platform automatically allows it.

## References

[^3]: Secure Connections with New Outbound Private Link with Snowflake Support in Preview, https://www.snowflake.com/en/engineering-blog/secure-communications-outbound-private-link/
[^7]: External network access and private connectivity on Microsoft Azure, https://docs.snowflake.com/en/developer-guide/external-network-access/creating-using-private-azure
[^10]: Connect an On-Premises Network to Azure using ExpressRoute, https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/expressroute-vpn-failover
[^11]: Link a virtual network to ExpressRoute circuits, https://learn.microsoft.com/en-us/azure/expressroute/expressroute-howto-linkvnet-portal-resource-manager
[^15]: What is Azure DNS Private Resolver?, https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview
[^21]: About ExpressRoute Virtual Network Gateways, https://learn.microsoft.com/en-us/azure/expressroute/expressroute-about-virtual-network-gateways
[^23]: Azure Private Link and Snowflake, https://docs.snowflake.com/en/user-guide/privatelink-azure
[^43]: Azure DNS Private Resolver endpoints and rulesets, https://learn.microsoft.com/en-us/azure/dns/private-resolver-endpoints-rulesets
[^44]: DNS forwarding ruleset for Azure DNS Private Resolver, https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-get-started-portal
[^46]: User-defined routes overview, https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview

