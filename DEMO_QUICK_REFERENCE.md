# Oracle XStream CDC Demo - Quick Reference Guide

## Pre-Demo Checklist

```bash
# 1. Check Oracle is running
docker ps | grep oracle21c

# 2. Check if shared-network exists
docker network inspect shared-network

# 3. If network doesn't exist, create it
docker network create shared-network
docker network connect shared-network oracle21c

# 4. Verify Oracle connectivity
docker exec -it oracle21c sqlplus -v
```

---

## Phase 1: Oracle Database Setup (15 minutes)

### 1.1 Enable ARCHIVELOG Mode

```bash
docker exec -it oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba
```

```sql
-- Check and enable
SELECT LOG_MODE FROM V$DATABASE;
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
SELECT LOG_MODE FROM V$DATABASE;  -- Should show ARCHIVELOG
```

### 1.2 Enable Supplemental Logging

```sql
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;  -- Should show YES
```

### 1.3 Create XStream Admin User

```sql
CREATE TABLESPACE xstream_tbs DATAFILE '/opt/oracle/oradata/XE/XEPDB1/xstream_tbs.dbf' SIZE 100M AUTOEXTEND ON;
CREATE USER xstrmadmin IDENTIFIED BY xstrmadmin123 DEFAULT TABLESPACE xstream_tbs QUOTA UNLIMITED ON xstream_tbs;

GRANT CREATE SESSION, SET CONTAINER, SELECT ANY TRANSACTION, LOGMINING TO xstrmadmin;
GRANT LOCK ANY TABLE, SELECT ANY TABLE, EXECUTE_CATALOG_ROLE, SELECT ANY DICTIONARY TO xstrmadmin;
GRANT CREATE TABLESPACE, ALTER TABLESPACE, DROP TABLESPACE TO xstrmadmin;
GRANT CREATE ANY DIRECTORY, DROP ANY DIRECTORY TO xstrmadmin;

BEGIN
   DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(grantee => 'xstrmadmin', privilege_type => 'CAPTURE', grant_select_privileges => TRUE);
END;
/

SELECT * FROM DBA_XSTREAM_ADMINISTRATOR;
EXIT;
```

### 1.4 Setup Source Tables

```bash
docker exec -it oracle21c sqlplus ordermgmt/kafka@XEPDB1
```

```sql
-- Create tables
CREATE TABLE ORDERS (ORDER_ID NUMBER PRIMARY KEY, CUSTOMER_NAME VARCHAR2(100), ORDER_DATE TIMESTAMP DEFAULT SYSTIMESTAMP, TOTAL_AMOUNT NUMBER(10,2), STATUS VARCHAR2(20), CREATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP, UPDATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP);
CREATE TABLE ORDER_ITEMS (ITEM_ID NUMBER PRIMARY KEY, ORDER_ID NUMBER, PRODUCT_NAME VARCHAR2(100), QUANTITY NUMBER, PRICE NUMBER(10,2), CREATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP);
CREATE TABLE CUSTOMERS (CUSTOMER_ID NUMBER PRIMARY KEY, CUSTOMER_NAME VARCHAR2(100), EMAIL VARCHAR2(100), PHONE VARCHAR2(20), CREATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP);

-- Enable supplemental logging
ALTER TABLE ORDERS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE ORDER_ITEMS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE CUSTOMERS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Grant permissions
GRANT SELECT ON ORDERS TO xstrmadmin;
GRANT SELECT ON ORDER_ITEMS TO xstrmadmin;
GRANT SELECT ON CUSTOMERS TO xstrmadmin;

-- Insert test data
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

SELECT COUNT(*) FROM ORDERS;
SELECT COUNT(*) FROM ORDER_ITEMS;
SELECT COUNT(*) FROM CUSTOMERS;
EXIT;
```

### 1.5 Create XStream Outbound Server

```bash
docker exec -it oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba
```

