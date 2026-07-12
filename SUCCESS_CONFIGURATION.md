# Oracle XStream CDC - SUCCESS Configuration for Oracle XE 21c

## ✅ WORKING SETUP CONFIRMED

**Date**: July 12, 2026  
**Environment**: Oracle Database 21c Express Edition + Confluent Platform 7.6.0  
**Status**: ✅ **FULLY OPERATIONAL**

---

## 🎉 What's Working

### Topics Created
- `XEPDB1.ORDERMGMT.ORDERS` - 3 messages
- `XEPDB1.ORDERMGMT.ORDER_ITEMS` - 3 messages

### Operations Captured
- ✅ **INSERT**: Captured with `"op_type":"I"`
- ✅ **UPDATE**: Captured with `"op_type":"U"`  
- ✅ **DELETE**: Captured with `"op_type":"D"`

### Pipeline Status
- Connector State: **RUNNING**
- Task State: **RUNNING**
- XStream Server: **xout** (ENABLED)
- Capture Process: **CAP$_XOUT_7** (mining redo logs)

---

## 🔑 Key Success Factors

### Critical Configuration Changes

1. **XStream Schema Rules** (CRITICAL - This was the breakthrough!)
```sql
-- Must be run from CDB$ROOT as sysdba
DECLARE
  v_capture_name VARCHAR2(30);
  v_queue_name VARCHAR2(61);
BEGIN
  SELECT CAPTURE_NAME, QUEUE_NAME 
  INTO v_capture_name, v_queue_name
  FROM DBA_XSTREAM_OUTBOUND
  WHERE SERVER_NAME = 'XOUT';
  
  -- Add schema rule for ORDERMGMT in XEPDB1
  DBMS_STREAMS_ADM.ADD_SCHEMA_RULES(
    schema_name     => 'ORDERMGMT',
    streams_type    => 'capture',
    streams_name    => v_capture_name,
    queue_name      => v_queue_name,
    include_dml     => TRUE,
    include_ddl     => FALSE,
    include_tagged_lcr => FALSE,
    source_database => 'XEPDB1'
  );
END;
/
```

2. **Connector Configuration** (Working version)
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
    "oracle.username": "c##xstrmadmin",
    "oracle.password": "xstrmadmin123",
    
    "xstream.server.name": "xout",
    
    "start.from": "CURRENT",
    "snapshot.mode": "schema_only",
    
    "table.inclusion.regex": ".*ORDERS.*|.*ORDER_ITEMS.*",
    
    "confluent.topic.bootstrap.servers": "broker:29092",
    "confluent.topic.replication.factor": "1",
    
    "redo.log.consumer.bootstrap.servers": "broker:29092",
    
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter.schemas.enable": "false"
  }
}
```

3. **Table Access Grants** (Required)
```sql
-- Connect to PDB as sysdba
ALTER SESSION SET CONTAINER = XEPDB1;

GRANT SELECT ON ORDERMGMT.ORDERS TO c##xstrmadmin;
GRANT SELECT ON ORDERMGMT.ORDER_ITEMS TO c##xstrmadmin;
```

---

## 📋 Complete Step-by-Step Setup (Verified Working)

### Phase 1: Oracle Database Prerequisites

**1.1 Verify ARCHIVELOG Mode**
```bash
docker exec oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba
```
```sql
SELECT LOG_MODE FROM V$DATABASE;
-- Should show: ARCHIVELOG
EXIT;
```

**1.2 Verify Supplemental Logging**
```sql
-- As sysdba in XEPDB1
SELECT SUPPLEMENTAL_LOG_DATA_MIN FROM V$DATABASE;
-- Should show: YES or IMPLICIT
```

---

### Phase 2: Create XStream Infrastructure

**2.1 Create Common User (from CDB root)**
```bash
docker exec oracle21c sqlplus sys/confluent123@XE as sysdba
```
```sql
-- Create common user
CREATE USER c##xstrmadmin IDENTIFIED BY xstrmadmin123 CONTAINER=ALL;

-- Grant privileges
GRANT CREATE SESSION TO c##xstrmadmin CONTAINER=ALL;
GRANT SET CONTAINER TO c##xstrmadmin CONTAINER=ALL;
GRANT SELECT ANY TRANSACTION TO c##xstrmadmin CONTAINER=ALL;
GRANT LOGMINING TO c##xstrmadmin CONTAINER=ALL;
GRANT LOCK ANY TABLE TO c##xstrmadmin CONTAINER=ALL;
GRANT SELECT ANY TABLE TO c##xstrmadmin CONTAINER=ALL;
GRANT EXECUTE_CATALOG_ROLE TO c##xstrmadmin CONTAINER=ALL;
GRANT SELECT ANY DICTIONARY TO c##xstrmadmin CONTAINER=ALL;

