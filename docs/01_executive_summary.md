## Chapter 1: Executive Summary

### Problem Statement

Snowflake Snowpark Container Services (SPCS) allows customers to run complex data applications like Openflow, machine learning models, and other long-running services directly on their data.[^1] However, a significant portion of critical enterprise data often resides in Microsoft SQL Server, Oracle, Teradata, and other servers in on-premise data centers. By default, SPCS containers are deployed within an isolated environment with no outbound network access, but they can also be configured to allow containers to securely query and interact with on-premise databases without exposing sensitive systems to the public internet.[^2]

### Solution Overview

The solution details an architectural blueprint and a step-by-step implementation guide. Its purpose is to establish a secure, private, and high-performance network path from Snowflake Snowpark Container Services to on-premise databases. The solution employs a multi-layered architecture to create an end-to-end private channel, ensuring all network traffic stays within the respective cloud provider's backbone and the customer's private network, thus completely avoiding the public internet. This is accomplished by integrating Snowflake's outbound private connectivity features with the hybrid networking capabilities of both Amazon Web Services (AWS) and Microsoft Azure.

### Key Technologies

The primary Snowflake component in this architecture is the External Access Integration (EAI) feature, specifically its capability for outbound private connectivity, which is available for Business Critical edition accounts or higher.[^4] This feature initiates a secure connection from Snowflake's environment to the customer's cloud environment. This connection then serves as the entry point to a dedicated hybrid network path built using cloud services. For AWS environments, the solution utilizes AWS PrivateLink, AWS Transit Gateway, and AWS Direct Connect. For Azure environments, the equivalent stack consists of Azure Private Link, Azure Virtual Network Gateway, and Azure ExpressRoute. In both scenarios, a hybrid Domain Name System (DNS) resolution strategy, using Amazon Route 53 Resolver or Azure Private DNS Resolver, is used to allow Snowflake services to connect to on-premise servers.

## References

[^1]: Snowpark Container Services - Snowflake Documentation, https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview
[^2]: Snowpark Container Services 101: A Complete Overview (2025) - Chaos Genius, https://www.chaosgenius.io/blog/snowpark-container-services/
[^4]: External network access overview - Snowflake Documentation, https://docs.snowflake.com/en/developer-guide/external-network-access/external-network-access-overview

