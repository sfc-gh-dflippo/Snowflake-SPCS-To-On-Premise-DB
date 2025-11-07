# Chapter 7: Troubleshooting Guide - Azure Implementation

This chapter provides systematic troubleshooting guidance for common issues in SPCS-to-on-premise connectivity on **Azure**. Each section follows a consistent format: Symptoms → Possible Causes → Diagnostic Steps → Resolution.

For AWS-specific troubleshooting, see Chapter 6.

---

## 7.1. Private Link Connection Issues (Azure)

Private Link connection failures are one of the most common issues during Azure setup, usually occurring during connection provisioning and approval. See the Azure Private Link and Snowflake documentation[^23][^7] for additional guidance.

### Issue 7.1.1: Connection Stuck in "Pending" State

**Symptoms:**
- After running `SYSTEM$PROVISION_PRIVATELINK_ENDPOINT`, the connection remains in "Pending" state indefinitely
- No connection request appears in Azure Private Link Service console
- Snowflake application cannot connect, shows "Connection timeout" or "No route to host"

**Possible Causes:**
1. Private Link Service not configured to accept connections from external subscriptions
2. Incorrect Private Link Service Resource ID provided to Snowflake
3. Private Link Service deleted or in failed state

**Diagnostic Steps:**

```bash
# 1. Verify Private Link Service exists
az network private-link-service show \
  --name <private-link-service-name> \
  --resource-group <resource-group>

# 2. Check for pending connections
az network private-link-service connection show \
  --name <connection-name> \
  --service-name <private-link-service-name> \
  --resource-group <resource-group>

# 3. Check visibility settings
az network private-link-service show \
  --name <private-link-service-name> \
  --resource-group <resource-group> \
  --query 'visibility'
```

**Resolution:**

1. Ensure Private Link Service visibility is set to allow subscriptions or specific subscription IDs
2. If using subscription-based access control, add Snowflake's Azure subscription ID (obtain from Snowflake support)
3. Verify the Resource ID provided to Snowflake matches exactly (case-sensitive)

---

### Issue 7.1.2: Connection Rejected

**Symptoms:**
- Connection request visible in Azure Portal but in "Rejected" state
- Snowflake endpoint provisioning fails with rejection error

**Possible Causes:**
1. Administrator manually rejected the connection request
2. Automatic rejection due to security policy
3. Connection request from unexpected Snowflake subscription

**Diagnostic Steps:**
1. Review Azure Activity Log for rejection event and initiator
2. Verify the requesting subscription matches expected Snowflake account
3. Check for Azure Policy assignments that may auto-reject external connections

**Resolution:**
1. If rejected in error, delete the rejected connection request in Azure Portal
2. Re-run `SYSTEM$PROVISION_PRIVATELINK_ENDPOINT` from Snowflake
3. Approve the new connection request promptly in Azure Portal
4. If using automation, update approval policies to whitelist Snowflake subscriptions

---

### Issue 7.1.3: Connection Timeout After Approval

**Symptoms:**
- Connection approved in Azure Portal and Private Endpoint created
- Snowflake application still shows "Connection timeout"
- `SYSTEM$PROVISION_PRIVATELINK_ENDPOINT` completed successfully but connections fail

**Possible Causes:**
1. Network Security Group (NSG) blocking traffic to/from Private Endpoint
2. Standard Load Balancer has no healthy targets (see Section 7.3)
3. Incorrect DNS name configured in Snowflake Network Rule
4. Route table missing route to SLB or on-premise network

**Diagnostic Steps:**

```bash
# 1. Check Private Endpoint status
az network private-endpoint show \
  --name <endpoint-name> \
  --resource-group <resource-group>

# 2. Check NSG rules
az network nsg show \
  --name <nsg-name> \
  --resource-group <resource-group>

# 3. Check Load Balancer backend health
az network lb show \
  --name <lb-name> \
  --resource-group <resource-group>

# 4. Check effective routes for Private Endpoint NIC
az network nic show-effective-route-table \
  --name <pe-nic-name> \
  --resource-group <resource-group>
```

**Resolution:**
1. **Fix NSG**: Add inbound rule allowing TCP traffic on database port from Snowflake VNet CIDR
2. **Fix SLB Health**: See Section 7.3 for health probe troubleshooting
3. **Verify DNS in Network Rule**: Ensure Snowflake Network Rule `VALUE_LIST` contains correct Private Link Service DNS
4. **Check Routes**: Verify route table for Private Endpoint subnet has route to on-premise CIDR via Virtual Network Gateway

---

## 7.2. DNS Resolution Failures (Azure)

DNS resolution issues prevent applications from resolving on-premise hostnames even when network routes are correct. Common error messages include "getaddrinfo failed" or "Name or service not known." For more details on Azure DNS Private Resolver configuration, see the Azure DNS documentation[^15][^16][^44][^45].

### Issue 7.2.1: DNS Query Timeout

**Symptoms:**
- Application shows DNS timeout errors
- `nslookup` or `dig` commands from container/VM time out
- No DNS response received after 5-10 seconds

**Possible Causes:**
1. Azure DNS Private Resolver Outbound Endpoint not reachable from VNet
2. DNS forwarding ruleset not configured or not linked to VNet
3. On-premise DNS servers unreachable due to routing or firewall issues
4. UDP/TCP port 53 blocked by NSGs or on-premise firewall

**Diagnostic Steps:**

```bash
# 1. Check DNS Resolver status
az dns-resolver show \
  --name <resolver-name> \
  --resource-group <resource-group>

# 2. Check outbound endpoint
az dns-resolver outbound-endpoint show \
  --name <endpoint-name> \
  --dns-resolver-name <resolver-name> \
  --resource-group <resource-group>

# 3. Check forwarding ruleset
az dns-resolver forwarding-ruleset show \
  --name <ruleset-name> \
  --resource-group <resource-group>

# 4. Check ruleset virtual network links
az dns-resolver forwarding-ruleset list \
  --resource-group <resource-group>

# 5. Test DNS from within VNet
# Launch VM in same VNet, then:
nslookup sql-prod.corp.local 192.168.1.10  # Replace with on-prem DNS IP
```

