# Oracle XStream CDC with Confluent Platform

Real-time Change Data Capture from Oracle Database to Apache Kafka using XStream API.

**Stack:** Oracle 21c XE + Confluent Platform 7.6.0 (KRaft Mode) + Oracle XStream CDC Connector

---

## Prerequisites

**System Requirements:**
- 4 vCPU, 16 GB RAM minimum
- **100 GB disk space** (Oracle 21c XE image is ~10 GB)
- Docker & Docker Compose

**Verified On:**
- AWS EC2 t3.xlarge (Amazon Linux 2023)
- Oracle Database 21c Express Edition
- Confluent Platform 7.6.0
- Oracle XStream CDC Source Connector 2.9.2

---

## Quick Start

```bash
# 1. Clone repository
git clone https://github.com/ManiselvanSE/OracleXstreamonCP.git
cd OracleXstreamonCP

# 2. Deploy Oracle Database
docker network create shared-network
docker run -d --name oracle21c \
  --network shared-network \
  -p 1521:1521 -p 5500:5500 \
  -e ORACLE_PWD=confluent123 \
  container-registry.oracle.com/database/express:21.3.0-xe

# Wait for Oracle to start (2-3 minutes)
docker logs -f oracle21c

# 3. Configure Oracle for CDC
cd oracle-setup/scripts
chmod +x 00_setup_cdc.sh
./00_setup_cdc.sh

# 4. Deploy Confluent Platform
cd ../../confluent-platform
wget -q https://download.oracle.com/otn-pub/otn_software/jdbc/233/ojdbc11.jar
docker cp oracle21c:/opt/oracle/product/21c/dbhomeXE/rdbms/jlib/xstreams.jar .
sudo chmod 777 $(pwd) && sudo chmod 644 *.jar
docker-compose up -d

# Wait for services to start (2-3 minutes)
docker-compose ps

# 5. Deploy CDC Connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @oracle-xstream-cdc-config.json

# 6. Verify connector status
curl http://localhost:8083/connectors/oracle-xstream-cdc-source/status

# 7. Test CDC pipeline
docker exec -i oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
INSERT INTO ORDERS (ORDER_ID, CUSTOMER_NAME, ORDER_DATE, TOTAL_AMOUNT, STATUS, CREATED_AT, UPDATED_AT)
VALUES (999, 'Test Customer', SYSTIMESTAMP, 100.00, 'PENDING', SYSTIMESTAMP, SYSTIMESTAMP);
COMMIT;
EXIT;
EOF

# 8. Consume message from Kafka
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.ORDERS \
  --from-beginning --max-messages 1
```

---

## Architecture

```
Oracle 21c XE (XEPDB1)
  ↓ XStream API
Kafka Connect (CDC Connector)
  ↓
Kafka Broker (KRaft Mode)
  ↓
Schema Registry
  ↓
Kafka Topics: XEPDB1.ORDERMGMT.*
```

**Services:**
- **Oracle Database:** Port 1521
- **Kafka Broker:** Port 9092
- **Schema Registry:** Port 8081
- **Kafka Connect:** Port 8083
- **Control Center:** Port 9021
- **JMX Monitoring:** Ports 9101-9104

---

## Repository Structure

```
OracleXstreamonCP/
├── README.md
├── DEPLOYMENT_GUIDE.md
├── confluent-platform/
│   ├── docker-compose.yml
│   └── oracle-xstream-cdc-config.json
└── oracle-setup/
    └── scripts/
        ├── 00_setup_cdc.sh
        ├── 01_setup_database.sql
        ├── 02_create_user.sql
        ├── 03_create_schema_datamodel.sql
        ├── 04_load_data.sql
        ├── 05_create_xstream_user.sql
        ├── 06_xstream_privs.sql
        └── 07_create_xstream_outbound.sql
```

---

## CDC Features

- **Real-time capture** of INSERT, UPDATE, DELETE operations
- **Sub-second latency** from database to Kafka
- **Exactly-once delivery** guarantees
- **Before/after values** for UPDATE operations
- **Automatic topic creation** per table
- **Schema evolution** via Schema Registry

---

## Testing

```bash
# Insert test record
docker exec -i oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
INSERT INTO CUSTOMERS (CUSTOMER_ID, CUSTOMER_NAME, EMAIL, PHONE, ADDRESS, CREATED_AT, UPDATED_AT)
VALUES (100, 'Alice Johnson', 'alice@test.com', '555-0100', '123 Main St', SYSTIMESTAMP, SYSTIMESTAMP);
COMMIT;
EXIT;
EOF

# Verify in Kafka
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.CUSTOMERS \
  --from-beginning --max-messages 1
```

---

## Monitoring

**JMX Metrics:**
- Broker: `jconsole <host>:9101`
- Schema Registry: `jconsole <host>:9102`
- Kafka Connect: `jconsole <host>:9103`
- Control Center: `jconsole <host>:9104`

**Control Center UI:**
- http://localhost:9021

**Connector Status:**
```bash
curl http://localhost:8083/connectors/oracle-xstream-cdc-source/status
```

---

## Troubleshooting

**Connector not running:**
```bash
curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart
```

**Check logs:**
```bash
docker logs broker
docker logs connect
docker logs oracle21c
```

**Verify XStream capture:**
```bash
docker exec oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba <<EOF
SELECT CAPTURE_NAME, STATUS, STATE FROM DBA_CAPTURE;
EXIT;
EOF
```

---

## Documentation

- **DEPLOYMENT_GUIDE.md** - Complete step-by-step deployment instructions
- **Oracle XStream:** https://docs.oracle.com/en/database/oracle/oracle-database/21/xstrm/
- **Confluent CDC Connector:** https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/

---

**Status:** Production-Ready  
**Last Verified:** July 13, 2026  
**License:** See Oracle and Confluent licensing requirements
