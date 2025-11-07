# Network Flow Diagrams

This document contains all network flow diagrams for the SPCS to On-Premise connectivity architecture. These diagrams use Mermaid syntax and render automatically in GitHub.

## Diagram 1: SPCS Egress Flow

This diagram shows the complete egress path from an SPCS container through the Snowflake environment to the customer VPC/VNet.

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#FF6B35','primaryTextColor':'#fff','primaryBorderColor':'#7C0000','lineColor':'#F8B229','secondaryColor':'#004E89','tertiaryColor':'#fff'}}}%%
flowchart TB
    subgraph Snowflake["Snowflake Environment<br/>(Snowflake-Managed)"]
        Container["SPCS Container<br/>Application Code"]
        Pool["Compute Pool<br/>VM Infrastructure"]
        SVPC["Snowflake VPC/VNet<br/>Snowflake's Network"]
        EAI{"External Access<br/>Integration (EAI)<br/>Policy Check"}
    end
    
    subgraph Customer["Customer Environment<br/>(Customer-Managed)"]
        PL["PrivateLink<br/>Connection"]
        CVPC["Customer VPC/VNet<br/>Private Endpoint"]
    end
    
    Container -->|"1. SQL Query Initiated"| Pool
    Pool -->|"2. Network Request"| SVPC
    SVPC -->|"3. Egress Attempt"| EAI
    EAI -->|"4. ALLOWED<br/>(Private Host Port)"| PL
    EAI -.->|"DENIED<br/>(No EAI/Wrong Type)"| Blocked["❌ Connection Blocked"]
    PL -->|"5. Private Connection"| CVPC
    
    style Snowflake fill:#FF6B35,stroke:#7C0000,color:#fff
    style Customer fill:#004E89,stroke:#003D73,color:#fff
    style EAI fill:#FFD700,stroke:#B8860B,color:#000
    style Blocked fill:#DC143C,stroke:#8B0000,color:#fff
    style PL fill:#32CD32,stroke:#228B22,color:#fff
    
    note1["🔒 Security Boundary:<br/>EAI enforces explicit<br/>egress control"]
    EAI -.-> note1
    style note1 fill:#FFF9E6,stroke:#FFD700,color:#000
```

**Key Points:**
- **Security Boundary**: EAI acts as the critical policy enforcement point
- **Explicit Allow**: Containers have no outbound access by default
- **Private Only**: TYPE=PRIVATE_HOST_PORT required for this architecture
- **Consent-Based**: Customer must approve PrivateLink connection

---

## Diagram 2: PrivateLink Handshake (Administrative Setup)

This state diagram shows the 8-step administrative process to establish a PrivateLink connection between Snowflake and the customer account.

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#FF6B35','primaryTextColor':'#fff','secondaryColor':'#004E89','tertiaryColor':'#fff'}}}%%
stateDiagram-v2
    [*] --> NLB_Created: 1. Customer creates NLB<br/>with on-premise DB IP in target group
    
    NLB_Created --> EndpointService_Created: 2. Customer creates<br/>VPC Endpoint Service<br/>(AWS) or Private Link Service (Azure)
    
    EndpointService_Created --> Principal_Authorized: 3. Customer authorizes<br/>Snowflake account principal<br/>in allowed principals list
    
    Principal_Authorized --> Connection_Requested: 4. Snowflake calls<br/>SYSTEM$PROVISION_PRIVATELINK_ENDPOINT<br/>(initiates connection request)
    
    Connection_Requested --> Approval_Pending: 5. Connection appears as<br/>"Pending" in customer console
    
    state Approval_Pending {
        [*] --> Waiting
        Waiting --> Approved: Customer approves
        Waiting --> Rejected: Customer rejects
    }
    
    Approval_Pending --> Endpoint_Creating: Connection approved
    Approval_Pending --> [*]: Connection rejected ❌
    
    Endpoint_Creating --> Endpoint_Available: 6. VPC Endpoint/Private Endpoint<br/>created with ENIs in customer VPC
    
    Endpoint_Available --> DNS_Configured: 7. Customer adds endpoint DNS<br/>to Snowflake Network Rule
    
    DNS_Configured --> Connection_Ready: 8. End-to-end connectivity<br/>established ✅
    
    Connection_Ready --> [*]: Ready for traffic
    
    note right of Connection_Requested
        Snowflake initiates request
        but customer retains control
        via approval workflow
    end note
    
    note right of Endpoint_Available
        Private IP assigned from
        customer VPC CIDR range
    end note
```