**Resolution:**
1. **Create/Fix Forwarding Rule**: Ensure forwarding rule exists for on-premise domain (e.g., `corp.local` or `*.corp.local`)
2. **Link Ruleset to VNet**: Verify forwarding ruleset is linked to the customer VNet
3. **Check NSGs**: Allow UDP and TCP port 53 outbound from outbound endpoint subnet to on-premise DNS IPs
4. **Check On-Premise Firewall**: Allow UDP and TCP port 53 inbound from VNet CIDRs to on-premise DNS servers
5. **Verify Routing**: Ensure route table for outbound endpoint subnet has route to on-premise network via Virtual Network Gateway

---

### Issue 7.2.2: NXDOMAIN Response (Domain Not Found)

**Symptoms:**
- DNS query returns "NXDOMAIN" (Non-Existent Domain)
- Error message: "Name or service not known" or similar
- Query completes quickly (not a timeout)

**Possible Causes:**
1. On-premise DNS server does not have authoritative records for the queried domain
2. DNS forwarding rule domain pattern doesn't match query
3. Query reaching wrong DNS server (not being forwarded to on-premise)
4. Typo in hostname

**Diagnostic Steps:**
1. **Verify domain match**:
   - Forwarding rule: `corp.local`
   - Query: `sql-prod.corp.local` ✅ Match
   - Query: `sql-prod.internal.local` ❌ No match (needs rule for `internal.local`)

2. **Test DNS directly from on-premise**:
```bash
# From on-premise network
nslookup sql-prod.corp.local 192.168.1.10  # Should resolve
```

3. **Check DNS query path**:
   - Enable diagnostic logs for Azure DNS Private Resolver
   - Verify query is being forwarded to on-premise DNS servers

**Resolution:**
1. **Add DNS Records**: Ensure on-premise DNS has A records for all required hostnames
2. **Update Forwarding Rule**: Modify domain pattern to match queries (use `*.` for wildcard if needed)
3. **Add Multiple Rules**: Create separate forwarding rules for each on-premise domain
4. **Verify Case Sensitivity**: Ensure hostname case matches DNS records

---

### Issue 7.2.3: Wrong IP Address Returned

**Symptoms:**
- DNS query returns an IP address, but it's the wrong one
- Connection attempts go to wrong server or fail with "Connection refused"

**Possible Causes:**
1. DNS query resolved by Azure Private DNS Zone overriding on-premise DNS
2. Cached stale DNS record (old IP from before database moved)
3. Split-horizon DNS misconfiguration

**Diagnostic Steps:**
1. **Check DNS response source**:
```bash
dig sql-prod.corp.local +trace  # Shows which server answered
```

2. **Check for overlapping zones**:
   - Check Azure Private DNS Zones linked to VNet
   - Look for zone with same domain name as on-premise domain

3. **Check TTL and caching**:
```bash
dig sql-prod.corp.local  # Look at TTL value in response
```

**Resolution:**
1. **Remove Overlapping Zones**: If an Azure Private DNS Zone has the same domain as on-premise, delete it or modify domain name
2. **Clear DNS Cache**: 
   - On-premise DNS: Clear server cache
   - Application: Restart application to clear client-side cache
3. **Update DNS Records**: Correct the IP address in the authoritative on-premise DNS server
4. **Reduce TTL**: If IPs change frequently, reduce TTL to 60-300 seconds

---

### Issue 7.2.4: Intermittent DNS Failures

**Symptoms:**
- DNS resolution works sometimes, fails other times
- Pattern may correlate with time of day, load, or specific servers

**Possible Causes:**
1. One on-premise DNS server is down (forwarding ruleset has multiple targets, some failing)
2. Network path intermittently congested (Virtual Network Gateway, ExpressRoute)
3. DNS server overloaded or rate-limiting queries
4. TTL too short causing excessive query volume

**Diagnostic Steps:**
1. **Test each DNS server individually**:
```bash
dig @192.168.1.10 sql-prod.corp.local  # Primary DNS
dig @192.168.1.11 sql-prod.corp.local  # Secondary DNS
```

2. **Check DNS server health and load**:
   - Monitor CPU, memory, query rate on on-premise DNS servers
   - Check DNS server logs for errors

3. **Monitor hybrid connection**:
   - Azure Monitor metrics for ExpressRoute and Virtual Network Gateway
   - Look for packet loss, latency spikes

**Resolution:**
1. **Fix/Replace Failed DNS Server**: Repair or remove unhealthy DNS server from forwarding rule targets
2. **Add More DNS Servers**: Increase redundancy by adding additional on-premise DNS servers
3. **Scale DNS Infrastructure**: Upgrade DNS server resources or distribute load
4. **Increase TTL**: Increase TTL to reduce query rate (balance against IP change frequency)
5. **Monitor Hybrid Connection Health**: Set up Azure Monitor alerts for ExpressRoute circuit issues

---

## 7.3. Standard Load Balancer Health Probe Failures

Azure SLB health probes control which backend targets receive traffic. When health probes fail, traffic is blocked even if the database is running.

### Issue 7.3.1: All Targets Showing Unhealthy

**Symptoms:**
- Azure Standard Load Balancer shows all backends in backend pool as "Unhealthy"
- Application connections fail with immediate "Connection refused" or timeout
- Load balancer returns errors (no healthy backends available)

**Possible Causes:**
1. Database listener not running or not accepting connections
2. Firewall blocking health probes from load balancer
3. Health probe configured for wrong port or protocol
4. Database server network unreachable from load balancer subnet
5. Health probe timeout too short for network latency over ExpressRoute
6. NSG not allowing Azure health probe traffic

