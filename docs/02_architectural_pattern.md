## Chapter 2: Architectural Pattern

This Chapter establishes the foundational concepts and the logical flow of a request from an SPCS container to an on-premise SQL Server. This is not a single connection but a precisely orchestrated chain of interconnected private endpoints, gateways, and DNS resolution mechanisms that must function in concert.

### 2.1. The Connectivity Chain

The flow of a network packet from a Snowpark container to an on-premise database follows a distinct sequence of logical hops across multiple network boundaries. Understanding this end-to-end path is critical for successful implementation and troubleshooting.

1. **Initiation**: A request, such as a SQL query, originates from application code running within a container. This container is hosted on a virtual machine node within a Snowflake Compute Pool, which provides the underlying resources for SPCS[^1]
2. **Snowflake Egress**: The outbound network request is intercepted by the SPCS runtime. Its permission to exit the secure Snowflake environment is governed by a Snowflake External Access Integration (EAI) that has been explicitly associated with the container's service definition. This EAI must be configured for private connectivity[^3]
3. **Cloud Provider Handoff**: The EAI leverages the underlying cloud provider's private link technology. Snowflake provides a private endpoint within its own managed Virtual Network (VNet) / Virtual Private Cloud (VPC). This endpoint then initiates a connection request to a corresponding private endpoint service in the customer's own VNet/VPC. This step represents the critical, consent-based handoff from the Snowflake-managed environment to the customer-managed environment[^3]. The customer's cloud administrator must explicitly approve this connection request, ensuring that the customer retains ultimate control over access to their private network.
4. **Cloud-to-On-Premise Transit**: Once traffic enters the customer's VNet/VPC via the private endpoint, it is subject to the customer's network routing rules. These rules direct the traffic to a central cloud routing hub, such as an AWS Transit Gateway or an Azure Virtual Network Gateway. This gateway, in turn, routes the traffic over a dedicated, private connection—either an AWS Direct Connect or Azure ExpressRoute circuit—that physically links the cloud environment to the on-premise data center[^8]
5. **Final Destination**: Upon arrival at the on-premise network edge router, the packet is routed through the internal corporate network to the final destination: the private IP address of the target SQL Server.

### 2.2. The Parallel DNS Resolution Chain

For the connectivity chain to function, the application code must be able to resolve the hostname of the on-premise SQL Server (e.g., sql-prod.corp.local) to its private IP address. This requires a parallel DNS resolution path that mirrors the network connectivity path.

1. The container code issues a DNS query for the on-premise hostname.
2. This query is first handled by the cloud provider's internal DNS infrastructure available to the Snowflake environment.
3. Because the domain (e.g., corp.local) is not public, the query must be forwarded to the customer's network for resolution. This is achieved through a hybrid DNS service.
4. In AWS, an Amazon Route 53 Resolver Outbound Endpoint, configured with a forwarding rule for the corp.local domain, sends the query across the private network path (via the Transit Gateway and Direct Connect) to the on-premise DNS servers[^12]
5. In Azure, an Azure Private DNS Resolver Outbound Endpoint uses a DNS forwarding ruleset to achieve the same outcome, sending the query over the ExpressRoute connection to the on-premise DNS servers[^15]
6. The on-premises DNS server resolves the hostname to its private IP address, and the response travels back along the same path to the SPCS container. The container can then initiate the TCP connection to the resolved IP address.

The architecture is equally dependent on a correctly configured hybrid DNS strategy as it is on network packet routing. A failure in DNS resolution will prevent the connection from ever being initiated, even if a valid IP route exists.

### 2.3. Snowflake External Access Integrations (EAI)

Outbound connectivity from SPCS is built upon the External Access Integration framework, which comprises three interconnected Snowflake objects. These objects collectively ensure secure and governable access to external endpoints.

