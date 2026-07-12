# Oracle XStream CDC with Confluent Platform - Technical Setup Guide

## Environment Details
- **Oracle Database**: Oracle 21c Express Edition (Running in Docker)
- **Oracle Container Name**: oracle21c
- **Oracle IP**: 172.17.0.2 (on shared-network)
- **Connector Type**: Oracle XStream CDC Source Connector (NOT JDBC)
- **Confluent Platform**: 7.6.0 (Docker-based)

---

## PHASE 1: Verify Oracle Database Status

### Step 1.1: Check Oracle Container
```bash
docker ps | grep oracle21c
```

**Expected Output:**
```
3bc3ac02cdb9   container-registry.oracle.com/database/express:21.3.0-xe   "/bin/bash -c $ORACL…"   3 weeks ago   Up 3 weeks (healthy)   0.0.0.0:1521->1521/tcp, :::1521->1521/tcp, 0.0.0.0:5500->5500/tcp, :::5500->5500/tcp, 0.0.0.0:8080->8080/tcp, :::8080->8080/tcp   oracle21c
```

### Step 1.2: Test Oracle Connectivity
```bash
docker exec -it oracle21c sqlplus -v
```

**Expected Output:**
```
SQL*Plus: Release 21.0.0.0.0 - Production
```

### Step 1.3: Connect to PDB
```bash
docker exec -it oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba
```

---

## PHASE 2: Configure Oracle for XStream CDC

### Step 2.1: Enable ARCHIVELOG Mode (CRITICAL for CDC)

```sql
-- Check current archive log mode
SELECT LOG_MODE FROM V$DATABASE;
```

**Current Expected Output:** `NOARCHIVELOG`

**Enable ARCHIVELOG:**
```sql
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
```

**Verify:**
```sql
SELECT LOG_MODE FROM V$DATABASE;
```

**Expected Output:** `ARCHIVELOG`

**Screenshot Point:** ✅ Take screenshot showing ARCHIVELOG mode enabled

---

### Step 2.2: Enable Supplemental Logging (CRITICAL for CDC)

```sql
-- Enable minimal supplemental logging
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Verify
SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;
```

**Expected Output:** `YES` or `IMPLICIT`

**Screenshot Point:** ✅ Take screenshot showing supplemental logging enabled

---

### Step 2.3: Create XStream Administrator User

```sql
-- Create tablespace for XStream
CREATE TABLESPACE xstream_tbs 
DATAFILE '/opt/oracle/oradata/XE/XEPDB1/xstream_tbs.dbf' 
SIZE 100M AUTOEXTEND ON MAXSIZE UNLIMITED;
```

**Expected Output:** `Tablespace created.`

```sql
-- Create XStream admin user
CREATE USER xstrmadmin IDENTIFIED BY xstrmadmin123
DEFAULT TABLESPACE xstream_tbs
QUOTA UNLIMITED ON xstream_tbs;
```

**Expected Output:** `User created.`

```sql
-- Grant basic privileges
GRANT CREATE SESSION TO xstrmadmin;
GRANT SET CONTAINER TO xstrmadmin;
GRANT SELECT ANY TRANSACTION TO xstrmadmin;
GRANT LOGMINING TO xstrmadmin;
GRANT LOCK ANY TABLE TO xstrmadmin;
GRANT SELECT ANY TABLE TO xstrmadmin;
GRANT EXECUTE_CATALOG_ROLE TO xstrmadmin;
GRANT SELECT ANY DICTIONARY TO xstrmadmin;
GRANT CREATE TABLESPACE TO xstrmadmin;
GRANT ALTER TABLESPACE TO xstrmadmin;
GRANT DROP TABLESPACE TO xstrmadmin;
GRANT CREATE ANY DIRECTORY TO xstrmadmin;
GRANT DROP ANY DIRECTORY TO xstrmadmin;
```

**Expected Output (for each GRANT):** `Grant succeeded.`

```sql
-- CRITICAL: Grant XStream CAPTURE privilege
-- This is what enables XStream CDC (NOT JDBC-based CDC)
BEGIN
   DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
      grantee => 'xstrmadmin',
      privilege_type => 'CAPTURE',
      grant_select_privileges => TRUE
   );
END;
/
```