**Diagnostic Steps:**

```bash
# 1. Check backend health
az network lb show \
  --name <lb-name> \
  --resource-group <resource-group> \
  --query 'backendAddressPools'

# 2. Check health probe configuration
az network lb probe show \
  --lb-name <lb-name> \
  --name <probe-name> \
  --resource-group <resource-group>

# 3. Check load balancing rule
az network lb rule show \
  --lb-name <lb-name> \
  --name <rule-name> \
  --resource-group <resource-group>

# 4. Test connectivity from VNet to on-premise DB
# Launch VM in SLB subnet, test:
Test-NetConnection -ComputerName 10.50.100.25 -Port 1433
```

**Resolution:**

1. **Verify Database Listener Running**:
   - SQL Server: Check SQL Server service status, verify TCP/IP protocol enabled
   - Oracle: Check listener status with `lsnrctl status`
   - MySQL/PostgreSQL: Check service status

2. **Check Database Listener Binding**:
   - Ensure listener bound to `0.0.0.0` (all interfaces) or specific NIC IP
   - SQL Server: SQL Server Configuration Manager → Protocols → TCP/IP → IP Addresses
   - Oracle: Check `listener.ora` HOST parameter
   - MySQL: Check `bind-address` in `my.cnf`
   - PostgreSQL: Check `listen_addresses` in `postgresql.conf`

3. **Fix Firewall and NSG Rules**:
   - **CRITICAL for Azure**: NSG must allow inbound from Azure health probe IP `168.63.129.16`
   - On-premise firewall: Allow TCP connections from VNet CIDR to database IP:port
   - OS firewall on DB server: Allow TCP on database port

**NSG Rule for Azure Health Probes:**
```bash
az network nsg rule create \
  --resource-group <resource-group> \
  --nsg-name <nsg-name> \
  --name AllowAzureLoadBalancerInbound \
  --priority 100 \
  --source-address-prefixes AzureLoadBalancer \
  --destination-port-ranges '*' \
  --access Allow \
  --protocol '*' \
  --direction Inbound
```

4. **Adjust Health Probe Parameters for Hybrid Connectivity**:
   - Increase probe interval to 15 seconds
   - Set unhealthy threshold to 2 consecutive failures
   - This accounts for additional latency over Virtual Network Gateway and ExpressRoute

5. **Verify Routing**:
   - Ensure load balancer subnet route table has route to on-premise CIDR via Virtual Network Gateway
   - Check VNet Gateway route propagation for on-premise routes

---

### Issue 7.3.2: Intermittent Health Probe Failures

**Symptoms:**
- Backends flip between "Healthy" and "Unhealthy" states
- Connection success rate less than 100%
- Pattern may correlate with database load or time of day

**Possible Causes:**
1. Database server CPU/memory overloaded, slow to respond to health probes
2. Network path intermittently congested or experiencing packet loss
3. Health probe interval too short relative to database response time
4. Database connection pool exhausted

**Diagnostic Steps:**
1. **Monitor Database Performance**:
   - Check CPU, memory, disk I/O on database server during health probe failures
   - Review database logs for connection errors or timeouts

2. **Monitor Network Path**:
   - Azure Monitor metrics for SLB (`DipAvailability`, `VipAvailability`)
   - Azure Monitor metrics for Virtual Network Gateway (`P2SBandwidth`, `TunnelIngressBytes`)
   - Azure Monitor metrics for ExpressRoute (`BitsInPerSecond`, `BitsOutPerSecond`)

3. **Review Health Probe Timing**:
   - Calculate total time: Network latency (round-trip) + database response time
   - Compare to health probe timeout/interval settings

**Resolution:**
1. **Scale Database Resources**: Increase CPU, memory, or use faster storage
2. **Optimize Database**: Index optimization, query performance tuning, connection pooling
3. **Increase Health Probe Intervals**:
   - Increase interval from 5s to 15s
   - Keep unhealthy threshold at 2
4. **Add Database Replicas**: Distribute load across multiple database instances in backend pool
5. **Upgrade ExpressRoute**: If network path is bottleneck, increase circuit bandwidth

---

### Issue 7.3.3: Target Never Becomes Healthy (New Target)

**Symptoms:**
- Newly added backend to backend pool never transitions to "Healthy" state
- Other existing backends remain healthy
- Connections to the new target fail

**Possible Causes:**
1. Wrong IP address configured in backend pool
2. New database server firewall rules not configured
3. Database not yet running or still initializing
4. Network route to new target not yet propagated via BGP

**Diagnostic Steps:**
1. **Verify Backend IP**:
```bash
az network lb address-pool show \
  --lb-name <lb-name> \
  --name <backend-pool-name> \
  --resource-group <resource-group>
```

2. **Test Direct Connectivity**:
   - From VM in load balancer subnet, test connectivity to new target IP:port
   - Should succeed if configuration is correct

3. **Check Database Status**:
   - Verify database service running on new server
   - Verify listener accepting connections

**Resolution:**
1. **Correct Backend IP**: Update backend pool with correct IP address
2. **Configure Firewall**: Ensure all firewall rules and NSGs allow traffic from VNet to new database server
3. **Allow Azure Health Probe**: Ensure NSG allows inbound from `168.63.129.16`
4. **Wait for Database Initialization**: Some databases take minutes to become ready after service start
5. **Verify BGP Route Advertisement**: If new database is in new subnet, ensure on-premise router is advertising the subnet CIDR via BGP to ExpressRoute

---

### Issue 7.3.4: Common Load Balancer Configuration Issues

The following table summarizes common issues encountered during Azure Standard Load Balancer and Private Link Service configuration:

| Symptom | Possible Cause | Solution |
|---------|----------------|----------|
| Health probe shows "Down" | ExpressRoute not advertising on-premise routes | Verify BGP peering status and route propagation |
| Health probe shows "Down" | NSG blocking traffic | Add NSG rule allowing load balancer subnet to on-premise IP/port |
| Cannot create Private Link Service | Load Balancer using Basic SKU | Delete and recreate load balancer with Standard SKU |
| Private Link Service creation fails | Frontend IP not configured | Ensure load balancer has frontend IP configuration before creating PLS |

---

### 7.3.4. Common Load Balancer Configuration Errors

This subsection documents typical beginner mistakes when configuring Azure Standard Load Balancer and Private Link Service for hybrid connectivity.

**Error 1: "Cannot create Private Link Service with Basic SKU Load Balancer"**

**Symptom:**
```
ErrorCode: PrivateLinkServiceCannotUseBasicLoadBalancer
Message: Private Link Service cannot be associated with a Basic SKU Load Balancer.
```

**Cause:** Private Link Service requires Standard SKU Load Balancer. The Basic SKU lacks the control plane integration required for Private Link connectivity.

**Resolution:**
1. Delete the Basic SKU Load Balancer (if already created)
2. Create a new Load Balancer using `--sku Standard` in the `az network lb create` command
3. Reconfigure backend pool, health probe, and load balancing rule on the Standard SKU Load Balancer
4. Retry Private Link Service creation

**Error 2: "Health probe shows Down status"**

**Symptom:**
- Load Balancer health probe shows "Down" or "Unhealthy" status
- Backend pool shows "Unavailable"
- Traffic does not flow to on-premise database

**Cause:** One or more connectivity issues between Azure and on-premise:
- ExpressRoute circuit is down or misconfigured
- NSG rules blocking health probe traffic
- On-premise database is not listening on the specified port
- On-premise firewall blocking Azure traffic
- Incorrect on-premise database IP address in backend pool

**Resolution:**
1. **Verify ExpressRoute connectivity:**
   ```bash
   az network express-route show \
     --resource-group $RESOURCE_GROUP \
     --name $CIRCUIT_NAME \
     --query "circuitProvisioningState"
   ```
   Expected: "Enabled"

2. **Check NSG rules allow health probe traffic:**
   - Verify outbound rules allow TCP to on-premise database IP and port
   - Health probes originate from Azure load balancer infrastructure (168.63.129.16)
   - Add explicit allow rule if needed:
   ```bash
   az network nsg rule create \
     --resource-group $RESOURCE_GROUP \
     --nsg-name $NSG_NAME \
     --name AllowHealthProbe \
     --priority 100 \
     --source-address-prefixes 168.63.129.16 \
     --destination-port-ranges $DB_PORT \
     --protocol Tcp \
     --access Allow \
     --direction Outbound
   ```

3. **Verify on-premise database accessibility:**
   - Deploy a test VM in the same subnet as load balancer frontend
   - Test connectivity: `telnet <on-premise-db-ip> 1433` or `Test-NetConnection`
   - If connection fails, check on-premise firewall rules and database listener status

4. **Confirm backend pool IP address is correct:**
   ```bash
   az network lb address-pool address list \
     --resource-group $RESOURCE_GROUP \
     --lb-name $LB_NAME \
     --pool-name backend-pool \
     --output table
   ```

**Error 3: "Backend pool cannot reach on-premise IP"**

**Symptom:**
- Backend pool configured with on-premise IP, but shows as unreachable
- Error message: "Backend address is not reachable"

**Cause:** ExpressRoute route advertisement issue or missing User-Defined Route (UDR).

**Resolution:**
1. **Verify BGP route advertisement from on-premise:**
   - Check that on-premise network CIDR blocks are advertised via ExpressRoute private peering
   - Verify BGP session is established:
   ```bash
   az network express-route peering show \
     --resource-group $RESOURCE_GROUP \
     --circuit-name $CIRCUIT_NAME \
     --name AzurePrivatePeering \
     --query "state"
   ```
   Expected: "Enabled"

2. **Check route table associated with load balancer subnet:**
   ```bash
   az network route-table route list \
     --resource-group $RESOURCE_GROUP \
     --route-table-name $ROUTE_TABLE_NAME \
     --output table
   ```
   Should include route for on-premise CIDR with next hop type "VirtualNetworkGateway"

3. **Create UDR if missing:**
   ```bash
   az network route-table route create \
     --resource-group $RESOURCE_GROUP \
     --route-table-name $ROUTE_TABLE_NAME \
     --name ToOnPremise \
     --address-prefix <on-premise-cidr> \
     --next-hop-type VirtualNetworkGateway
   ```

**Error 4: "Private Link Service provisioning failed"**

**Symptom:**
```
ErrorCode: PrivateLinkServiceProvisioningFailed
Message: Private Link Service provisioning failed due to invalid configuration.
```

**Cause:** One of several configuration issues:
- Load balancer frontend IP configuration not found
- Subnet has insufficient IP addresses for Private Link Service network interface
- NAT IP configuration conflicts

**Resolution:**
1. **Verify load balancer frontend IP exists:**
   ```bash
   az network lb frontend-ip list \
     --resource-group $RESOURCE_GROUP \
     --lb-name $LB_NAME \
     --output table
   ```

2. **Check subnet has available IP addresses:**
   - Private Link Service requires IP addresses for its network interfaces
   - Verify subnet has at least 8 available IPs:
   ```bash
   az network vnet subnet show \
     --resource-group $RESOURCE_GROUP \
     --vnet-name $VNET_NAME \
     --name $SUBNET_NAME \
     --query "{Name:name, AddressPrefix:addressPrefix, AvailableIPs:availableIpAddressesCount}"
   ```

3. **Retry Private Link Service creation with correct parameters:**
   - Ensure `--lb-frontend-ip-configs` uses full resource ID
   - Verify `--subnet` parameter references correct subnet

**Error 5: "Snowflake cannot connect to Private Link Service"**

