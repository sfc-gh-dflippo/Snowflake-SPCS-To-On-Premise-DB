# Chapter 6: Troubleshooting Guide - AWS Implementation

This chapter provides systematic troubleshooting guidance for common issues in SPCS-to-on-premise connectivity on **AWS**. Each section follows a consistent format: Symptoms → Possible Causes → Diagnostic Steps → Resolution.

For Azure-specific troubleshooting, see Chapter 7.

---

## 6.1. PrivateLink Connection Issues (AWS)

PrivateLink connection failures are one of the most common issues during AWS setup, usually occurring during connection provisioning and approval. See the AWS PrivateLink troubleshooting guide[^53] for additional guidance.

### Issue 6.1.1: Connection Stuck in "Pending" State

**Symptoms:**
- After running `SYSTEM$PROVISION_PRIVATELINK_ENDPOINT`, the connection remains in "Pending" state indefinitely
- No connection request appears in AWS VPC Endpoint Service console
- Snowflake application cannot connect, shows "Connection timeout" or "No route to host"

**Possible Causes:**
1. Snowflake account principal not authorized in VPC Endpoint Service "Allowed Principals"
2. Incorrect VPC Endpoint Service name provided to Snowflake
3. VPC Endpoint Service deleted or in failed state

**Diagnostic Steps:**

```bash
# 1. Verify VPC Endpoint Service exists and is active
aws ec2 describe-vpc-endpoint-services \
  --service-names com.amazonaws.vpce.us-west-2.vpce-svc-xxxxxxxxxxxxxxxxx

# 2. Check allowed principals
aws ec2 describe-vpc-endpoint-service-permissions \
  --service-id vpce-svc-xxxxxxxxxxxxxxxxx

# 3. Check for pending connection requests
aws ec2 describe-vpc-endpoint-connections \
  --filters Name=service-id,Values=vpce-svc-xxxxxxxxxxxxxxxxx
```

**Resolution:**

1. Retrieve Snowflake account principal[^22]:
```sql
SELECT key, value FROM TABLE(FLATTEN(INPUT => PARSE_JSON(SYSTEM$GET_PRIVATELINK_CONFIG())));
```

2. Add the `privatelink-account-principal` value to VPC Endpoint Service allowed principals[^6]:
```bash
aws ec2 modify-vpc-endpoint-service-permissions \
  --service-id vpce-svc-xxxxxxxxxxxxxxxxx \
  --add-allowed-principals arn:aws:iam::123456789012:root
```

---

### Issue 6.1.2: Connection Rejected

**Symptoms:**
- Connection request visible in AWS console but in "Rejected" state
- Snowflake endpoint provisioning fails with rejection error

**Possible Causes:**
1. Administrator manually rejected the connection request
2. Automatic rejection due to security policy
3. Connection request from unexpected Snowflake account

**Diagnostic Steps:**
1. Review AWS CloudTrail logs for rejection event and initiator
2. Verify the requesting principal matches expected Snowflake account
3. Check for AWS Organizations policies that may auto-reject cross-account connections

**Resolution:**
1. If rejected in error, delete the rejected connection request in AWS console
2. Re-run `SYSTEM$PROVISION_PRIVATELINK_ENDPOINT` from Snowflake
3. Approve the new connection request promptly
4. If using automation, update approval policies to whitelist Snowflake principals

---

### Issue 6.1.3: Connection Timeout After Approval

**Symptoms:**
- Connection approved in AWS console and VPC Interface Endpoint created
- Snowflake application still shows "Connection timeout"
- `SYSTEM$PROVISION_PRIVATELINK_ENDPOINT` completed successfully but connections fail

**Possible Causes:**
1. Security Group blocking traffic to/from VPC Endpoint
2. Network ACL blocking traffic
3. NLB has no healthy targets (see Section 6.3)
4. Incorrect DNS name configured in Snowflake Network Rule
5. Route table missing route to NLB or on-premise network

**Diagnostic Steps:**

```bash
# 1. Check VPC Endpoint status
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids vpce-xxxxxxxxxxxxxxxxx

# 2. Check Security Group rules on VPC Endpoint ENIs
aws ec2 describe-network-interfaces \
  --filters Name=vpc-endpoint-id,Values=vpce-xxxxxxxxxxxxxxxxx \
  --query 'NetworkInterfaces[*].Groups[*]'

# 3. Check NLB target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:region:account:targetgroup/...
```

**Resolution:**
1. **Fix Security Group**: Add inbound rule allowing TCP traffic on database port from Snowflake VNet CIDR
2. **Fix Network ACL**: Ensure both inbound (database port) and outbound (ephemeral ports 1024-65535) rules exist
3. **Fix NLB Health**: See Section 6.3 for health check troubleshooting
4. **Verify DNS in Network Rule**: Ensure Snowflake Network Rule `VALUE_LIST` contains correct NLB DNS name
5. **Check Routes**: Verify route table for VPC Endpoint subnet has route to on-premise CIDR via Transit Gateway

---

### Issue 6.1.4: VPC Endpoint Service Configuration Errors

**Symptoms:**
- VPC Endpoint Service not appearing in AWS console
- Service in "Failed" state
- NLB association not working
- Traffic not flowing through endpoint service

**Possible Causes:**
1. VPC Endpoint Service wasn't created properly
2. Wrong AWS region selected
3. NLB doesn't exist or was deleted
4. Wrong NLB ARN was specified during service creation
5. NLB targets are unhealthy

**Diagnostic Steps:**

```bash
# 1. Verify VPC Endpoint Service exists
aws ec2 describe-vpc-endpoint-service-configurations

# 2. Check service state and NLB association
aws ec2 describe-vpc-endpoint-service-configurations \
  --query "ServiceConfigurations[?contains(NetworkLoadBalancerArns[0], '<nlb-name>')].{ServiceName:ServiceName,State:ServiceState,NLB:NetworkLoadBalancerArns[0]}"

# 3. Verify NLB exists and is active
aws elbv2 describe-load-balancers --names <nlb-name> \
  --query 'LoadBalancers[0].{State:State.Code,DNS:DNSName}'
```

**Common Issues and Resolutions:**

**Issue: "No ServiceConfigurations returned"**
- **Cause**: VPC Endpoint Service wasn't created or wrong region
- **Fix**: Re-create the endpoint service, ensure you're querying the correct AWS region
- **Verification**: Check AWS Console → VPC → Endpoint Services for manual confirmation

**Issue: "ServiceState shows 'Failed'"**
- **Cause**: NLB doesn't exist, was deleted, or wrong NLB ARN was specified
- **Fix**: Verify NLB exists with `aws elbv2 describe-load-balancers --names <nlb-name>`
- **Resolution**: Delete failed service and recreate with correct NLB selection

**Issue: "NetworkLoadBalancerArns doesn't match my NLB"**
- **Cause**: Wrong NLB was selected during service creation
- **Fix**: VPC Endpoint Service NLB association cannot be changed—must delete and recreate service
- **Prevention**: Verify NLB name carefully before creating endpoint service