**Expected Output:** `PL/SQL procedure successfully completed.`

```sql
-- Verify XStream privileges
SELECT * FROM DBA_XSTREAM_ADMINISTRATOR;
```

**Expected Output:**
```
USERNAME     PRIVILEGE_TYPE    CREATE_TIME
--------     --------------    -----------
XSTRMADMIN   CAPTURE          12-JUL-26
```

**Screenshot Point:** ✅ Take screenshot showing XStream admin privileges

---

### Step 2.4: Configure Source Schema (ordermgmt)

```sql
-- Exit as sysdba
EXIT;
```

```bash
# Connect as ordermgmt user
docker exec -it oracle21c sqlplus ordermgmt/kafka@XEPDB1
```

```sql
-- Create demo tables
CREATE TABLE ORDERS (
    ORDER_ID NUMBER PRIMARY KEY,
    CUSTOMER_NAME VARCHAR2(100),
    ORDER_DATE TIMESTAMP DEFAULT SYSTIMESTAMP,
    TOTAL_AMOUNT NUMBER(10,2),
    STATUS VARCHAR2(20),
    CREATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP,
    UPDATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE TABLE ORDER_ITEMS (
    ITEM_ID NUMBER PRIMARY KEY,
    ORDER_ID NUMBER,
    PRODUCT_NAME VARCHAR2(100),
    QUANTITY NUMBER,
    PRICE NUMBER(10,2),
    CREATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP,
    FOREIGN KEY (ORDER_ID) REFERENCES ORDERS(ORDER_ID)
);

CREATE TABLE CUSTOMERS (
    CUSTOMER_ID NUMBER PRIMARY KEY,
    CUSTOMER_NAME VARCHAR2(100),
    EMAIL VARCHAR2(100),
    PHONE VARCHAR2(20),
    CREATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP
);
```

**Expected Output (for each table):** `Table created.`

```sql
-- CRITICAL: Enable supplemental logging on ALL columns
-- This ensures XStream captures complete before/after images
ALTER TABLE ORDERS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE ORDER_ITEMS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE CUSTOMERS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
```

**Expected Output (for each):** `Table altered.`

```sql
-- Grant SELECT to XStream admin
GRANT SELECT ON ORDERS TO xstrmadmin;
GRANT SELECT ON ORDER_ITEMS TO xstrmadmin;
GRANT SELECT ON CUSTOMERS TO xstrmadmin;
```

**Expected Output (for each):** `Grant succeeded.`

```sql
-- Insert initial test data
INSERT INTO CUSTOMERS VALUES (1, 'John Doe', 'john@example.com', '+1-555-0101', SYSTIMESTAMP);
INSERT INTO CUSTOMERS VALUES (2, 'Jane Smith', 'jane@example.com', '+1-555-0102', SYSTIMESTAMP);
INSERT INTO CUSTOMERS VALUES (3, 'Bob Johnson', 'bob@example.com', '+1-555-0103', SYSTIMESTAMP);

INSERT INTO ORDERS VALUES (1, 'John Doe', SYSTIMESTAMP, 1500.00, 'PENDING', SYSTIMESTAMP, SYSTIMESTAMP);
INSERT INTO ORDERS VALUES (2, 'Jane Smith', SYSTIMESTAMP, 2300.50, 'CONFIRMED', SYSTIMESTAMP, SYSTIMESTAMP);
INSERT INTO ORDERS VALUES (3, 'Bob Johnson', SYSTIMESTAMP, 750.25, 'PENDING', SYSTIMESTAMP, SYSTIMESTAMP);

INSERT INTO ORDER_ITEMS VALUES (101, 1, 'Laptop', 1, 1200.00, SYSTIMESTAMP);
INSERT INTO ORDER_ITEMS VALUES (102, 1, 'Mouse', 2, 150.00, SYSTIMESTAMP);
INSERT INTO ORDER_ITEMS VALUES (103, 2, 'Monitor', 2, 1150.25, SYSTIMESTAMP);
INSERT INTO ORDER_ITEMS VALUES (104, 3, 'Keyboard', 1, 750.25, SYSTIMESTAMP);

COMMIT;
```