```sql
-- Create outbound server
DECLARE
  tables  DBMS_UTILITY.UNCL_ARRAY;
  schemas DBMS_UTILITY.UNCL_ARRAY;
BEGIN
  schemas(1) := 'ordermgmt';
  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(server_name => 'xout', table_names => tables, schema_names => schemas, source_database => 'XEPDB1');
END;
/

-- Configure
BEGIN
  DBMS_XSTREAM_ADM.ALTER_OUTBOUND(server_name => 'xout', connect_user => 'xstrmadmin');
END;
/

SELECT SERVER_NAME, CAPTURE_NAME, QUEUE_NAME, CONNECT_USER FROM DBA_XSTREAM_OUTBOUND;

-- Start capture
BEGIN
  DBMS_CAPTURE_ADM.START_CAPTURE(capture_name => 'CAPTURE_XOUT');
END;
/

SELECT CAPTURE_NAME, STATUS, STATE FROM DBA_CAPTURE;  -- Should show ENABLED, CAPTURING CHANGES
SELECT CAPTURE_NAME, STATE, TOTAL_MESSAGES_CAPTURED FROM V$XSTREAM_CAPTURE;
EXIT;
```

---

## Phase 2: Confluent Platform Setup (10 minutes)

### 2.1 Create Project Directory

```bash
cd ~
mkdir -p confluent-oracle-cdc/jdbc-drivers
cd confluent-oracle-cdc
```

### 2.2 Download JDBC Driver

```bash
cd jdbc-drivers
wget https://download.oracle.com/otn-pub/otn_software/jdbc/218/ojdbc8.jar
ls -lh ojdbc8.jar
cd ..
```

### 2.3 Create docker-compose.yml

```bash
cat > docker-compose.yml <<'DOCKEREOF'
version: '3.8'
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.6.0
    container_name: zookeeper
    ports: ["2181:2181"]
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
    networks: [shared-network]
  broker:
    image: confluentinc/cp-kafka:7.6.0
    container_name: broker
    depends_on: [zookeeper]
    ports: ["9092:9092"]
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://broker:29092,PLAINTEXT_HOST://localhost:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: 'true'
    networks: [shared-network]
  schema-registry:
    image: confluentinc/cp-schema-registry:7.6.0
    container_name: schema-registry
    depends_on: [broker]
    ports: ["8081:8081"]
    environment:
      SCHEMA_REGISTRY_HOST_NAME: schema-registry
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: 'broker:29092'
    networks: [shared-network]
  connect:
    image: confluentinc/cp-kafka-connect:7.6.0
    container_name: connect
    depends_on: [broker, schema-registry]
    ports: ["8083:8083"]
    environment:
      CONNECT_BOOTSTRAP_SERVERS: 'broker:29092'
      CONNECT_REST_ADVERTISED_HOST_NAME: connect
      CONNECT_GROUP_ID: compose-connect-group
      CONNECT_CONFIG_STORAGE_TOPIC: docker-connect-configs
      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_OFFSET_STORAGE_TOPIC: docker-connect-offsets
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_STATUS_STORAGE_TOPIC: docker-connect-status
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_PLUGIN_PATH: "/usr/share/java,/usr/share/confluent-hub-components"
    volumes:
      - ./jdbc-drivers:/usr/share/java/kafka-connect-jdbc
    networks: [shared-network]
    command:
      - bash
      - -c
      - |
        echo "Installing Oracle XStream CDC Connector..."
        confluent-hub install --no-prompt confluentinc/kafka-connect-oracle-cdc:2.9.2
        cp /usr/share/java/kafka-connect-jdbc/ojdbc8.jar /usr/share/confluent-hub-components/confluentinc-kafka-connect-oracle-cdc/lib/
        /etc/confluent/docker/run
  control-center:
    image: confluentinc/cp-enterprise-control-center:7.6.0
    container_name: control-center
    depends_on: [broker, schema-registry, connect]
    ports: ["9021:9021"]
    environment:
      CONTROL_CENTER_BOOTSTRAP_SERVERS: 'broker:29092'
      CONTROL_CENTER_CONNECT_CONNECT-DEFAULT_CLUSTER: 'connect:8083'
      CONTROL_CENTER_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
      CONTROL_CENTER_REPLICATION_FACTOR: 1
    networks: [shared-network]
networks:
  shared-network:
    external: true
DOCKEREOF
```

### 2.4 Start Services

```bash
docker-compose up -d
sleep 120  # Wait 2 minutes
docker-compose ps  # Verify all running
```

### 2.5 Verify Connector Plugin

```bash
curl http://localhost:8083/
curl -s http://localhost:8083/connector-plugins | jq '.[] | select(.class | contains("Oracle"))'
# Should show: io.confluent.connect.oracle.cdc.OracleCdcSourceConnector
```

---

## Phase 3: Deploy Oracle XStream CDC Connector (5 minutes)

### 3.1 Test Network Connectivity