**Issue: "Traffic not flowing through VPC Endpoint Service"**
- **Cause**: NLB targets are unhealthy or security group blocks traffic
- **Fix**: Check target health status (see Section 6.3)
- **Additional checks**: Verify security groups allow traffic on database port, check NACLs, verify routing

**Resolution Steps:**

1. **Recreate VPC Endpoint Service** (if in failed state):
```bash
# Delete the failed service
aws ec2 delete-vpc-endpoint-service-configurations \
  --service-ids vpce-svc-xxxxxxxxxxxxx

# Create new service with correct NLB
aws ec2 create-vpc-endpoint-service-configuration \
  --network-load-balancer-arns <correct-nlb-arn> \
  --acceptance-required
```

2. **Verify NLB is operational** (see Section 6.3 for NLB troubleshooting)
3. **Confirm target health** before expecting endpoint service to work

---

### Issue 6.1.5: Principal Allowlist Configuration Errors

**Symptoms:**
- Connection request not appearing in AWS console
- "Access denied" when provisioning endpoint from Snowflake
- Snowflake shows "Connection request failed"

**Possible Causes:**
1. Snowflake principal not in VPC Endpoint Service allowlist
2. Incorrect ARN format
3. Wrong Snowflake account ID for the region
4. Typo in principal ARN

**Diagnostic Steps:**

```bash
# 1. Check allowed principals on VPC Endpoint Service
aws ec2 describe-vpc-endpoint-service-permissions \
  --service-id vpce-svc-xxxxxxxxxxxxx

# 2. Verify Snowflake account principal from Snowflake
# Run in Snowflake:
SELECT key, value FROM TABLE(FLATTEN(INPUT => PARSE_JSON(SYSTEM$GET_PRIVATELINK_CONFIG())));
```

**Common Errors and Resolutions:**

**Error: "Connection request not appearing"**
- **Cause**: Snowflake principal not in allowlist or ARN format incorrect
- **Fix**: Verify ARN in allowlist matches EXACTLY what `SYSTEM$GET_PRIVATELINK_CONFIG()` returned
- **Verification**: Run `describe-vpc-endpoint-service-permissions` to confirm ARN is present

**Error: "Principal ARN is invalid"**
- **Cause**: Malformed ARN (typo, missing colons, incorrect account ID length)
- **Fix**: ARN must match format `arn:aws:iam::{12-digit-id}:{resource-type}/{resource-name}`
- **Verification**: Account ID must be exactly 12 digits, no spaces or special characters

