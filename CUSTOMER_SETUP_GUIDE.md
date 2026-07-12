# Oracle XStream CDC with Confluent Platform
## Implementation Guide

---

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Oracle Database Configuration](#oracle-database-configuration)
5. [Confluent Platform Deployment](#confluent-platform-deployment)
6. [Oracle XStream CDC Connector Setup](#oracle-xstream-cdc-connector-setup)
7. [Testing and Validation](#testing-and-validation)
8. [Monitoring](#monitoring)
9. [Production Considerations](#production-considerations)

---

## Overview

This guide demonstrates the implementation of real-time Change Data Capture (CDC) from Oracle Database to Apache Kafka using **Oracle XStream CDC Source Connector** from Confluent.

### What is XStream CDC?

Oracle XStream is a log-based CDC technology that:
- Reads Oracle redo logs directly
- Captures all DML operations (INSERT, UPDATE, DELETE) in real-time
- Provides before/after values for UPDATE operations
- Guarantees data consistency and ordering
- Minimizes impact on source database

### XStream CDC vs JDBC Source Connector

| Feature | XStream CDC | JDBC Connector |
|---------|-------------|----------------|
| **Capture Method** | Log-based (redo logs) | Query-based (polling) |
| **Operations Captured** | INSERT, UPDATE, DELETE | INSERT, UPDATE only |
| **Latency** | Sub-second | Seconds to minutes |
| **Database Impact** | Minimal (reads logs) | High (SELECT queries) |
| **Before/After Values** | ✅ Yes | ❌ No |
| **Guaranteed Ordering** | ✅ Yes | ❌ No |
| **Production Grade** | ✅ Enterprise | Limited |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      ORACLE DATABASE                             │
│  ┌──────────────┐         ┌────────────────┐                   │
│  │  ORDERMGMT   │────────▶│  Redo Logs     │                   │
│  │   Schema     │         │                │                   │
│  └──────────────┘         └────────┬───────┘                   │
│                                     │                            │
│                           ┌─────────▼────────┐                  │
│                           │ XStream Outbound │                  │
│                           │   Server (xout)  │                  │
│                           └─────────┬────────┘                  │
└─────────────────────────────────────┼───────────────────────────┘
                                      │
                                      │ XStream Protocol
                                      │
┌─────────────────────────────────────▼───────────────────────────┐
│                    CONFLUENT PLATFORM                            │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │           Kafka Connect (Connect Worker)                  │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  Oracle XStream CDC Source Connector              │  │  │
│  │  │  - Connects to XStream outbound server            │  │  │
│  │  │  - Transforms CDC events to Kafka messages        │  │  │
│  │  └────────────────┬───────────────────────────────────┘  │  │
│  └───────────────────┼──────────────────────────────────────┘  │
│                      │                                          │
│  ┌───────────────────▼──────────────────────────────────────┐  │
│  │              Apache Kafka Broker                         │  │
│  │  ┌──────────────────┐  ┌──────────────────┐            │  │
│  │  │ ORDERMGMT.ORDERS │  │ ORDERMGMT.ITEMS  │  ...       │  │
│  │  │   (Topic)        │  │   (Topic)        │            │  │
│  │  └──────────────────┘  └──────────────────┘            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Confluent Control Center (Monitoring)            │  │
│  └──────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Software Requirements
- Oracle Database 21c Express Edition (running in Docker)
- Docker and Docker Compose installed
- Minimum 8GB RAM available
- Network connectivity between Oracle and Confluent containers

### Oracle Database Requirements
- Database must be in **ARCHIVELOG** mode (mandatory for XStream)
- **Supplemental logging** must be enabled
- Oracle user with **XStream CAPTURE** privileges

### Network Configuration
- Oracle Database port: 1521
- Kafka broker port: 9092
- Kafka Connect REST API port: 8083
- Control Center UI port: 9021

---

## Oracle Database Configuration

### Step 1: Enable ARCHIVELOG Mode

**Purpose:** ARCHIVELOG mode is required for Oracle XStream to read redo logs for CDC.

```sql
-- Connect as sysdba
sqlplus sys/confluent123@XEPDB1 as sysdba

-- Check current mode
SELECT LOG_MODE FROM V$DATABASE;

-- Enable ARCHIVELOG if not already enabled
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- Verify
SELECT LOG_MODE FROM V$DATABASE;
-- Expected: ARCHIVELOG
```

### Step 2: Enable Supplemental Logging

**Purpose:** Supplemental logging ensures all necessary information is captured in redo logs for CDC.

```sql
-- Enable minimal supplemental logging at database level
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Verify
SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;
-- Expected: YES or IMPLICIT
```

### Step 3: Create XStream Administrator User

**Purpose:** Create a dedicated user with XStream CAPTURE privileges.

```sql
-- Create tablespace
CREATE TABLESPACE xstream_tbs 
DATAFILE '/opt/oracle/oradata/XE/XEPDB1/xstream_tbs.dbf' 
SIZE 100M AUTOEXTEND ON MAXSIZE UNLIMITED;

-- Create user
CREATE USER xstrmadmin IDENTIFIED BY xstrmadmin123
DEFAULT TABLESPACE xstream_tbs
QUOTA UNLIMITED ON xstream_tbs;

-- Grant required privileges
GRANT CREATE SESSION TO xstrmadmin;
GRANT SET CONTAINER TO xstrmadmin;
GRANT SELECT ANY TRANSACTION TO xstrmadmin;
GRANT LOGMINING TO xstrmadmin;
GRANT LOCK ANY TABLE TO xstrmadmin;
GRANT SELECT ANY TABLE TO xstrmadmin;
GRANT EXECUTE_CATALOG_ROLE TO xstrmadmin;
GRANT SELECT ANY DICTIONARY TO xstrmadmin;

-- Grant XStream CAPTURE privilege (CRITICAL)
BEGIN
   DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
      grantee => 'xstrmadmin',
      privilege_type => 'CAPTURE',
      grant_select_privileges => TRUE
   );
END;
/

-- Verify
SELECT * FROM DBA_XSTREAM_ADMINISTRATOR;
```

### Step 4: Prepare Source Tables

**Purpose:** Configure source schema tables for CDC capture.

```sql
-- Connect as source schema user
sqlplus ordermgmt/kafka@XEPDB1

-- Create sample tables
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
    CREATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP
);

-- Enable table-level supplemental logging (CRITICAL)
-- This captures all column values in redo logs
ALTER TABLE ORDERS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE ORDER_ITEMS ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Grant SELECT to XStream admin
GRANT SELECT ON ORDERS TO xstrmadmin;
GRANT SELECT ON ORDER_ITEMS TO xstrmadmin;

-- Insert test data
INSERT INTO ORDERS VALUES (1, 'John Doe', SYSTIMESTAMP, 1500.00, 'PENDING', SYSTIMESTAMP, SYSTIMESTAMP);
INSERT INTO ORDERS VALUES (2, 'Jane Smith', SYSTIMESTAMP, 2300.50, 'CONFIRMED', SYSTIMESTAMP, SYSTIMESTAMP);
INSERT INTO ORDER_ITEMS VALUES (101, 1, 'Laptop', 1, 1200.00, SYSTIMESTAMP);
INSERT INTO ORDER_ITEMS VALUES (102, 2, 'Monitor', 2, 1150.25, SYSTIMESTAMP);
COMMIT;
```

### Step 5: Create XStream Outbound Server

**Purpose:** Create the CDC engine that reads redo logs and streams changes.

```sql
-- Connect as sysdba
sqlplus sys/confluent123@XEPDB1 as sysdba

-- Create XStream outbound server
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

-- Configure connect user
BEGIN
  DBMS_XSTREAM_ADM.ALTER_OUTBOUND(
    server_name => 'xout',
    connect_user => 'xstrmadmin'
  );
END;
/

-- Verify outbound server
SELECT SERVER_NAME, CAPTURE_NAME, QUEUE_NAME, CONNECT_USER 
FROM DBA_XSTREAM_OUTBOUND;

-- Start capture process
BEGIN
  DBMS_CAPTURE_ADM.START_CAPTURE(capture_name => 'CAPTURE_XOUT');
END;
/

-- Verify capture is running
SELECT CAPTURE_NAME, STATUS, STATE FROM DBA_CAPTURE;
-- Expected: STATUS=ENABLED, STATE=CAPTURING CHANGES
```

---

## Confluent Platform Deployment

### Step 1: Create Project Directory

```bash
mkdir -p ~/confluent-oracle-cdc/{connectors,jdbc-drivers}
cd ~/confluent-oracle-cdc
```

### Step 2: Download Oracle JDBC Driver

```bash
cd jdbc-drivers
wget https://download.oracle.com/otn-pub/otn_software/jdbc/218/ojdbc8.jar
cd ..
```

### Step 3: Create Docker Compose Configuration

Create `docker-compose.yml` with the following services:
- **Zookeeper**: Cluster coordination
- **Kafka Broker**: Message streaming platform
- **Schema Registry**: Schema management
- **Kafka Connect**: Connector runtime with Oracle XStream CDC plugin
- **Control Center**: Web-based monitoring and management UI

```yaml
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
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://broker:29092,PLAINTEXT_HOST://localhost:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
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
    networks:
      - shared-network
    command:
      - bash
      - -c
      - |
        echo "Installing Oracle XStream CDC Source Connector..."
        confluent-hub install --no-prompt confluentinc/kafka-connect-oracle-cdc:2.9.2
        echo "Copying Oracle JDBC Driver..."
        cp /usr/share/java/kafka-connect-jdbc/ojdbc8.jar /usr/share/confluent-hub-components/confluentinc-kafka-connect-oracle-cdc/lib/
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
    networks:
      - shared-network

networks:
  shared-network:
    external: true
```

### Step 4: Start Confluent Platform

```bash
# Ensure Oracle is on shared network
docker network connect shared-network oracle21c

# Start Confluent Platform
docker-compose up -d

# Wait for initialization (2 minutes)
sleep 120

# Verify all services are running
docker-compose ps
```

### Step 5: Verify Connector Plugin

```bash
# Check Oracle CDC connector is installed
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

---

## Oracle XStream CDC Connector Setup

### Step 1: Create Connector Configuration

Create `oracle-xstream-cdc-config.json`:

```json
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
    
    "table.inclusion.regex": "ORDERMGMT\\.(ORDERS|ORDER_ITEMS)",
    
    "topic.creation.default.partitions": "3",
    "topic.creation.default.replication.factor": "1",
    
    "numeric.mapping": "best_fit",
    
    "redo.log.consumer.bootstrap.servers": "broker:29092",
    
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true",
    "value.converter.schemas.enable": "true",
    
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.deadletterqueue.topic.name": "dlq-oracle-cdc"
  }
}
```

### Key Configuration Parameters

| Parameter | Description |
|-----------|-------------|
| `xstream.server.name` | Name of Oracle XStream outbound server (xout) |
| `start.from` | CURRENT = capture changes from now; SNAPSHOT = include existing data |
| `table.inclusion.regex` | Regex pattern for tables to capture |
| `numeric.mapping` | How to map Oracle NUMBER type (best_fit, precision_only) |
| `redo.log.consumer.bootstrap.servers` | Kafka broker for internal metadata |

### Step 2: Deploy Connector

```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @oracle-xstream-cdc-config.json
```

### Step 3: Verify Connector Status

```bash
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
  ]
}
```

### Step 4: Verify Topics Created

```bash
docker exec broker kafka-topics --bootstrap-server broker:29092 --list | grep ORDERMGMT
```

**Expected Output:**
```
ORDERMGMT.ORDERS
ORDERMGMT.ORDER_ITEMS
```

---

## Testing and Validation

### Test 1: Verify Initial Data (Snapshot)

```bash
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic ORDERMGMT.ORDERS \
  --from-beginning \
  --max-messages 5
```

### Test 2: INSERT Operation (Real-time CDC)

**Terminal 1 - Start Consumer:**
```bash
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic ORDERMGMT.ORDERS \
  --property print.key=true
```

**Terminal 2 - Insert Data:**
```sql
sqlplus ordermgmt/kafka@XEPDB1

INSERT INTO ORDERS VALUES (
  100, 
  'Alice Williams', 
  SYSTIMESTAMP, 
  3200.00, 
  'PENDING',
  SYSTIMESTAMP,
  SYSTIMESTAMP
);
COMMIT;
```

**Expected in Terminal 1:**
```json
{
  "schema": {...},
  "payload": {
    "op_type": "I",
    "op_ts": "2026-07-12 10:30:45.123456",
    "table": "ORDERMGMT.ORDERS",
    "ORDER_ID": 100,
    "CUSTOMER_NAME": "Alice Williams",
    "TOTAL_AMOUNT": 3200.00,
    "STATUS": "PENDING"
  }
}
```

### Test 3: UPDATE Operation

```sql
UPDATE ORDERS 
SET STATUS = 'SHIPPED', 
    TOTAL_AMOUNT = 1650.00
WHERE ORDER_ID = 1;
COMMIT;
```

**Expected Kafka Message:**
```json
{
  "op_type": "U",
  "before": {
    "ORDER_ID": 1,
    "STATUS": "PENDING",
    "TOTAL_AMOUNT": 1500.00
  },
  "after": {
    "ORDER_ID": 1,
    "STATUS": "SHIPPED",
    "TOTAL_AMOUNT": 1650.00
  }
}
```

### Test 4: DELETE Operation

```sql
DELETE FROM ORDER_ITEMS WHERE ITEM_ID = 102;
COMMIT;
```

**Expected Kafka Message:**
```json
{
  "op_type": "D",
  "before": {
    "ITEM_ID": 102,
    "ORDER_ID": 2,
    "PRODUCT_NAME": "Monitor",
    "QUANTITY": 2,
    "PRICE": 1150.25
  },
  "after": null
}
```

---

## Monitoring

### Confluent Control Center

Access the web UI at: `http://<SERVER-IP>:9021`

**Features:**
- Real-time topic monitoring
- Message inspection with schema
- Connector health and metrics
- Consumer lag monitoring
- Throughput and latency graphs

### Connector Metrics

```bash
# Connector status
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '.'

# List all connectors
curl -s http://localhost:8083/connectors
```

### Oracle XStream Metrics

```sql
-- Capture statistics
SELECT CAPTURE_NAME, 
       STATE,
       TOTAL_MESSAGES_CAPTURED,
       TOTAL_MESSAGES_ENQUEUED,
       LATENCY_SECONDS
FROM V$XSTREAM_CAPTURE;

-- Current SCN
SELECT CURRENT_SCN FROM V$DATABASE;
```

### Kafka Topic Metrics

```bash
# Describe topic
docker exec broker kafka-topics \
  --bootstrap-server broker:29092 \
  --topic ORDERMGMT.ORDERS \
  --describe

# Consumer groups
docker exec broker kafka-consumer-groups \
  --bootstrap-server broker:29092 \
  --list
```

---

## Production Considerations

### High Availability

**Kafka Connect:**
- Deploy multiple Connect workers
- Configure `tasks.max` > 1 for parallelism
- Use distributed mode (already configured)

**Kafka Broker:**
- Minimum 3 brokers for production
- Replication factor ≥ 3
- Min in-sync replicas = 2

**Oracle:**
- Oracle Data Guard for HA
- RAC (Real Application Clusters)

### Security

**Network:**
- TLS encryption for all connections
- SASL authentication (PLAIN, SCRAM, or Kerberos)
- Network segmentation

**Credentials:**
- Vault/Secrets management (HashiCorp Vault, AWS Secrets Manager)
- Encrypted passwords in connector config
- Least privilege access

**Sample Secure Configuration:**
```json
{
  "oracle.server": "${vault:oracle/hostname}",
  "oracle.username": "${vault:oracle/username}",
  "oracle.password": "${vault:oracle/password}",
  "security.protocol": "SSL",
  "ssl.truststore.location": "/path/to/truststore.jks",
  "ssl.truststore.password": "${vault:ssl/truststore_password}"
}
```

### Performance Tuning

**Oracle Side:**
```sql
-- Increase SGA for LogMiner
ALTER SYSTEM SET sga_target=4G SCOPE=SPFILE;

-- Optimize redo log size
ALTER DATABASE ADD LOGFILE GROUP 4 SIZE 500M;
```

**Connector Side:**
```json
{
  "tasks.max": "4",
  "batch.size": "2000",
  "poll.interval.ms": "500",
  "redo.log.row.fetch.size": "2000"
}
```

**Kafka Side:**
```properties
# Producer compression
compression.type=lz4

# Batching
linger.ms=10
batch.size=32768
```

### Monitoring and Alerting

**Recommended Metrics:**
- Connector status (should be RUNNING)
- XStream capture lag (should be < 5 seconds)
- Kafka consumer lag
- Throughput (messages/sec)
- Error rate

**Tools:**
- Prometheus + Grafana
- Confluent Control Center
- Oracle Enterprise Manager
- Custom scripts

**Sample Alert Rules:**
```yaml
- alert: ConnectorDown
  expr: kafka_connect_connector_status{connector="oracle-xstream-cdc-source"} != 1
  for: 2m
  
- alert: HighCaptureLag
  expr: xstream_capture_latency_seconds > 30
  for: 5m
```

### Data Governance

**Schema Evolution:**
- Use Schema Registry for centralized schema management
- Configure schema compatibility (BACKWARD, FORWARD, FULL)
- Version control for schemas

**Data Quality:**
- Implement data validation at consumer side
- Dead letter queue for malformed messages
- Data reconciliation checks

**Compliance:**
- PII data masking/encryption
- Audit logging for all data access
- Data retention policies
- GDPR/CCPA compliance

---

## Troubleshooting

### Common Issues

**Issue 1: Connector fails with "ORA-01327"**

**Cause:** Multiple processes trying to lock dictionary

**Solution:**
```sql
-- Restart capture
BEGIN
  DBMS_CAPTURE_ADM.STOP_CAPTURE(capture_name => 'CAPTURE_XOUT');
  DBMS_CAPTURE_ADM.START_CAPTURE(capture_name => 'CAPTURE_XOUT');
END;
/
```

**Issue 2: No messages in Kafka**

**Checklist:**
1. Connector status is RUNNING
2. Capture state is "CAPTURING CHANGES"
3. Changes made AFTER connector started (start.from=CURRENT)
4. Tables match inclusion regex
5. Network connectivity OK

**Issue 3: Connector shows FAILED**

**Debug:**
```bash
# Get detailed error
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '.tasks[0].trace'

# Check logs
docker logs connect 2>&1 | grep -i error

# Restart connector
curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart
```

### Verification Checklist

**Oracle Configuration:**
- [ ] ARCHIVELOG mode enabled
- [ ] Supplemental logging enabled (database level)
- [ ] Supplemental logging enabled (table level - ALL COLUMNS)
- [ ] XStream admin user created with CAPTURE privilege
- [ ] XStream outbound server created
- [ ] Capture process state = "CAPTURING CHANGES"

**Confluent Configuration:**
- [ ] All containers running
- [ ] Oracle JDBC driver installed
- [ ] Oracle CDC connector plugin available
- [ ] Network connectivity: Connect → Oracle
- [ ] Connector deployed and status = RUNNING
- [ ] Topics auto-created

---

## Appendix

### Useful Commands

```bash
# Restart connector
curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart

# Pause connector
curl -X PUT http://localhost:8083/connectors/oracle-xstream-cdc-source/pause

# Resume connector
curl -X PUT http://localhost:8083/connectors/oracle-xstream-cdc-source/resume

# Delete connector
curl -X DELETE http://localhost:8083/connectors/oracle-xstream-cdc-source

# Update connector config
curl -X PUT http://localhost:8083/connectors/oracle-xstream-cdc-source/config \
  -H "Content-Type: application/json" \
  -d @oracle-xstream-cdc-config.json
```

### Reference Documentation

- [Oracle XStream Concepts](https://docs.oracle.com/en/database/oracle/oracle-database/21/xstrm/)
- [Confluent Oracle CDC Connector](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/)
- [Kafka Connect Documentation](https://docs.confluent.io/platform/current/connect/index.html)
- [Oracle Supplemental Logging](https://docs.oracle.com/en/database/oracle/oracle-database/21/sutil/oracle-logminer-utility.html#GUID-D857AF96-AC24-4CA1-B620-8EA3DF30D72E)

---

## Support

For issues or questions:
- Confluent Support: https://support.confluent.io
- Community Forums: https://forum.confluent.io
- Oracle Support: https://support.oracle.com

---

**Document Version:** 1.0  
**Date:** July 12, 2026  
**Technology Stack:**
- Oracle Database 21c Express Edition
- Confluent Platform 7.6.0
- Oracle XStream CDC Source Connector 2.9.2