**Symptom:**
- Private Link Service created successfully
- Snowflake `SYSTEM$PROVISION_PRIVATELINK_ENDPOINT` returns error
- Connection remains in "Pending" or fails immediately

**Cause:** Visibility or approval settings incorrect, or wrong alias provided.

**Resolution:**
1. **Verify Private Link Service visibility settings include Snowflake subscription:**
   ```bash
   az network private-link-service show \
     --resource-group $RESOURCE_GROUP \
     --name $PLS_NAME \
     --query "visibility.subscriptions"
   ```
   Should include Snowflake's Azure subscription ID

2. **Update visibility if needed:**
   ```bash
   az network private-link-service update \
     --resource-group $RESOURCE_GROUP \
     --name $PLS_NAME \
     --visibility-subscriptions $SNOWFLAKE_SUBSCRIPTION_ID
   ```

3. **Verify correct alias is used in Snowflake:**
   ```bash
   az network private-link-service show \
     --resource-group $RESOURCE_GROUP \
     --name $PLS_NAME \
     --query "alias" \
     --output tsv
   ```
   Use this exact alias in Snowflake network rule creation

4. **Enable auto-approval for Snowflake subscription:**
   ```bash
   az network private-link-service update \
     --resource-group $RESOURCE_GROUP \
     --name $PLS_NAME \
     --auto-approval-subscriptions $SNOWFLAKE_SUBSCRIPTION_ID
   ```

**Error 6: "NSG blocking load balancer traffic"**

**Symptom:**
- Health probe shows healthy
- Private Link Service connected
- Snowflake containers cannot reach on-premise database

**Cause:** NSG rules on load balancer frontend subnet or private endpoint subnet blocking traffic.

**Resolution:**
1. **Check effective security rules for load balancer subnet:**
   ```bash
   az network nic list-effective-nsg \
     --resource-group $RESOURCE_GROUP \
     --name <load-balancer-nic-name>
   ```

2. **Add explicit allow rules for Private Link Service traffic:**
   ```bash
   # Allow inbound from Private Link Service
   az network nsg rule create \
     --resource-group $RESOURCE_GROUP \
     --nsg-name $NSG_NAME \
     --name AllowPrivateLinkService \
     --priority 110 \
     --source-address-prefixes PrivateLinkService \
     --destination-address-prefixes VirtualNetwork \
     --destination-port-ranges $DB_PORT \
     --protocol Tcp \
     --access Allow \
     --direction Inbound
   ```

3. **Verify outbound rules allow traffic to on-premise:**
   ```bash
   az network nsg rule create \
     --resource-group $RESOURCE_GROUP \
     --nsg-name $NSG_NAME \
     --name AllowToOnPremise \
     --priority 120 \
     --destination-address-prefixes <on-premise-cidr> \
     --destination-port-ranges $DB_PORT \
     --protocol Tcp \
     --access Allow \
     --direction Outbound
   ```

**Quick Diagnostics Checklist:**

Use this checklist to systematically troubleshoot load balancer connectivity issues:

- [ ] Load Balancer SKU is Standard (not Basic)
- [ ] Health probe shows "Up" status
- [ ] Backend pool shows "Available" status
- [ ] Private Link Service provisioning state is "Succeeded"
- [ ] Private Link Service alias matches what's configured in Snowflake
- [ ] ExpressRoute circuit state is "Enabled"
- [ ] BGP peering state is "Enabled"
- [ ] On-premise CIDR appears in VNet effective routes
- [ ] NSG allows traffic from health probe source (168.63.129.16)
- [ ] NSG allows traffic from Private Link Service to load balancer subnet
- [ ] NSG allows traffic from load balancer subnet to on-premise CIDR
- [ ] Route table includes route for on-premise CIDR via VirtualNetworkGateway
- [ ] On-premise firewall allows traffic from Azure VNet CIDR
- [ ] On-premise database is listening on configured port

---

## 7.4. Azure ExpressRoute Issues

ExpressRoute issues affect both data traffic and DNS resolution, as both traverse the ExpressRoute circuit. For monitoring and troubleshooting guidance, see the ExpressRoute monitoring documentation[^57] and Connection Monitor configuration guide[^59].

### Issue 7.4.1: BGP Session Down

**Symptoms:**
- No connectivity from Azure to on-premise (complete outage)
- ExpressRoute shows BGP peering state as "Down"
- Routes from on-premise not appearing in Virtual Network Gateway effective routes

**Possible Causes:**
1. Physical circuit down (fiber cut, equipment failure at provider)
2. BGP configuration mismatch (wrong ASN, authentication key, or peering IPs)
3. On-premise router BGP process not running
4. Firewall blocking BGP traffic (TCP port 179)
5. Maximum prefix limit exceeded

**Diagnostic Steps:**

```bash
# 1. Check ExpressRoute circuit status
az network express-route show \
  --name <circuit-name> \
  --resource-group <resource-group>

# 2. Check BGP peering status
az network express-route peering show \
  --circuit-name <circuit-name> \
  --name AzurePrivatePeering \
  --resource-group <resource-group>

# 3. Check Virtual Network Gateway BGP status
az network vnet-gateway show \
  --name <gateway-name> \
  --resource-group <resource-group> \
  --query 'bgpSettings'

# 4. List BGP peers
az network vnet-gateway list-bgp-peer-status \
  --name <gateway-name> \
  --resource-group <resource-group>
```

**On-Premise:**
```bash
# Check BGP neighbor status (Cisco example)
show ip bgp summary
show ip bgp neighbors <azure-bgp-peer-ip>
```

**Resolution:**

1. **Physical Circuit Issues**:
   - Contact ExpressRoute provider for circuit status
   - Check Azure Service Health for known issues
   - If circuit down, provider must repair