**Error: "Access denied when provisioning endpoint"**
- **Cause**: Wrong Snowflake account ID for your region
- **Fix**: Re-run `SYSTEM$GET_PRIVATELINK_CONFIG()` in your Snowflake account (don't copy from documentation examples)
- **Verification**: Confirm your Snowflake account region matches the AWS VPC region

**Resolution:**

1. **Add correct principal to allowlist**:
```bash
# Get the correct principal from Snowflake first (see diagnostic steps above)
aws ec2 modify-vpc-endpoint-service-permissions \
  --service-id vpce-svc-xxxxxxxxxxxxx \
  --add-allowed-principals arn:aws:iam::123456789012:user/myorg-myaccount
```

2. **Verify addition was successful**:
```bash
aws ec2 describe-vpc-endpoint-service-permissions \
  --service-id vpce-svc-xxxxxxxxxxxxx
```

3. **Retry connection from Snowflake** after confirming principal is in allowlist

---

## 6.2. DNS Resolution Failures (AWS)

DNS resolution issues prevent applications from resolving on-premise hostnames even when network routes are correct. Common error messages include "getaddrinfo failed" or "Name or service not known." For more details on Route 53 Resolver configuration, see the Route 53 documentation[^60][^34][^33].

### Issue 6.2.1: DNS Query Timeout

**Symptoms:**
- Application shows DNS timeout errors
- `nslookup` or `dig` commands from container/instance time out
- No DNS response received after 5-10 seconds

**Possible Causes:**
1. Route 53 Resolver Outbound Endpoint not reachable from VPC
2. DNS forwarding rule not configured or not associated with VPC
3. On-premise DNS servers unreachable due to routing or firewall issues
4. UDP/TCP port 53 blocked by security groups or on-premise firewall

**Diagnostic Steps:**

```bash
# 1. Check Route 53 Resolver Outbound Endpoint status
aws route53resolver describe-resolver-endpoints \
  --resolver-endpoint-ids rslvr-out-xxxxxxxxxxxxxxxxx

# 2. Check forwarding rules
aws route53resolver list-resolver-rules \
  --query 'ResolverRules[?DomainName==`corp.local`]'

# 3. Check rule associations
aws route53resolver list-resolver-rule-associations \
  --query 'ResolverRuleAssociations[?VPCId==`vpc-xxxxxxxxxxxxxxxxx`]'

# 4. Test DNS from within VPC
# Launch EC2 instance in same VPC, then:
dig @192.168.1.10 sql-prod.corp.local  # Replace with on-prem DNS IP
```

**Resolution:**
1. **Create/Fix Forwarding Rule**: Ensure rule exists for on-premise domain (e.g., `corp.local` or `*.corp.local`)
2. **Associate Rule with VPC**: Verify forwarding rule is linked to the customer VPC
3. **Check Security Groups**: Allow UDP and TCP port 53 outbound from outbound endpoint subnet to on-premise DNS IPs
4. **Check On-Premise Firewall**: Allow UDP and TCP port 53 inbound from VPC CIDRs to on-premise DNS servers
5. **Verify Routing**: Ensure route table for outbound endpoint subnet has route to on-premise network via Transit Gateway

---

### Issue 6.2.2: NXDOMAIN Response (Domain Not Found)

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
   - Enable VPC DNS query logging in Route 53 Resolver
   - Verify query is being forwarded to on-premise DNS servers

**Resolution:**
1. **Add DNS Records**: Ensure on-premise DNS has A records for all required hostnames
2. **Update Forwarding Rule**: Modify domain pattern to match queries (use `*.` for wildcard if needed)
3. **Add Multiple Rules**: Create separate forwarding rules for each on-premise domain
4. **Verify Case Sensitivity**: Ensure hostname case matches DNS records

---

### Issue 6.2.3: Wrong IP Address Returned

**Symptoms:**
- DNS query returns an IP address, but it's the wrong one
- Connection attempts go to wrong server or fail with "Connection refused"

**Possible Causes:**
1. DNS query resolved by VPC-local Private Hosted Zone overriding on-premise DNS
2. Cached stale DNS record (old IP from before database moved)
3. Split-horizon DNS misconfiguration

**Diagnostic Steps:**
1. **Check DNS response source**:
```bash
dig sql-prod.corp.local +trace  # Shows which server answered
```

2. **Check for overlapping zones**:
   - Check Route 53 Private Hosted Zones associated with VPC
   - Look for zone with same domain name as on-premise domain

3. **Check TTL and caching**:
```bash
dig sql-prod.corp.local  # Look at TTL value in response
```

**Resolution:**
1. **Remove Overlapping Zones**: If a Private Hosted Zone has the same domain as on-premise, delete it or modify domain name
2. **Clear DNS Cache**: 
   - On-premise DNS: Clear server cache
   - Application: Restart application to clear client-side cache
3. **Update DNS Records**: Correct the IP address in the authoritative on-premise DNS server
4. **Reduce TTL**: If IPs change frequently, reduce TTL to 60-300 seconds

---

### Issue 6.2.4: Intermittent DNS Failures

**Symptoms:**
- DNS resolution works sometimes, fails other times
- Pattern may correlate with time of day, load, or specific servers

**Possible Causes:**
1. One on-premise DNS server is down (forwarding rule has multiple targets, some failing)
2. Network path intermittently congested (Transit Gateway, Direct Connect)
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
   - CloudWatch metrics for Direct Connect and Transit Gateway
   - Look for packet loss, latency spikes

**Resolution:**
1. **Fix/Replace Failed DNS Server**: Repair or remove unhealthy DNS server from forwarding rule targets
2. **Add More DNS Servers**: Increase redundancy by adding additional on-premise DNS servers
3. **Scale DNS Infrastructure**: Upgrade DNS server resources or distribute load
4. **Increase TTL**: Increase TTL to reduce query rate (balance against IP change frequency)
5. **Monitor Hybrid Connection Health**: Set up CloudWatch alarms for Direct Connect circuit issues

---

### Issue 6.2.5: Route 53 Resolver Configuration Issues

**Symptoms:**
- DNS queries timeout consistently
- Some DNS queries work while others fail
- Resolver endpoint creation fails
- DNS resolution works from some instances but not others

**Possible Causes:**
1. Outbound endpoint not operational
2. Security group blocking DNS traffic
3. Forwarding rule not associated with VPC
4. On-premise DNS servers unreachable
5. TCP port 53 blocked (causing large responses to fail)
6. Domain pattern mismatch in forwarding rules
7. Insufficient IP addresses in subnets for ENIs

**Diagnostic Steps:**

```bash
# 1. Check outbound endpoint status
aws route53resolver get-resolver-endpoint \
  --resolver-endpoint-id rslvr-out-xxxxxxxxxxxxx \
  --region us-east-1
# Status should be "OPERATIONAL"

# 2. Verify security group allows egress on port 53
aws ec2 describe-security-groups \
  --group-ids sg-xxxxxxxxxxxxx \
  --region us-east-1 \
  --query 'SecurityGroups[0].IpPermissionsEgress[?((ToPort==`53`))]'

# 3. Verify rule association exists and is active
aws route53resolver list-resolver-rule-associations \
  --filters Name=VPCId,Values=vpc-xxxxxxxxxxxxx \
  --region us-east-1

# 4. Test DNS resolution from within VPC
# SSH to EC2 instance in VPC and test:
dig @10.0.1.10 db-server.corp.local  # Use on-prem DNS IP
nslookup db-server.corp.local
```

**Common Issues and Resolutions:**

**Issue: DNS Queries Timeout**

Possible causes and resolutions:

1. **Outbound endpoint not operational**
   - **Check Status**: Verify endpoint status is "OPERATIONAL" (see diagnostic steps above)
   - **Check ENIs**: Ensure ENIs are in "in-use" state and have IP addresses assigned
   - **Fix**: If failed, delete and recreate endpoint in operational subnets

2. **Security group blocking DNS traffic**
   - **Verify Rules**: Ensure security group attached to resolver endpoint allows egress:
     - UDP port 53 to on-premise DNS servers
     - TCP port 53 to on-premise DNS servers (for large responses)
   - **Fix**: Add egress rules for both UDP and TCP port 53 to on-premise DNS server IPs

3. **Rule not associated with VPC**
   - **Verify Association**: Check that forwarding rule is associated with the VPC (see diagnostic step #3)
   - **Fix**: Associate the rule with the VPC:
   ```bash
   aws route53resolver associate-resolver-rule \
     --resolver-rule-id rslvr-rr-xxxxxxxxxxxxx \
     --vpc-id vpc-xxxxxxxxxxxxx
   ```

4. **On-premise DNS servers unreachable**
   - **Check Connectivity**: Verify Transit Gateway/VPN connection is operational
   - **Check Routes**: Ensure route table has route to on-premise CIDR via Transit Gateway
   - **Check Firewall**: Verify on-premise firewall allows DNS traffic from VPC CIDR
   - **Test**: Use VPC Reachability Analyzer to test path to on-premise DNS server

**Issue: Some DNS Queries Work, Others Fail**

Possible causes:

1. **TCP port 53 blocked** (large responses failing)
   - **Why**: DNS responses larger than 512 bytes (common with DNSSEC or many records) require TCP
   - **Verify**: Check if security group allows BOTH UDP and TCP port 53
   - **Fix**: Add TCP port 53 egress rule to security group
   - **Verify NACLs**: Ensure network ACLs also allow both UDP and TCP on port 53

2. **Domain pattern mismatch**
   - **Check Pattern**: Verify domain pattern in forwarding rule matches query pattern
   - **Leading Dot**: Use `.corp.local` to match all subdomains (e.g., `db.corp.local`, `app.corp.local`)
   - **Exact Match**: Use `corp.local` to match only the exact domain
   - **Wildcard**: Use `*` to forward all queries
   - **Fix**: Update forwarding rule with correct domain pattern
   - **Check Conflicts**: Look for conflicting rules with different targets that might match the same domain

**Issue: Endpoint Creation Fails**

Possible causes:

1. **Insufficient IP addresses in subnets**
   - **Requirement**: Each ENI needs 1 IP address from the subnet
   - **Verify**: Check subnet has available IPs (AWS Console → VPC → Subnets → Available IPs)
   - **Fix**: Use a subnet with more available IPs or create a new subnet with larger CIDR

2. **Subnets in wrong configuration**
   - **Multi-AZ Requirement**: Endpoint requires at least 2 ENIs in different Availability Zones
   - **Fix**: Select subnets in at least 2 different AZs

3. **IAM permissions missing**
   - **Required**: User needs `route53resolver:CreateResolverEndpoint` permission
   - **Fix**: Add required IAM permissions to user/role

**Resolution Summary:**

1. **For timeout issues**:
   - Verify endpoint is OPERATIONAL
   - Check security groups allow UDP AND TCP port 53
   - Confirm rule is associated with VPC
   - Test connectivity to on-premise DNS servers

2. **For intermittent failures**:
   - Add TCP port 53 rules (if only UDP was configured)
   - Verify both security groups AND network ACLs allow DNS traffic
   - Check domain pattern syntax in forwarding rules

3. **For creation failures**:
   - Ensure subnets have available IPs
   - Use subnets in different Availability Zones
   - Verify IAM permissions

---

## 6.3. Network Load Balancer Health Check Failures

NLB health checks control which backend targets receive traffic. When health checks fail, traffic is blocked even if the database is running.

### Issue 6.3.1: All Targets Showing Unhealthy

**Symptoms:**
- AWS NLB shows all targets in target group as "Unhealthy"
- Application connections fail with immediate "Connection refused" or timeout
- NLB returns 503 errors (no healthy targets available)

**Possible Causes:**
1. Database listener not running or not accepting connections
2. Firewall blocking health check probes from NLB
3. Health check configured for wrong port or protocol
4. Database server network unreachable from load balancer subnet
5. Health check timeout too short for network latency over Direct Connect

**Diagnostic Steps:**

```bash
# 1. Check target health and reason
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:region:account:targetgroup/... \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]'

# 2. Check health check configuration
aws elbv2 describe-target-groups \
  --target-group-arns arn:aws:elasticloadbalancing:... \
  --query 'TargetGroups[0].{Protocol:HealthCheckProtocol,Port:HealthCheckPort,Interval:HealthCheckIntervalSeconds,Timeout:HealthCheckTimeoutSeconds}'

# 3. Test connectivity from VPC to on-premise DB
# Launch EC2 in NLB subnet, test:
telnet 10.50.100.25 1433  # Should connect
nc -zv 10.50.100.25 1433  # Alternative test
```

**Resolution:**

1. **Verify Database Listener Running**:
   - SQL Server: Check SQL Server service status, verify TCP/IP protocol enabled
   - Oracle: Check listener status with `lsnrctl status`
   - MySQL/PostgreSQL: Check service status with `systemctl status mysql/postgresql`

2. **Check Database Listener Binding**:
   - Ensure listener bound to `0.0.0.0` (all interfaces) or specific NIC IP
   - SQL Server: SQL Server Configuration Manager → Protocols → TCP/IP → IP Addresses
   - Oracle: Check `listener.ora` HOST parameter
   - MySQL: Check `bind-address` in `my.cnf`
   - PostgreSQL: Check `listen_addresses` in `postgresql.conf`

3. **Fix Firewall Rules**:
   - On-premise firewall: Allow TCP connections from VPC CIDR to database IP:port
   - OS firewall on DB server: Allow TCP on database port from NLB subnets
   - Network ACLs: Ensure both inbound (database port) and outbound (ephemeral ports) rules exist

4. **Adjust Health Check Parameters for Hybrid Connectivity**:
   - Increase `HealthCheckIntervalSeconds` to 30
   - Increase `HealthCheckTimeoutSeconds` to 10
   - This accounts for additional latency over Transit Gateway and Direct Connect

5. **Verify Routing**:
   - Ensure NLB subnet route table has route to on-premise CIDR via Transit Gateway
   - Check Transit Gateway route propagation for on-premise routes

---

### Issue 6.3.2: Intermittent Health Check Failures

**Symptoms:**
- Targets flip between "Healthy" and "Unhealthy" states
- Connection success rate less than 100%
- Pattern may correlate with database load or time of day

**Possible Causes:**
1. Database server CPU/memory overloaded, slow to respond to health checks
2. Network path intermittently congested or experiencing packet loss
3. Health check interval too short relative to database response time
4. Database connection pool exhausted

**Diagnostic Steps:**
1. **Monitor Database Performance**:
   - Check CPU, memory, disk I/O on database server during health check failures
   - Review database logs for connection errors or timeouts

2. **Monitor Network Path**:
   - CloudWatch metrics for NLB (`HealthyHostCount`, `UnHealthyHostCount`)
   - CloudWatch metrics for Transit Gateway (`BytesIn`, `BytesOut`, `PacketLoss`)
   - CloudWatch metrics for Direct Connect (`ConnectionBpsEgress`, `ConnectionBpsIngress`)

3. **Review Health Check Timing**:
   - Calculate total time: Network latency (round-trip) + database response time
   - Compare to health check timeout setting

**Resolution:**
1. **Scale Database Resources**: Increase CPU, memory, or use faster storage
2. **Optimize Database**: Index optimization, query performance tuning, connection pooling
3. **Increase Health Check Intervals**:
   - Increase interval from 10s to 30s
   - Increase timeout from 2s to 10s
4. **Add Database Replicas**: Distribute load across multiple database instances in target group
5. **Upgrade Direct Connect**: If network path is bottleneck, increase port speed

---

### Issue 6.3.3: Target Never Becomes Healthy (New Target)

**Symptoms:**
- Newly added target to target group never transitions to "Healthy" state
- Other existing targets remain healthy
- Connections to the new target fail

**Possible Causes:**
1. Wrong IP address configured in target group
2. New database server firewall rules not configured
3. Database not yet running or still initializing
4. Network route to new target not yet propagated via BGP

**Diagnostic Steps:**
1. **Verify Target IP**:
```bash
aws elbv2 describe-target-health --target-group-arn <arn> \
  --query 'TargetHealthDescriptions[*].Target'
```

2. **Test Direct Connectivity**:
   - From EC2 instance in NLB subnet, test connectivity to new target IP:port
   - Should succeed if configuration is correct

3. **Check Database Status**:
   - Verify database service running on new server
   - Verify listener accepting connections

**Resolution:**
1. **Correct Target IP**: Update target group with correct IP address
2. **Configure Firewall**: Ensure all firewall rules allow traffic from VPC to new database server
3. **Wait for Database Initialization**: Some databases take minutes to become ready after service start
4. **Verify BGP Route Advertisement**: If new database is in new subnet, ensure on-premise router is advertising the subnet CIDR via BGP to Direct Connect

---

### Issue 6.3.4: Common NLB Configuration Errors

This section documents typical beginner mistakes when configuring NLB and target groups for on-premise database connectivity. Each error includes the mistake description, why it causes problems, and step-by-step resolution.

**Error 1: Selecting Public Subnets for Internal NLB**

**The Mistake:**
Creating an internal NLB but selecting public subnets (subnets with routes to an Internet Gateway) instead of private subnets.

**Why It Causes Problems:**
- Internal NLBs require private subnets (no Internet Gateway route) to maintain the internal-only access pattern
- AWS Console may allow the configuration but the NLB will fail to provision correctly
- Violates security best practice of keeping database connectivity off public networks

**Error Message:**
```
"The load balancer subnets cannot be associated with a route table that includes an internet gateway."
```

**Resolution:**
1. Delete the misconfigured NLB (it won't provision successfully)
2. Identify your private subnets: **VPC Console** > **Subnets** > Check **Route Table** column
   - Private subnet: Route table has NO route to `igw-` (Internet Gateway)
   - Public subnet: Route table has route `0.0.0.0/0 → igw-xxxxx`
3. Recreate NLB selecting only private subnets
4. **Prevention**: Before creating NLB, verify subnet type in VPC console

---

**Error 2: Selecting Only One Subnet / Same AZ**

**The Mistake:**
Creating NLB with only one subnet or selecting multiple subnets that are all in the same Availability Zone.

**Why It Causes Problems:**
- Single AZ deployment has no fault tolerance—if that AZ fails, your entire connection goes down
- AWS best practices require multi-AZ for production workloads
- Snowflake connections will fail if the single AZ experiences an outage

**Warning Message:**
```
"It is recommended to enable at least two Availability Zones for high availability."
```

**Resolution:**
1. Edit the NLB configuration (or recreate if just created)
2. Navigate to: **Load Balancers** > Select your NLB > **Actions** > **Edit subnets**
3. Select additional subnets ensuring they are in **different AZs** (e.g., us-west-2a AND us-west-2b)
4. Save changes
5. **Prevention**: Always select "at least 2 subnets in different AZs" as documented in configuration steps

---

**Error 3: Using Instance Target Type for On-Premise Database**

**The Mistake:**
Creating target group with "Instance" target type instead of "IP address" target type when configuring connectivity to on-premise databases.

**Why It Causes Problems:**
- Instance targets expect EC2 instance IDs (e.g., `i-1234567890abcdef0`)
- On-premise databases don't have EC2 instance IDs—they only have IP addresses
- Cannot register on-premise database targets with instance-type target groups

**Error Message When Registering Target:**
```
"Invalid target ID. Instance 'i-10.50.100.25' does not exist."
```

**Resolution:**
1. Delete the misconfigured target group (cannot change target type after creation)
2. Create new target group with correct settings:
   - **Target type**: IP addresses
   - **Protocol**: TCP
   - **Port**: Your database port
   - **VPC**: Same VPC as NLB
3. Register on-premise database IP addresses as targets
4. Reattach new target group to NLB listener
5. **Prevention**: Always select "IP addresses" target type for on-premise or container-based targets

---

**Error 4: Health Check Timeout Greater Than Interval**

**The Mistake:**
Configuring health check timeout value that is greater than or equal to the interval value (e.g., timeout 30s, interval 30s or timeout 35s, interval 30s).

**Why It Causes Problems:**
- AWS enforces the constraint: `Timeout < Interval`
- Logically impossible: Can't wait 30 seconds for response when checks occur every 30 seconds
- Health check configuration will be rejected

**Error Message:**
```
"Health check timeout must be less than the health check interval."
```

**Resolution:**
1. Adjust health check settings in target group:
   - **Navigation**: **Target Groups** > Select your TG > **Health checks** tab > **Edit**
2. Ensure: **Timeout < Interval**
   - Example valid config: Interval 30s, Timeout 10s ✅
   - Example invalid config: Interval 30s, Timeout 30s ❌
3. Recommended for hybrid connectivity: Interval 30s, Timeout 10s
4. **Prevention**: Remember the constraint `Timeout < Interval` when configuring health checks

---

**Error 5: Wrong Protocol for Database Health Checks**

**The Mistake:**
Selecting HTTP or HTTPS health check protocol for database targets that don't serve HTTP endpoints.

**Why It Causes Problems:**
- Most databases (SQL Server, MySQL, PostgreSQL) don't natively serve HTTP endpoints
- HTTP health checks will always fail because the database can't respond to HTTP GET requests
- Targets remain perpetually "unhealthy" even though database is running fine

**Symptoms:**
- Target health status stuck in "unhealthy"
- Error reason: "Health checks failed"
- Database connection works fine when tested directly

**Resolution:**
1. Change health check protocol to TCP:
   - **Navigation**: **Target Groups** > Select your TG > **Health checks** tab > **Edit**
2. Set **Protocol** to **TCP**
3. Ensure **Port** matches your database port (e.g., 1433 for SQL Server)
4. Wait ~90 seconds for health checks to transition to "healthy"
5. **Prevention**: Use TCP health checks for database targets (checks if port is open and accepting connections)

---

**Error 6: Target Registered with Wrong Port**

**The Mistake:**
Registering target with incorrect port number (e.g., registering with port 3306 when database actually listens on port 3301).

**Why It Causes Problems:**
- Health checks attempt to connect to wrong port
- NLB forwards traffic to wrong port where nothing is listening
- Target remains "unhealthy" and connections fail

**Symptoms:**
- Target health: "unhealthy"
- Error reason: "Target.FailedHealthChecks" or "Target.Timeout"
- Direct connection to database on correct port works fine

**Resolution:**
1. Verify actual database port:
   ```bash
   # Test from VPC instance or on-premise
   telnet 10.50.100.25 1433
   # Or
   nc -zv 10.50.100.25 1433
   ```
2. Deregister incorrect target:
   - **Target Groups** > Select TG > **Targets** tab > Select target > **Deregister**
3. Register target with correct port:
   - **Register targets** > Enter IP `10.50.100.25` > Port `1433` (correct port)
4. **Prevention**: Verify database listening port before registering target

---

**Error 7: Security Group Doesn't Allow NLB Health Check Traffic**

**The Mistake:**
Database target's security group blocks inbound traffic from the NLB subnets or VPC CIDR, preventing health checks from reaching the target.

**Why It Causes Problems:**
- Health checks originate from NLB nodes in your VPC subnets
- If security group blocks this traffic, health checks time out
- Target remains "unhealthy" even though database is accessible

**Symptoms:**
- Target health: "unhealthy"
- Error reason: "Target.Timeout"
- Health checks timing out consistently

**Resolution:**
1. Identify NLB subnet CIDR blocks:
   - **VPC Console** > **Subnets** > Find subnets used by NLB > Note CIDR (e.g., 10.0.1.0/24)
2. Update target (database) security group:
   - **EC2 Console** > **Security Groups** > Find target's SG
3. Add inbound rule:
   - **Type**: Custom TCP
   - **Port**: Your database port (e.g., 1433)
   - **Source**: NLB subnet CIDRs or entire VPC CIDR (e.g., 10.0.0.0/16)
   - **Description**: "Allow NLB health checks"
4. Save changes
5. Wait ~90 seconds for target to become healthy
6. **Prevention**: Configure security groups before creating NLB

---

**Error 8: Listener Port Doesn't Match Target Group Port**

**The Mistake:**
NLB listener configured for one port (e.g., TCP:1433) but target group uses a different port (e.g., 3306), causing port mismatch.

**Why It Causes Problems:**
- Snowflake connects to NLB listener port (e.g., 1433)
- NLB forwards to target group's port (e.g., 3306)
- Database not listening on forwarded port, connections fail

**Symptoms:**
- Targets show "healthy" (health checks work)
- Actual database connections fail or timeout
- Port mismatch in traffic flow

**Resolution:**
1. Determine correct port:
   - What port does Snowflake expect? (usually database default)
   - What port is database actually listening on?
2. Option A: Change listener port to match target group:
   - **Load Balancers** > Select NLB > **Listeners** tab
   - Delete existing listener, create new with correct port
3. Option B: Change target group port to match listener:
   - Cannot change existing target group port
   - Create new target group with correct port
   - Update listener to use new target group
4. **Prevention**: Ensure listener port and target port match throughout configuration

---

**Error 9: Forgetting to Record NLB DNS Name**

**The Mistake:**
Completing NLB configuration but not recording the DNS name needed for Snowflake configuration and VPC Endpoint Service creation.

**Why It Causes Problems:**
- DNS name is required for Snowflake external access integration
- DNS name format: `<nlb-name>-<random-id>.elb.<region>.amazonaws.com`
- Must be copied exactly (including random ID)
- Later steps cannot proceed without this value

**Symptoms:**
- Needing to return to Load Balancers console to find DNS name
- Risk of using incorrect or outdated DNS name

**Resolution:**
1. Find NLB DNS name:
   - **EC2 Console** > **Load Balancers** > Select your NLB
   - Copy **DNS name** from **Description** tab
2. Or use AWS CLI:
   ```bash
   aws elbv2 describe-load-balancers --names your-nlb-name \
     --query 'LoadBalancers[0].DNSName' --output text
   ```
3. Document in your configuration file or runbook
4. **Prevention**: Record DNS name immediately after NLB becomes "active"

---

**Error 10: Not Waiting for Health Checks to Complete**

**The Mistake:**
Attempting to use NLB immediately after creation before health checks have had time to mark targets as "healthy".

**Why It Causes Problems:**
- Targets start in "initial" state
- Takes ~90 seconds for 3 consecutive successful health checks (with default 30s interval)
- NLB won't route traffic to targets in "initial" state
- Premature connection attempts fail

**Symptoms:**
- "No healthy targets available" errors
- Connection refused or timeout
- Works fine after waiting a few minutes

**Resolution:**
1. Check target health status:
   - **Target Groups** > Select your TG > **Targets** tab
   - Or use CLI:
   ```bash
   aws elbv2 describe-target-health --target-group-arn <arn>
   ```
2. Wait for state transition: `initial` → `healthy`
   - Expected time: ~90 seconds (3 checks × 30s interval)
3. Only proceed to next configuration steps after targets show "healthy"
4. **Prevention**: Always verify target health before moving forward

---

**Error 11: Cross-Region Configuration (NLB and Target in Different Regions)**

**The Mistake:**
Attempting to create NLB in one AWS region (e.g., us-west-2) while target database or Direct Connect is in a different region (e.g., us-east-1).

**Why It Causes Problems:**
- NLBs can only route to targets within the same region
- Cross-region connectivity requires different architecture (Transit Gateway peering or AWS PrivateLink cross-region)
- Health checks and traffic routing will fail

**Error Message:**
```
"The specified target group does not exist in this region."
```

**Resolution:**
1. Verify your architecture:
   - Where is your Direct Connect attachment located? (region)
   - Where is Transit Gateway deployed? (region)
   - Where do you want the NLB? (must be same region as above)
2. Create NLB in the **same region** as your hybrid network infrastructure
3. If you need cross-region connectivity, consult AWS documentation for Transit Gateway inter-region peering
4. **Prevention**: Plan region architecture before creating resources

---

**Error 12: Missing IAM Permissions to Create NLB**

**The Mistake:**
Attempting to create NLB or target groups without sufficient IAM permissions, resulting in access denied errors.

**Why It Causes Problems:**
- Load balancer creation requires specific IAM permissions
- Without proper permissions, operations fail silently or with cryptic errors
- Common in environments with restrictive IAM policies

**Error Message:**
```
"User: arn:aws:iam::123456789012:user/username is not authorized to perform: elasticloadbalancing:CreateLoadBalancer"
```

**Required IAM Permissions:**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs"
    ],
    "Resource": "*"
  }]
}
```

**Resolution:**
1. Request IAM permissions from your AWS administrator
2. Verify your current permissions:
   ```bash
   aws iam get-user-policy --user-name your-username --policy-name your-policy
   ```
3. If using IAM roles, attach the required policy to your role
4. **Prevention**: Verify IAM permissions before starting NLB configuration

---

## 6.4. AWS Direct Connect Issues

Direct Connect issues affect both data traffic and DNS resolution, as both traverse the Direct Connect circuit. For monitoring and troubleshooting guidance, see the Direct Connect CloudWatch documentation[^54].

### Issue 6.4.1: BGP Session Down

**Symptoms:**
- No connectivity from AWS to on-premise (complete outage)
- Direct Connect shows BGP session state as "Down"
- Routes from on-premise not appearing in Transit Gateway route tables

**Possible Causes:**
1. Physical circuit down (fiber cut, equipment failure at provider)
2. BGP configuration mismatch (wrong ASN, authentication key, or peering IPs)
3. On-premise router BGP process not running
4. Firewall blocking BGP traffic (TCP port 179)
5. Maximum prefix limit exceeded

**Diagnostic Steps:**

```bash
# 1. Check Direct Connect connection status
aws directconnect describe-connections \
  --connection-id dxcon-xxxxxxxxxxxxxxxxx