**Key Points:**
- **Bidirectional Consent**: Both Snowflake and customer must take explicit actions
- **Customer Control**: Customer approval required at step 5, retaining network sovereignty
- **Private IPs**: Endpoint gets IP from customer's VPC CIDR, not public IP
- **Failure Points**: Connection can fail at authorization (step 3) or approval (step 5)

---

## Diagram 3: PrivateLink Runtime Connection Flow

This diagram shows how traffic flows through the PrivateLink connection during runtime, including health checks and load balancing.

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#FF6B35','secondaryColor':'#004E89','tertiaryColor':'#fff'}}}%%
flowchart LR
    subgraph Snowflake["Snowflake Environment"]
        SF["Snowflake<br/>SPCS Container"]
    end
    
    subgraph PrivateLink["PrivateLink Service"]
        PL["AWS PrivateLink /<br/>Azure Private Link<br/>(Managed Connection)"]
    end
    
    subgraph Customer["Customer VPC/VNet"]
        VPCEndpoint["VPC Endpoint /<br/>Private Endpoint<br/>(Private IP: 172.16.10.50)"]
        
        subgraph LoadBalancer["Network/Standard Load Balancer"]
            LB["Load Balancer<br/>Frontend"]
            Health{"Health Check<br/>TCP Port 1433<br/>Every 30 sec"}
            Algorithm["Routing Algorithm<br/>(Flow Hash)"]
        end
        
        subgraph OnPremProxy["Hybrid Connection"]
            TGW["Transit Gateway /<br/>VNet Gateway"]
            DC["Direct Connect /<br/>ExpressRoute"]
        end
        
        DB["On-Premise<br/>Database<br/>10.50.100.25:1433"]
    end
    
    SF -->|"1. SQL Query<br/>(Private Connection)"| PL
    PL -->|"2. Routes to"| VPCEndpoint
    VPCEndpoint -->|"3. Forwards to"| LB
    
    LB --> Health
    Health -->|"Healthy ✅"| Algorithm
    Health -.->|"Unhealthy ❌<br/>Remove from pool"| HealthFail["Target Unavailable"]
    
    Algorithm -->|"4. Selects target<br/>(5-tuple hash)"| TGW
    TGW -->|"5. Routes via"| DC
    DC -->|"6. Delivers to"| DB
    
    DB -->|"7. Response"| DC
    DC -->|"8. Return path"| TGW
    TGW --> LB
    LB -->|"9. Back to"| VPCEndpoint
    VPCEndpoint -->|"10. Via PrivateLink"| PL
    PL -->|"11. Response delivered"| SF
    
    style Snowflake fill:#FF6B35,stroke:#7C0000,color:#fff
    style Customer fill:#004E89,stroke:#003D73,color:#fff
    style PrivateLink fill:#32CD32,stroke:#228B22,color:#fff
    style Health fill:#FFD700,stroke:#B8860B,color:#000
    style HealthFail fill:#DC143C,stroke:#8B0000,color:#fff
    style DB fill:#4B0082,stroke:#2F0052,color:#fff