2. **BGP Configuration Mismatch**:
   - **ASN Mismatch**: Verify on-premise router ASN matches what's configured in Azure VNet Gateway
   - **Authentication Key**: Verify MD5 authentication key matches on both sides (case-sensitive)
   - **Peering IPs**: Verify /30 subnet configuration matches on both sides

3. **BGP Process Not Running**:
   - On-premise: Restart BGP process or router BGP daemon
   - Check router logs for BGP process crashes

4. **Firewall Blocking BGP**:
   - Ensure TCP port 179 allowed between on-premise router and Azure BGP peer IPs
   - BGP uses TCP port 179, must be bidirectional

5. **Maximum Prefix Limit**:
   - ExpressRoute Standard: 4000 routes, Premium: 10,000 routes
   - Reduce number of advertised routes (use BGP summarization)
   - Or upgrade to ExpressRoute Premium
   - Reset BGP session after fixing

---

### Issue 7.4.2: Routes Not Propagating

**Symptoms:**
- BGP session shows "Connected" status
- Connectivity partially works (some subnets reachable, others not)
- Some on-premise routes missing from Virtual Network Gateway learned routes

**Possible Causes:**
1. On-premise router not advertising specific subnets via BGP
2. Route filtering or route maps blocking specific prefixes
3. Virtual Network Gateway not learning routes correctly
4. Maximum routes limit reached
5. IP prefix overlap causing route selection issues

**Diagnostic Steps:**

```bash
# 1. Check routes learned by Virtual Network Gateway
az network vnet-gateway list-learned-routes \
  --name <gateway-name> \
  --resource-group <resource-group>

# 2. Check routes advertised to on-premise
az network vnet-gateway list-advertised-routes \
  --name <gateway-name> \
  --resource-group <resource-group> \
  --peer <on-prem-bgp-peer-ip>

# 3. Check effective routes for VNet subnet
az network nic show-effective-route-table \
  --name <nic-name> \
  --resource-group <resource-group>

# 4. Check VNet peering (if using hub-spoke)
az network vnet peering list \
  --vnet-name <vnet-name> \
  --resource-group <resource-group>
```

**On-Premise:**
```bash
# Check advertised and received routes (Cisco example)
show ip bgp neighbors <peer-ip> advertised-routes
show ip bgp neighbors <peer-ip> received-routes
```

**Resolution:**

1. **Add Missing Route Advertisements**:
   - On-premise: Add network statements to BGP configuration for missing subnets
   - Ensure subnets are in routing table before advertising via BGP

2. **Remove/Modify Route Filters**:
   - Check for route maps, prefix lists, or AS-path filters blocking desired routes
   - Modify filters to allow required prefixes

3. **Fix VNet Gateway Route Propagation**:
   - Ensure "Propagate gateway routes" enabled on route tables
   - Verify VNet peering configured correctly for hub-spoke topologies

4. **Increase Route Limits**:
   - ExpressRoute Standard: 4000 routes
   - ExpressRoute Premium: 10,000 routes
   - Upgrade to Premium if needed

5. **Resolve IP Overlap**:
   - If VNet CIDR overlaps with on-premise CIDR, more specific route wins
   - May require CIDR redesign or use of NAT

---

### Issue 7.4.3: Intermittent Connectivity

**Symptoms:**
- Connectivity works most of the time but occasionally fails
- Pattern may show regular intervals
- Symptoms may correlate with high traffic volume

**Possible Causes:**
1. ExpressRoute circuit bandwidth saturated during peak usage
2. Provider network maintenance or congestion
3. BGP route flapping
4. Packet loss due to circuit errors

**Diagnostic Steps:**

1. **Monitor Circuit Utilization**:
```bash
# Get Azure Monitor metrics for ExpressRoute
az monitor metrics list \
  --resource /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/expressRouteCircuits/<circuit-name> \
  --metric BitsInPerSecond,BitsOutPerSecond \
  --start-time 2025-11-07T00:00:00Z \
  --end-time 2025-11-07T01:00:00Z
```

2. **Check for Packet Loss**:
   - Run continuous ping tests from Azure VM to on-premise and vice versa
   - Monitor packet loss percentage and latency

3. **Review BGP Route Stability**:
   - Check for frequent route withdrawals and re-advertisements
   - Look for BGP flapping in router logs

**Resolution:**

1. **Increase Circuit Bandwidth**:
   - If utilization consistently exceeds 70-80%, upgrade ExpressRoute circuit
   - Available bandwidths: 50 Mbps to 10 Gbps

2. **Implement QoS**:
   - Prioritize critical traffic (database queries, DNS) over bulk data transfers
   - Configure QoS policies on on-premise router

3. **Add Redundant Circuit**:
   - Add second ExpressRoute circuit for redundancy
   - Consider using different service providers for true resilience

4. **Fix BGP Route Flapping**:
   - Implement BGP damping to suppress flapping routes
   - Investigate root cause of route instability

5. **Contact Provider**:
   - If packet loss or errors persist, open Azure Support case
   - Request ExpressRoute circuit testing

---

## 7.5. On-Premise Connectivity Failures

Issues within the on-premise network are often the most challenging to diagnose due to multiple security layers and organizational boundaries. These issues are common to both AWS and Azure implementations.

### Issue 7.5.1: Firewall Blocking Traffic

**Symptoms:**
- Connections time out after passing through Azure environment
- Traceroute from Azure VM shows packets reaching on-premise edge router but going no further
- On-premise firewall logs show dropped packets from VNet CIDR ranges

**Possible Causes:**
1. Perimeter firewall rules not configured to allow traffic from VNet CIDRs
2. Internal firewall between network zones blocking traffic
3. Host-based firewall on database server blocking connections
4. Firewall rule specifies wrong source IP, destination IP, or port

**Diagnostic Steps:**

1. **Review Firewall Logs**:
   - Check perimeter firewall logs for blocks from source IPs in VNet CIDR ranges
   - Note exact source IP, destination IP, and port of blocked traffic