# 2. Check Virtual Interface status
aws directconnect describe-virtual-interfaces \
  --virtual-interface-id dxvif-xxxxxxxxxxxxxxxxx

# 3. Check BGP peer status
aws ec2 describe-transit-gateway-attachments \
  --filters Name=resource-id,Values=tgw-attach-xxxxxxxxxxxxxxxxx

# 4. Check Transit Gateway BGP details
aws ec2 describe-transit-gateway-route-tables \
  --transit-gateway-route-table-ids tgw-rtb-xxxxxxxxxxxxxxxxx
```

**On-Premise:**
```bash
# Check BGP neighbor status (Cisco example)
show ip bgp summary
show ip bgp neighbors <aws-bgp-peer-ip>
```

**Resolution:**

1. **Physical Circuit Issues**:
   - Contact AWS Direct Connect provider for circuit status
   - Check AWS Service Health Dashboard for known issues
   - If circuit down, provider must repair

2. **BGP Configuration Mismatch**:
   - **ASN Mismatch**: Verify on-premise router ASN matches what's configured in AWS DXGW
   - **Authentication Key**: Verify MD5 authentication key matches on both sides (case-sensitive)
   - **Peering IPs**: Verify /30 subnet configuration matches on both sides

3. **BGP Process Not Running**:
   - On-premise: Restart BGP process or router BGP daemon
   - Check router logs for BGP process crashes

4. **Firewall Blocking BGP**:
   - Ensure TCP port 179 allowed between on-premise router and AWS BGP peer IPs

5. **Maximum Prefix Limit**:
   - Increase Direct Connect Gateway max prefix limit
   - Or reduce number of advertised routes (use BGP summarization)
   - Reset BGP session after increasing limit

---

### Issue 6.4.2: Routes Not Propagating

**Symptoms:**
- BGP session shows "Up" status
- Connectivity partially works (some subnets reachable, others not)
- Some on-premise routes missing from Transit Gateway route tables

**Possible Causes:**
1. On-premise router not advertising specific subnets via BGP
2. Route filtering or route maps blocking specific prefixes
3. Transit Gateway route table not propagating routes correctly
4. Maximum routes limit reached
5. IP prefix overlap causing route selection issues

**Diagnostic Steps:**

```bash
# 1. Check routes learned by Transit Gateway
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id tgw-rtb-xxxxxxxxxxxxxxxxx \
  --filters Name=type,Values=propagated

