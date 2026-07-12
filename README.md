# Oracle XStream CDC with Confluent Platform - Complete Documentation Package

This package contains comprehensive documentation for setting up Oracle XStream CDC (Change Data Capture) with Confluent Platform.

## 📋 Documentation Overview

### 1. **CUSTOMER_SETUP_GUIDE.md** - For Your Customer
- **Audience**: Customer's technical team
- **Purpose**: Professional, detailed implementation guide
- **Content**:
  - Architecture overview
  - XStream CDC vs JDBC comparison
  - Step-by-step setup instructions
  - Testing and validation procedures
  - Production considerations
  - Troubleshooting guide

**📤 Share this document with your customer**

---

### 2. **SETUP_GUIDE_TECHNICAL.md** - For Internal Use
- **Audience**: Your technical team
- **Purpose**: Detailed technical execution guide with expected outputs
- **Content**:
  - Complete command reference
  - Expected outputs for each step
  - Screenshot points for documentation
  - Verification commands
  - Troubleshooting commands

**🔧 Use this for actual implementation**

---

### 3. **DEMO_QUICK_REFERENCE.md** - For Demo Execution
- **Audience**: Demo presenters
- **Purpose**: Quick reference during live demos
- **Content**:
  - Pre-demo checklist
  - Condensed setup commands
  - Demo flow (INSERT/UPDATE/DELETE)
  - Monitoring commands
  - Common issues & quick fixes

**🎯 Use this during customer presentations**

---

### 4. **Helper Scripts**

#### `monitor-cdc.sh` - Monitoring Dashboard
Comprehensive health check script that displays:
- Connector status
- Kafka topics
- Message counts
- XStream capture statistics
- Container health
- Recent logs

**Usage:**
```bash
chmod +x monitor-cdc.sh
./monitor-cdc.sh
```

#### `demo-helper.sh` - Demo Automation
Simplifies common demo operations:
- Start consumers
- Insert/update/delete test data
- Manage connector (restart, pause, resume)
- View statistics

**Usage:**
```bash
chmod +x demo-helper.sh

# Examples:
./demo-helper.sh consume-orders    # Start consumer
./demo-helper.sh insert-test       # Insert test data
./demo-helper.sh status            # Check health
./demo-helper.sh --help            # See all commands
```

---

## 🚀 Quick Start Guide

### Step 1: Copy Files to EC2 Instance

```bash
# On your local machine
scp -i "/path/to/your-key.pem" \
  SETUP_GUIDE_TECHNICAL.md \
  monitor-cdc.sh \
  demo-helper.sh \
  ec2-user@your-ec2-ip:~/
```

### Step 2: On EC2 Instance - Execute Setup

```bash
# SSH to EC2
ssh -i "/path/to/your-key.pem" ec2-user@your-ec2-ip

# Make scripts executable
chmod +x monitor-cdc.sh demo-helper.sh

# Follow SETUP_GUIDE_TECHNICAL.md or DEMO_QUICK_REFERENCE.md
```

### Step 3: Verify Installation

```bash
# Run monitoring script
./monitor-cdc.sh

# Or check status with demo helper
./demo-helper.sh status
```

---

## 📊 Architecture Summary

```
Oracle Database (oracle21c)
    ↓
    ↓ Redo Logs
    ↓
XStream Outbound Server (xout)
    ↓
    ↓ XStream Protocol
    ↓
Kafka Connect
    ↓ Oracle XStream CDC Source Connector
    ↓
Apache Kafka
    ↓
    ├── ORDERMGMT.ORDERS
    ├── ORDERMGMT.ORDER_ITEMS
    └── ORDERMGMT.CUSTOMERS
```

---

## 🔑 Key Technologies

| Component | Technology | Version |
|-----------|-----------|---------|
| **Database** | Oracle Database Express Edition | 21c |
| **Streaming Platform** | Apache Kafka (Confluent Platform) | 7.6.0 |
| **CDC Connector** | Oracle XStream CDC Source Connector | 2.9.2 |
| **Containerization** | Docker & Docker Compose | Latest |
| **Monitoring** | Confluent Control Center | 7.6.0 |

---

## ⚡ Why Oracle XStream CDC?