```

**Key Points:**
- **Stateful Connection**: Return path automatically allowed by stateful security groups/NSGs
- **Health Monitoring**: Load balancer continuously checks target health (default 30 sec interval)
- **Flow Hash**: 5-tuple (source IP, source port, dest IP, dest port, protocol) determines target selection
- **Session Persistence**: Same 5-tuple always routes to same target (stickiness)
- **Failover**: If health check fails, target removed from pool within ~90 seconds (3 failed checks)

---

## Diagram 4: Complete DNS Query Resolution Flow

This sequence diagram shows the detailed 15-step DNS resolution process for resolving on-premise hostnames from Snowflake.

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#FF6B35','secondaryColor':'#004E89','tertiaryColor':'#fff'}}}%%
sequenceDiagram
    autonumber
    
    participant Container as SPCS Container
    participant SnowflakeDNS as Snowflake DNS Resolver
    participant PrivateLink as PrivateLink Connection
    participant VPCDNS as Customer VPC DNS<br/>(.2 Address)
    participant R53 as Route 53 Outbound /<br/>Azure DNS Outbound
    participant TGW as Transit Gateway /<br/>VNet Gateway
    participant DC as Direct Connect /<br/>ExpressRoute
    participant OnPremDNS as On-Premise<br/>DNS Server
    
    rect rgb(255, 245, 230)
    Note over Container,OnPremDNS: DNS Query Phase (Steps 1-13)
    Container->>SnowflakeDNS: DNS Query: sql-prod.corp.local<br/>(UDP port 53)
    SnowflakeDNS->>SnowflakeDNS: Check: Not public domain
    SnowflakeDNS->>PrivateLink: Forward query to customer VPC<br/>(via PrivateLink network path)
    PrivateLink->>VPCDNS: Query arrives at VPC DNS resolver
    VPCDNS->>VPCDNS: Evaluate domain: *.corp.local
    VPCDNS->>VPCDNS: Match forwarding rule for corp.local
    VPCDNS->>R53: Forward to outbound endpoint<br/>(UDP 53 to on-prem DNS IPs)
    R53->>TGW: Query routed to Transit Gateway
    TGW->>DC: Query traverses hybrid connection
    DC->>OnPremDNS: Query reaches on-premise network<br/>On-prem DNS: 192.168.1.10
    OnPremDNS->>OnPremDNS: Resolve sql-prod.corp.local<br/>→ 10.50.100.25 (A record)
    end
    
    rect rgb(230, 245, 255)
    Note over Container,OnPremDNS: DNS Response Phase (Steps 11-15)
    OnPremDNS-->>DC: Response: 10.50.100.25<br/>(UDP 53, TTL: 3600 sec)
    DC-->>TGW: Response via hybrid connection
    TGW-->>R53: Response to outbound endpoint
    R53-->>VPCDNS: Response to VPC DNS
    VPCDNS-->>VPCDNS: Cache response (TTL: 3600 sec)
    VPCDNS-->>PrivateLink: Response via PrivateLink
    PrivateLink-->>SnowflakeDNS: Response to Snowflake DNS
    SnowflakeDNS-->>Container: DNS Response: 10.50.100.25
    end
    
    rect rgb(245, 255, 230)
    Note over Container,OnPremDNS: Connection Initiation (Step 15)
    Container->>Container: Initiate TCP connection<br/>to 10.50.100.25:1433
    end
    
    Note right of VPCDNS: If response > 512 bytes,<br/>DNS retries over TCP port 53
    Note right of OnPremDNS: Authoritative for<br/>*.corp.local domain
    Note right of SnowflakeDNS: Caching occurs at<br/>multiple layers
```

**Key Points:**
- **UDP to TCP Fallback**: DNS starts with UDP (fast), falls back to TCP if response exceeds 512 bytes
- **Caching**: Responses cached at VPC DNS and Snowflake DNS layers (respects TTL)
- **TTL Impact**: Low TTL (e.g., 60 sec) means frequent re-queries; high TTL (e.g., 3600 sec) reduces query load
- **Critical Dependency**: PrivateLink must be active for DNS forwarding to work
- **Authoritative Requirement**: On-premise DNS must be authoritative for the private domain

---

## Diagram 5: Load Balancer Traffic and Health Check Flow

