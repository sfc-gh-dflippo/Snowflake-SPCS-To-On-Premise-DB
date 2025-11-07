## Chapter 5\. SPCS Setup and Validation

Snowpark Container Services networking architecture[^38] enables containers to communicate with external resources securely. For SQL reference on creating External Access Integrations[^19], step-by-step EAI setup guide[^18], and retrieving data from external APIs with External Access[^20].

### 5.1. Deploying and Configuring an Openflow Snowpark Container Service

As of this writing, this is a public preview feature. You should double check the current documentation here:
[https://docs.snowflake.com/en/user-guide/data-integration/openflow/about-spcs](https://docs.snowflake.com/en/user-guide/data-integration/openflow/about-spcs)

#### 5.1.1. Initial Openflow DB Setup

If we are using Openflow, we start by setting up an OPENFLOW\_ADMIN role and SPCS to Snowflake network rule

```sql
SET OPENFLOW_ADMIN_USER = (SELECT CURRENT_USER());
USE ROLE ACCOUNTADMIN;

-- Create the OPENFLOW_ADMIN role
CREATE ROLE IF NOT EXISTS OPENFLOW_ADMIN;
GRANT ROLE OPENFLOW_ADMIN TO USER IDENTIFIER($OPENFLOW_ADMIN_USER);
ALTER USER IDENTIFIER($OPENFLOW_ADMIN_USER) SET DEFAULT_SECONDARY_ROLES = ('ALL');
GRANT CREATE OPENFLOW DATA PLANE INTEGRATION ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
GRANT CREATE OPENFLOW RUNTIME INTEGRATION ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
GRANT CREATE COMPUTE POOL ON ACCOUNT TO ROLE OPENFLOW_ADMIN;

-- Create the OPENFLOW database and schema
CREATE DATABASE IF NOT EXISTS OPENFLOW;
USE DATABASE OPENFLOW;
CREATE SCHEMA IF NOT EXISTS OPENFLOW;
USE SCHEMA OPENFLOW;
CREATE IMAGE REPOSITORY IF NOT EXISTS OPENFLOW;
grant usage on database OPENFLOW to role public;
grant usage on schema OPENFLOW to role public;
grant read on image repository OPENFLOW.OPENFLOW.OPENFLOW to role public;

-- Create network rule to allow SPCS to connect to Snowflake
-- These 10.16.x.x IP are not Internet routable and used internaly within Snowflake
CREATE NETWORK RULE IF NOT EXISTS ALLOW_OPENFLOW_SPCS
   MODE = INGRESS
   TYPE = IPV4
   VALUE_LIST = ('10.16.0.0/12');
-- Add this rules to the default account network policy
SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN ACCOUNT;
set account_level_network_policy_name = (select "value" from table(result_scan(last_query_id())));
ALTER NETWORK POLICY IDENTIFIER($account_level_network_policy_name) ADD ALLOWED_NETWORK_RULE_LIST= (ALLOW_OPENFLOW_SPCS);

```

#### 5.1.2. Create a deployment

1. Sign in to Snowsight with a role defined in Configure core Snowflake requirements.
2. Navigate to **Data** » **Ingestion** » **Openflow**.
3. Click "Launch Openflow" in the top right corner
4. Select OPENFLOW\_ADMIN as your role
5. In the Openflow UI, select Create a deployment. The Deployments tab opens.
6. Select Create a deployment. The Creating a deployment wizard opens.
7. In the Prerequisites step, ensure that you meet all the requirements. Select Next.
8. In the Deployment location step, select Snowflake as the deployment location. Enter a name for your deployment. Select Next.
9. Select Create Deployment.

Your deployment will then be created.

#### 5.1.3. Create a runtime role for Openflow

```sql
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS OPENFLOW_RUNTIME_ROLE_<RUNTIMENAME>;
GRANT ROLE OPENFLOW_RUNTIME_ROLE_<RUNTIMENAME> TO ROLE OPENFLOW_ADMIN;
GRANT USAGE, OPERATE ON WAREHOUSE <OPENFLOW_INGEST_WAREHOUSE> TO ROLE OPENFLOW_RUNTIME_ROLE_<RUNTIMENAME>;
GRANT USAGE ON DATABASE <OPENFLOW_SPCS_DATABASE> TO ROLE OPENFLOW_RUNTIME_ROLE_<RUNTIMENAME>;
GRANT USAGE ON SCHEMA <OPENFLOW_SPCS_SCHEMA> TO ROLE OPENFLOW_RUNTIME_ROLE_<RUNTIMENAME>;
```

#### 5.1.4. Grant External Access Integrations to Runtime Role

**Purpose:** Grant the runtime role permission to use External Access Integrations. This step must be completed BEFORE creating the runtime.

**When to perform this step:** After creating the runtime role (5.1.3) but before creating the runtime (5.1.6).

```sql
USE ROLE ACCOUNTADMIN;

-- Grant on-premise connectivity EAI to runtime role
-- This EAI contains PrivateLink network rules for on-premise database access
GRANT USAGE ON INTEGRATION aws_onprem_eai 
   TO ROLE OPENFLOW_RUNTIME_ROLE_<REPLACE_WITH_YOUR_RUNTIME_NAME>;

-- If using CDC, Streaming, or SaaS connectors, also grant Snowpipe Streaming EAI
-- This EAI enables access to Snowflake's internal S3 buckets for staging
GRANT USAGE ON INTEGRATION OPENFLOW_SSV1_EAI 
   TO ROLE OPENFLOW_RUNTIME_ROLE_<REPLACE_WITH_YOUR_RUNTIME_NAME>;
```

**Important Notes:**
- Replace `<REPLACE_WITH_YOUR_RUNTIME_NAME>` with the actual runtime role name you created in step 5.1.3
- The `aws_onprem_eai` should have been created in Chapter 3 (AWS) or Chapter 4 (Azure)
- Only EAIs that have been granted to the runtime role will appear in the UI dropdown during runtime creation
- For CDC/Streaming connectors, you must grant BOTH EAIs

**Verify the grants:**
```sql
SHOW GRANTS TO ROLE OPENFLOW_RUNTIME_ROLE_<YOUR_RUNTIME_NAME>;
-- Should include: "USAGE ON INTEGRATION AWS_ONPREM_EAI"
-- Should include: "USAGE ON INTEGRATION OPENFLOW_SSV1_EAI" (if using CDC/Streaming)
```

#### 5.1.5. Set up Snowpipe Streaming

When using any of the following connector types: Database CDC, SaaS, Streaming, Slack, you need to create an External Access Integration to ensure connectivity to Snowpipe Streaming.

To create a Snowpipe Streaming External Access Integration, perform the following steps:

```sql
-- Create a temp stage to determine the prefix needed for S3 bucket access from Openflow.
CREATE TEMPORARY STAGE my_int_stage
ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
Retrieve host name prefix from temporary stage.
SELECT GET_PRESIGNED_URL(@my_int_stage, '/', 3600);
-- For example if https://example-customer-stage.s3.us-west-2.amazonaws.com was returned, the <PREFIX> would be example-customer-stage.

-- Create network rule with <PREFIX>.s3.amazonaws.com:443 AND <PREFIX>.s3.
CREATE NETWORK RULE IF NOT EXISTS SSV1
  MODE = EGRESS
  TYPE = HOST_PORT
   VALUE_LIST = ('<PREFIX>.s3.amazonaws.com:443', '<PREFIX>.s3.us-west-2.amazonaws.com:443');

-- Create EAI for S3 Network rule
CREATE EXTERNAL ACCESS IF NOT EXISTS INTEGRATION OPENFLOW_SSV1_EAI
   ALLOWED_NETWORK_RULES = (SSV1)
   ENABLED = TRUE;

-- Grant usage on EAI to runtime role
GRANT USAGE ON INTEGRATION OPENFLOW_SSV1_EAI TO ROLE OPENFLOW_RUNTIME_ROLE_<RUNTIME_NAME>;
```

#### 5.1.6. Create a runtime environment in your Snowflake Deployment

1. Sign in to Snowsight.
2. Navigate to **Data** » **Ingestion** » **Openflow**.
3. Select **Launch Openflow**. A new tab opens for the Openflow canvas.
4. In the Openflow **Control Plane**, select **Create a runtime**. The **Create Runtime** dialog box appears.
5. In the **Create Runtime** populate the following fields:

| Field | Description |
| :---- | :---- |
| Runtime Name | Enter a name for your runtime. |
| Deployment drop down | Choose the deployment previously created in [Set up Openflow \- Snowflake Deployment: Create deployment](https://docs.snowflake.com/en/user-guide/data-integration/openflow/setup-openflow-spcs-deployment) |
| Node Type | Choose a node type from the Node type drop-down list. This specifies the size of your nodes. **See Node Type Sizing Guide below for recommendations.** |
| Min/Max node | In the Min/Max node range selector, select a range. The minimum value specifies the number of nodes that the runtime starts with when idle and the maximum value specifies the number of nodes that the runtime can scale up to, in the event of high data volume or CPU load. **See Node Count Recommendations below.** |
| Runtime Role | Choose the runtime role previously created in [Set up Openflow \- Snowflake Deployment: Create Runtime role](https://docs.snowflake.com/en/user-guide/data-integration/openflow/setup-openflow-spcs-create-rr). |
| Usage Roles | Optionally, select the roles created to grant usage to the runtime for required databases, schema, and table access. |
| External Access Integrations | **Required for on-premise connectivity.** Select the EAIs granted in step 5.1.4. For on-premise database access, select `aws_onprem_eai`. If using CDC/Streaming connectors, also select `OPENFLOW_SSV1_EAI`. |

   **Node Type Sizing Guide:**
   
   Choose the appropriate node type based on your workload:
   
   - **CPU_X64_XS** (2 vCPU, 8 GB RAM): Development, testing, light data ingestion
   - **CPU_X64_S** (4 vCPU, 16 GB RAM): Small production workloads, low-volume CDC
   - **CPU_X64_M** (8 vCPU, 32 GB RAM): **Recommended for most production workloads**, standard CDC, moderate throughput
   - **CPU_X64_L** (16 vCPU, 64 GB RAM): High-volume streaming, complex transformations
   - **CPU_X64_XL** (32 vCPU, 128 GB RAM): Enterprise-scale, very high throughput, multiple concurrent pipelines
   
   **Node Count Recommendations:**
   
   - **Development/Testing**: Min: 1, Max: 2 nodes
   - **Production (Standard)**: Min: 2, Max: 4-6 nodes (provides high availability and handles load spikes)
   - **Production (High-Volume)**: Min: 3, Max: 8-10 nodes (for 24/7 operations with high throughput)
   
   **Note:** Multiple nodes provide high availability (if one node fails, others continue processing) and enable parallel processing of multiple data streams.

   **Important - Selecting External Access Integrations:**
   - Click "+ Add External Access Integration" in the dialog
   - Select `aws_onprem_eai` from the dropdown (this enables connectivity to your on-premise database via PrivateLink)
   - If using CDC, Streaming, or SaaS connectors, click "+ Add External Access Integration" again and select `OPENFLOW_SSV1_EAI`
   - **Note:** Only EAIs that were granted to the runtime role in step 5.1.4 will appear in the dropdown
   - If an EAI doesn't appear, verify the GRANT statement was executed successfully

6. Select **Create**. The runtime takes a couple of minutes to be created.

Once created, view your runtime by navigating to the **Runtimes** tab of the Openflow control plane. Select the runtime to open the Openflow canvas.

#### 5.1.7. Verify EAI Association

After runtime creation, verify that the External Access Integrations were correctly associated:

```sql
USE ROLE OPENFLOW_ADMIN;

-- Verify EAI associations
-- Replace <deployment_name> and <runtime_name> with your actual values
SELECT SYSTEM$OPENFLOW_GET_EAI_ASSOCIATION('<deployment_name>', '<runtime_name>');

-- Expected output should include your EAI names in the runtime_eai array:
-- {
--   "controlplane_eai": "OPENFLOW_CONTROLPLANE_EAI",
--   "runtime_eai": ["AWS_ONPREM_EAI", "OPENFLOW_SSV1_EAI"]
-- }
```

**Success Criteria:**
- ✅ `runtime_eai` array includes `AWS_ONPREM_EAI` (or equivalent for your environment)
- ✅ `runtime_eai` array includes `OPENFLOW_SSV1_EAI` (if using CDC/Streaming)
- ✅ Runtime status shows "Running"

**If EAI is missing from the association:**

This issue typically occurs if the EAI was not selected during runtime creation. You can manually associate it using:

```sql
-- Manually associate EAI with runtime (rarely needed - prefer UI method)
-- Parameters: (deployment_name, runtime_name, controlplane_eai, runtime_eai_csv)
SELECT SYSTEM$OPENFLOW_ALTER_EAI_ASSOCIATION(
   '<deployment_name>',
   '<runtime_name>',
   'OPENFLOW_CONTROLPLANE_EAI',  -- Internal Openflow control plane EAI (don't change)
   'AWS_ONPREM_EAI,OPENFLOW_SSV1_EAI'  -- Your runtime EAIs (comma-separated, no spaces)
);
```

**Note:** Changing EAI associations on a running runtime may require a runtime restart. It's preferred to select the correct EAIs during runtime creation.

#### 5.1.8. Set up a dedicated event table for Openflow (Optional)

```sql
USE ROLE ACCOUNTADMIN;
GRANT USAGE ON DATABASE <DATABASE> TO ROLE OPENFLOW_ADMIN;
GRANT USAGE ON SCHEMA <DATABASE>.<SCHEMA> TO ROLE OPENFLOW_ADMIN;
GRANT CREATE EVENT TABLE ON SCHEMA <db_name>.<schema_name> TO ROLE OPENFLOW_ADMIN;


USE ROLE OPENFLOW_ADMIN;
CREATE EVENT TABLE IF NOT EXISTS <DATABASE>.<SCHEMA>.EVENTS;
SHOW OPENFLOW DATA PLANE INTEGRATIONS;

ALTER OPENFLOW DATA PLANE INTEGRATION
  <OPENFLOW_DATAPLANE_UUID>
  SET EVENT_TABLE = '<DATABASE>.<SCHEMA>.EVENTS';
```

####

### 5[^2]. Deploying and Configuring a Custom Snowpark Container Service

Finally, deploy the SPCS service that will utilize this private connection.

Create the Service: Use the CREATE SERVICE command, referencing the EAI and the secret.

```sql
CREATE SERVICE my_onprem_connector  IN COMPUTE POOL my_compute_pool  FROM SPECIFICATION $$  spec:    containers:    - name: connector-app      image: <image_repo>/my_connector_image:latest    endpoints:    - name: api      port: 8080  $$  EXTERNAL_ACCESS_INTEGRATIONS = (aws_onprem_eai)  SECRETS = ('cred' = sql_server_creds);
```

2
Container Application Code: The application code within the container can now use a standard database library (like pyodbc for Python) to connect. It retrieves credentials from the secret mounted by Snowflake and connects to the on-premise server using its private DNS name.

```py
# Example Python snippet inside the containerimport _snowflakeimport pyodbc# Retrieve credentials from the mounted secretcreds = _snowflake.get_username_password('cred')username = creds.usernamepassword = creds.password# Connect using the private DNS nameconn_str = (    f"DRIVER={{ODBC Driver 17 for SQL Server}};"    f"SERVER=nlb-dns-name.elb.us-west-2.amazonaws.com;"    f"DATABASE=my_database;"    f"UID={username};"    f"PWD={password};")cnxn = pyodbc.connect(conn_str)cursor = cnxn.cursor()cursor.execute("SELECT @@VERSION;")row = cursor.fetchone()print(row)
```

### 5.3. End-to-End Connectivity Validation

After completing Openflow runtime creation and configuration, systematically validate connectivity through each component of the chain.

#### 5.3.1. Pre-Test Validation Checklist

Before running connectivity tests, verify:

- [ ] Runtime status shows "Running" (check Runtimes tab in Openflow UI)
- [ ] EAI associations confirmed via `SELECT SYSTEM$OPENFLOW_GET_EAI_ASSOCIATION('<deployment_name>', '<runtime_name>');`
- [ ] NLB target health checks passing (AWS Console or CLI)
- [ ] Security groups allow traffic from Snowflake VPC CIDR
- [ ] Database service is running and accessible from on-premise network
- [ ] Database user credentials stored in Snowflake secret

#### 5.3.2. Runtime Health Validation

**Purpose:** Confirm Openflow runtime is operational

```sql
USE ROLE OPENFLOW_ADMIN;

-- Check runtime status
SHOW OPENFLOW RUNTIMES;
-- Expected: STATUS = 'RUNNING'

-- Check compute pool status
SHOW COMPUTE POOLS;
-- Expected: STATE = 'ACTIVE' or 'RUNNING'

-- Verify runtime node count matches configuration
SELECT * FROM TABLE(INFORMATION_SCHEMA.COMPUTE_POOL_STATUS('<pool_name>'));
-- Expected: num_nodes >= min_nodes configured
```

**Success Criteria:**
- ✅ Runtime status = "RUNNING"
- ✅ Compute pool active with expected node count
- ✅ No error messages in output

#### 5.3.3. EAI Association Verification

**Purpose:** Confirm EAIs are correctly assigned to runtime

```sql
-- Verify EAI associations
SELECT SYSTEM$OPENFLOW_GET_EAI_ASSOCIATION('<deployment_name>', '<runtime_name>');
-- Expected output should include your EAI names in the runtime_eai array

-- Verify runtime role has EAI grants
SHOW GRANTS TO ROLE OPENFLOW_RUNTIME_ROLE_<YOUR_RUNTIME>;
-- Should include: "USAGE ON INTEGRATION AWS_ONPREM_EAI"
-- Should include: "USAGE ON INTEGRATION OPENFLOW_SSV1_EAI" (if using CDC/Streaming)
```

**Success Criteria:**
- ✅ runtime_eai array includes aws_onprem_eai
- ✅ runtime_eai array includes OPENFLOW_SSV1_EAI (for CDC/Streaming connectors)
- ✅ SHOW GRANTS confirms USAGE permissions

#### 5.3.4. NLB Target Health Validation

**Purpose:** Confirm on-premise database targets are healthy

```bash
# AWS CLI
aws elbv2 describe-target-health --target-group-arn <target-group-arn>

# Expected: All targets show State = "healthy"
```

**Success Criteria:**
- ✅ All targets show State = "healthy"
- ✅ HealthCheckPort matches database port
- ✅ No targets in "unhealthy" or "draining" state

#### 5.3.5. Openflow Connection Testing

**Purpose:** Validate Openflow can connect to on-premise database

**From Openflow Canvas:**

1. Navigate to Openflow runtime (Runtimes tab → Click runtime name)
2. Click "Connections" in left panel
3. Click your database connection (or create one if not exists)
4. Click "Test Connection" button

**Expected Results:**
- ✅ Success message: "Connection successful"
- ✅ Response time displayed (typically < 5 seconds)
- ✅ No error messages

**Common Error Messages:**

| Error Message | Likely Cause | Resolution |
|---------------|--------------|------------|
| "Connection timeout" | Network routing issue or NLB unhealthy | Check NLB target health, security groups, route tables |
| "Authentication failed" | Incorrect credentials | Verify secret contents, test database login manually |
| "Host not found" | DNS resolution failure | Check Private DNS zone configuration |
| "Network access denied" | EAI not assigned | Verify EAI grant and runtime association |
| "SSL handshake failed" | Certificate validation issue | Enable TrustServerCertificate or install valid certificate |

#### 5.3.6. Query Execution Testing

**Purpose:** Validate end-to-end data retrieval

**Create Test Pipeline in Openflow:**

1. In Openflow canvas, click "+ Add Source"
2. Select your database connection
3. Configure source:
   - **Source Type:** Query
   - **SQL Server Query:** `SELECT @@VERSION AS db_version, GETDATE() AS current_time;`
   - **PostgreSQL Query:** `SELECT version() AS db_version, NOW() AS current_time;`
4. Click "+ Add Destination"
5. Select Snowflake table as destination
6. Map columns appropriately
7. Click "Run Test"

**Expected Results:**
- ✅ Test execution completes successfully
- ✅ Data preview shows database version and timestamp
- ✅ Snowflake destination table receives data
- ✅ Execution time < 10 seconds for simple query

**Additional Test Queries:**

```sql
-- SQL Server: Test table access
SELECT TOP 10 * FROM <your_table>;

-- PostgreSQL: Test table access
SELECT * FROM <your_table> LIMIT 10;

-- Test data retrieval
SELECT COUNT(*) FROM <your_table>;
```

**Success Criteria:**
- ✅ Queries execute without errors
- ✅ Data returns as expected
- ✅ Performance is acceptable (queries complete in reasonable time)

#### 5.3.7. End-to-End Integration Test

**Purpose:** Validate complete data pipeline functionality

**Scenario: Batch Data Load from On-Premise to Snowflake**

1. **Setup:**
   - Create test table in on-premise database
   - Configure Openflow pipeline with source and destination

2. **Test Data Load:**
   ```sql
   -- On-premise database: Insert test records
   INSERT INTO test_table (id, name, created_date)
   VALUES (1, 'Test Record 1', GETDATE()),
          (2, 'Test Record 2', GETDATE()),
          (3, 'Test Record 3', GETDATE());
   ```

3. **Run Pipeline:**
   - Execute pipeline in Openflow
   - Monitor execution progress

4. **Verify Results:**
   ```sql
   -- In Snowflake: Verify data arrived
   SELECT * FROM target_snowflake_table 
   ORDER BY created_date DESC 
   LIMIT 10;
   
   -- Compare record count
   SELECT COUNT(*) FROM target_snowflake_table;
   ```

**Success Criteria:**
- ✅ All records transferred correctly
- ✅ Data types preserved accurately
- ✅ Timestamps reflect actual operation times
- ✅ No data loss or corruption
- ✅ End-to-end latency acceptable for use case

#### 5.3.8. Troubleshooting Common Issues

**Issue: Runtime Creation Fails**
- **Symptoms:** Runtime stuck in "Creating" or "Failed" status
- **Diagnostic Steps:**
  1. Check account-level permissions: `SHOW GRANTS TO ROLE OPENFLOW_ADMIN;`
  2. Verify compute pool status: `SHOW COMPUTE POOLS;`
  3. Check for error messages in runtime logs
- **Resolution:** Ensure all account-level grants are present, verify compute pool has capacity

**Issue: EAI Not Available in UI**
- **Symptoms:** EAI doesn't appear in dropdown during runtime creation
- **Diagnostic Steps:**
  1. Verify EAI exists: `SHOW INTEGRATIONS LIKE '<eai_name>';`
  2. Check runtime role grants: `SHOW GRANTS TO ROLE <runtime_role>;`
  3. Confirm EAI is enabled
- **Resolution:** Grant USAGE on EAI to runtime role, ensure EAI is enabled

**Issue: Connection Test Fails with Timeout**
- **Symptoms:** "Connection timeout" error when testing connection
- **Diagnostic Steps:**
  1. Check NLB target health: `aws elbv2 describe-target-health --target-group-arn <arn>`
  2. Verify security groups allow traffic from Snowflake VPC
  3. Check route tables have path to on-premise network
  4. Test on-premise database is accessible from on-premise network
- **Resolution:** Fix unhealthy NLB targets, update security group rules, verify network routing

**Issue: Authentication Failures**
- **Symptoms:** "Authentication failed" or "Login failed for user"
- **Diagnostic Steps:**
  1. Verify secret contents: `DESC SECRET <secret_name>;` (password won't be visible but check username)
  2. Test credentials manually from on-premise network
  3. Check database user permissions
- **Resolution:** Update secret with correct credentials, verify database user has required permissions

**Issue: Pipeline Execution Fails**
- **Symptoms:** Pipeline shows error status, no data transferred
- **Diagnostic Steps:**
  1. Check pipeline execution logs in Openflow
  2. Verify source query syntax is correct for database type
  3. Test source query manually in database
  4. Verify destination table schema matches source
- **Resolution:** Fix SQL syntax errors, adjust column mappings, verify permissions

#### 5.3.9. Validation Checklist Summary

After completing all validation steps, use this checklist to confirm readiness:

| Component | Test | Status | Notes |
|-----------|------|--------|-------|
| Runtime Health | SHOW OPENFLOW RUNTIMES | ⬜ | |
| EAI Association | SYSTEM$OPENFLOW_GET_EAI_ASSOCIATION | ⬜ | |
| NLB Target Health | describe-target-health | ⬜ | |
| Openflow Connection | Test Connection button | ⬜ | |
| Query Execution | Test queries | ⬜ | |
| Integration Test | End-to-end pipeline | ⬜ | |

**Overall Validation Status:** ⬜ PASS - System ready for production use

---

## References

[^1]: Snowpark Container Services - Snowflake Documentation, https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview
[^2]: Snowpark Container Services 101: A Complete Overview (2025) - Chaos Genius, https://www.chaosgenius.io/blog/snowpark-container-services/
[^3]: Secure Connections with New Outbound Private Link with Snowflake Support in Preview, https://www.snowflake.com/en/engineering-blog/secure-communications-outbound-private-link/
[^4]: External network access overview - Snowflake Documentation, https://docs.snowflake.com/en/developer-guide/external-network-access/external-network-access-overview
[^5]: Creating and using an external access integration | Snowflake Documentation, https://docs.snowflake.com/en/developer-guide/external-network-access/creating-using-external-network-access
[^6]: External network access and private connectivity on AWS, https://docs.snowflake.com/en/developer-guide/external-network-access/creating-using-private-aws