**Expected Output:** `1 row created.` (for each INSERT), then `Commit complete.`

```sql
-- Verify data
SELECT COUNT(*) AS TOTAL_CUSTOMERS FROM CUSTOMERS;
SELECT COUNT(*) AS TOTAL_ORDERS FROM ORDERS;
SELECT COUNT(*) AS TOTAL_ITEMS FROM ORDER_ITEMS;
```

**Expected Output:**
```
TOTAL_CUSTOMERS
---------------
              3

TOTAL_ORDERS
------------
           3

TOTAL_ITEMS
-----------
          4
```

**Screenshot Point:** ✅ Take screenshot showing table counts

```sql
EXIT;
```

---

### Step 2.5: Create XStream Outbound Server (CDC Engine)

```bash
# Connect as sysdba
docker exec -it oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba
```

```sql
-- Create XStream Outbound Server
-- This is the CDC engine that reads Oracle redo logs
DECLARE
  tables  DBMS_UTILITY.UNCL_ARRAY;
  schemas DBMS_UTILITY.UNCL_ARRAY;
BEGIN
  schemas(1) := 'ordermgmt';
  
  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
    server_name     => 'xout',
    table_names     => tables,
    schema_names    => schemas,
    source_database => 'XEPDB1'
  );
END;
/
```

**Expected Output:** `PL/SQL procedure successfully completed.`

```sql
-- Configure outbound server to use xstrmadmin
BEGIN
  DBMS_XSTREAM_ADM.ALTER_OUTBOUND(
    server_name => 'xout',
    connect_user => 'xstrmadmin'
  );
END;
/
```

**Expected Output:** `PL/SQL procedure successfully completed.`

```sql
-- Verify outbound server created
SELECT SERVER_NAME, CAPTURE_NAME, QUEUE_NAME, CONNECT_USER, SOURCE_DATABASE
FROM DBA_XSTREAM_OUTBOUND;
```

**Expected Output:**
```
SERVER_NAME  CAPTURE_NAME   QUEUE_NAME          CONNECT_USER  SOURCE_DATABASE
-----------  ------------   -----------------   ------------  ---------------
xout         CAPTURE_XOUT   (auto-generated)    XSTRMADMIN    XEPDB1
```

**Screenshot Point:** ✅ Take screenshot showing XStream outbound server details

```sql
-- Start the XStream capture process
BEGIN
  DBMS_CAPTURE_ADM.START_CAPTURE(
    capture_name => 'CAPTURE_XOUT'
  );
END;
/
```

**Expected Output:** `PL/SQL procedure successfully completed.`

```sql
-- Verify capture is RUNNING
SELECT CAPTURE_NAME, STATUS, STATE, CAPTURE_TYPE 
FROM DBA_CAPTURE;
```

**Expected Output:**
```
CAPTURE_NAME   STATUS     STATE                 CAPTURE_TYPE
------------   -------    -------------------   ------------
CAPTURE_XOUT   ENABLED    CAPTURING CHANGES     LOCAL
```

**Screenshot Point:** ✅ Take screenshot showing capture state as "CAPTURING CHANGES"

```sql
-- Check detailed capture statistics
SELECT CAPTURE_NAME, 
       STATE,
       TOTAL_MESSAGES_CAPTURED,
       TOTAL_MESSAGES_ENQUEUED,
       CAPTURE_TIME,
       LATENCY_SECONDS
FROM V$XSTREAM_CAPTURE;
```

**Expected Output:**
```
CAPTURE_NAME   STATE              TOTAL_MESSAGES_CAPTURED  TOTAL_MESSAGES_ENQUEUED  CAPTURE_TIME         LATENCY_SECONDS
------------   ----------------   -----------------------  -----------------------  ------------------   ---------------
CAPTURE_XOUT   CAPTURING CHANGES  0                        0                        12-JUL-26 08:30:45   0
```

```sql
EXIT;
```

---

