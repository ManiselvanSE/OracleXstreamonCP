# Oracle XStream CDC Deployment Guide

Professional deployment guide for Oracle XStream CDC with Confluent Platform.

---

## Prerequisites

### System Requirements

| Component | Requirement |
|-----------|-------------|
| CPU | 4 vCPU minimum |
| Memory | 16 GB minimum |
| Disk | **100 GB minimum** |
| OS | Amazon Linux 2023 / RHEL 8+ / Ubuntu 20.04+ |
| Docker | 20.10+ |
| Docker Compose | 2.24.0+ |

### Network Ports

```
1521  - Oracle Database
9092  - Kafka Broker
8081  - Schema Registry
8083  - Kafka Connect
9021  - Control Center
9101-9104 - JMX Monitoring
```

### AWS EC2 Configuration

**Instance Type:** t3.xlarge or larger

**Security Group Rules:**
```bash
# SSH access
22/tcp from your IP

# Oracle Database
1521/tcp from 0.0.0.0/0

# Kafka services
9092/tcp from 0.0.0.0/0
8081/tcp from 0.0.0.0/0
8083/tcp from 0.0.0.0/0
9021/tcp from 0.0.0.0/0

# JMX monitoring
9101-9104/tcp from 0.0.0.0/0
```

**⚠️ Critical:** Resize root volume to 100 GB before deployment.

---

## Phase 1: Infrastructure Setup

### 1.1 Install Docker

```bash
# Update system
sudo yum update -y

# Install Docker
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# Logout and login for group changes to take effect
exit
```

### 1.2 Install Docker Compose

```bash
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version
```

### 1.3 Create Docker Network

```bash
docker network create shared-network
docker network ls | grep shared-network
```

---

## Phase 2: Oracle Database Deployment

### 2.1 Deploy Oracle 21c XE

```bash
docker run -d \
  --name oracle21c \
  --network shared-network \
  -p 1521:1521 \
  -p 5500:5500 \
  -e ORACLE_PWD=confluent123 \
  container-registry.oracle.com/database/express:21.3.0-xe
```

**Wait for startup (2-3 minutes):**
```bash
docker logs -f oracle21c
# Wait for: "DATABASE IS READY TO USE!"
```

### 2.2 Verify Oracle Connectivity

```bash
docker exec oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba <<EOF
SELECT name, open_mode, cdb FROM v\$database;
EXIT;
EOF
```

**Expected Output:**
```
NAME      OPEN_MODE  CDB
--------- ---------- ---
XE        READ WRITE YES
```

---

## Phase 3: Oracle CDC Configuration

### 3.1 Clone Repository

```bash
cd ~
git clone https://github.com/ManiselvanSE/OracleXstreamonCP.git
cd OracleXstreamonCP/oracle-setup/scripts
chmod +x 00_setup_cdc.sh
```

### 3.2 Execute CDC Setup

```bash
./00_setup_cdc.sh
```