This diagram shows the internal logic of the Network/Standard Load Balancer, including health checks and routing decisions.

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#FF6B35','secondaryColor':'#004E89','tertiaryColor':'#fff'}}}%%
flowchart TB
    subgraph Incoming["Traffic from VPC Endpoint"]
        Request["Incoming Request<br/>Src: Snowflake VNet<br/>Dst: 172.16.10.50:1433"]
    end
    
    subgraph NLB["Network/Standard Load Balancer"]
        Frontend["Frontend IP<br/>172.16.10.50"]
        
        FlowHash{"Flow Hash Algorithm<br/>(5-Tuple Hash)<br/>Src IP + Src Port +<br/>Dst IP + Dst Port +<br/>Protocol"}
        
        subgraph HealthChecks["Health Check System"]
            HC1["Health Check Target 1<br/>TCP 10.50.100.25:1433<br/>Interval: 30 sec<br/>Timeout: 10 sec"]
            HC2["Health Check Target 2<br/>TCP 10.50.100.26:1433<br/>Interval: 30 sec<br/>Timeout: 10 sec"]
        end
        
        subgraph TargetPool["Target Pool / Backend Pool"]
            Target1["Target 1<br/>10.50.100.25:1433<br/>Status: Healthy ✅"]
            Target2["Target 2<br/>10.50.100.26:1433<br/>Status: Healthy ✅"]
        end
    end
    
    subgraph Decision["Routing Decision"]
        SelectTarget{"Select Target<br/>Based on Hash"}
    end
    
    subgraph OnPrem["On-Premise Database Servers"]
        DB1["Primary DB<br/>10.50.100.25:1433"]
        DB2["Secondary DB<br/>10.50.100.26:1433"]
    end
    
    Request --> Frontend
    Frontend --> FlowHash
    
    HC1 -.->|"Continuous monitoring"| Target1
    HC2 -.->|"Continuous monitoring"| Target2
    
    HC1 -->|"3 consecutive successes<br/>= Healthy"| Target1
    HC1 -.->|"3 consecutive failures<br/>= Unhealthy"| Unhealthy1["❌ Remove from pool"]
    
    HC2 -->|"3 consecutive successes<br/>= Healthy"| Target2
    HC2 -.->|"3 consecutive failures<br/>= Unhealthy"| Unhealthy2["❌ Remove from pool"]
    
    FlowHash --> SelectTarget
    SelectTarget --> Target1
    SelectTarget --> Target2
    
    Target1 -->|"Forward request"| DB1
    Target2 -->|"Forward request"| DB2
    
    DB1 -.->|"Response"| Target1
    DB2 -.->|"Response"| Target2
    
    Target1 -.->|"Return via same path"| Frontend
    Target2 -.->|"Return via same path"| Frontend
    
    style NLB fill:#004E89,stroke:#003D73,color:#fff
    style HealthChecks fill:#FFD700,stroke:#B8860B,color:#000
    style Unhealthy1 fill:#DC143C,stroke:#8B0000,color:#fff
    style Unhealthy2 fill:#DC143C,stroke:#8B0000,color:#fff
    style DB1 fill:#4B0082,stroke:#2F0052,color:#fff
    style DB2 fill:#4B0082,stroke:#2F0052,color:#fff
    
    note1["Health Check Thresholds:<br/>✅ Healthy: 3 consecutive successes<br/>❌ Unhealthy: 3 consecutive failures<br/>⏱️ Total failover time: ~90 seconds"]
    HealthChecks -.-> note1
    style note1 fill:#FFF9E6,stroke:#FFD700,color:#000