## PHASE 3: Setup Confluent Platform with Docker Compose

### Step 3.1: Create Project Directory Structure

```bash
# Create project directory
cd ~
mkdir -p confluent-oracle-cdc/connectors
mkdir -p confluent-oracle-cdc/jdbc-drivers
cd confluent-oracle-cdc

# Verify directory structure
ls -la
```

**Expected Output:**
```
drwxrwxr-x 4 ec2-user ec2-user   42 Jul 12 08:35 .
drwx------ 6 ec2-user ec2-user  150 Jul 12 08:35 ..
drwxrwxr-x 2 ec2-user ec2-user    6 Jul 12 08:35 connectors
drwxrwxr-x 2 ec2-user ec2-user    6 Jul 12 08:35 jdbc-drivers
```

---

### Step 3.2: Download Oracle JDBC Driver

```bash
cd ~/confluent-oracle-cdc/jdbc-drivers

# Download Oracle JDBC driver (ojdbc8 for Oracle 21c)
wget https://download.oracle.com/otn-pub/otn_software/jdbc/218/ojdbc8.jar

# Verify download
ls -lh ojdbc8.jar
```

**Expected Output:**
```
-rw-rw-r-- 1 ec2-user ec2-user 4.5M Jul 12 08:36 ojdbc8.jar
```

```bash
cd ~/confluent-oracle-cdc
```

---

### Step 3.3: Create Docker Compose Configuration

```bash
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.6.0
    hostname: zookeeper
    container_name: zookeeper
    ports:
      - "2181:2181"
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    networks:
      - shared-network

  broker:
    image: confluentinc/cp-kafka:7.6.0
    hostname: broker
    container_name: broker
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
      - "9101:9101"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://broker:29092,PLAINTEXT_HOST://localhost:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      KAFKA_JMX_PORT: 9101
      KAFKA_JMX_HOSTNAME: localhost
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: 'true'
    networks:
      - shared-network

  schema-registry:
    image: confluentinc/cp-schema-registry:7.6.0
    hostname: schema-registry
    container_name: schema-registry
    depends_on:
      - broker
    ports:
      - "8081:8081"
    environment:
      SCHEMA_REGISTRY_HOST_NAME: schema-registry
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: 'broker:29092'
      SCHEMA_REGISTRY_LISTENERS: http://0.0.0.0:8081
    networks:
      - shared-network

  connect:
    image: confluentinc/cp-kafka-connect:7.6.0
    hostname: connect
    container_name: connect
    depends_on:
      - broker
      - schema-registry
    ports:
      - "8083:8083"
    environment:
      CONNECT_BOOTSTRAP_SERVERS: 'broker:29092'
      CONNECT_REST_ADVERTISED_HOST_NAME: connect
      CONNECT_REST_PORT: 8083
      CONNECT_GROUP_ID: compose-connect-group
      CONNECT_CONFIG_STORAGE_TOPIC: docker-connect-configs
      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_OFFSET_FLUSH_INTERVAL_MS: 10000
      CONNECT_OFFSET_STORAGE_TOPIC: docker-connect-offsets
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_STATUS_STORAGE_TOPIC: docker-connect-status
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_KEY_CONVERTER: org.apache.kafka.connect.storage.StringConverter
      CONNECT_VALUE_CONVERTER: io.confluent.connect.avro.AvroConverter
      CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_URL: http://schema-registry:8081
      CONNECT_PLUGIN_PATH: "/usr/share/java,/usr/share/confluent-hub-components"
      CONNECT_LOG4J_LOGGERS: org.apache.zookeeper=ERROR,org.I0Itec.zkclient=ERROR,org.reflections=ERROR
    volumes:
      - ./connectors:/usr/share/confluent-hub-components
      - ./jdbc-drivers:/usr/share/java/kafka-connect-jdbc
    networks:
      - shared-network
    command:
      - bash
      - -c
      - |
        echo "=========================================="
        echo "Installing Oracle XStream CDC Source Connector"
        echo "=========================================="
        confluent-hub install --no-prompt confluentinc/kafka-connect-oracle-cdc:2.9.2
        echo ""
        echo "Copying Oracle JDBC Driver..."
        if [ -f /usr/share/java/kafka-connect-jdbc/ojdbc8.jar ]; then
          cp /usr/share/java/kafka-connect-jdbc/ojdbc8.jar /usr/share/confluent-hub-components/confluentinc-kafka-connect-oracle-cdc/lib/
          echo "Oracle JDBC driver copied successfully"
        else
          echo "WARNING: Oracle JDBC driver not found!"
        fi
        echo ""
        echo "Starting Kafka Connect..."
        /etc/confluent/docker/run

  control-center:
    image: confluentinc/cp-enterprise-control-center:7.6.0
    hostname: control-center
    container_name: control-center
    depends_on:
      - broker
      - schema-registry
      - connect
    ports:
      - "9021:9021"
    environment:
      CONTROL_CENTER_BOOTSTRAP_SERVERS: 'broker:29092'
      CONTROL_CENTER_CONNECT_CONNECT-DEFAULT_CLUSTER: 'connect:8083'
      CONTROL_CENTER_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
      CONTROL_CENTER_REPLICATION_FACTOR: 1
      CONTROL_CENTER_INTERNAL_TOPICS_PARTITIONS: 1
      CONTROL_CENTER_MONITORING_INTERCEPTOR_TOPIC_PARTITIONS: 1
      CONFLUENT_METRICS_TOPIC_REPLICATION: 1
      PORT: 9021
    networks:
      - shared-network

networks:
  shared-network:
    external: true
EOF
```

