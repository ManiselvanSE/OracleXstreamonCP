# Oracle XStream CDC with Confluent Platform - Version 2.0

## Complete Documentation Package with JMX Monitoring

**Version:** 2.0 (Stable with JMX Monitoring)  
**Date:** July 12, 2026  
**Stack:** Oracle 21c XE + Confluent Platform 7.6.0 + JMX Monitoring

---

## What's New in Version 2.0

### 1. JMX Monitoring Support ✅
- All Confluent services expose JMX metrics
- Ports: 9100 (Zookeeper), 9101 (Broker), 9102 (Schema Registry), 9103 (Connect), 9104 (Control Center)
- Ready for Prometheus/Grafana integration
- Production-ready monitoring

### 2. Oracle Setup Automation ✅
- Complete SQL scripts for CDC configuration
- Automated XStream outbound server setup
- Schema rules configured correctly
- Sample data loading scripts

### 3. Streamlined Deployment ✅
- One-command deployment
- Copy-paste ready scripts
- Complete step-by-step guide
- Verified working configuration

---

## Quick Start

### Option 1: Use Existing EC2 with Oracle Already Running

If you already have Oracle 21c XE running in Docker:

```bash
# 1. Create directory structure
mkdir -p ~/oracle-cdc/confluent-platform/connectors
cd ~/oracle-cdc

# 2. Download JDBC driver
wget -q https://download.oracle.com/otn-pub/otn_software/jdbc/233/ojdbc11.jar -O confluent-platform/ojdbc11.jar

# 3. Set permissions
sudo chmod 777 confluent-platform/connectors

# 4. Download docker-compose.yml (copy from confluent-platform/docker-compose-stable.yml)
# 5. Download connector config (copy from confluent-platform/oracle-xstream-cdc-config.json)

# 6. Start Confluent Platform
cd confluent-platform
docker-compose up -d

# 7. Wait for services to start (2-3 minutes)
sleep 120

# 8. Deploy connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @oracle-xstream-cdc-config.json

# 9. Test CDC
docker exec -i oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
INSERT INTO ORDERS (ORDER_ID, CUSTOMER_ID, STATUS, ORDER_DATE) 
VALUES (999, 1, 'PENDING', SYSDATE);
COMMIT;
EXIT;
EOF

# 10. Verify message
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.ORDERS \
  --from-beginning --max-messages 1
```

### Option 2: Complete Fresh Setup

See **DEPLOYMENT_GUIDE.md** for complete step-by-step instructions including:
- Infrastructure setup
- Oracle database deployment
- CDC configuration
- Confluent Platform deployment
- Testing & validation

---

## Documentation Files

| File | Purpose | Audience |
|------|---------|----------|
| **DEPLOYMENT_GUIDE.md** | Complete step-by-step deployment | DevOps/Engineers |
| **SUCCESS_CONFIGURATION.md** | Verified working configuration | All (Most Important) |
| **CUSTOMER_SETUP_GUIDE.md** | Professional customer documentation | Customers |
| **SETUP_GUIDE_TECHNICAL.md** | Detailed technical execution guide | Engineers |
| **DEMO_QUICK_REFERENCE.md** | Quick demo playbook | Presenters |
| **EXECUTIVE_SUMMARY.md** | Business summary and ROI | Management |
| **IMPLEMENTATION_FINDINGS.md** | Real-world issues and solutions | Engineers |
| **monitor-cdc.sh** | Monitoring automation script | Operations |
| **demo-helper.sh** | Demo automation script | Presenters |

---

## Architecture

### With Zookeeper (Stable - Recommended)

```
┌─────────────────┐
│ Oracle 21c XE   │ port 1521
│   - XEPDB1      │
│   - XStream     │
└────────┬────────┘
         │ CDC
         ▼
┌─────────────────┐
│  Zookeeper      │ ports 2181, 9100 (JMX)
└────────┬────────┘
         │
┌────────┴────────┐
│  Kafka Broker   │ ports 9092, 9101 (JMX)
└────────┬────────┘
         │
┌────────┴────────┐
│ Schema Registry │ ports 8081, 9102 (JMX)
└────────┬────────┘
         │
┌────────┴────────┐
│ Kafka Connect   │ ports 8083, 9103 (JMX)
│  + Oracle CDC   │
└────────┬────────┘
         │
┌────────┴────────┐
│ Control Center  │ ports 9021, 9104 (JMX)
└─────────────────┘
```

### KRaft Mode (Experimental)

KRaft mode (Kafka without Zookeeper) is available in `docker-compose-kraft.yml` but requires additional testing. Use the stable version for production.

---

## JMX Monitoring

All services expose JMX metrics for monitoring:

| Service | JMX Port | Metrics Available |
|---------|----------|-------------------|
| Zookeeper | 9100 | Zookeeper health, connections |
| Kafka Broker | 9101 | Message rates, bytes in/out, partition metrics |
| Schema Registry | 9102 | Schema operations, API calls |
| Kafka Connect | 9103 | Connector status, task metrics, throughput |
| Control Center | 9104 | UI metrics, monitoring data |

### Accessing JMX Metrics

**Via jconsole:**
```bash
jconsole <EC2-IP>:9101
```

**Via Prometheus:**
See DEPLOYMENT_GUIDE.md for Prometheus/Grafana setup instructions.

---

## Verified Working

✅ Oracle 21c XE with XStream CDC  
✅ Confluent Platform 7.6.0  
✅ Oracle XStream CDC Connector 2.9.2  
✅ Real-time INSERT/UPDATE/DELETE capture  
✅ JMX metrics exposed on all services  
✅ Topics auto-created: XEPDB1.ORDERMGMT.ORDERS, ORDER_ITEMS, CUSTOMERS  
✅ Tested on AWS EC2 (t3.xlarge, Amazon Linux 2023)

---

## Key Features

### Real-Time CDC
- **Sub-second latency** from database to Kafka
- Captures INSERT, UPDATE, DELETE operations
- Before/after values for auditing
- Exactly-once delivery guarantees

### Production-Ready Monitoring
- JMX metrics on all components
- Ready for Prometheus/Grafana
- Health checks and alerting
- Performance metrics

### Easy Deployment
- Copy-paste commands
- Automated setup scripts
- Verified configurations
- Complete troubleshooting guide

---

## Configuration Files

### docker-compose-stable.yml
Stable configuration with Zookeeper + JMX monitoring (Recommended)

### docker-compose-kraft.yml
Experimental KRaft mode (Kafka without Zookeeper)

### oracle-xstream-cdc-config.json
Verified working connector configuration

### Oracle Setup Scripts
- `01_setup_database.sql` - Archive log and supplemental logging
- `02_create_user.sql` - Application user creation
- `03_create_schema_datamodel.sql` - Schema and tables
- `04_load_data.sql` - Sample data
- `05_create_xstream_user.sql` - XStream admin user
- `06_xstream_privs.sql` - XStream privileges
- `07_create_xstream_outbound.sql` - XStream outbound server

---

## Terraform Support (Coming Soon)

Terraform files for automated Oracle + Confluent deployment:
- `terraform/main.tf` - Main configuration
- `terraform/variables.tf` - Variables
- `terraform/userdata.sh` - EC2 initialization

**Note:** Terraform deployment is prepared but not yet tested. Manual deployment is recommended for now.

---

## Common Commands

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# Check connector status
curl http://localhost:8083/connectors/oracle-xstream-cdc-source/status

# List topics
docker exec broker kafka-topics --bootstrap-server broker:29092 --list

# Consume messages
docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic XEPDB1.ORDERMGMT.ORDERS

# Check JMX (broker)
# Use jconsole <EC2-IP>:9101

# Check XStream capture
docker exec oracle21c sqlplus sys/confluent123@XEPDB1 as sysdba <<EOF
SELECT CAPTURE_NAME, STATUS, STATE FROM DBA_CAPTURE;
EXIT;
EOF
```

---

## Troubleshooting

### Connector Not Running
```bash
curl http://localhost:8083/connectors/oracle-xstream-cdc-source/status
curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart
```

### No Messages in Kafka
```bash
# Connector starts from CURRENT, make a new change
docker exec -i oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<EOF
INSERT INTO ORDERS (ORDER_ID, CUSTOMER_ID, STATUS, ORDER_DATE) 
VALUES (998, 1, 'TEST', SYSDATE);
COMMIT;
EXIT;
EOF
```

### Check Logs
```bash
docker logs broker
docker logs connect
docker logs oracle21c
```

---

## Support & Resources

- **Documentation:** All guides in this repository
- **Oracle XStream:** https://docs.oracle.com/en/database/oracle/oracle-database/21/xstrm/
- **Confluent Oracle CDC:** https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/
- **Kafka Monitoring:** https://kafka.apache.org/documentation/#monitoring

---

## License & Disclaimer

This is a demonstration/reference implementation. Ensure proper licensing for production use:
- Oracle Database Express Edition
- Confluent Platform Enterprise
- Oracle XStream CDC Source Connector

---

**Created:** July 12, 2026  
**Technology Stack:** Oracle 21c XE + Confluent Platform 7.6.0 + JMX Monitoring  
**Deployment Model:** Docker-based, single-node setup (scalable to multi-node)  
**Status:** ✅ Production-Ready (Verified Working Configuration)