-- Grant XStream CAPTURE privilege
BEGIN
   DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
      grantee => 'c##xstrmadmin',
      privilege_type => 'CAPTURE',
      grant_select_privileges => TRUE,
      container => 'ALL'
   );
END;
/
```

**2.2 Create XStream Outbound Server**
```sql
-- Still as sysdba in CDB root (XE)
BEGIN
  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(server_name => 'xout');
END;
/

-- Configure connect user
BEGIN
  DBMS_XSTREAM_ADM.ALTER_OUTBOUND(
    server_name => 'xout',
    connect_user => 'c##xstrmadmin'
  );
END;
/

-- Verify
SELECT SERVER_NAME, CAPTURE_NAME, QUEUE_NAME, CONNECT_USER
FROM DBA_XSTREAM_OUTBOUND;
```

**2.3 Add Schema Rules (CRITICAL STEP)**
```sql
-- Add schema-level capture rule for ORDERMGMT in XEPDB1
DECLARE
  v_capture_name VARCHAR2(30);
  v_queue_name VARCHAR2(61);
BEGIN
  SELECT CAPTURE_NAME, QUEUE_NAME 
  INTO v_capture_name, v_queue_name
  FROM DBA_XSTREAM_OUTBOUND
  WHERE SERVER_NAME = 'XOUT';
  
  DBMS_STREAMS_ADM.ADD_SCHEMA_RULES(
    schema_name     => 'ORDERMGMT',
    streams_type    => 'capture',
    streams_name    => v_capture_name,
    queue_name      => v_queue_name,
    include_dml     => TRUE,
    include_ddl     => FALSE,
    include_tagged_lcr => FALSE,
    source_database => 'XEPDB1'
  );
END;
/

-- Verify rules were added
SELECT STREAMS_TYPE, STREAMS_NAME, SCHEMA_NAME, SOURCE_DATABASE
FROM DBA_STREAMS_SCHEMA_RULES
WHERE STREAMS_NAME LIKE 'CAP$%';

EXIT;
```

**2.4 Grant Table Access in PDB**
```bash
docker exec oracle21c sqlplus sys/confluent123@XE as sysdba
```
```sql
ALTER SESSION SET CONTAINER = XEPDB1;

GRANT SELECT ON ORDERMGMT.ORDERS TO c##xstrmadmin;
GRANT SELECT ON ORDERMGMT.ORDER_ITEMS TO c##xstrmadmin;

EXIT;
```

---

### Phase 3: Deploy Confluent Platform

**3.1 Create Project Structure**
```bash
cd ~
mkdir -p confluent-oracle-cdc/jdbc-drivers
mkdir -p confluent-oracle-cdc/connectors
sudo chmod 777 confluent-oracle-cdc/connectors
```

**3.2 Download Oracle JDBC Driver**
```bash
cd confluent-oracle-cdc/jdbc-drivers
wget https://download.oracle.com/otn-pub/otn_software/jdbc/218/ojdbc8.jar
cd ..
```

**3.3 Create docker-compose.yml**
```yaml
version: "3.3"

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
      - ./connectors:/usr/share/confluent-hub-components
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

**3.4 Start Services**
```bash
# Ensure shared network exists
docker network create shared-network 2>/dev/null || true
docker network connect shared-network oracle21c 2>/dev/null || true

# Start Confluent Platform
docker-compose up -d

# Wait for services
sleep 120

# Verify
docker-compose ps
curl http://localhost:8083/
```

---

### Phase 4: Deploy Oracle XStream CDC Connector

**4.1 Create Connector Configuration**
```bash
cd ~/confluent-oracle-cdc

cat > oracle-xstream-cdc-config.json << 'EOF'
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
    
    "table.inclusion.regex": ".*ORDERS.*|.*ORDER_ITEMS.*",
    
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

**4.2 Deploy Connector**
```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @oracle-xstream-cdc-config.json

# Wait and verify
sleep 15
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '.'
```

---

### Phase 5: Test CDC Pipeline

**5.1 Insert Test Data**
```bash
docker exec oracle21c sqlplus ordermgmt/kafka@XEPDB1
```
```sql
INSERT INTO ORDERS (ORDER_ID, CUSTOMER_ID, STATUS, SALESMAN_ID, ORDER_DATE)
VALUES (9001, 1, 'PENDING', 54, SYSDATE);

INSERT INTO ORDER_ITEMS (ORDER_ID, ITEM_ID, PRODUCT_ID, QUANTITY, UNIT_PRICE)
VALUES (9001, 90001, 1, 5, 29.99);

COMMIT;
EXIT;
```

**5.2 Verify Topics Created**
```bash
# Wait 10 seconds
sleep 10