**Verify file created:**
```bash
ls -lh docker-compose.yml
```

**Expected Output:**
```
-rw-rw-r-- 1 ec2-user ec2-user 3.2K Jul 12 08:38 docker-compose.yml
```

---

### Step 3.4: Start Confluent Platform

```bash
# Make sure we're in the right directory
cd ~/confluent-oracle-cdc

# Start all services
docker-compose up -d
```

**Expected Output:**
```
Creating zookeeper ... done
Creating broker ... done
Creating schema-registry ... done
Creating connect ... done
Creating control-center ... done
```

```bash
# Wait for services to initialize (2 minutes)
echo "Waiting for services to start (120 seconds)..."
sleep 120
```

```bash
# Check all containers are running
docker-compose ps
```

**Expected Output:**
```
NAME              IMAGE                                      STATUS      PORTS
broker            confluentinc/cp-kafka:7.6.0               Up 2 min    0.0.0.0:9092->9092/tcp, 0.0.0.0:9101->9101/tcp
connect           confluentinc/cp-kafka-connect:7.6.0       Up 2 min    0.0.0.0:8083->8083/tcp
control-center    confluentinc/cp-enterprise-control-center Up 2 min    0.0.0.0:9021->9021/tcp
schema-registry   confluentinc/cp-schema-registry:7.6.0     Up 2 min    0.0.0.0:8081->8081/tcp
zookeeper         confluentinc/cp-zookeeper:7.6.0           Up 2 min    0.0.0.0:2181->2181/tcp
```

**Screenshot Point:** ✅ Take screenshot showing all containers running

---

### Step 3.5: Verify Services are Ready

```bash
# Test Kafka broker
docker exec broker kafka-topics --bootstrap-server broker:29092 --list
```

**Expected Output:** (May show internal topics like __consumer_offsets, etc.)

```bash
# Test Connect REST API
curl http://localhost:8083/
```

**Expected Output:**
```json
{"version":"7.6.0","commit":"...","kafka_cluster_id":"..."}
```

```bash
# List installed connector plugins
curl -s http://localhost:8083/connector-plugins | jq '.[] | select(.class | contains("Oracle"))'
```

**Expected Output:**
```json
{
  "class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
  "type": "source",
  "version": "2.9.2"
}
```

**Screenshot Point:** ✅ Take screenshot showing Oracle CDC connector plugin installed

---

## PHASE 4: Deploy Oracle XStream CDC Source Connector

### Step 4.1: Verify Network Connectivity

```bash
# Get Oracle container IP on shared network
docker network inspect shared-network | grep -A 5 oracle21c
```