### XStream CDC (Log-based) ✅
- Reads Oracle redo logs directly
- Captures INSERT, UPDATE, DELETE in real-time
- Sub-second latency
- Minimal database impact
- Before/after values for UPDATEs
- Guaranteed ordering and consistency
- **Production-grade, enterprise-ready**

### vs JDBC Connector (Query-based) ❌
- Polls tables periodically
- INSERT and UPDATE only (no DELETE)
- Higher latency (seconds to minutes)
- Higher database load (SELECT queries)
- No before/after values
- Can miss intermediate changes

---

## 📝 Setup Overview

### Oracle Database Configuration (15 min)
1. ✅ Enable ARCHIVELOG mode
2. ✅ Enable supplemental logging (database + table level)
3. ✅ Create XStream admin user with CAPTURE privilege
4. ✅ Create demo tables with test data
5. ✅ Create and start XStream outbound server

### Confluent Platform Setup (10 min)
1. ✅ Download Oracle JDBC driver
2. ✅ Create Docker Compose configuration
3. ✅ Start all services (Zookeeper, Kafka, Connect, Control Center)
4. ✅ Verify connector plugin installation

### Connector Deployment (5 min)
1. ✅ Create connector configuration
2. ✅ Deploy via REST API
3. ✅ Verify connector status
4. ✅ Verify topics auto-created

### Testing & Demo (10 min)
1. ✅ Test INSERT operation
2. ✅ Test UPDATE operation (see before/after)
3. ✅ Test DELETE operation (see tombstone)
4. ✅ View in Confluent Control Center

**Total Time: ~40 minutes**

---

## 🎯 Demo Flow

### Before Customer Arrives
1. Run through complete setup
2. Verify all services running
3. Test INSERT/UPDATE/DELETE
4. Prepare Control Center browser tabs
5. Have monitoring script ready

### During Demo (10 min)
1. **Introduction (2 min)**
   - Show architecture diagram
   - Explain XStream CDC vs JDBC

2. **Infrastructure Tour (2 min)**
   - Show docker containers
   - Show Control Center UI
   - Show existing topics

3. **Live INSERT Demo (2 min)**
   - Terminal 1: Start consumer
   - Terminal 2: Insert order
   - Show real-time message in Kafka

4. **Live UPDATE Demo (2 min)**
   - Update order in Oracle
   - Show before/after values in Kafka message

5. **Live DELETE Demo (1 min)**
   - Delete order item
   - Show tombstone message

6. **Monitoring & Discussion (1 min)**
   - Run `./monitor-cdc.sh`
   - Show metrics in Control Center

---

## 🔍 Verification Checklist

### Oracle Configuration
- [ ] LOG_MODE = ARCHIVELOG
- [ ] SUPPLEMENTAL_LOG_DATA_MIN = YES
- [ ] XStream admin user created
- [ ] XStream admin has CAPTURE privilege
- [ ] Tables have supplemental logging (ALL COLUMNS)
- [ ] XStream outbound server exists
- [ ] Capture state = "CAPTURING CHANGES"

### Confluent Platform
- [ ] All containers running (5 containers)
- [ ] Oracle JDBC driver present
- [ ] Oracle CDC connector plugin installed
- [ ] Connector status = RUNNING
- [ ] Task status = RUNNING
- [ ] Topics created (3 topics: ORDERS, ORDER_ITEMS, CUSTOMERS)

### End-to-End Testing
- [ ] INSERT captured in real-time
- [ ] UPDATE shows before/after values
- [ ] DELETE shows tombstone event
- [ ] Control Center accessible
- [ ] Message schema visible

---

## 🛠️ Common Commands

### Quick Health Check
```bash
./monitor-cdc.sh
```

### Start Real-time Consumer
```bash
./demo-helper.sh consume-orders
```

### Test INSERT
```bash
./demo-helper.sh insert-test
```

### Test UPDATE
```bash
./demo-helper.sh update-test
```

### Check Connector Status
```bash
./demo-helper.sh status
```

### Restart Connector
```bash
./demo-helper.sh restart
```

### View Capture Statistics
```bash
./demo-helper.sh capture-stats
```

---

## 🌐 Access URLs

```bash
# Get EC2 public IP
curl http://169.254.169.254/latest/meta-data/public-ipv4

# Access these URLs:
# - Control Center:     http://<EC2-IP>:9021
# - Connect REST API:   http://<EC2-IP>:8083
# - Schema Registry:    http://<EC2-IP>:8081
```