```bash
docker exec connect bash -c "timeout 5 bash -c '</dev/tcp/oracle21c/1521' && echo 'Oracle reachable' || echo 'Cannot reach Oracle'"
```

### 3.2 Create Connector Config

```bash
cat > oracle-xstream-cdc-config.json <<'CONNEOF'
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
    "redo.log.consumer.bootstrap.servers": "broker:29092",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true",
    "value.converter.schemas.enable": "true",
    "errors.tolerance": "all",
    "errors.log.enable": "true"
  }
}
CONNEOF
```

### 3.3 Deploy Connector

```bash
curl -X POST http://localhost:8083/connectors -H "Content-Type: application/json" -d @oracle-xstream-cdc-config.json
sleep 10
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '.'
# Should show: connector.state="RUNNING", tasks[0].state="RUNNING"
```

### 3.4 Verify Topics

```bash
docker exec broker kafka-topics --bootstrap-server broker:29092 --list | grep ORDERMGMT
# Should show: ORDERMGMT.ORDERS, ORDERMGMT.ORDER_ITEMS, ORDERMGMT.CUSTOMERS
```

---

## Phase 4: Demo Real-Time CDC (10 minutes)

### 4.1 Test INSERT

**Terminal 1 (Consumer):**
```bash
docker exec broker kafka-console-consumer --bootstrap-server broker:29092 --topic ORDERMGMT.ORDERS --property print.key=true --property print.timestamp=true
```

**Terminal 2 (Producer):**
```bash
docker exec -it oracle21c sqlplus ordermgmt/kafka@XEPDB1
```
```sql
INSERT INTO ORDERS VALUES (4, 'Alice Williams', SYSTIMESTAMP, 3200.00, 'PENDING', SYSTIMESTAMP, SYSTIMESTAMP);
COMMIT;
-- Check Terminal 1 for INSERT event with op_type="I"
```

### 4.2 Test UPDATE

```sql
UPDATE ORDERS SET STATUS = 'SHIPPED', TOTAL_AMOUNT = 1650.00, UPDATED_AT = SYSTIMESTAMP WHERE ORDER_ID = 1;
COMMIT;
-- Check Terminal 1 for UPDATE event with before/after values
```

### 4.3 Test DELETE

```sql
DELETE FROM ORDER_ITEMS WHERE ITEM_ID = 104;
COMMIT;
-- Check Terminal 1 for DELETE event with op_type="D"
EXIT;
```

---

## Monitoring Commands

### Quick Health Check

```bash
# All in one
echo "=== Connector Status ===" && \
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '{name, connector_state: .connector.state, task_state: .tasks[0].state}' && \
echo -e "\n=== Topics ===" && \
docker exec broker kafka-topics --bootstrap-server broker:29092 --list | grep ORDERMGMT && \
echo -e "\n=== XStream Capture ===" && \
docker exec oracle21c sqlplus -s sys/confluent123@XEPDB1 as sysdba <<< "SELECT CAPTURE_NAME, STATE, TOTAL_MESSAGES_CAPTURED FROM V\$XSTREAM_CAPTURE WHERE CAPTURE_NAME='CAPTURE_XOUT'; EXIT;"
```

### Message Counts

```bash
for topic in ORDERMGMT.ORDERS ORDERMGMT.ORDER_ITEMS ORDERMGMT.CUSTOMERS; do
  echo -n "$topic: "
  docker exec broker kafka-run-class kafka.tools.GetOffsetShell --broker-list broker:29092 --topic $topic 2>/dev/null | awk -F':' '{sum += $3} END {print sum " messages"}'
done
```

### Check Logs

```bash
# Connect logs
docker logs connect 2>&1 | grep -i oracle | tail -20

# Errors only
docker logs connect 2>&1 | grep -i error | tail -10
```

---

## Connector Management

```bash
# Status
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '.'

# Restart
curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart

# Pause
curl -X PUT http://localhost:8083/connectors/oracle-xstream-cdc-source/pause

# Resume
curl -X PUT http://localhost:8083/connectors/oracle-xstream-cdc-source/resume

# Delete
curl -X DELETE http://localhost:8083/connectors/oracle-xstream-cdc-source

# Recreate
curl -X POST http://localhost:8083/connectors -H "Content-Type: application/json" -d @oracle-xstream-cdc-config.json
```

---

## Oracle Troubleshooting