# 2. Check Direct Connect Gateway route advertisements
aws directconnect describe-direct-connect-gateway-attachments \
  --direct-connect-gateway-id <dxgw-id>

# 3. Check VPC route table
aws ec2 describe-route-tables --route-table-ids rtb-xxxxxxxxxxxxxxxxx

# 4. Check allowed prefixes on Transit Gateway attachment
aws ec2 describe-transit-gateway-attachments \
  --transit-gateway-attachment-ids tgw-attach-xxxxxxxxxxxxxxxxx
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

3. **Fix Transit Gateway Route Propagation**:
   - Ensure Transit Gateway route table has propagation enabled for Direct Connect Gateway attachment
   - Verify route table associations are correct

4. **Increase Route Limits**:
   - Request AWS service limit increase for Direct Connect Gateway routes (default 20, max 1000+)

5. **Resolve IP Overlap**:
   - If VPC CIDR overlaps with on-premise CIDR, more specific route wins
   - May require CIDR redesign or use of NAT

---

### Issue 6.4.3: Intermittent Connectivity

**Symptoms:**
- Connectivity works most of the time but occasionally fails
- Pattern may show regular intervals
- Symptoms may correlate with high traffic volume

**Possible Causes:**
1. Direct Connect bandwidth saturated during peak usage
2. AWS provider network maintenance or congestion
3. BGP route flapping
4. Packet loss due to circuit errors