```

**Key Points:**
- **Flow Hash**: 5-tuple hash ensures same client connection always routes to same target (session affinity)
- **Health Check Frequency**: Every 30 seconds by default (configurable 10-300 seconds)
- **Failure Detection**: 3 consecutive failures = ~90 seconds until target removed
- **Recovery**: 3 consecutive successes required to mark target healthy again
- **High Availability**: Multiple targets provide automatic failover if one fails

---

## Diagram 6: Direct Connect / ExpressRoute Packet Traversal

This diagram shows packet traversal over the hybrid connection, including BGP routing and the encryption layer (or lack thereof).

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#FF6B35','secondaryColor':'#004E89','tertiaryColor':'#fff'}}}%%
flowchart LR
    subgraph Cloud["Cloud Environment (AWS/Azure)"]
        VPC["Customer VPC/VNet<br/>CIDR: 172.16.0.0/16"]
        RouteTable["Route Table<br/>Destination: 10.0.0.0/8<br/>Target: Transit Gateway"]
        TGW["Transit Gateway (AWS) /<br/>Virtual Network Gateway (Azure)"]
        
        subgraph BGP_Cloud["BGP Session (Cloud Side)"]
            CloudBGP["Cloud BGP Router<br/>AS: 64512<br/>Advertises: 172.16.0.0/16"]
        end
    end
    
    subgraph HybridLink["Hybrid Connection"]
        direction TB
        DC["AWS Direct Connect /<br/>Azure ExpressRoute<br/>(Physical Circuit)"]
        
        EncryptionLayer{"Encryption Layer?"}
        NoEncrypt["❌ NOT Encrypted<br/>by Default"]
        WithEncrypt["✅ Optional:<br/>VPN over DC/ER<br/>or MACsec"]
    end
    
    subgraph Provider["Provider Network"]
        Backbone["AWS/Microsoft<br/>Provider Backbone<br/>(Private, not Public Internet)"]
    end
    
    subgraph OnPremise["On-Premise Data Center"]
        EdgeRouter["Edge Router<br/>BGP Peer"]
        
        subgraph BGP_OnPrem["BGP Session (On-Prem Side)"]
            OnPremBGP["On-Premise BGP Router<br/>AS: 65001<br/>Advertises: 10.0.0.0/8"]
        end
        
        Firewall["Perimeter Firewall"]
        InternalNet["Internal Network<br/>10.0.0.0/8"]
    end
    
    VPC --> RouteTable
    RouteTable -->|"Lookup: 10.50.100.25<br/>Match: 10.0.0.0/8"| TGW
    TGW --> CloudBGP
    CloudBGP <-.->|"BGP Peering<br/>AS 64512 ↔ AS 65001<br/>Exchange Routes"| OnPremBGP
    CloudBGP --> DC
    
    DC --> EncryptionLayer
    EncryptionLayer -->|"Default Path"| NoEncrypt
    EncryptionLayer -.->|"Enhanced Security"| WithEncrypt
    
    NoEncrypt --> Backbone
    WithEncrypt --> Backbone
    
    Backbone --> OnPremBGP
    OnPremBGP --> EdgeRouter
    EdgeRouter --> Firewall
    Firewall -->|"Allow: 172.16.0.0/16<br/>→ 10.50.100.25:1433"| InternalNet
    
    style Cloud fill:#004E89,stroke:#003D73,color:#fff
    style OnPremise fill:#4B0082,stroke:#2F0052,color:#fff
    style HybridLink fill:#32CD32,stroke:#228B22,color:#fff
    style Provider fill:#808080,stroke:#505050,color:#fff
    style NoEncrypt fill:#DC143C,stroke:#8B0000,color:#fff
    style WithEncrypt fill:#32CD32,stroke:#228B22,color:#fff
    style BGP_Cloud fill:#FFD700,stroke:#B8860B,color:#000
    style BGP_OnPrem fill:#FFD700,stroke:#B8860B,color:#000
    
    warning["⚠️ SECURITY WARNING:<br/>Direct Connect and ExpressRoute<br/>are PRIVATE but NOT ENCRYPTED<br/>by default. Add VPN or MACsec<br/>for sensitive data."]
    NoEncrypt -.-> warning
    style warning fill:#FFF9E6,stroke:#DC143C,color:#DC143C
```