2. **Test from Different Locations**:
   - Test from Azure VM → on-premise edge: Should succeed if ExpressRoute working
   - Test from edge → database: If fails, issue is within on-premise network
   - Test from another on-premise server → database: If succeeds, confirms database reachable

3. **Verify Firewall Rule Configuration**:
   - Confirm rules exist for:
     - Source: VNet CIDR (e.g., `172.16.0.0/16`)
     - Destination: Database server IP (e.g., `10.50.100.25`)
     - Port: Database port (1433, 1521, 3306, 5432)
     - Protocol: TCP
     - Action: ALLOW

**Resolution:**

1. **Add Perimeter Firewall Rules**:
```
Rule Name: Allow_Azure_to_Database
Source: 172.16.0.0/16 (VNet CIDR)
Destination: 10.50.100.25 (Database IP)
Service: TCP/1433 (SQL Server)
Action: Allow
Logging: Enabled
```

2. **Add Internal Firewall Rules**:
   - If DMZ or database tier has separate firewall, add similar rules
   - Ensure rule allows traffic transitioning between zones

3. **Configure Host-Based Firewall**:

**Windows:**
```powershell
New-NetFirewallRule -DisplayName "Allow SQL from Azure" `
  -Direction Inbound `
  -LocalPort 1433 `
  -Protocol TCP `
  -RemoteAddress 172.16.0.0/16 `
  -Action Allow
```

**Linux:**
```bash
# iptables
iptables -A INPUT -p tcp -s 172.16.0.0/16 --dport 1433 -j ACCEPT

# firewalld
firewall-cmd --permanent --add-rich-rule='
  rule family="ipv4" source address="172.16.0.0/16" port port="1433" protocol="tcp" accept'
firewall-cmd --reload
```

---

### Issue 7.5.2: Database Listener Not Responding

*See detailed database listener configuration in Section 7.5.1 resolution steps.*

**Quick Diagnostics:**
```bash
# Check if database is listening on expected port
netstat -tlnp | grep 1433  # Linux
netstat -an | findstr 1433  # Windows

# Test local connectivity on database server
telnet localhost 1433
```

**Common Fix**: Ensure database listener bound to `0.0.0.0` or correct NIC IP, not `127.0.0.1`.

---

### Issue 7.5.3: Authentication Failures

*Authentication issues are database-specific and apply to both AWS and Azure implementations. See database-specific resolution steps in the general troubleshooting section.*

**Quick Resolution Steps:**
1. Verify credentials in Snowflake secret match database user
2. Ensure database user allows connections from Azure VNet CIDR (not restricted to specific IPs)
3. For SQL Server: Ensure "SQL Server and Windows Authentication mode" enabled
4. For MySQL: Create user with host `'%'` or `'172.16.%'` to allow cloud connections

---

## 7.6. General Troubleshooting Methodology (Azure)

When facing connectivity issues in Azure hybrid architecture, use this systematic approach:

### 1. Isolate the Layer
Work through the networking stack to isolate the issue:
- **Layer 3 (Network)**: Can you ping/traceroute across ExpressRoute?
- **Layer 4 (Transport)**: Can you establish TCP connection via SLB?
- **Layer 7 (Application)**: Does database authentication work?

### 2. Test from Multiple Azure Locations
- From Snowflake SPCS container (if accessible for testing)
- From Azure VM in same VNet as Private Endpoint
- From Azure VM in Standard Load Balancer subnet
- From on-premise server

### 3. Check Both Directions
- Azure VNet → On-premise (forward path)
- On-premise → Azure VNet (return path)

### 4. Enable Azure Logging
- **NSG Flow Logs**: Capture accepted/rejected traffic
- **Azure Activity Log**: Track configuration changes
- **Azure Monitor Logs**: SLB health probe logs, DNS resolver logs
- **Firewall logs**: On-premise perimeter and internal firewalls

### 5. Monitor Azure Metrics
- Standard Load Balancer: `DipAvailability`, `VipAvailability`, `ByteCount`
- ExpressRoute: `BitsInPerSecond`, `BitsOutPerSecond`, `BgpAvailability`
- Virtual Network Gateway[^58]: `TunnelAverageBandwidth`, `TunnelEgressBytes`, `TunnelIngressBytes`
- DNS Private Resolver: Query count, query latency

### 6. Engage Multiple Teams
- **Azure Cloud Team**: VNet, SLB, Private Endpoint, Virtual Network Gateway
- **Network Team**: ExpressRoute, BGP, routing, firewalls
- **Database Team**: Listener, user accounts, performance
- **Snowflake Team**: EAI configuration, network rules

---

## 7.7. Useful Azure Diagnostic Commands

### VNet and Private Link Commands

```bash
# Check Private Endpoint status
az network private-endpoint show \
  --name <endpoint-name> \
  --resource-group <resource-group>

# Check Private Link Service
az network private-link-service show \
  --name <service-name> \
  --resource-group <resource-group>

# Check Private Link Service connections
az network private-link-service connection list \
  --service-name <service-name> \
  --resource-group <resource-group>

# Check NSG
az network nsg show \
  --name <nsg-name> \
  --resource-group <resource-group>

# Check NSG rules
az network nsg rule list \
  --nsg-name <nsg-name> \
  --resource-group <resource-group>

# Check route table
az network route-table show \
  --name <route-table-name> \
  --resource-group <resource-group>

# Check effective routes for NIC
az network nic show-effective-route-table \
  --name <nic-name> \
  --resource-group <resource-group>
```

### Standard Load Balancer Commands

```bash
# Check SLB details
az network lb show \
  --name <lb-name> \
  --resource-group <resource-group>

# Check backend pool
az network lb address-pool show \
  --lb-name <lb-name> \
  --name <backend-pool-name> \
  --resource-group <resource-group>