**Note:** Ensure EC2 Security Group allows inbound traffic on these ports.

---

## 🚨 Troubleshooting

### Issue: Connector shows FAILED
```bash
# Get error details
curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status | jq '.tasks[0].trace'

# Restart
./demo-helper.sh restart
```

### Issue: No messages in Kafka
```bash
# Verify connector is running
./demo-helper.sh status

# Verify capture is active
./demo-helper.sh capture-stats

# Make a new change (connector starts from CURRENT SCN)
./demo-helper.sh insert-test
```

### Issue: Cannot connect to Oracle
```bash
# Test connectivity
docker exec connect bash -c "timeout 5 bash -c '</dev/tcp/oracle21c/1521' && echo 'OK' || echo 'FAIL'"

# Ensure Oracle is on shared-network
docker network connect shared-network oracle21c

# Restart connector
./demo-helper.sh restart
```

---

## 📚 Additional Resources

### Documentation
- [Oracle XStream Documentation](https://docs.oracle.com/en/database/oracle/oracle-database/21/xstrm/)
- [Confluent Oracle CDC Connector Docs](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/)
- [Kafka Connect Documentation](https://docs.confluent.io/platform/current/connect/)

### Support
- Confluent Support: https://support.confluent.io
- Community Forums: https://forum.confluent.io
- Oracle Support: https://support.oracle.com

---

## 📦 Package Contents

```
.
├── README.md                      # This file
├── CUSTOMER_SETUP_GUIDE.md        # For customer (professional doc)
├── SETUP_GUIDE_TECHNICAL.md       # For execution (detailed with outputs)
├── DEMO_QUICK_REFERENCE.md        # For live demos (condensed)
├── monitor-cdc.sh                 # Monitoring script
└── demo-helper.sh                 # Demo automation script
```

---

## 🎓 Training Recommendations

### For Your Team
1. Review SETUP_GUIDE_TECHNICAL.md
2. Practice complete setup (2-3 times)
3. Familiarize with monitoring script
4. Practice demo flow with helper script
5. Know troubleshooting steps

### For Customer Team
1. Share CUSTOMER_SETUP_GUIDE.md
2. Schedule knowledge transfer session
3. Walk through architecture
4. Demonstrate live setup
5. Hand over monitoring scripts
6. Provide ongoing support plan

---

## ✅ Success Criteria

Your implementation is successful when:

1. **Oracle Side**
   - ✅ ARCHIVELOG enabled
   - ✅ Supplemental logging active
   - ✅ XStream capture state = "CAPTURING CHANGES"

2. **Confluent Side**
   - ✅ All containers healthy
   - ✅ Connector state = RUNNING
   - ✅ Topics auto-created

3. **End-to-End**
   - ✅ Real-time INSERT events
   - ✅ UPDATE events with before/after
   - ✅ DELETE events with tombstones
   - ✅ Sub-second latency
   - ✅ Zero data loss

4. **Operational**
   - ✅ Monitoring working
   - ✅ Control Center accessible
   - ✅ Team trained
   - ✅ Documentation handed over

---

## 🤝 Support & Feedback

For questions or issues:
1. Check DEMO_QUICK_REFERENCE.md troubleshooting section
2. Review connector logs: `./demo-helper.sh logs`
3. Check Oracle capture stats: `./demo-helper.sh capture-stats`
4. Contact Confluent support with error details

---

## 📄 License & Disclaimer

This documentation is provided for educational and demonstration purposes. Ensure you have proper licensing for:
- Oracle Database
- Confluent Platform (Enterprise features)
- Oracle XStream CDC Source Connector

---

**Created:** July 12, 2026  
**Technology Stack:** Oracle 21c XE, Confluent Platform 7.6.0, Oracle XStream CDC 2.9.2  
**Deployment Model:** Docker-based, single-node setup  

**For production deployments, consider:**
- Multi-node Kafka cluster (minimum 3 brokers)
- Multiple Connect workers
- High availability for Oracle (Data Guard, RAC)
- Security hardening (TLS, SASL, encryption)
- Monitoring & alerting (Prometheus, Grafana)
- Disaster recovery plan