**Key Points:**
- **Private, Not Public**: Traffic never traverses public internet, uses provider backbone
- **NOT Encrypted by Default**: Data sent in cleartext over provider network (security gap)
- **BGP Dynamic Routing**: Routes automatically exchanged, enables failover and redundancy
- **Autonomous Systems (AS)**: BGP uses AS numbers to identify routers and prevent loops
- **Encryption Options**: VPN over DC/ER (more flexible) or MACsec (faster, limited availability)
- **Performance**: Direct Connect/ExpressRoute provides consistent latency and high bandwidth

---

## Diagram 7: On-Premise Network Ingress Flow

This diagram shows the detailed path a packet takes through the on-premise network, including all security layers.

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#FF6B35','secondaryColor':'#004E89','tertiaryColor':'#fff'}}}%%
flowchart TB
    subgraph Entry["From Hybrid Connection"]
        Incoming["Packet from Cloud<br/>Src: 172.16.10.50<br/>Dst: 10.50.100.25:1433"]
    end
    
    subgraph OnPrem["On-Premise Network"]
        EdgeRouter["1. Edge Router<br/>Routing table lookup<br/>Route to DB subnet"]
        
        PerimeterFW["2. Perimeter Firewall<br/>(Next-Gen Firewall/NGFW)"]
        
        subgraph FirewallRules["Firewall Rules"]
            Rule1["✅ Allow: 172.16.0.0/16<br/>→ 10.50.100.25:1433<br/>Protocol: TCP"]
            Rule2["❌ Deny: All other traffic<br/>(Default Deny)"]
        end
        
        DMZ["3. DMZ / Transit Network<br/>(Optional)<br/>172.20.10.0/24"]
        
        InternalFW["4. Internal Firewall<br/>(Database Tier Protection)"]
        
        subgraph NetworkSeg["Network Segmentation"]
            WebTier["Web Tier<br/>172.20.0.0/24"]
            AppTier["App Tier<br/>172.20.5.0/24"]
            DBTier["5. Database Tier<br/>10.50.100.0/24<br/>(Most Restricted)"]
        end
        
        subgraph DBServer["6. Database Server"]
            NIC["Server NIC<br/>10.50.100.25"]
            HostFW["OS Firewall<br/>(Windows Firewall /<br/>iptables)"]
            Listener["7. Database Listener<br/>SQL Server: Port 1433<br/>Oracle: Port 1521<br/>MySQL: Port 3306<br/>PostgreSQL: Port 5432"]
        end
    end
    
    Incoming --> EdgeRouter
    EdgeRouter -->|"Route exists:<br/>10.50.100.0/24<br/>via internal gateway"| PerimeterFW
    
    PerimeterFW --> Rule1
    PerimeterFW -.-> Rule2
    
    Rule1 -->|"Pass"| DMZ
    Rule2 -.->|"Block"| Blocked["❌ Traffic Blocked<br/>Connection Timeout"]
    
    DMZ --> InternalFW
    InternalFW -->|"Pass to DB tier only"| DBTier
    InternalFW -.->|"Block lateral movement"| Blocked2["❌ Blocked to<br/>Web/App Tiers"]
    
    DBTier --> NIC
    NIC --> HostFW
    
    HostFW -->|"Allow TCP 1433<br/>from 172.16.0.0/16"| Listener
    HostFW -.->|"Block other sources"| Blocked3["❌ Host-level block"]
    
    Listener -->|"Accept connection<br/>Authenticate user"| DBProcess["Database Process<br/>SQL query execution"]
    
    style OnPrem fill:#4B0082,stroke:#2F0052,color:#fff
    style FirewallRules fill:#FFD700,stroke:#B8860B,color:#000
    style NetworkSeg fill:#004E89,stroke:#003D73,color:#fff
    style DBServer fill:#4B0082,stroke:#2F0052,color:#fff
    style Blocked fill:#DC143C,stroke:#8B0000,color:#fff
    style Blocked2 fill:#DC143C,stroke:#8B0000,color:#fff
    style Blocked3 fill:#DC143C,stroke:#8B0000,color:#fff
    style Rule1 fill:#32CD32,stroke:#228B22,color:#fff
    style Rule2 fill:#DC143C,stroke:#8B0000,color:#fff
    
    security["🔒 Defense-in-Depth:<br/>Multiple security layers<br/>protect the database:<br/>• Perimeter Firewall<br/>• Internal Firewall<br/>• Network Segmentation<br/>• Host Firewall<br/>• Listener Authentication"]
    DBServer -.-> security
    style security fill:#FFF9E6,stroke:#FFD700,color:#000