**Diagnostic Steps:**

1. **Monitor Circuit Utilization**:
```bash
# Get CloudWatch metrics for Direct Connect
aws cloudwatch get-metric-statistics \
  --namespace AWS/DX \
  --metric-name ConnectionBpsEgress \
  --dimensions Name=ConnectionId,Value=dxcon-xxxxx \
  --start-time 2025-11-07T00:00:00Z \
  --end-time 2025-11-07T01:00:00Z \
  --period 300 \
  --statistics Average,Maximum
```

2. **Check for Packet Loss**:
   - Run continuous ping tests from EC2 to on-premise and vice versa
   - Monitor packet loss percentage and latency

3. **Review BGP Route Stability**:
   - Check for frequent route withdrawals and re-advertisements
   - Look for BGP flapping in router logs

**Resolution:**

1. **Increase Circuit Bandwidth**:
   - If utilization consistently exceeds 70-80%, upgrade Direct Connect port speed
   - Options: 1 Gbps, 10 Gbps, 100 Gbps

2. **Implement QoS**:
   - Prioritize critical traffic (database queries, DNS) over bulk data transfers
   - Configure QoS policies on on-premise router

3. **Add Redundant Circuit**:
   - Add second Direct Connect connection for redundancy
   - Configure with separate circuit and physical path for true resilience

