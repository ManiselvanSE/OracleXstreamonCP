#!/bin/bash

################################################################################
# Oracle XStream CDC Monitoring Script
# Purpose: Monitor the health and status of Oracle XStream CDC pipeline
################################################################################

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================="
echo "Oracle XStream CDC Monitoring Dashboard"
echo -e "==========================================${NC}"
echo ""

# 1. Connector Status
echo -e "${YELLOW}1. Connector Status${NC}"
echo "-------------------"
STATUS=$(curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status 2>/dev/null)
if [ $? -eq 0 ]; then
  CONNECTOR_STATE=$(echo "$STATUS" | jq -r '.connector.state')
  TASK_STATE=$(echo "$STATUS" | jq -r '.tasks[0].state')

  if [ "$CONNECTOR_STATE" == "RUNNING" ] && [ "$TASK_STATE" == "RUNNING" ]; then
    echo -e "${GREEN}✓ Connector: $CONNECTOR_STATE${NC}"
    echo -e "${GREEN}✓ Task:      $TASK_STATE${NC}"
  else
    echo -e "${RED}✗ Connector: $CONNECTOR_STATE${NC}"
    echo -e "${RED}✗ Task:      $TASK_STATE${NC}"
  fi
else
  echo -e "${RED}✗ Cannot connect to Kafka Connect API${NC}"
fi
echo ""

# 2. Kafka Topics
echo -e "${YELLOW}2. Kafka Topics (ORDERMGMT schema)${NC}"
echo "-----------------------------------"
TOPICS=$(docker exec broker kafka-topics --bootstrap-server broker:29092 --list 2>/dev/null | grep "ORDERMGMT" || echo "")
if [ -n "$TOPICS" ]; then
  echo -e "${GREEN}$TOPICS${NC}"
else
  echo -e "${RED}✗ No ORDERMGMT topics found${NC}"
fi
echo ""

# 3. Message Counts
echo -e "${YELLOW}3. Message Counts per Topic${NC}"
echo "---------------------------"
for topic in ORDERMGMT.ORDERS ORDERMGMT.ORDER_ITEMS ORDERMGMT.CUSTOMERS; do
  COUNT=$(docker exec broker kafka-run-class kafka.tools.GetOffsetShell \
    --broker-list broker:29092 \
    --topic $topic 2>/dev/null | awk -F':' '{sum += $3} END {print sum}')

  if [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ]; then
    echo -e "${GREEN}$topic: $COUNT messages${NC}"
  else
    echo -e "${YELLOW}$topic: 0 messages (or topic doesn't exist)${NC}"
  fi
done
echo ""

# 4. Oracle XStream Capture Statistics
echo -e "${YELLOW}4. XStream Capture Statistics (Oracle)${NC}"
echo "---------------------------------------"
CAPTURE_INFO=$(docker exec oracle21c sqlplus -s sys/confluent123@XEPDB1 as sysdba 2>/dev/null <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF LINESIZE 200
SELECT 'Capture Name: ' || CAPTURE_NAME FROM V\$XSTREAM_CAPTURE WHERE CAPTURE_NAME='CAPTURE_XOUT';
SELECT 'State: ' || STATE FROM V\$XSTREAM_CAPTURE WHERE CAPTURE_NAME='CAPTURE_XOUT';
SELECT 'Status: ' || STATUS FROM DBA_CAPTURE WHERE CAPTURE_NAME='CAPTURE_XOUT';
SELECT 'Total Messages Captured: ' || TOTAL_MESSAGES_CAPTURED FROM V\$XSTREAM_CAPTURE WHERE CAPTURE_NAME='CAPTURE_XOUT';
SELECT 'Total Messages Enqueued: ' || TOTAL_MESSAGES_ENQUEUED FROM V\$XSTREAM_CAPTURE WHERE CAPTURE_NAME='CAPTURE_XOUT';
SELECT 'Current SCN: ' || CURRENT_SCN FROM V\$DATABASE;
EXIT;
EOF
)