```

**Key Points:**
- **Defense-in-Depth**: Multiple security layers, not single point of failure
- **Default Deny**: Firewalls configured to deny all except explicit allow rules
- **Network Segmentation**: Database tier isolated from other tiers (web, app)
- **Least Privilege**: Only specific source CIDRs allowed, only specific database port open
- **Host-Based Security**: OS firewall provides additional protection at server level
- **Common Failure Point**: Perimeter firewall blocking (most common issue during initial setup)

---

## Diagram 8: End-to-End Integration (Complete Flow)

This comprehensive diagram shows the complete path from SPCS to on-premise database with both SQL data path (solid lines) and DNS resolution path (dashed lines) shown simultaneously.

```mermaid
%%{init: {'theme':'base', 'themeVariables': { 'primaryColor':'#FF6B35','secondaryColor':'#004E89','tertiaryColor':'#fff'}}}%%
flowchart TB
    subgraph Snowflake["Snowflake Environment (Snowflake-Managed)"]
        Container["SPCS Container<br/>Application"]
        SnowflakeDNS["Snowflake DNS"]
        SnowflakeVPC["Snowflake VPC/VNet"]
        EAI["External Access<br/>Integration"]
    end
    
    subgraph PrivateLinkLayer["PrivateLink Connection Layer"]
        PL["AWS PrivateLink /<br/>Azure Private Link<br/>(Cross-Account Private Connection)"]
    end
    
    subgraph CustomerCloud["Customer Cloud Environment (Customer-Managed)"]
        VPCEndpoint["VPC Endpoint /<br/>Private Endpoint<br/>(Private IP)"]
        
        VPCDNS["VPC DNS Resolver<br/>(.2 Address)"]
        
        NLB["Network Load Balancer /<br/>Standard Load Balancer<br/>(Proxy)"]
        
        DNSOutbound["Route 53 Outbound /<br/>Azure DNS Outbound<br/>Resolver"]
        
        TGW["Transit Gateway /<br/>Virtual Network Gateway<br/>(Cloud Router)"]
        
        DC["Direct Connect /<br/>ExpressRoute<br/>(Hybrid Link)"]
    end
    
    subgraph OnPremise["On-Premise Data Center (Customer-Managed)"]
        EdgeRouter["Edge Router"]
        OnPremDNS["On-Premise<br/>DNS Server"]
        PerimeterFW["Perimeter Firewall"]
        InternalNet["Internal Network"]
        DBServer["Database Server<br/>10.50.100.25:1433"]
    end
    
    %% SQL Data Path (Solid Lines)
    Container -->|"1. SQL Query"| SnowflakeVPC
    SnowflakeVPC -->|"2. EAI Check"| EAI
    EAI -->|"3. Allowed"| PL
    PL -->|"4. Private Connection"| VPCEndpoint
    VPCEndpoint -->|"5. Forward"| NLB
    NLB -->|"6. Route"| TGW
    TGW -->|"7. Hybrid Link"| DC
    DC -->|"8. To On-Prem"| EdgeRouter
    EdgeRouter -->|"9. Route"| PerimeterFW
    PerimeterFW -->|"10. Allow Rule"| InternalNet
    InternalNet -->|"11. Deliver"| DBServer
    
    %% DNS Path (Dashed Lines)
    Container -.->|"A. DNS Query:<br/>sql-prod.corp.local"| SnowflakeDNS
    SnowflakeDNS -.->|"B. Forward via<br/>PrivateLink"| PL
    PL -.->|"C. DNS to VPC"| VPCDNS
    VPCDNS -.->|"D. Forwarding Rule<br/>Match: *.corp.local"| DNSOutbound
    DNSOutbound -.->|"E. Query via TGW"| TGW
    TGW -.->|"F. Query via DC/ER"| DC
    DC -.->|"G. To On-Prem"| EdgeRouter
    EdgeRouter -.->|"H. To DNS Server"| OnPremDNS
    OnPremDNS -.->|"I. Response:<br/>10.50.100.25"| EdgeRouter
    EdgeRouter -.->|"J. Response Path<br/>(Reverse)"| Container
    
    %% Response Paths
    DBServer -.->|"12. SQL Response<br/>(Return Path)"| Container
    
    style Snowflake fill:#FF6B35,stroke:#7C0000,color:#fff
    style CustomerCloud fill:#004E89,stroke:#003D73,color:#fff
    style OnPremise fill:#4B0082,stroke:#2F0052,color:#fff
    style PrivateLinkLayer fill:#32CD32,stroke:#228B22,color:#fff
    
    legend["Legend:<br/>━━━ SQL Data Path<br/>┈┈┈ DNS Resolution Path<br/>🔵 Snowflake-Managed<br/>🟠 Customer-Managed Cloud<br/>🟣 Customer-Managed On-Prem"]
    style legend fill:#FFF9E6,stroke:#000,color:#000
    
    troubleshoot["🔧 Troubleshooting Checkpoints:<br/>1. EAI configured? (Step 2)<br/>2. PrivateLink approved? (Step 4)<br/>3. NLB healthy targets? (Step 5)<br/>4. TGW routes correct? (Step 6)<br/>5. DC/ER BGP up? (Step 7)<br/>6. Firewall rules allow? (Step 10)<br/>7. DNS forwarding configured? (Step D)<br/>8. On-prem DNS authoritative? (Step H)"]
    style troubleshoot fill:#FFF9E6,stroke:#DC143C,color:#000