4. **Fix BGP Route Flapping**:
   - Implement BGP damping to suppress flapping routes
   - Investigate root cause of route instability

5. **Contact AWS**:
   - If packet loss or errors persist, open AWS Support case
   - Request Direct Connect circuit testing

---

## 6.5. On-Premise Connectivity Failures

Issues within the on-premise network are often the most challenging to diagnose due to multiple security layers and organizational boundaries. These issues are common to both AWS and Azure implementations.

### Issue 6.5.1: Firewall Blocking Traffic

**Symptoms:**
- Connections time out after passing through AWS environment
- Traceroute from EC2 shows packets reaching on-premise edge router but going no further
- On-premise firewall logs show dropped packets from VPC CIDR ranges

**Possible Causes:**
1. Perimeter firewall rules not configured to allow traffic from VPC CIDRs
2. Internal firewall between network zones blocking traffic
3. Host-based firewall on database server blocking connections
4. Firewall rule specifies wrong source IP, destination IP, or port

**Diagnostic Steps:**

1. **Review Firewall Logs**:
   - Check perimeter firewall logs for blocks from source IPs in VPC CIDR ranges
   - Note exact source IP, destination IP, and port of blocked traffic

2. **Test from Different Locations**:
   - Test from EC2 → on-premise edge: Should succeed if Direct Connect working
   - Test from edge → database: If fails, issue is within on-premise network
   - Test from another on-premise server → database: If succeeds, confirms database reachable

3. **Verify Firewall Rule Configuration**:
   - Confirm rules exist for:
     - Source: VPC CIDR (e.g., `172.16.0.0/16`)
     - Destination: Database server IP (e.g., `10.50.100.25`)
     - Port: Database port (1433, 1521, 3306, 5432)
     - Protocol: TCP
     - Action: ALLOW

**Resolution:**

1. **Add Perimeter Firewall Rules**:
```
Rule Name: Allow_AWS_to_Database
Source: 172.16.0.0/16 (VPC CIDR)
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
New-NetFirewallRule -DisplayName "Allow SQL from AWS" `
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

### Issue 6.5.2: Database Listener Not Responding

*See detailed database listener configuration in Section 6.5.1 resolution steps.*

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

### Issue 6.5.3: Authentication Failures

*Authentication issues are database-specific and apply to both AWS and Azure implementations. See database-specific resolution steps in the general troubleshooting section.*

**Quick Resolution Steps:**
1. Verify credentials in Snowflake secret match database user
2. Ensure database user allows connections from AWS VPC CIDR (not restricted to specific IPs)
3. For SQL Server: Ensure "SQL Server and Windows Authentication mode" enabled
4. For MySQL: Create user with host `'%'` or `'172.16.%'` to allow cloud connections

---

## 6.6. General Troubleshooting Methodology (AWS)

When facing connectivity issues in AWS hybrid architecture, use this systematic approach:

### 1. Isolate the Layer
Work through the networking stack to isolate the issue:
- **Layer 3 (Network)**: Can you ping/traceroute across Direct Connect?
- **Layer 4 (Transport)**: Can you establish TCP connection via NLB?
- **Layer 7 (Application)**: Does database authentication work?

### 2. Test from Multiple AWS Locations
- From Snowflake SPCS container (if accessible for testing)
- From EC2 instance in same VPC as VPC Endpoint
- From EC2 instance in NLB subnet
- From on-premise server

### 3. Check Both Directions
- AWS VPC → On-premise (forward path)
- On-premise → AWS VPC (return path for stateless NACLs)

### 4. Enable AWS Logging
- **VPC Flow Logs**: Capture accepted/rejected traffic at ENI level
- **CloudTrail**: Track API calls and configuration changes
- **CloudWatch Logs**: NLB access logs, resolver query logs
- **Firewall logs**: On-premise perimeter and internal firewalls

