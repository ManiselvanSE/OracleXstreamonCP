# Oracle XStream CDC with Confluent Platform - Complete Deployment Guide

**Version:** 2.0 (KRaft Mode + JMX Monitoring)  
**Updated:** July 12, 2026  
**Architecture:** Oracle 21c XE + Confluent Platform 7.6.0 + KRaft (No Zookeeper)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Infrastructure Setup](#infrastructure-setup)
3. [Oracle Database Deployment](#oracle-database-deployment)
4. [Confluent Platform Deployment (KRaft Mode)](#confluent-platform-deployment-kraft-mode)
5. [Oracle CDC Configuration](#oracle-cdc-configuration)
6. [Connector Deployment](#connector-deployment)
7. [Testing & Validation](#testing--validation)
8. [JMX Monitoring Setup](#jmx-monitoring-setup)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements
- **EC2 Instance:** t3.xlarge or larger (4 vCPU, 16 GB RAM minimum)
- **Storage:** 100 GB minimum
- **OS:** Amazon Linux 2023
- **Network:** Security group with required ports open

### Required Ports
```
22    - SSH
1521  - Oracle Database
9092  - Kafka Broker
8081  - Schema Registry
8083  - Kafka Connect
9021  - Control Center
9101-9105 - JMX Ports (for monitoring)
```

### Software Versions
- Docker: Latest
- Docker Compose: 2.24.0+
- Oracle 21c XE: 21.3.0-xe
- Confluent Platform: 7.6.0
- Oracle XStream CDC Connector: 2.9.2

---

## Infrastructure Setup

### Step 1: Connect to EC2

```bash
ssh -i "/path/to/your-key.pem" ec2-user@<EC2-PUBLIC-IP>
```

### Step 2: Install Docker

```bash
# Update system
sudo yum update -y

# Install Docker
sudo yum install -y docker

# Start Docker service
sudo service docker start

# Add ec2-user to docker group
sudo usermod -a -G docker ec2-user

# Enable Docker on boot
sudo chkconfig docker on

# Configure Docker for production
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -w vm.max_map_count=262144

# Update file limits
echo "    *       soft  nofile  65535" | sudo tee -a /etc/security/limits.conf
echo "    *       hard  nofile  65535" | sudo tee -a /etc/security/limits.conf

# Log out and log back in for group changes to take effect
exit
```

### Step 3: Log Back In and Verify Docker

```bash
ssh -i "/path/to/your-key.pem" ec2-user@<EC2-PUBLIC-IP>

# Verify Docker
docker --version
docker ps
```

### Step 4: Install Docker Compose

```bash
# Download Docker Compose
sudo curl -SL https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64 \
  -o /usr/local/bin/docker-compose

# Make executable
sudo chmod +x /usr/local/bin/docker-compose

# Create symlink
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify
docker-compose --version
```

### Step 5: Install Additional Tools

```bash
sudo yum install -y wget unzip jq git nc
```

---

## Oracle Database Deployment

### Step 1: Create Working Directory

```bash
mkdir -p ~/oracle-cdc/oracle-setup/scripts
cd ~/oracle-cdc
```

### Step 2: Download Oracle JDBC Driver

```bash
wget -q https://download.oracle.com/otn-pub/otn_software/jdbc/233/ojdbc11.jar -O ~/oracle-cdc/ojdbc11.jar
```

### Step 3: Create Oracle Setup Scripts

Create the CDC setup scripts:

```bash
# Create main setup script
cat > ~/oracle-cdc/oracle-setup/scripts/00_setup_cdc.sh << 'EOF'
#!/bin/bash
echo "========================================"
echo "Oracle CDC Setup - Starting"
echo "========================================"

export ORACLE_SID=XE

echo "Step 1: Enable archive log and supplemental logging..."
sqlplus /nolog @/opt/oracle/scripts/setup/01_setup_database.sql

echo "Step 2: Create application user (ordermgmt)..."
sqlplus sys/confluent123@XEPDB1 as sysdba @/opt/oracle/scripts/setup/02_create_user.sql

echo "Step 3: Create schema and data model..."
sqlplus ordermgmt/kafka@XEPDB1 @/opt/oracle/scripts/setup/03_create_schema_datamodel.sql

echo "Step 4: Load sample data..."
sqlplus ordermgmt/kafka@XEPDB1 @/opt/oracle/scripts/setup/04_load_data.sql

echo "Step 5: Create XStream CDC user (c##xstrmadmin)..."
sqlplus sys/confluent123@XE as sysdba @/opt/oracle/scripts/setup/05_create_xstream_user.sql

echo "Step 6: Grant XStream privileges in PDB..."
sqlplus sys/confluent123@XEPDB1 as sysdba @/opt/oracle/scripts/setup/06_xstream_privs.sql

echo "Step 7: Create XStream outbound server..."
sqlplus sys/confluent123@XE as sysdba @/opt/oracle/scripts/setup/07_create_xstream_outbound.sql

echo "========================================"
echo "Oracle CDC Setup - Completed Successfully"
echo "========================================"
EOF

chmod +x ~/oracle-cdc/oracle-setup/scripts/00_setup_cdc.sh
```

Create SQL scripts (see full scripts in oracle-setup/scripts directory):

```bash
# Download all setup scripts from repository
cd ~/oracle-cdc/oracle-setup/scripts

# Or copy them manually from the repository
# Scripts: 01_setup_database.sql through 07_create_xstream_outbound.sql
```

### Step 4: Deploy Oracle Container

```bash
# Create Docker network first
docker network create shared-network

# Run Oracle 21c XE container
docker run --name oracle21c \
  -p 1521:1521 -p 5500:5500 \
  -e ORACLE_SID=XE \
  -e ORACLE_PDB=XEPDB1 \
  -e ORACLE_PWD=confluent123 \
  -e ORACLE_MEM=4000 \
  -e ORACLE_CHARACTERSET=AL32UTF8 \
  -e ENABLE_ARCHIVELOG=true \
  -v /opt/oracle/oradata \
  -v ~/oracle-cdc/oracle-setup/scripts:/opt/oracle/scripts/setup \
  --network shared-network \
  -d container-registry.oracle.com/database/express:21.3.0-xe
```

### Step 5: Wait for Oracle to Start

```bash
# Monitor Oracle startup (takes 3-5 minutes)
docker logs -f oracle21c

# Wait for: "DATABASE IS READY TO USE!"
# Press Ctrl+C to stop following logs
```

### Step 6: Run CDC Setup

```bash
# Wait 60 seconds after database is ready
sleep 60

# Execute CDC setup
docker exec oracle21c /bin/bash -c "bash /opt/oracle/scripts/setup/00_setup_cdc.sh"
```

### Step 7: Verify Oracle Setup

```bash
# Connect to Oracle
docker exec -it oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba

# Check ARCHIVELOG mode
SELECT LOG_MODE FROM V$DATABASE;
-- Expected: ARCHIVELOG

# Check supplemental logging
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_ALL FROM V$DATABASE;
-- Expected: YES, YES

# Check XStream outbound server
SELECT SERVER_NAME, CAPTURE_NAME, STATUS FROM DBA_XSTREAM_OUTBOUND;
-- Expected: XOUT, CAPTURE_XOUT, ENABLED

# Check capture process
SELECT CAPTURE_NAME, STATUS, STATE FROM DBA_CAPTURE;
-- Expected: CAPTURE_XOUT, ENABLED, CAPTURING CHANGES

# Check data
SELECT COUNT(*) FROM ordermgmt.ORDERS;
SELECT COUNT(*) FROM ordermgmt.ORDER_ITEMS;
SELECT COUNT(*) FROM ordermgmt.CUSTOMERS;

EXIT;
```

---

## Confluent Platform Deployment (KRaft Mode)

### Step 1: Create Confluent Platform Directory

```bash
mkdir -p ~/oracle-cdc/confluent-platform/connectors
cd ~/oracle-cdc/confluent-platform
```

### Step 2: Copy JDBC Driver

```bash
cp ~/oracle-cdc/ojdbc11.jar ~/oracle-cdc/confluent-platform/ojdbc11.jar
```

### Step 3: Set Directory Permissions

```bash
sudo chmod 777 ~/oracle-cdc/confluent-platform/connectors
```

### Step 4: Create docker-compose.yml

```bash
cat > ~/oracle-cdc/confluent-platform/docker-compose.yml << 'EOF'
version: "3.3"

services:
  broker:
    image: confluentinc/cp-kafka:7.6.0
    hostname: broker
    container_name: broker
    ports:
      - "9092:9092"
      - "9101:9101"
    networks:
      - shared-network
    environment:
      # KRaft settings (no Zookeeper)
      KAFKA_NODE_ID: 1
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: 'CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT'
      KAFKA_ADVERTISED_LISTENERS: 'PLAINTEXT://broker:29092,PLAINTEXT_HOST://localhost:9092'
      KAFKA_PROCESS_ROLES: 'broker,controller'
      KAFKA_CONTROLLER_QUORUM_VOTERS: '1@broker:29093'
      KAFKA_LISTENERS: 'PLAINTEXT://broker:29092,CONTROLLER://broker:29093,PLAINTEXT_HOST://0.0.0.0:9092'
      KAFKA_INTER_BROKER_LISTENER_NAME: 'PLAINTEXT'
      KAFKA_CONTROLLER_LISTENER_NAMES: 'CONTROLLER'
      KAFKA_LOG_DIRS: '/tmp/kraft-combined-logs'
      CLUSTER_ID: 'MkU3OEVBNTcwNTJENDM2Qk'

      # Broker settings
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: 'true'
      KAFKA_DEFAULT_REPLICATION_FACTOR: 1

      # JMX settings for monitoring
      KAFKA_JMX_PORT: 9101
      KAFKA_JMX_HOSTNAME: broker
      KAFKA_JMX_OPTS: "-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=broker -Dcom.sun.management.jmxremote.rmi.port=9101"
    command: >
      bash -c "
      mkdir -p /tmp/kraft-combined-logs &&
      kafka-storage format -t $$CLUSTER_ID -c /etc/kafka/kafka.properties &&
      /etc/confluent/docker/run
      "

  schema-registry:
    image: confluentinc/cp-schema-registry:7.6.0
    hostname: schema-registry
    container_name: schema-registry
    depends_on:
      - broker
    ports:
      - "8081:8081"
      - "9102:9102"
    networks:
      - shared-network
    environment:
      SCHEMA_REGISTRY_HOST_NAME: schema-registry
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: 'broker:29092'
      SCHEMA_REGISTRY_LISTENERS: http://0.0.0.0:8081
      SCHEMA_REGISTRY_JMX_PORT: 9102
      SCHEMA_REGISTRY_JMX_HOSTNAME: schema-registry
      SCHEMA_REGISTRY_JMX_OPTS: "-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=schema-registry -Dcom.sun.management.jmxremote.rmi.port=9102"

  connect:
    image: confluentinc/cp-kafka-connect:7.6.0
    hostname: connect
    container_name: connect
    depends_on:
      - broker
      - schema-registry
    ports:
      - "8083:8083"
      - "9103:9103"
    networks:
      - shared-network
    volumes:
      - ./connectors:/usr/share/confluent-hub-components
      - ./ojdbc11.jar:/usr/share/java/kafka-connect-jdbc/ojdbc11.jar
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
      KAFKA_JMX_PORT: 9103
      KAFKA_JMX_HOSTNAME: connect
      KAFKA_JMX_OPTS: "-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=connect -Dcom.sun.management.jmxremote.rmi.port=9103"
    command: >
      bash -c "
      echo 'Installing Oracle XStream CDC Connector...' &&
      confluent-hub install --no-prompt confluentinc/kafka-connect-oracle-cdc:2.9.2 &&
      echo 'Connector installed successfully' &&
      /etc/confluent/docker/run
      "

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
      - "9104:9104"
    networks:
      - shared-network
    environment:
      CONTROL_CENTER_BOOTSTRAP_SERVERS: 'broker:29092'
      CONTROL_CENTER_CONNECT_CONNECT-DEFAULT_CLUSTER: 'connect:8083'
      CONTROL_CENTER_SCHEMA_REGISTRY_URL: "http://schema-registry:8081"
      CONTROL_CENTER_REPLICATION_FACTOR: 1
      CONTROL_CENTER_INTERNAL_TOPICS_PARTITIONS: 1
      CONTROL_CENTER_MONITORING_INTERCEPTOR_TOPIC_PARTITIONS: 1
      CONFLUENT_METRICS_TOPIC_REPLICATION: 1
      PORT: 9021
      CONTROL_CENTER_JMX_PORT: 9104
      CONTROL_CENTER_JMX_HOSTNAME: control-center
      CONTROL_CENTER_JMX_OPTS: "-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Djava.rmi.server.hostname=control-center -Dcom.sun.management.jmxremote.rmi.port=9104"

networks:
  shared-network:
    external: true
EOF
```

### Step 5: Start Confluent Platform

```bash
cd ~/oracle-cdc/confluent-platform
docker-compose up -d
```

### Step 6: Monitor Startup

```bash
# Watch logs
docker-compose logs -f

# Wait for all services to be ready (2-3 minutes)
# Press Ctrl+C when ready

# Check container status
docker ps

# Verify all containers are healthy:
# - broker
# - schema-registry
# - connect
# - control-center
```

### Step 7: Verify Kafka (KRaft Mode)

```bash
# Check broker is running in KRaft mode
docker exec broker kafka-metadata-shell --snapshot /tmp/kraft-combined-logs/__cluster_metadata-0/00000000000000000000.log --print > /tmp/kafka-metadata.txt

# List topics
docker exec broker kafka-topics --bootstrap-server broker:29092 --list

# Verify connector plugin installed
curl -s http://localhost:8083/connector-plugins | jq '.[].class' | grep -i oracle
# Expected: "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector"
```

---

## Oracle CDC Configuration

### Step 1: Create Connector Configuration

```bash
cat > ~/oracle-cdc/confluent-platform/oracle-xstream-cdc-config.json << 'EOF'
{
  "name": "oracle-xstream-cdc-source",
  "config": {
    "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
    "tasks.max": "1",
    "oracle.server": "oracle21c",
    "oracle.port": "1521",
    "oracle.sid": "XE",
    "oracle.pdb.name": "XEPDB1",
    "oracle.username": "c##xstrmadmin",
    "oracle.password": "xstrmadmin123",
    "xstream.server.name": "xout",
    "start.from": "CURRENT",
    "snapshot.mode": "schema_only",
    "table.inclusion.regex": ".*ORDERS.*|.*ORDER_ITEMS.*|.*CUSTOMERS.*",
    "confluent.topic.bootstrap.servers": "broker:29092",
    "confluent.topic.replication.factor": "1",
    "redo.log.consumer.bootstrap.servers": "broker:29092",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter.schemas.enable": "false"
  }
}
EOF
```

---

## Connector Deployment

### Step 1: Deploy Connector

```bash
cd ~/oracle-cdc/confluent-platform

curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @oracle-xstream-cdc-config.json
```

### Step 2: Verify Connector Status

```bash
# Check connector status
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq

# Expected output:
# {
#   "name": "oracle-xstream-cdc-source",
#   "connector": {
#     "state": "RUNNING",
#     "worker_id": "connect:8083"
#   },
#   "tasks": [
#     {
#       "id": 0,
#       "state": "RUNNING",
#       "worker_id": "connect:8083"
#     }
#   ]
# }
```

### Step 3: Verify Topics Created

```bash
# List topics
docker exec broker kafka-topics --bootstrap-server broker:29092 --list

# Expected topics:
# XEPDB1.ORDERMGMT.CUSTOMERS
# XEPDB1.ORDERMGMT.ORDERS
# XEPDB1.ORDERMGMT.ORDER_ITEMS
```

---

## Testing & Validation

### Step 1: Start Consumer in One Terminal

```bash
# Terminal 1: Consume ORDERS topic
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.ORDERS \
  --property print.key=true \
  --property print.timestamp=true
```

### Step 2: Test INSERT in Another Terminal

```bash
# Terminal 2: Insert new order
docker exec oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
INSERT INTO ORDERS VALUES (100, 'Test Customer CDC', SYSTIMESTAMP, 9999.99, 'PENDING', SYSTIMESTAMP, SYSTIMESTAMP);
COMMIT;
EXIT;
EOF

# Check Terminal 1 - you should see the INSERT event immediately
```

### Step 3: Test UPDATE

```bash
# Terminal 2: Update order
docker exec oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
UPDATE ORDERS SET STATUS = 'SHIPPED', TOTAL_AMOUNT = 1234.56 WHERE ORDER_ID = 100;
COMMIT;
EXIT;
EOF

# Check Terminal 1 - you should see UPDATE event with before/after values
```

### Step 4: Test DELETE

```bash
# Terminal 2: Delete order
docker exec oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
DELETE FROM ORDERS WHERE ORDER_ID = 100;
COMMIT;
EXIT;
EOF

# Check Terminal 1 - you should see DELETE event (tombstone)
```

---

## JMX Monitoring Setup

### JMX Ports Overview

All services expose JMX metrics on the following ports:

| Service | JMX Port |
|---------|----------|
| Kafka Broker | 9101 |
| Schema Registry | 9102 |
| Kafka Connect | 9103 |
| Control Center | 9104 |

### Option 1: Using jconsole (Local)

```bash
# From your local machine
jconsole <EC2-PUBLIC-IP>:9101
```

### Option 2: Using Prometheus + Grafana

```bash
# Create prometheus.yml
cat > ~/oracle-cdc/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'kafka-broker'
    static_configs:
      - targets: ['localhost:9101']

  - job_name: 'schema-registry'
    static_configs:
      - targets: ['localhost:9102']

  - job_name: 'kafka-connect'
    static_configs:
      - targets: ['localhost:9103']

  - job_name: 'control-center'
    static_configs:
      - targets: ['localhost:9104']
EOF

# Run Prometheus with JMX Exporter
docker run -d --name prometheus \
  -p 9090:9090 \
  -v ~/oracle-cdc/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus
```

### Option 3: Using JMX CLI Tools

```bash
# Install jmxterm
wget https://github.com/jiaqi/jmxterm/releases/download/v1.0.4/jmxterm-1.0.4-uber.jar -O jmxterm.jar

# Connect to broker
java -jar jmxterm.jar -l localhost:9101

# Example commands in jmxterm:
# domains
# beans
# info -b kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec
# get -b kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec Count
```

### Key JMX Metrics to Monitor

**Kafka Broker:**
- `kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec` - Incoming message rate
- `kafka.server:type=BrokerTopicMetrics,name=BytesInPerSec` - Incoming bytes rate
- `kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions` - Under-replicated partitions
- `kafka.network:type=RequestMetrics,name=RequestsPerSec,request=Produce` - Producer requests

**Kafka Connect:**
- `kafka.connect:type=connector-metrics,connector=oracle-xstream-cdc-source` - Connector metrics
- `kafka.connect:type=connector-task-metrics,connector=oracle-xstream-cdc-source,task=0` - Task metrics
- `kafka.connect:type=source-task-metrics,connector=oracle-xstream-cdc-source,task=0` - Source task metrics

---

## Troubleshooting

### Issue: Connector Not Running

```bash
# Check connector status
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq

# Get error details
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '.tasks[0].trace'

# Restart connector
curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart
```

### Issue: No Messages in Kafka

```bash
# 1. Verify XStream is capturing
docker exec oracle21c sqlplus -s sys/confluent123@XEPDB1 as sysdba <<EOF
SELECT CAPTURE_NAME, STATUS, STATE FROM DBA_CAPTURE;
EXIT;
EOF

# 2. Make a new change (connector starts from CURRENT)
docker exec oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
INSERT INTO ORDERS VALUES (999, 'Test', SYSTIMESTAMP, 1.00, 'TEST', SYSTIMESTAMP, SYSTIMESTAMP);
COMMIT;
EXIT;
EOF

# 3. Check connector logs
docker logs connect 2>&1 | grep -i oracle | tail -50
```

### Issue: Kafka Not Starting (KRaft Issues)

```bash
# Check if cluster ID is formatted
docker logs broker 2>&1 | grep -i "kafka-storage"

# Restart broker
docker-compose restart broker

# If needed, recreate with fresh storage
docker-compose down
docker volume prune -f
docker-compose up -d
```

### Issue: JMX Connection Refused

```bash
# Verify JMX port is exposed
docker port broker 9101

# Check JMX is listening
docker exec broker netstat -tuln | grep 9101

# Ensure security group allows JMX ports
# AWS Console > Security Groups > Inbound Rules > Add 9101-9105
```

---

## Quick Commands Reference

```bash
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# View logs
docker-compose logs -f

# Restart connector
curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart

# Check connector status
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq

# List topics
docker exec broker kafka-topics --bootstrap-server broker:29092 --list

# Consume topic
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.ORDERS \
  --property print.key=true

# Check Oracle capture
docker exec oracle21c sqlplus -s sys/confluent123@XEPDB1 as sysdba <<EOF
SELECT CAPTURE_NAME, STATUS, STATE FROM DBA_CAPTURE;
EXIT;
EOF
```

---

## Access URLs

```bash
# Get EC2 public IP
curl http://169.254.169.254/latest/meta-data/public-ipv4

# Access URLs:
# Control Center:     http://<EC2-IP>:9021
# Connect REST API:   http://<EC2-IP>:8083
# Schema Registry:    http://<EC2-IP>:8081
# Kafka Broker:       <EC2-IP>:9092
# JMX Broker:         <EC2-IP>:9101
# JMX Connect:        <EC2-IP>:9103
```

---

## What's New in Version 2.0

### KRaft Mode (No Zookeeper)
- ✅ Kafka runs in KRaft mode (no Zookeeper dependency)
- ✅ Simpler architecture
- ✅ Faster startup
- ✅ Better scalability

### JMX Monitoring
- ✅ All services expose JMX metrics
- ✅ Ports: 9101 (broker), 9102 (schema-registry), 9103 (connect), 9104 (control-center)
- ✅ Ready for Prometheus/Grafana integration
- ✅ Production-ready monitoring

### Streamlined Deployment
- ✅ Docker Compose 2.24.0+ support
- ✅ Automated Oracle setup scripts
- ✅ One-command deployment
- ✅ Copy-paste ready commands

---

## Support & Resources

- **Oracle XStream:** https://docs.oracle.com/en/database/oracle/oracle-database/21/xstrm/
- **Confluent Oracle CDC:** https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/
- **Kafka KRaft:** https://kafka.apache.org/documentation/#kraft
- **Kafka JMX Metrics:** https://kafka.apache.org/documentation/#monitoring

---

**Created:** July 12, 2026  
**Architecture:** Oracle 21c XE + Confluent Platform 7.6.0 + KRaft Mode  
**Purpose:** Production-ready CDC pipeline with monitoring  