if [ $? -eq 0 ]; then
  while IFS= read -r line; do
    if [[ $line == *"CAPTURING CHANGES"* ]] || [[ $line == *"ENABLED"* ]]; then
      echo -e "${GREEN}$line${NC}"
    elif [[ $line == *"State:"* ]] && [[ ! $line == *"CAPTURING CHANGES"* ]]; then
      echo -e "${RED}$line${NC}"
    else
      echo "$line"
    fi
  done <<< "$CAPTURE_INFO"
else
  echo -e "${RED}✗ Cannot connect to Oracle database${NC}"
fi
echo ""

# 5. Container Health
echo -e "${YELLOW}5. Docker Container Status${NC}"
echo "--------------------------"
CONTAINERS="zookeeper broker schema-registry connect control-center oracle21c"
for container in $CONTAINERS; do
  STATUS=$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null || echo "not found")
  if [ "$STATUS" == "running" ]; then
    echo -e "${GREEN}✓ $container: running${NC}"
  else
    echo -e "${RED}✗ $container: $STATUS${NC}"
  fi
done
echo ""

# 6. Latest Messages (sample)
echo -e "${YELLOW}6. Latest Message from ORDERS Topic (sample)${NC}"
echo "--------------------------------------------"
LATEST_MSG=$(docker exec broker kafka-console-consumer \
  --bootstrap-server broker:29092 \
  --topic ORDERMGMT.ORDERS \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 5000 2>/dev/null | jq -c '.' 2>/dev/null || echo "No messages or parsing failed")

if [ "$LATEST_MSG" != "No messages or parsing failed" ] && [ -n "$LATEST_MSG" ]; then
  echo -e "${GREEN}$LATEST_MSG${NC}"
else
  echo -e "${YELLOW}No messages available or topic is empty${NC}"
fi
echo ""

# 7. Recent Connect Worker Logs
echo -e "${YELLOW}7. Recent Connect Logs (Oracle-related, last 5 lines)${NC}"
echo "-----------------------------------------------------"
docker logs connect 2>&1 | grep -i "oracle" | tail -5
echo ""

# 8. Summary
echo -e "${BLUE}=========================================="
echo "Monitoring Summary"
echo -e "==========================================${NC}"

# Count successes
CHECKS_PASSED=0
TOTAL_CHECKS=5

# Check 1: Connector running
if [ "$CONNECTOR_STATE" == "RUNNING" ] && [ "$TASK_STATE" == "RUNNING" ]; then
  ((CHECKS_PASSED++))
fi

# Check 2: Topics exist
if [ -n "$TOPICS" ]; then
  ((CHECKS_PASSED++))
fi

# Check 3: Oracle capture running
if echo "$CAPTURE_INFO" | grep -q "CAPTURING CHANGES"; then
  ((CHECKS_PASSED++))
fi

# Check 4: Containers running
if docker ps | grep -q "broker" && docker ps | grep -q "connect"; then
  ((CHECKS_PASSED++))
fi

# Check 5: Messages exist
if [ -n "$LATEST_MSG" ] && [ "$LATEST_MSG" != "No messages or parsing failed" ]; then
  ((CHECKS_PASSED++))
fi

if [ $CHECKS_PASSED -eq $TOTAL_CHECKS ]; then
  echo -e "${GREEN}✓ All systems operational ($CHECKS_PASSED/$TOTAL_CHECKS checks passed)${NC}"
elif [ $CHECKS_PASSED -ge 3 ]; then
  echo -e "${YELLOW}⚠ System partially operational ($CHECKS_PASSED/$TOTAL_CHECKS checks passed)${NC}"
else
  echo -e "${RED}✗ System issues detected ($CHECKS_PASSED/$TOTAL_CHECKS checks passed)${NC}"
fi

echo ""
echo -e "${BLUE}Control Center:${NC} http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9021"
echo -e "${BLUE}Connect API:${NC}    http://localhost:8083"
echo ""
echo -e "${BLUE}=========================================="
echo "Monitoring Complete - $(date)"
echo -e "==========================================${NC}"