### 5. Monitor AWS Metrics
- NLB: `HealthyHostCount`, `UnHealthyHostCount`, `ProcessedBytes`
- Direct Connect: `ConnectionState`, `ConnectionBpsEgress`, `ConnectionBpsIngress`
- Transit Gateway[^55]: `BytesIn`, `BytesOut`, `PacketsDrop` - use CloudWatch Logs Insights for TGW flow log analysis[^56]
- Route 53 Resolver: Query count, query duration

### 6. Engage Multiple Teams
- **AWS Cloud Team**: VPC, NLB, VPC Endpoint, Transit Gateway
- **Network Team**: Direct Connect, BGP, routing, firewalls
- **Database Team**: Listener, user accounts, performance
- **Snowflake Team**: EAI configuration, network rules

---

## 6.7. Useful AWS Diagnostic Commands

### VPC and PrivateLink Commands

```bash
# Check VPC Endpoint status
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids vpce-xxxxxxxxxxxxxxxxx

# Check VPC Endpoint Service
aws ec2 describe-vpc-endpoint-services \
  --service-names com.amazonaws.vpce.us-west-2.vpce-svc-xxxxx

# Check VPC Endpoint connections
aws ec2 describe-vpc-endpoint-connections \
  --filters Name=service-id,Values=vpce-svc-xxxxx

# Check Security Groups
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxxxxxxxxxx

# Check Network ACLs
aws ec2 describe-network-acls --network-acl-ids acl-xxxxxxxxxxxxxxxxx

# Check route tables
aws ec2 describe-route-tables --route-table-ids rtb-xxxxxxxxxxxxxxxxx
```

### Network Load Balancer Commands

```bash
# Check NLB details
aws elbv2 describe-load-balancers \
  --names my-network-load-balancer

# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# Check target group configuration
aws elbv2 describe-target-groups \
  --target-group-arns arn:aws:elasticloadbalancing:...

# Check listeners
aws elbv2 describe-listeners \
  --load-balancer-arn arn:aws:elasticloadbalancing:...
```

### Transit Gateway Commands

```bash
# Check Transit Gateway details
aws ec2 describe-transit-gateways \
  --transit-gateway-ids tgw-xxxxxxxxxxxxxxxxx

# Check TGW attachments
aws ec2 describe-transit-gateway-attachments \
  --filters Name=transit-gateway-id,Values=tgw-xxxxx

# Search TGW routes
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id tgw-rtb-xxxxx \
  --filters Name=type,Values=propagated

# Get TGW route table details
aws ec2 describe-transit-gateway-route-tables \
  --transit-gateway-route-table-ids tgw-rtb-xxxxx
```

### Direct Connect Commands

```bash
# Check Direct Connect connection status
aws directconnect describe-connections

# Check Virtual Interfaces
aws directconnect describe-virtual-interfaces

# Check Direct Connect Gateway
aws directconnect describe-direct-connect-gateways

# Check DXGW attachments
aws directconnect describe-direct-connect-gateway-attachments \
  --direct-connect-gateway-id <dxgw-id>

# Check VIF BGP peers
aws directconnect describe-virtual-interface-test-history \
  --virtual-interface-id dxvif-xxxxx
```

### Route 53 Resolver Commands

```bash
# Check resolver endpoints
aws route53resolver list-resolver-endpoints

# Check resolver rules
aws route53resolver list-resolver-rules

# Check rule associations
aws route53resolver list-resolver-rule-associations

# Get resolver query logs (if enabled)
aws route53resolver list-resolver-query-log-configs
```

### CloudWatch Metrics Commands

```bash
# Get NLB metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name HealthyHostCount \
  --dimensions Name=LoadBalancer,Value=net/my-nlb/xxxxx \
  --start-time 2025-11-07T00:00:00Z \
  --end-time 2025-11-07T01:00:00Z \
  --period 300 \
  --statistics Average

# Get Direct Connect metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/DX \
  --metric-name ConnectionBpsEgress \
  --dimensions Name=ConnectionId,Value=dxcon-xxxxx \
  --start-time 2025-11-07T00:00:00Z \
  --end-time 2025-11-07T01:00:00Z \
  --period 300 \
  --statistics Average,Maximum

# Get Transit Gateway metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/TransitGateway \
  --metric-name BytesIn \
  --dimensions Name=TransitGateway,Value=tgw-xxxxx \
  --start-time 2025-11-07T00:00:00Z \
  --end-time 2025-11-07T01:00:00Z \
  --period 300 \
  --statistics Sum
```

### Connectivity Testing Commands

```bash
# From EC2 instance in VPC:

# Test TCP connectivity to on-premise database
telnet 10.50.100.25 1433
nc -zv 10.50.100.25 1433

# Test DNS resolution
dig sql-prod.corp.local
nslookup sql-prod.corp.local

# Test via NLB DNS name
telnet nlb-xxxxx.elb.us-west-2.amazonaws.com 1433

# Traceroute to on-premise
traceroute -T -p 1433 10.50.100.25

# Continuous ping test
ping -c 100 10.50.100.25
```

---

## References

[^6]: External network access and private connectivity on AWS, https://docs.snowflake.com/en/developer-guide/external-network-access/creating-using-private-aws
[^9]: How AWS Transit Gateway works - Amazon VPC, https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html
[^22]: AWS PrivateLink and Snowflake, https://docs.snowflake.com/en/user-guide/admin-security-privatelink
[^33]: Route 53 Resolver endpoints and forwarding rules - Hybrid Cloud DNS Options for Amazon VPC, https://docs.aws.amazon.com/whitepapers/latest/hybrid-cloud-dns-options-for-vpc/route-53-resolver-endpoints-and-forwarding-rules.html
[^34]: Configure Route 53 Resolver outbound endpoint for VPC DNS, https://repost.aws/knowledge-center/route53-resolve-with-outbound-endpoint
[^53]: AWS PrivateLink and Snowflake detailed troubleshooting Guide, https://community.snowflake.com/s/article/AWS-PrivateLink-and-Snowflake-detailed-troubleshooting-Guide
[^54]: Monitor with Amazon CloudWatch - AWS Direct Connect, https://docs.aws.amazon.com/directconnect/latest/UserGuide/monitoring-cloudwatch.html
[^55]: CloudWatch metrics in AWS Transit Gateway - Amazon VPC, https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-cloudwatch-metrics.html
[^56]: How can I use Cloudwatch logs insight to analyze Transit Gateway flow logs?, https://repost.aws/articles/ARTCqosbzeRIGtoDS4F-RqmA/how-can-i-use-cloudwatch-logs-insight-to-analyze-transit-gateway-flow-logs
[^60]: What is Amazon Route 53 Resolver? - AWS Documentation, https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html

---

*This AWS-specific troubleshooting guide provides systematic approaches to diagnosing and resolving connectivity issues. For Azure-specific guidance, see Chapter 7. For issues not covered here, contact AWS Support or Snowflake Support.*