# Check health probe
az network lb probe show \
  --lb-name <lb-name> \
  --name <probe-name> \
  --resource-group <resource-group>

# Check load balancing rule
az network lb rule show \
  --lb-name <lb-name> \
  --name <rule-name> \
  --resource-group <resource-group>

# Check frontend IP configuration
az network lb frontend-ip show \
  --lb-name <lb-name> \
  --name <frontend-ip-name> \
  --resource-group <resource-group>
```

### Virtual Network Gateway Commands

```bash
# Check VNet Gateway details
az network vnet-gateway show \
  --name <gateway-name> \
  --resource-group <resource-group>

# Check learned routes
az network vnet-gateway list-learned-routes \
  --name <gateway-name> \
  --resource-group <resource-group>

# Check advertised routes
az network vnet-gateway list-advertised-routes \
  --name <gateway-name> \
  --resource-group <resource-group> \
  --peer <on-prem-bgp-peer-ip>

# Check BGP peer status
az network vnet-gateway list-bgp-peer-status \
  --name <gateway-name> \
  --resource-group <resource-group>

# Reset VNet Gateway connection
az network vpn-connection show \
  --name <connection-name> \
  --resource-group <resource-group>
```

### ExpressRoute Commands

```bash
# Check ExpressRoute circuit status
az network express-route show \
  --name <circuit-name> \
  --resource-group <resource-group>

# Check ExpressRoute peerings
az network express-route peering list \
  --circuit-name <circuit-name> \
  --resource-group <resource-group>

# Check specific peering
az network express-route peering show \
  --circuit-name <circuit-name> \
  --name AzurePrivatePeering \
  --resource-group <resource-group>

# Check route tables for peering
az network express-route peering get-stats \
  --circuit-name <circuit-name> \
  --name AzurePrivatePeering \
  --resource-group <resource-group>
```

### Azure DNS Private Resolver Commands

```bash
# Check DNS Resolver
az dns-resolver show \
  --name <resolver-name> \
  --resource-group <resource-group>

# Check outbound endpoint
az dns-resolver outbound-endpoint show \
  --name <endpoint-name> \
  --dns-resolver-name <resolver-name> \
  --resource-group <resource-group>

# Check forwarding ruleset
az dns-resolver forwarding-ruleset show \
  --name <ruleset-name> \
  --resource-group <resource-group>

# List forwarding rules
az dns-resolver forwarding-rule list \
  --ruleset-name <ruleset-name> \
  --resource-group <resource-group>

# Check ruleset VNet links
az dns-resolver vnet-link list \
  --ruleset-name <ruleset-name> \
  --resource-group <resource-group>
```

### Azure Monitor Metrics Commands

```bash
# Get Standard Load Balancer metrics
az monitor metrics list \
  --resource /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/loadBalancers/<lb-name> \
  --metric DipAvailability,VipAvailability \
  --start-time 2025-11-07T00:00:00Z \
  --end-time 2025-11-07T01:00:00Z

# Get ExpressRoute metrics
az monitor metrics list \
  --resource /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/expressRouteCircuits/<circuit-name> \
  --metric BitsInPerSecond,BitsOutPerSecond,BgpAvailability \
  --start-time 2025-11-07T00:00:00Z \
  --end-time 2025-11-07T01:00:00Z

# Get Virtual Network Gateway metrics
az monitor metrics list \
  --resource /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworkGateways/<gateway-name> \
  --metric TunnelAverageBandwidth,TunnelEgressBytes \
  --start-time 2025-11-07T00:00:00Z \
  --end-time 2025-11-07T01:00:00Z
```

### Connectivity Testing Commands

```bash
# From Azure VM in VNet:

# Test TCP connectivity to on-premise database (PowerShell)
Test-NetConnection -ComputerName 10.50.100.25 -Port 1433

# Test DNS resolution
nslookup sql-prod.corp.local
Resolve-DnsName sql-prod.corp.local

# Test via SLB DNS name
Test-NetConnection -ComputerName <lb-private-ip> -Port 1433

# Traceroute to on-premise (PowerShell)
Test-NetConnection -ComputerName 10.50.100.25 -TraceRoute

# Continuous ping test
Test-Connection -ComputerName 10.50.100.25 -Count 100
```

---

## References

[^7]: External network access and private connectivity on Microsoft Azure, https://docs.snowflake.com/en/developer-guide/external-network-access/creating-using-private-azure
[^15]: What is Azure DNS Private Resolver? | Microsoft Learn, https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview
[^16]: Azure DNS Private Resolver - Azure Architecture Center | Microsoft Learn, https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/azure-dns-private-resolver
[^23]: Azure Private Link and Snowflake, https://docs.snowflake.com/en/user-guide/privatelink-azure
[^44]: Resolve Azure and on-premises domains | Microsoft Learn, https://learn.microsoft.com/en-us/azure/dns/private-resolver-hybrid-dns
[^45]: Tutorial: Create a private endpoint DNS infrastructure with Azure Private Resolver for an on-premises workload - Microsoft Learn, https://learn.microsoft.com/en-us/azure/private-link/tutorial-dns-on-premises-private-resolver
[^57]: Monitor Azure ExpressRoute | Microsoft Learn, https://learn.microsoft.com/en-us/azure/expressroute/monitor-expressroute
[^58]: Monitor Azure VPN Gateway | Microsoft Learn, https://learn.microsoft.com/en-us/azure/vpn-gateway/monitor-vpn-gateway
[^59]: Configure Connection Monitor for Azure ExpressRoute - Microsoft Learn, https://learn.microsoft.com/en-us/azure/expressroute/how-to-configure-connection-monitor

---

*This Azure-specific troubleshooting guide provides systematic approaches to diagnosing and resolving connectivity issues. For AWS-specific guidance, see Chapter 6. For issues not covered here, contact Azure Support or Snowflake Support.*