**Expected to see Oracle's IP in the shared-network**

```bash
# Test connectivity from Connect to Oracle
docker exec connect bash -c "timeout 5 bash -c '</dev/tcp/oracle21c/1521' && echo 'Oracle is reachable' || echo 'Cannot reach Oracle'"
```

**Expected Output:** `Oracle is reachable`

---

### Step 4.2: Create Connector Configuration

```bash
cd ~/confluent-oracle-cdc

cat > oracle-xstream-cdc-config.json <<'EOF'
{
  "name": "oracle-xstream-cdc-source",
  "config": {
    "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
    "tasks.max": "1",
    
    "oracle.server": "oracle21c",
    "oracle.port": "1521",
    "oracle.sid": "XE",
    "oracle.pdb.name": "XEPDB1",
    "oracle.username": "xstrmadmin",
    "oracle.password": "xstrmadmin123",
    
    "xstream.server.name": "xout",
    
    "start.from": "CURRENT",
    
    "table.inclusion.regex": "ORDERMGMT\\.(ORDERS|ORDER_ITEMS|CUSTOMERS)",
    
    "topic.creation.default.partitions": "3",
    "topic.creation.default.replication.factor": "1",
    
    "numeric.mapping": "best_fit",
    "query.timeout.ms": "60000",
    
    "redo.log.consumer.bootstrap.servers": "broker:29092",
    
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true",
    "value.converter.schemas.enable": "true",
    
    "batch.size": "1000",
    "poll.interval.ms": "1000",
    
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true",
    "errors.deadletterqueue.topic.name": "dlq-oracle-cdc",
    "errors.deadletterqueue.topic.replication.factor": "1"
  }
}
EOF
```

**Verify configuration file:**
```bash
cat oracle-xstream-cdc-config.json | jq '.'
```

---

### Step 4.3: Deploy the Connector

```bash
# Deploy connector via REST API
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @oracle-xstream-cdc-config.json
```

**Expected Output:**
```json
{
  "name": "oracle-xstream-cdc-source",
  "config": {
    "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
    "tasks.max": "1",
    ...
  },
  "tasks": [],
  "type": "source"
}
```

```bash
# Wait 10 seconds for connector to initialize
echo "Waiting for connector to initialize..."
sleep 10
```

```bash
# Check connector status
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '.'
```

**Expected Output:**
```json
{
  "name": "oracle-xstream-cdc-source",
  "connector": {
    "state": "RUNNING",
    "worker_id": "connect:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "connect:8083"
    }
  ],
  "type": "source"
}
```

**Screenshot Point:** ✅ Take screenshot showing connector state as "RUNNING"

---

### Step 4.4: Verify Topics Created

```bash
# Wait a few seconds for topics to be created
sleep 5

# List Kafka topics - should see ORDERMGMT tables
docker exec broker kafka-topics --bootstrap-server broker:29092 --list | grep ORDERMGMT
```

**Expected Output:**
```
ORDERMGMT.CUSTOMERS
ORDERMGMT.ORDERS
ORDERMGMT.ORDER_ITEMS
```

**Screenshot Point:** ✅ Take screenshot showing auto-created topics

```bash
# Describe ORDERS topic
docker exec broker kafka-topics \
  --bootstrap-server broker:29092 \
  --topic ORDERMGMT.ORDERS \
  --describe
```

**Expected Output:**
```
Topic: ORDERMGMT.ORDERS   PartitionCount: 3   ReplicationFactor: 1
```

---

## PHASE 5: Test Real-Time Change Data Capture

### Step 5.1: Consume Initial Snapshot

```bash
# Consume messages from ORDERS topic (initial snapshot)
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic ORDERMGMT.ORDERS \
  --from-beginning \
  --max-messages 3 \
  --property print.key=true \
  --property print.timestamp=true \
  --timeout-ms 10000
```

**Expected Output:** (JSON messages with order data)

**Screenshot Point:** ✅ Take screenshot showing initial data in Kafka

---

### Step 5.2: Test INSERT Operation (Real-time CDC)

**Open TWO terminal sessions to your EC2 instance**

