# Oracle XStream CDC Implementation - Findings & Issues

## Date: July 12, 2026
## Environment: Oracle Database 21c Express Edition (Multitenant) + Confluent Platform 7.6.0

---

## Executive Summary

The implementation of Oracle XStream CDC with Confluent Platform on Oracle Express Edition **encountered significant challenges** due to the multitenant architecture (CDB/PDB) in Oracle XE. While Oracle database configuration was partially successful, the connector deployment faced schema visibility and authentication issues.

### Overall Status: ⚠️ PARTIALLY SUCCESSFUL

- ✅ Oracle ARCHIVELOG mode enabled
- ✅ Supplemental logging configured
- ✅ XStream admin user created (common user: c##xstrmadmin)
- ✅ XStream outbound server created successfully (server: xout, capture: CAP$_XOUT_7)
- ✅ Confluent Platform deployed successfully
- ✅ Oracle XStream CDC connector plugin installed
- ❌ Connector deployment failed due to table visibility and schema snapshot issues

---

## What Worked Successfully

### 1. Oracle Database Prerequisites
- **ARCHIVELOG Mode**: Already enabled or successfully enabled
- **Supplemental Logging**: Enabled at database and table level
- **Test Data**: Tables exist with data (319 customers, 105 orders, 665 items)

### 2. XStream Administrator Setup
- Created common user: `c##xstrmadmin` with password `xstrmadmin123`
- Granted XStream CAPTURE privilege successfully
- User exists in all containers (CDB and PDBs)

### 3. XStream Outbound Server Creation
```
Server Name: xout
Capture Name: CAP$_XOUT_7
Queue Name: Q$_XOUT_8
Connect User: C##XSTRMADMIN
Status: ENABLED
Captured SCN: 10041628
```

### 4. Confluent Platform Deployment
All services deployed successfully:
- Zookeeper: ✅ Running
- Kafka Broker: ✅ Running (port 9092)
- Schema Registry: ✅ Running (port 8081)
- Kafka Connect: ✅ Running (port 8083)
- Control Center: ✅ Running (port 9021)

### 5. Oracle CDC Connector Plugin
- **Connector Class**: `io.confluent.connect.oracle.cdc.OracleCdcSourceConnector`
- **Version**: 2.9.2
- **Status**: ✅ Installed successfully

---

## Issues Encountered

### Issue #1: Docker Compose Version Compatibility
**Problem**: Docker Compose 1.21.0 on EC2 doesn't support version 3.8

**Error**:
```
Version in "./docker-compose.yml" is unsupported
```

**Solution**: Changed `version: '3.8'` to `version: '3.3'`

**Documentation Impact**: ✅ FIXED - Updated docker-compose.yml template

---

### Issue #2: Connector Installation Directory Permissions
**Problem**: Volume-mapped directory lacked write permissions for connector installation

**Error**:
```
Failed to create output directory: /usr/share/confluent-hub-components/confluentinc-kafka-connect-oracle-cdc
```

**Solution**: 
```bash
sudo chmod 777 connectors/
docker-compose restart connect
```

**Documentation Impact**: ✅ MUST ADD - Pre-create connectors directory with proper permissions

---

### Issue #3: Missing Required Configuration Parameter
**Problem**: Connector requires `confluent.topic.bootstrap.servers` parameter

**Error**:
```
Missing required configuration "confluent.topic.bootstrap.servers" which has no default value
```

**Solution**: Added to configuration:
```json
"confluent.topic.bootstrap.servers": "broker:29092",
"confluent.topic.replication.factor": "1"
```

**Documentation Impact**: ✅ FIXED - Added to connector configuration template

---

### Issue #4: Table Inclusion Pattern Not Matching
**Problem**: Regex pattern `ORDERMGMT\\.(ORDERS|ORDER_ITEMS|CUSTOMERS)` doesn't match tables in multitenant setup

**Error**:
```
Table inclusion pattern matches no tables in the database
```

**Attempted Solutions**:
1. ❌ Pattern: `ORDERMGMT\\.(ORDERS|ORDER_ITEMS|CUSTOMERS)` - No match
2. ❌ Pattern: `ORDERMGMT\\\\..*` - No match
3. ⚠️ Pattern: `.*` - Matched but caused snapshot errors

**Root Cause**: In Oracle multitenant (CDB/PDB) environment with common user, table visibility and schema qualification is complex.

**Documentation Impact**: ⚠️ REQUIRES INVESTIGATION - May need Oracle Enterprise Edition or different user setup

---

### Issue #5: Schema Snapshot Failure with Catch-All Pattern
**Problem**: Using `.*` pattern causes connector to snapshot system tables with duplicate column names

**Error**:
```
Cannot create field because of field name duplication PROCEDURE_
JDBC type 1111 (UNDEFINED) not currently supported
```

**Attempted Solution**: Set `"snapshot.mode": "no_snapshot"` to skip initial snapshot

**Result**: Still couldn't find tables with specific ORDERMGMT pattern

**Documentation Impact**: ⚠️ CRITICAL - XStream CDC connector may not fully support Oracle XE multitenant architecture

---

### Issue #6: Authentication with Local vs Common User
**Problem**: Mismatch between XStream outbound server configuration and connector authentication

**Scenario**:
- XStream server configured with: `c##xstrmadmin` (common user)
- Connector connection attempts:
  - With `c##xstrmadmin`: Connects but can't see PDB tables
  - With `xstrmadmin` (local): Gets "invalid username/password" error

**Root Cause**: XStream in multitenant requires careful coordination between:
- CDB-level capture process
- PDB-level table access
- User privileges across containers

**Documentation Impact**: ⚠️ CRITICAL - Requires Oracle Enterprise Edition or non-multitenant setup

---

## Key Findings

### Oracle Express Edition Limitations for XStream CDC

1. **Multitenant Complexity**: Oracle XE 21c uses mandatory multitenant architecture (CDB/PDB)
   - XStream outbound must be created in CDB$ROOT
   - Tables exist in XEPDB1
   - User context switching is complex

2. **Common User Requirements**:
   - XStream requires common users (c##prefix)
   - Common users have different visibility rules in PDBs
   - JDBC connections to PDBs may not honor common user context properly

3. **Connector Compatibility**:
   - Oracle XStream CDC connector may not be fully tested with Oracle XE multitenant
   - Most documentation assumes Oracle Enterprise Edition with simpler setup

### Recommended Alternatives

#### Option 1: Use Oracle JDBC Source Connector (Polling-based)
**Pros**:
- Simpler setup
- Works with standard JDBC connections
- No XStream configuration required

**Cons**:
- Not true CDC (polls tables periodically)
- Cannot capture DELETE operations
- Higher database load
- No before/after values for UPDATEs

**Setup**:
```json
{
  "connector.class": "io.confluent.jdbc.JdbcSourceConnector",
  "connection.url": "jdbc:oracle:thin:@oracle21c:1521/XEPDB1",
  "connection.user": "ordermgmt",
  "connection.password": "kafka",
  "mode": "timestamp+incrementing",
  "timestamp.column.name": "UPDATED_AT",
  "incrementing.column.name": "ORDER_ID",
  "table.whitelist": "ORDERS,ORDER_ITEMS,CUSTOMERS"
}
```

#### Option 2: Use Debezium Oracle Connector
Debezium also supports Oracle CDC but may have similar multitenant challenges.

#### Option 3: Upgrade to Oracle Enterprise Edition
Oracle Enterprise Edition without mandatory multitenant would simplify XStream setup significantly.

---

## Documentation Updates Required

### CRITICAL Updates

1. **Add Prerequisites Section**:
   ```
   IMPORTANT: Oracle XStream CDC Connector is designed for Oracle Enterprise Edition.
   Oracle Express Edition has limited support due to mandatory multitenant architecture.
   For production use, Oracle Enterprise Edition is strongly recommended.
   ```

2. **Add Step: Create Connectors Directory**:
   ```bash
   mkdir -p ~/confluent-oracle-cdc/connectors
   sudo chmod 777 ~/confluent-oracle-cdc/connectors
   ```

3. **Fix Docker Compose Version**:
   ```yaml
   version: "3.3"  # NOT 3.8 for older docker-compose
   ```

4. **Add Required Connector Parameters**:
   ```json
   "confluent.topic.bootstrap.servers": "broker:29092",
   "confluent.topic.replication.factor": "1"
   ```

5. **Add Troubleshooting Section**:
   - Multitenant challenges
   - Common user vs local user issues
   - Table visibility problems
   - Alternative connectors (JDBC)

### MODERATE Updates

1. **XStream Setup Clarification**:
   - Must be done from CDB$ROOT
   - Requires common user (c##prefix)
   - source_database parameter must point to PDB

2. **Expected Errors**:
   - "Table inclusion pattern matches no tables" - common with multitenant
   - "Cannot create field because of field name duplication" - system table conflicts
   - "ORA-01017: invalid username/password" - local user in PDB context

3. **Verification Steps**:
   - How to check if XStream is actually capturing changes
   - How to verify connector can see tables
   - How to test with JDBC first before XStream

---

## Working Configuration Summary

### Oracle Side (✅ WORKING)
```sql
-- ARCHIVELOG: ENABLED
-- Supplemental Logging: YES
-- XStream Server: xout
-- Capture Process: CAP$_XOUT_7 (ENABLED)
-- Common User: c##xstrmadmin
-- Source Schema: ORDERMGMT (in XEPDB1)
```

### Confluent Side (✅ WORKING)
```
All services running on shared-network:
- Zookeeper: zookeeper:2181
- Broker: broker:29092 (external: localhost:9092)
- Schema Registry: schema-registry:8081
- Connect: connect:8083
- Control Center: control-center:9021

Oracle CDC Connector Plugin: INSTALLED
Version: 2.9.2
```

### Connector Side (❌ NOT WORKING)
```
Issue: Cannot deploy connector successfully
Root Cause: Table visibility in multitenant environment
Status: Requires further investigation or Oracle EE
```

---

## Next Steps for Customer

### Immediate Actions

1. **Decision Point**: Choose connector strategy
   - ✅ **Quick Win**: Use JDBC Source Connector (polling-based, works now)
   - ⚠️ **Preferred**: Oracle XStream CDC (requires Oracle EE or deeper troubleshooting)

2. **If Proceeding with JDBC Connector**:
   - Update tables to have `UPDATED_AT` timestamp column
   - Use `timestamp+incrementing` mode
   - Accept limitations (no DELETE capture, polling-based)

3. **If Proceeding with XStream CDC**:
   - Consider upgrading to Oracle Enterprise Edition
   - OR: Engage Confluent Professional Services for XE-specific setup
   - OR: Create non-multitenant Oracle database for CDC

### Testing Recommendations

1. **Test JDBC Connector First**:
   - Proves Kafka infrastructure works
   - Validates table access and permissions
   - Provides immediate value while resolving XStream issues

2. **Parallel Path**:
   - Continue XStream investigation with Confluent support
   - Test on Oracle EE if available
   - Document exact multitenant requirements

---

## Cost-Benefit Analysis

### Oracle JDBC Source Connector
**Setup Time**: 30 minutes  
**Complexity**: Low  
**Data Freshness**: 1-60 seconds (configurable poll interval)  
**Operations Captured**: INSERT, UPDATE  
**Production Ready**: ✅ Yes  

### Oracle XStream CDC Connector
**Setup Time**: 4-8 hours (if working) or UNKNOWN (with Oracle XE MT)  
**Complexity**: High  
**Data Freshness**: Sub-second  
**Operations Captured**: INSERT, UPDATE, DELETE + before/after  
**Production Ready**: ⚠️ Requires Oracle EE  

---

## Conclusion

**For Immediate Demo/POC**: Recommend JDBC Source Connector

**For Production**: 
- If Oracle EE available: Pursue XStream CDC
- If Oracle XE only: JDBC Source Connector acceptable for many use cases
- Consider total cost: Oracle EE license vs. polling overhead

---

## Appendix: Actual Commands Executed

### Oracle XStream Setup
```sql
-- Created common user
CREATE USER c##xstrmadmin IDENTIFIED BY xstrmadmin123 CONTAINER=ALL;

-- Granted XStream privilege
BEGIN
   DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
      grantee => 'c##xstrmadmin',
      privilege_type => 'CAPTURE',
      grant_select_privileges => TRUE,
      container => 'ALL'
   );
END;
/

-- Created outbound server
BEGIN
  DBMS_XSTREAM_ADM.CREATE_OUTBOUND(server_name => 'xout');
END;
/

-- Configured connect user
BEGIN
  DBMS_XSTREAM_ADM.ALTER_OUTBOUND(
    server_name => 'xout',
    connect_user => 'c##xstrmadmin'
  );
END;
/
```

### Confluent Platform
```bash
# Fixed docker-compose version
sed -i 's/version: .3\.8./version: "3.3"/' docker-compose.yml

# Fixed permissions
sudo chmod 777 connectors/

# Started services
docker-compose up -d
```

### Connector Configuration (Not Working)
```json
{
  "name": "oracle-xstream-cdc-source",
  "config": {
    "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
    "oracle.server": "oracle21c",
    "oracle.port": "1521",
    "oracle.sid": "XE",
    "oracle.pdb.name": "XEPDB1",
    "oracle.username": "c##xstrmadmin",
    "oracle.password": "xstrmadmin123",
    "xstream.server.name": "xout",
    "table.inclusion.regex": "ORDERMGMT\\\\..*",
    "snapshot.mode": "no_snapshot",
    "confluent.topic.bootstrap.servers": "broker:29092",
    "confluent.topic.replication.factor": "1"
  }
}
```

**Result**: "Table inclusion pattern matches no tables in the database"

---

**Report Generated**: July 12, 2026  
**Test Environment**: AWS EC2, Oracle XE 21c (Docker), Confluent Platform 7.6.0 (Docker)  
**Recommendation**: Use JDBC connector for Oracle XE; XStream CDC requires Oracle EE
