## Chapter 5\. SPCS Setup and Validation

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

#### 5.1.2. Associate our External Access Integrations with Openflow

```sql
GRANT USAGE ON INTEGRATION aws_onprem_eai TO ROLE OPENFLOW_RUNTIME_ROLE_<RUNTIME_NAME>;
-- Query the existing EAI associated with Openflow
SELECT SYSTEM$OPENFLOW_GET_EAI_ASSOCIATION('', '');
-- Associate our new EAI to OPENFLOW
SELECT SYSTEM$OPENFLOW_ALTER_EAI_ASSOCIATION('', '', 'OPENFLOW_CONTROLPLANE_EAI', 'AWS_ONPREM_EAI');
```

#### 5.1.3. Create a deployment

1. Sign in to Snowsight with a role defined in Configure core Snowflake requirements.
2. Navigate to Ingestion » Openflow.
3. Click "Launch Openflow" in the top right corner
4. Select OPENFLOW\_ADMIN as your role
5. In the Openflow UI, select Create a deployment. The Deployments tab opens.
6. Select Create a deployment. The Creating a deployment wizard opens.
7. In the Prerequisites step, ensure that you meet all the requirements. Select Next.
8. In the Deployment location step, select Snowflake as the deployment location. Enter a name for your deployment. Select Next.
9. Select Create Deployment.

Your deployment will then be created.

#### 5.1.4. Create a runtime role for Openflow

```sql
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS OPENFLOW_RUNTIME_ROLE_<RUNTIMENAME>;
GRANT ROLE OPENFLOW_RUNTIME_ROLE_<RUNTIMENAME> TO ROLE OPENFLOW_ADMIN;
GRANT USAGE, OPERATE ON WAREHOUSE <OPENFLOW_INGEST_WAREHOUSE> TO ROLE OPENFLOW_RUNTIME_ROLE_<RUNTIMENAME>;
GRANT USAGE ON DATABASE <OPENFLOW_SPCS_DATABASE> TO ROLE OPENFLOW_RUNTIME_ROLE_<RUNTIMENAME>;
GRANT USAGE ON SCHEMA <OPENFLOW_SPCS_SCHEMA> TO ROLE OPENFLOW_RUNTIME_ROLE_<RUNTIMENAME>;
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
2. Navigate to **Data** » **Openflow**.
3. Select **Launch Openflow**. A new tab opens for the Openflow canvas.
4. In the Openflow **Control Plane**, select **Create a runtime**. The **Create Runtime** dialog box appears.
5. In the **Create Runtime** populate the following fields:

| Field | Description |
| :---- | :---- |
| Runtime Name | Enter a name for your runtime. |
| Deployment drop down | Choose the deployment previously created in [Set up Openflow \- Snowflake Deployment: Create deployment](https://docs.snowflake.com/en/user-guide/data-integration/openflow/setup-openflow-spcs-deployment) |
| Node Type | Choose a node type from the Node type drop-down list. This specifies the size of your nodes. |
| Min/Max node | In the Min/Max node range selector, select a range. The minimum value specifies the number of nodes that the runtime starts with when idle and the maximum value specifies the number of nodes that the runtime can scale up to, in the event of high data volume or CPU load. |
| Runtime Role | Choose the runtime role previously created in [Set up Openflow \- Snowflake Deployment: Create Runtime role](https://docs.snowflake.com/en/user-guide/data-integration/openflow/setup-openflow-spcs-create-rr). |
| Usage Roles | Optionally, select the roles created to grant usage to the runtime for required databases, schema, and table access. |
| External Access Integrations | Optionally, select the previously created external access integrations to grant access to external resources. |

6. Select **Create**. The runtime takes a couple of minutes to be created.

Once created, view your runtime by navigating to the **Runtimes** tab of the Openflow control plane. Select the runtime to open the Openflow canvas.

#### 5.1.7. Set up a dedicated event table for Openflow (Optional)

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

1. **Validation**: After deploying the service, check the service logs to confirm a successful connection and query execution. Any failures will likely point to misconfigurations in routing, security groups, NACLs, or DNS forwarding.

## References

[^1]: Snowpark Container Services - Snowflake Documentation, https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview
[^2]: Snowpark Container Services 101: A Complete Overview (2025) - Chaos Genius, https://www.chaosgenius.io/blog/snowpark-container-services/
[^3]: Secure Connections with New Outbound Private Link with Snowflake Support in Preview, https://www.snowflake.com/en/engineering-blog/secure-communications-outbound-private-link/
[^4]: External network access overview - Snowflake Documentation, https://docs.snowflake.com/en/developer-guide/external-network-access/external-network-access-overview
[^5]: Creating and using an external access integration | Snowflake Documentation, https://docs.snowflake.com/en/developer-guide/external-network-access/creating-using-external-network-access
[^6]: External network access and private connectivity on AWS, https://docs.snowflake.com/en/developer-guide/external-network-access/creating-using-private-aws