**Terminal 1 - Start Real-time Consumer:**
```bash
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic ORDERMGMT.ORDERS \
  --property print.key=true \
  --property print.timestamp=true
```

**Terminal 2 - Insert New Record:**
```bash
docker exec -it oracle21c sqlplus ordermgmt/kafka@XEPDB1
```

```sql
-- Insert new order
INSERT INTO ORDERS VALUES (
  4, 
  'Alice Williams', 
  SYSTIMESTAMP, 
  3200.00, 
  'PENDING',
  SYSTIMESTAMP,
  SYSTIMESTAMP
);
COMMIT;
```

**Expected in Terminal 1:** You should immediately see the INSERT event with op_type="I"

**Screenshot Point:** ✅ Take screenshot showing real-time INSERT event in Kafka

---

### Step 5.3: Test UPDATE Operation

**In Terminal 2 (still in sqlplus):**
```sql
-- Update existing order
UPDATE ORDERS 
SET STATUS = 'SHIPPED', 
    TOTAL_AMOUNT = 1650.00,
    UPDATED_AT = SYSTIMESTAMP
WHERE ORDER_ID = 1;
COMMIT;
```

**Expected in Terminal 1:** You should see UPDATE event with:
- op_type="U"
- "before" values (old values)
- "after" values (new values)

**Screenshot Point:** ✅ Take screenshot showing UPDATE event with before/after values

---

### Step 5.4: Test DELETE Operation

**In Terminal 2:**
```sql
-- Delete an order item
DELETE FROM ORDER_ITEMS WHERE ITEM_ID = 104;
COMMIT;

EXIT;
```

**Expected in Terminal 1:** You should see DELETE event with:
- op_type="D"
- "before" values (deleted record)
- "after": null

**Screenshot Point:** ✅ Take screenshot showing DELETE event

---

## PHASE 6: Access Confluent Control Center

### Step 6.1: Get EC2 Public IP

```bash
# Get your EC2 public IP
curl http://169.254.169.254/latest/meta-data/public-ipv4
```

**Output Example:** `13.204.45.27`

### Step 6.2: Open in Browser

**URL:** `http://<YOUR-EC2-PUBLIC-IP>:9021`

**Note:** Ensure Security Group allows inbound traffic on port 9021

### Step 6.3: Navigate in Control Center

1. **Topics** → Select `ORDERMGMT.ORDERS`
   - View message schema
   - Inspect message content
   - See throughput metrics

2. **Connect** → `connect-default` → `oracle-xstream-cdc-source`
   - View connector configuration
   - Monitor task status
   - Check throughput and latency

**Screenshot Point:** ✅ Take multiple screenshots of Control Center UI

---

## PHASE 7: Monitoring and Health Checks

### Step 7.1: Check Connector Status

```bash
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '{
  name: .name,
  connector_state: .connector.state,
  task_state: .tasks[0].state
}'
```

**Expected Output:**
```json
{
  "name": "oracle-xstream-cdc-source",
  "connector_state": "RUNNING",
  "task_state": "RUNNING"
}
```

---

### Step 7.2: Check Oracle XStream Capture Statistics

```bash
docker exec oracle21c sqlplus -s sys/confluent123@XEPDB1 as sysdba <<EOF
SET PAGESIZE 50 LINESIZE 200
COLUMN CAPTURE_NAME FORMAT A15
COLUMN STATE FORMAT A20
COLUMN TOTAL_MESSAGES_CAPTURED FORMAT 999999999
COLUMN TOTAL_MESSAGES_ENQUEUED FORMAT 999999999

SELECT CAPTURE_NAME, 
       STATE,
       TOTAL_MESSAGES_CAPTURED,
       TOTAL_MESSAGES_ENQUEUED
FROM V\$XSTREAM_CAPTURE;

EXIT;
EOF
```

**Expected Output:**
```
CAPTURE_NAME    STATE                TOTAL_MESSAGES_CAPTURED TOTAL_MESSAGES_ENQUEUED
--------------- -------------------- ----------------------- -----------------------
CAPTURE_XOUT    CAPTURING CHANGES                         7                       7
```