**This script executes:**
1. Enable ARCHIVELOG mode
2. Enable supplemental logging
3. Create application user (ordermgmt)
4. Create schema (CUSTOMERS, ORDERS, ORDER_ITEMS)
5. Load sample data
6. Create XStream admin user (c##xstrmadmin)
7. Grant XStream privileges
8. Create XStream outbound server (XOUT)

### 3.3 Verify CDC Configuration

**Check ARCHIVELOG mode:**
```bash
docker exec oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba <<EOF
SELECT log_mode FROM v\$database;
EXIT;
EOF
```
Expected: `ARCHIVELOG`

**Check supplemental logging:**
```bash
docker exec oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba <<EOF
SELECT supplemental_log_data_min FROM v\$database;
EXIT;
EOF
```
Expected: `YES` or `IMPLICIT`

**Check XStream outbound server:**
```bash
docker exec oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba <<EOF
SELECT server_name, connect_user, capture_user, queue_owner, status 
FROM DBA_XSTREAM_OUTBOUND;
EXIT;
EOF
```
Expected: `XOUT` with `ENABLED` status

**Check capture process:**
```bash
docker exec oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba <<EOF
SELECT capture_name, status, state FROM DBA_CAPTURE;
EXIT;
EOF
```
Expected: `CAP$_XOUT_1` with `ENABLED` status

### 3.4 Verify Sample Data

```bash
docker exec oracle21c sqlplus ordermgmt/kafka@XEPDB1 <<EOF
SELECT 'CUSTOMERS: ' || COUNT(*) FROM CUSTOMERS;
SELECT 'ORDERS: ' || COUNT(*) FROM ORDERS;
SELECT 'ORDER_ITEMS: ' || COUNT(*) FROM ORDER_ITEMS;
EXIT;
EOF
```
Expected: 5 customers, 5 orders, 10 order items

---

## Phase 4: Confluent Platform Deployment

### 4.1 Prerequisites

Before deploying Confluent Platform, ensure you have:

**System Requirements:**
- Docker and Docker Compose running
- Oracle container deployed and healthy
- Shared Docker network created (`shared-network`)
- Minimum 8 GB free disk space for Confluent images

**Network Connectivity:**
- Ports 9092, 8081, 8083, 9021, 9101-9104 available
- Connectivity between Oracle container and Confluent services

**Required JAR Files:**

The Oracle XStream CDC connector requires Oracle client libraries that are not included in the connector package:

1. **ojdbc11.jar** - Oracle JDBC Driver (required)
2. **xstreams.jar** - Oracle XStream API Library (required for XStream mode)

### 4.2 Prepare Confluent Directory

```bash
cd ~/OracleXstreamonCP/confluent-platform
```

### 4.3 Download Oracle JDBC Driver

Download the Oracle JDBC driver (ojdbc11.jar) from Oracle's website:

```bash
# Option 1: Direct download (requires accepting Oracle license)
wget -q https://download.oracle.com/otn-pub/otn_software/jdbc/233/ojdbc11.jar

# Option 2: If wget fails due to license acceptance, download manually from:
# https://www.oracle.com/database/technologies/appdev/jdbc-downloads.html
# Then upload to the confluent-platform directory
```

**Verify download:**
```bash
ls -lh ojdbc11.jar
# Expected: ~6.8 MB
```

### 4.4 Copy Oracle XStream Library

The `xstreams.jar` library is required for XStream API connectivity. This file is included in the Oracle Database installation.

**Copy from Oracle container:**

```bash
# Copy xstreams.jar from Oracle 21c container
docker cp oracle21c:/opt/oracle/product/21c/dbhomeXE/rdbms/jlib/xstreams.jar .

# Verify the file
ls -lh xstreams.jar
# Expected: ~73 KB
```

**Alternative - If using Oracle Instant Client:**

If you have Oracle Instant Client installed locally:

```bash
# Find xstreams.jar in Oracle Instant Client directory
find /opt/oracle/instantclient* -name xstreams.jar

# Copy to confluent-platform directory
cp /opt/oracle/instantclient_21_X/xstreams.jar .
```

**Alternative - Download Oracle Instant Client:**

If Oracle container is not available:

1. Download Oracle Instant Client Basic package from:
   - https://www.oracle.com/database/technologies/instant-client/downloads.html
   
2. Extract and locate xstreams.jar:
   ```bash
   unzip instantclient-basic-linux.x64-21.X.zip
   find instantclient_21_X -name xstreams.jar
   cp instantclient_21_X/xstreams.jar ~/OracleXstreamonCP/confluent-platform/
   ```

### 4.5 Set File Permissions

```bash
# Set directory permissions
sudo chmod 777 $(pwd)

# Set JAR file permissions
sudo chmod 644 ojdbc11.jar xstreams.jar
```

### 4.6 Verify Required Files

```bash
ls -lh *.jar
```

**Expected output:**
```
-rw-r--r-- 1 user user 6.8M ojdbc11.jar
-rw-r--r-- 1 user user  73K xstreams.jar
```

**Required files checklist:**
- ✅ `docker-compose.yml` (from repository)
- ✅ `oracle-xstream-cdc-config.json` (from repository)
- ✅ `ojdbc11.jar` (downloaded from Oracle)
- ✅ `xstreams.jar` (copied from Oracle container/client)

### 4.7 Deploy Confluent Platform

```bash
docker-compose up -d
```

### 4.8 Verify Services

```bash
docker-compose ps
```

**Expected Services (4):**
- `broker` (Kafka in KRaft mode)
- `schema-registry`
- `connect`
- `control-center`

**Wait for all services to be healthy (2-3 minutes):**
```bash
watch -n 5 'docker-compose ps'
```

### 4.9 Verify Kafka Connect Plugins

```bash
curl -s http://localhost:8083/connector-plugins | jq '.[] | select(.class | contains("OracleCdc"))'
```

**Expected:**
```json
{
  "class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
  "type": "source",
  "version": "2.9.2"
}
```

---

## Phase 5: CDC Connector Deployment

### 5.1 Deploy Connector

```bash
cd ~/OracleXstreamonCP/confluent-platform

curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @oracle-xstream-cdc-config.json
```

### 5.2 Verify Connector Status

```bash
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq
```

**Expected:**
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

### 5.3 Check Connector Logs

```bash
docker logs connect | tail -50
```

Look for:
- `XStream connection successful`
- `Started connector oracle-xstream-cdc-source`

---

## Phase 6: Testing & Validation

### 6.1 Verify Kafka Topics Created

```bash
docker exec broker kafka-topics \
  --bootstrap-server broker:29092 \
  --list | grep XEPDB1
```

**Expected Topics:**
```
XEPDB1.ORDERMGMT.CUSTOMERS
XEPDB1.ORDERMGMT.ORDERS
XEPDB1.ORDERMGMT.ORDER_ITEMS
oracle-xstream-cdc-source-XEPDB1-redo-log
```

### 6.2 Test INSERT Operation

```bash
docker exec -i oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
INSERT INTO CUSTOMERS (CUSTOMER_ID, CUSTOMER_NAME, EMAIL, PHONE, ADDRESS, CREATED_AT, UPDATED_AT)
VALUES (100, 'Alice Johnson', 'alice@test.com', '555-0100', '123 Main St', SYSTIMESTAMP, SYSTIMESTAMP);
COMMIT;
EXIT;
EOF
```

**Consume message:**
```bash
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.CUSTOMERS \
  --from-beginning --max-messages 1
```

**Expected Message:**
```json
{
  "CUSTOMER_ID": "...",
  "CUSTOMER_NAME": "Alice Johnson",
  "EMAIL": "alice@test.com",
  "PHONE": "555-0100",
  "ADDRESS": "123 Main St",
  "op_type": "I",
  "scn": "...",
  "table": "XEPDB1.ORDERMGMT.CUSTOMERS"
}
```

### 6.3 Test UPDATE Operation

```bash
docker exec -i oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
UPDATE CUSTOMERS 
SET EMAIL = 'alice.johnson@newdomain.com', UPDATED_AT = SYSTIMESTAMP 
WHERE CUSTOMER_ID = 100;
COMMIT;
EXIT;
EOF
```

**Consume message:**
```bash
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.CUSTOMERS \
  --from-beginning --timeout-ms 5000 2>/dev/null | grep '"op_type":"U"' | tail -1
```

**Expected:** `"op_type": "U"` with updated email

### 6.4 Test DELETE Operation

```bash
docker exec -i oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
DELETE FROM CUSTOMERS WHERE CUSTOMER_ID = 100;
COMMIT;
EXIT;
EOF
```

**Consume message:**
```bash
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.CUSTOMERS \
  --from-beginning --timeout-ms 5000 2>/dev/null | grep '"op_type":"D"' | tail -1
```

**Expected:** `"op_type": "D"` with deleted record data

### 6.5 Test All Tables

**INSERT into ORDERS:**
```bash
docker exec -i oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
INSERT INTO ORDERS (ORDER_ID, CUSTOMER_NAME, ORDER_DATE, TOTAL_AMOUNT, STATUS, CREATED_AT, UPDATED_AT)
VALUES (200, 'Alice Johnson', SYSTIMESTAMP, 599.99, 'PENDING', SYSTIMESTAMP, SYSTIMESTAMP);
COMMIT;
EXIT;
EOF
```

**INSERT into ORDER_ITEMS:**
```bash
docker exec -i oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
INSERT INTO ORDER_ITEMS (ITEM_ID, ORDER_ID, PRODUCT_NAME, QUANTITY, PRICE, CREATED_AT)
VALUES (300, 200, 'Laptop', 1, 599.99, SYSTIMESTAMP);
COMMIT;
EXIT;
EOF
```

**Verify messages in both topics:**
```bash
# ORDERS topic
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.ORDERS \
  --from-beginning --max-messages 1

# ORDER_ITEMS topic
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.ORDER_ITEMS \
  --from-beginning --max-messages 1
```

---

## Phase 7: Monitoring

### 7.1 Control Center

**Access:** http://\<host-ip\>:9021

**Features:**
- Cluster overview
- Topic browser
- Connector management
- Consumer lag monitoring

### 7.2 JMX Monitoring

**Connect with JConsole:**
```bash
# Broker metrics
jconsole <host-ip>:9101

# Schema Registry metrics
jconsole <host-ip>:9102

# Kafka Connect metrics
jconsole <host-ip>:9103

# Control Center metrics
jconsole <host-ip>:9104
```

### 7.3 Connector Metrics

```bash
# Connector status
curl http://localhost:8083/connectors/oracle-xstream-cdc-source/status

# Connector config
curl http://localhost:8083/connectors/oracle-xstream-cdc-source/config

# All connectors
curl http://localhost:8083/connectors
```

### 7.4 XStream Monitoring

```bash
docker exec oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba <<EOF
-- Capture process status
SELECT capture_name, status, state, total_messages_captured 
FROM DBA_CAPTURE;

-- Outbound server status
SELECT server_name, status, connect_user 
FROM DBA_XSTREAM_OUTBOUND;

-- Current SCN
SELECT current_scn FROM v\$database;
EXIT;
EOF
```

---

## Troubleshooting

### Connector Issues

**Connector not starting:**
```bash
# Check logs
docker logs connect | grep -i error

# Restart connector
curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart

# Delete and recreate
curl -X DELETE http://localhost:8083/connectors/oracle-xstream-cdc-source
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @oracle-xstream-cdc-config.json
```

**No messages in Kafka:**
```bash
# Verify connector is RUNNING
curl http://localhost:8083/connectors/oracle-xstream-cdc-source/status

# Check if capture is enabled
docker exec oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba <<EOF
SELECT capture_name, status, state FROM DBA_CAPTURE;
EXIT;
EOF

# Make a new change (connector starts from CURRENT)
docker exec -i oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
INSERT INTO ORDERS (ORDER_ID, CUSTOMER_NAME, ORDER_DATE, TOTAL_AMOUNT, STATUS, CREATED_AT, UPDATED_AT)
VALUES (999, 'Test', SYSTIMESTAMP, 1.00, 'TEST', SYSTIMESTAMP, SYSTIMESTAMP);
COMMIT;
EXIT;
EOF
```

### Oracle Issues

**ARCHIVELOG not enabled:**
```bash
docker exec oracle21c sqlplus sys/confluent123 as sysdba <<EOF
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
EXIT;
EOF
```

**XStream server not created:**
```bash
cd ~/OracleXstreamonCP/oracle-setup/scripts
docker exec -i oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba < 07_create_xstream_outbound.sql
```

### Kafka Issues

**Broker not started:**
```bash
docker logs broker
docker-compose restart broker
```

**Topics not created:**
```bash
# List all topics
docker exec broker kafka-topics --bootstrap-server broker:29092 --list

# Create topic manually (if needed)
docker exec broker kafka-topics \
  --bootstrap-server broker:29092 \
  --create \
  --topic XEPDB1.ORDERMGMT.CUSTOMERS \
  --partitions 1 \
  --replication-factor 1
```

### Service Health Check

```bash
# All containers
docker ps

# Confluent services
cd ~/OracleXstreamonCP/confluent-platform
docker-compose ps

# Service logs
docker logs broker
docker logs schema-registry
docker logs connect
docker logs control-center
docker logs oracle21c
```

---

## Production Considerations

### Security

1. **Change default passwords:**
   - Oracle SYS password
   - Application user passwords
   - XStream admin password

2. **Enable SSL/TLS:**
   - Kafka broker encryption
   - Schema Registry authentication
   - Kafka Connect REST API security

3. **Network security:**
   - Restrict security group rules
   - Use VPC private subnets
   - Enable VPN/bastion access

### High Availability

1. **Multi-broker Kafka cluster:**
   - 3+ brokers for production
   - Replication factor 3
   - Min in-sync replicas 2

2. **Oracle RAC or Data Guard:**
   - Primary-standby configuration
   - Automatic failover

3. **Distributed Kafka Connect:**
   - 3+ Connect workers
   - Distributed mode configuration

### Performance Tuning

1. **Kafka broker:**
   - Increase `num.network.threads`
   - Tune `num.io.threads`
   - Adjust `socket.send.buffer.bytes`

2. **Oracle XStream:**
   - Configure parallelism
   - Tune capture buffer size
   - Optimize redo log size

3. **Connector:**
   - Adjust `batch.size`
   - Tune `max.poll.records`
   - Configure `buffer.memory`

### Backup & Recovery

1. **Oracle backups:**
   - RMAN configuration
   - Automated backup schedule
   - Test restore procedures

2. **Kafka topic backups:**
   - Enable retention policies
   - Configure MirrorMaker for DR
   - Document recovery procedures

---

## Support Resources

- **Oracle XStream Documentation:** https://docs.oracle.com/en/database/oracle/oracle-database/21/xstrm/
- **Confluent CDC Connector:** https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/
- **Kafka Documentation:** https://kafka.apache.org/documentation/
- **GitHub Repository:** https://github.com/ManiselvanSE/OracleXstreamonCP

---

**Last Updated:** July 13, 2026  
**Verified Configuration:** Production-Ready