# Check topics
docker exec broker kafka-topics --bootstrap-server broker:29092 --list | grep ORDERMGMT
```

**Expected Output:**
```
XEPDB1.ORDERMGMT.ORDERS
XEPDB1.ORDERMGMT.ORDER_ITEMS
```

**5.3 Consume Messages**
```bash
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.ORDERS \
  --from-beginning \
  --max-messages 5
```

**5.4 Test UPDATE**
```sql
UPDATE ORDERS SET STATUS = 'SHIPPED' WHERE ORDER_ID = 9001;
COMMIT;
```

**5.5 Test DELETE**
```sql
DELETE FROM ORDER_ITEMS WHERE ITEM_ID = 90001;
COMMIT;
```

---

## 📊 Message Format

### INSERT Message
```json
{
  "ORDER_ID": "Iyk=",
  "CUSTOMER_ID": "AQ==",
  "STATUS": "PENDING",
  "SALESMAN_ID": "Ng==",
  "ORDER_DATE": 20646,
  "table": "XEPDB1.ORDERMGMT.ORDERS",
  "scn": "10053885",
  "op_type": "I",
  "op_ts": "1783870610000",
  "current_ts": "1783870612292",
  "row_id": "AAAShFAAMAAAAEVAAA",
  "username": "ORDERMGMT"
}
```

### UPDATE Message
```json
{
  "ORDER_ID": "Iyk=",
  "STATUS": "SHIPPED",
  "op_type": "U",
  "scn": "10054660",
  "table": "XEPDB1.ORDERMGMT.ORDERS"
}
```

### DELETE Message
```json
{
  "ITEM_ID": "AV+S",
  "op_type": "D",
  "scn": "10054671",
  "table": "XEPDB1.ORDERMGMT.ORDER_ITEMS"
}
```

**Note**: NUMBER columns are Base64 encoded. To decode:
- Oracle NUMBER values are serialized as Base64
- Use Avro converter for proper type handling in production

---

## 🔧 Troubleshooting

### Issue: "Table inclusion pattern matches no tables"

**Solution**: Add XStream schema rules (Phase 2.3 above)

### Issue: Connector fails to connect

**Check**:
1. XStream server exists: `SELECT * FROM DBA_XSTREAM_OUTBOUND;`
2. Capture is running: `SELECT * FROM DBA_CAPTURE;`
3. Network connectivity: `docker exec connect ping oracle21c`

### Issue: No messages appear in Kafka

**Check**:
1. Connector status: `curl http://localhost:8083/connectors/oracle-xstream-cdc-source/status`
2. Insert new data (connector starts from CURRENT SCN)
3. Check Connect logs: `docker logs connect | grep oracle`

---

## ✅ Success Verification Checklist

- [ ] Docker Compose version is 3.3 (not 3.8)
- [ ] Connectors directory has 777 permissions
- [ ] ARCHIVELOG mode enabled
- [ ] Supplemental logging enabled
- [ ] Common user c##xstrmadmin created with XStream privilege
- [ ] XStream outbound server 'xout' created
- [ ] Schema rules added for ORDERMGMT in XEPDB1
- [ ] Table SELECT grants given to c##xstrmadmin
- [ ] Confluent Platform all services running
- [ ] Oracle CDC connector plugin installed
- [ ] Connector deployed with status RUNNING
- [ ] Topics created with pattern XEPDB1.ORDERMGMT.*
- [ ] INSERT messages captured
- [ ] UPDATE messages captured
- [ ] DELETE messages captured

---

## 🎯 Key Learnings

1. **XStream Schema Rules are Mandatory**: The connector cannot automatically discover tables without explicit schema rules in multitenant Oracle

2. **snapshot.mode: "schema_only"** works better than full snapshots for Oracle XE to avoid system table conflicts

3. **Permissive Regex Pattern** (`.*ORDERS.*`) works better than exact patterns for table matching

4. **Docker Compose Version**: Use 3.3 for compatibility with older docker-compose versions

5. **Directory Permissions**: Connector installation directory needs write permissions

6. **Required Parameters**: `confluent.topic.bootstrap.servers` is mandatory (not in some documentation)

---

## 📚 Additional Resources

- **Working Configuration Files**: All files in ~/confluent-oracle-cdc/
- **Connector Documentation**: https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/
- **XStream Documentation**: https://docs.oracle.com/en/database/oracle/oracle-database/21/xstrm/
- **Control Center**: http://<EC2-IP>:9021

---

**Document Version**: 1.0  
**Status**: ✅ VERIFIED WORKING  
**Last Tested**: July 12, 2026  
**Environment**: Oracle 21c XE + Confluent Platform 7.6.0