**Screenshot Point:** ✅ Take screenshot showing capture statistics

---

### Step 7.3: Check Message Counts per Topic

```bash
for topic in ORDERMGMT.ORDERS ORDERMGMT.ORDER_ITEMS ORDERMGMT.CUSTOMERS; do
  echo "Topic: $topic"
  docker exec broker kafka-run-class kafka.tools.GetOffsetShell \
    --broker-list broker:29092 \
    --topic $topic 2>/dev/null | awk -F':' '{sum += $3} END {print "  Total Messages: " sum}'
  echo ""
done
```

**Expected Output:**
```
Topic: ORDERMGMT.ORDERS
  Total Messages: 4

Topic: ORDERMGMT.ORDER_ITEMS
  Total Messages: 3

Topic: ORDERMGMT.CUSTOMERS
  Total Messages: 3
```

---

## PHASE 8: Troubleshooting Commands

### Check Connect Logs
```bash
docker logs connect 2>&1 | grep -i "oracle" | tail -20
```

### Check for Errors
```bash
docker logs connect 2>&1 | grep -i "error" | grep -i "oracle" | tail -10
```

### Restart Connector
```bash
curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart
```

### Check Oracle Archive Log Mode
```bash
docker exec oracle21c sqlplus -s sys/confluent123@XEPDB1 as sysdba <<< "SELECT LOG_MODE FROM V\$DATABASE; EXIT;"
```

### Check Supplemental Logging
```bash
docker exec oracle21c sqlplus -s sys/confluent123@XEPDB1 as sysdba <<< "SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V\$DATABASE; EXIT;"
```

---

## Summary of Key Configuration Points

### Oracle Side:
1. ✅ ARCHIVELOG mode enabled (CRITICAL)
2. ✅ Supplemental logging enabled at database level
3. ✅ Supplemental logging enabled on all source tables (ALL COLUMNS)
4. ✅ XStream admin user (xstrmadmin) created with CAPTURE privilege
5. ✅ XStream outbound server (xout) created and running
6. ✅ Capture process (CAPTURE_XOUT) in "CAPTURING CHANGES" state

### Confluent Side:
1. ✅ Oracle JDBC driver (ojdbc8.jar) installed
2. ✅ Oracle XStream CDC Source Connector plugin installed
3. ✅ Connector configured with xstream.server.name="xout"
4. ✅ Network connectivity between Connect and Oracle containers
5. ✅ Topics auto-created with naming pattern: ORDERMGMT.<TABLE_NAME>

---

## Next Steps for Production

1. **Security:**
   - Enable TLS/SSL for Kafka
   - Configure SASL authentication
   - Secure Oracle credentials (use secrets management)

2. **Scalability:**
   - Increase tasks.max for parallel processing
   - Multiple Connect workers for HA

3. **Monitoring:**
   - Set up Prometheus + Grafana
   - Configure alerts for connector failures
   - Monitor XStream capture lag

4. **Data Governance:**
   - Schema Registry for schema evolution
   - Data lineage tracking
   - Audit logging

---

## Screenshot Checklist for Customer Documentation

- [ ] Oracle ARCHIVELOG mode enabled
- [ ] Supplemental logging enabled
- [ ] XStream admin privileges granted
- [ ] XStream outbound server details
- [ ] Capture state showing "CAPTURING CHANGES"
- [ ] All Confluent containers running
- [ ] Oracle CDC connector plugin installed
- [ ] Connector status showing "RUNNING"
- [ ] Auto-created Kafka topics
- [ ] Initial data in Kafka topics
- [ ] Real-time INSERT event
- [ ] UPDATE event with before/after values
- [ ] DELETE event with tombstone
- [ ] Capture statistics
- [ ] Control Center UI - Topics view
- [ ] Control Center UI - Connector view

---

**Document Version:** 1.0  
**Last Updated:** July 12, 2026  
**Connector Type:** Oracle XStream CDC Source Connector (Log-based CDC)  
**Confluent Platform Version:** 7.6.0  
**Oracle Version:** Oracle Database 21c Express Edition