```

**Key Points:**
- **Dual Paths**: SQL data (solid) and DNS (dashed) paths shown simultaneously
- **Critical Dependencies**: DNS must resolve before SQL connection can be initiated
- **8 Troubleshooting Checkpoints**: Common failure points numbered for diagnostics
- **Ownership Boundaries**: Clear visual separation of Snowflake-managed vs customer-managed components
- **Bidirectional Flow**: Forward (request) and return (response) paths both critical
- **Security Layers**: Multiple security boundaries crossed (EAI, PrivateLink, firewall, listener)

---

## Diagram Usage Notes

### Color Coding Convention
- **Orange (#FF6B35)**: Snowflake-managed components
- **Blue (#004E89)**: Customer-managed cloud components
- **Green (#32CD32)**: PrivateLink/secure connections
- **Purple (#4B0082)**: On-premise components
- **Gold (#FFD700)**: Policy/security decision points
- **Red (#DC143C)**: Blocked/failed paths

### Diagram Maintenance
These diagrams are text-based (Mermaid syntax) and version-controlled alongside the documentation. When architecture changes occur:
1. Update the relevant diagram(s) in this file
2. Ensure color coding remains consistent
3. Update any cross-references in main documentation chapters
4. Test rendering in GitHub preview before committing

### Viewing Diagrams
- **In GitHub**: Diagrams render automatically in markdown preview and published pages
- **In VS Code**: Install "Markdown Preview Mermaid Support" extension
- **In Other Editors**: Most modern markdown editors support Mermaid natively or via plugin

### Exporting Diagrams
To export diagrams as images (PNG/SVG) for use in presentations or other documents:
1. Use [Mermaid Live Editor](https://mermaid.live/)
2. Copy diagram code from this file
3. Export as PNG or SVG from the editor
4. Alternatively, use `mermaid-cli` tool for batch export

---

*Last Updated: 2025-11-07*  
*Diagram Count: 8*  
*Style: Mermaid (GitHub-native)*