* **Secrets**: The CREATE SECRET command is used to create a secure object within Snowflake that stores sensitive information, such as the username and password for the on-premise SQL Server. The code within the SPCS container can then reference this secret by a logical name, retrieving the credentials at runtime without them ever being exposed in code, logs, or service definitions. This is a fundamental security best practice that decouples authentication from application logic[^17]
* **Network Rules**: The CREATE NETWORK RULE command defines a schema-level object that specifies the allowed network destinations. For this private connectivity architecture, the rule must be configured with MODE \= EGRESS to permit outbound traffic. The most critical parameter is TYPE \= PRIVATE\_HOST\_PORT, which explicitly instructs Snowflake to utilize the outbound private link feature. The VALUE\_LIST for this rule must contain the fully qualified domain name (FQDN) of the target endpoint that is resolvable within the customer's private network. By specifying port 0, we whitelist using any port number, allowing additional ports to later map to additional databases. Other network controls on the cloud provider side will provide limits on port numbers anyways.[^3]
* **Integration Object**: The CREATE EXTERNAL ACCESS INTEGRATION command creates an account-level object that bundles one or more network rules and secrets. It specifies the ALLOWED\_NETWORK\_RULES and ALLOWED\_AUTHENTICATION\_SECRETS that can be used by any function, procedure, or service that references it. This integration object is the entity to which privileges are granted, allowing administrators to control which roles can create services that access specific external endpoints.[^5]

### Table 2.1: Comparison of Core Services in AWS and Azure Solutions

For architects, the table below offers a comparative overview of key cloud service solutions, translating concepts to illustrate the parallel nature of the two architectures.

| Function | AWS Service | Azure Service | Key Role in Architecture |
| :---: | :---: | :---: | :---- |
| **Dedicated On-Premise Link** | AWS Direct Connect | Azure ExpressRoute | Provides the secure, private, high-bandwidth physical or logical connection between the on-premise data center and the cloud provider's network backbone[^8] |
| **Cloud Network Hub/Router** | AWS Transit Gateway | Azure Virtual Network Gateway | Acts as the central routing hub in the cloud, connecting the customer's VPC/VNet to the Direct Connect/ExpressRoute circuit and enabling scalable routing[^9] |
| **Hybrid DNS Resolution** | Amazon Route 53 Resolver | Azure Private DNS Resolver | Forwards DNS queries for on-premise hostnames from the cloud environment to the on-premise DNS servers, enabling private name resolution across the hybrid network[^13] |
| **Cloud Network Proxy** | Network Load Balancer | Azure Standard Load Balancer | The load balancer proxies traffic based on the port to cloud or on-premise databases and is attached to the private endpoint. |
| **Cloud-Side Private Endpoint** | VPC Interface Endpoint | Azure Private Endpoint | Provides a network interface with a private IP address in the customer's VPC/VNet that serves as the secure entry point for traffic originating from Snowflake[^22] |
| **Snowflake-to-Cloud Connection** | AWS PrivateLink | Azure Private Link / Azure Private Link Service | The underlying technology that enables the secure, private, unidirectional connection between the Snowflake-managed VNet/VPC and the customer's VNet/VPC[^22] |
| **Network Traffic Filtering** | Security Groups & Network ACLs | Network Security Groups (NSGs) | Provide stateful (Security Groups/NSGs) and stateless (NACLs) packet filtering to control traffic flow to and from the private endpoint and other network interfaces, forming a critical security layer[^22] |

## References

[^1]: Snowpark Container Services - Snowflake Documentation, https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview
[^3]: Secure Connections with New Outbound Private Link with Snowflake Support in Preview, https://www.snowflake.com/en/engineering-blog/secure-communications-outbound-private-link/
[^5]: Creating and using an external access integration | Snowflake Documentation, https://docs.snowflake.com/en/developer-guide/external-network-access/creating-using-external-network-access
[^8]: AWS Direct Connect - Building a Scalable and Secure Multi-VPC AWS Network Infrastructure, https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/direct-connect.html
[^9]: How AWS Transit Gateway works - Amazon VPC, https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html
[^12]: Streamline hybrid DNS management using Amazon Route 53 Resolver endpoints delegation, https://aws.amazon.com/blogs/networking-and-content-delivery/streamline-hybrid-dns-management-using-amazon-route-53-resolver-endpoints-delegation/
[^13]: How to achieve DNS high availability with Route 53 Resolver endpoints, https://aws.amazon.com/blogs/networking-and-content-delivery/how-to-achieve-dns-high-availability-with-route-53-resolver-endpoints/
[^15]: What is Azure DNS Private Resolver?, https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview
[^17]: Configure external access for services in an app with containers - Snowflake Documentation, https://docs.snowflake.com/en/developer-guide/native-apps/container-eai-example
[^22]: AWS PrivateLink and Snowflake, https://docs.snowflake.com/en/user-guide/admin-security-privatelink