### Check ARCHIVELOG Status
```sql
SELECT LOG_MODE FROM V$DATABASE;
```

### Check Supplemental Logging
```sql
SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;
SELECT TABLE_NAME, LOG_GROUP_NAME FROM DBA_LOG_GROUPS WHERE OWNER='ORDERMGMT';
```

### Check XStream Status
```sql
SELECT * FROM DBA_XSTREAM_OUTBOUND;
SELECT CAPTURE_NAME, STATUS, STATE, ERROR_NUMBER FROM DBA_CAPTURE;
SELECT * FROM V$XSTREAM_CAPTURE;
```

### Restart Capture
```sql
BEGIN
  DBMS_CAPTURE_ADM.STOP_CAPTURE(capture_name => 'CAPTURE_XOUT');
  DBMS_CAPTURE_ADM.START_CAPTURE(capture_name => 'CAPTURE_XOUT');
END;
/
```

---

## Access URLs

```bash
# Get EC2 public IP
curl -s http://169.254.169.254/latest/meta-data/public-ipv4

# Control Center: http://<EC2-IP>:9021
# Kafka REST Proxy: http://<EC2-IP>:8083
# Schema Registry: http://<EC2-IP>:8081
```

---

## Stop/Start Environment

### Stop All
```bash
cd ~/confluent-oracle-cdc
docker-compose down
# Optionally stop Oracle
docker stop oracle21c
```

### Start All
```bash
# Start Oracle if stopped
docker start oracle21c
sleep 30

# Start Confluent
cd ~/confluent-oracle-cdc
docker-compose up -d
sleep 120

# Verify
docker-compose ps

# Verify capture is running
docker exec oracle21c sqlplus -s sys/confluent123@XEPDB1 as sysdba <<< "SELECT STATE FROM V\$XSTREAM_CAPTURE WHERE CAPTURE_NAME='CAPTURE_XOUT'; EXIT;"
# If not running, start it:
docker exec oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba <<< "BEGIN DBMS_CAPTURE_ADM.START_CAPTURE(capture_name => 'CAPTURE_XOUT'); END; / EXIT;"
```

---

## Common Issues & Quick Fixes

### Issue: Connector FAILED
```bash
# Get error details
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '.tasks[0].trace'
# Restart
curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart
```

### Issue: No messages in Kafka
```bash
# 1. Check connector is RUNNING
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '.tasks[0].state'

# 2. Check capture is CAPTURING CHANGES
docker exec oracle21c sqlplus -s sys/confluent123@XEPDB1 as sysdba <<< "SELECT STATE FROM V\$XSTREAM_CAPTURE WHERE CAPTURE_NAME='CAPTURE_XOUT'; EXIT;"

# 3. Make a new change (connector starts from CURRENT SCN)
docker exec oracle21c sqlplus ordermgmt/kafka@XEPDB1 <<< "INSERT INTO ORDERS VALUES (999, 'Test', SYSTIMESTAMP, 99.99, 'TEST', SYSTIMESTAMP, SYSTIMESTAMP); COMMIT; EXIT;"

# 4. Check Kafka again
docker exec broker kafka-console-consumer --bootstrap-server broker:29092 --topic ORDERMGMT.ORDERS --from-beginning --max-messages 1 --timeout-ms 5000
```

### Issue: Cannot connect to Oracle from Connect
```bash
# Test connectivity
docker exec connect bash -c "timeout 5 bash -c '</dev/tcp/oracle21c/1521' && echo 'OK' || echo 'FAIL'"

# Check if Oracle is on shared-network
docker network inspect shared-network | grep oracle21c

# If not, add it
docker network connect shared-network oracle21c

# Restart connector
curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart
```

---

## Success Criteria

✅ Oracle ARCHIVELOG mode = ARCHIVELOG  
✅ Supplemental logging = YES  
✅ XStream admin created with CAPTURE privilege  
✅ XStream outbound server exists  
✅ Capture state = CAPTURING CHANGES  
✅ All Confluent containers = Up  
✅ Oracle CDC connector plugin installed  
✅ Connector state = RUNNING  
✅ Topics auto-created (3 topics)  
✅ INSERT event captured in real-time  
✅ UPDATE event shows before/after  
✅ DELETE event shows tombstone  
✅ Control Center accessible  

---

**Total Setup Time:** ~30-40 minutes  
**Demo Time:** ~10 minutes  
**Audience:** Technical stakeholders, architects, DBAs
