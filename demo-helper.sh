#!/bin/bash

################################################################################
# Oracle XStream CDC Demo Helper Script
# Purpose: Simplify common demo operations
################################################################################

ACTION=$1

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

show_usage() {
  echo -e "${BLUE}Oracle XStream CDC Demo Helper${NC}"
  echo ""
  echo "Usage: $0 {command}"
  echo ""
  echo -e "${YELLOW}Consumer Commands:${NC}"
  echo "  consume-orders       Start consuming ORDERS topic in real-time"
  echo "  consume-items        Start consuming ORDER_ITEMS topic in real-time"
  echo "  consume-customers    Start consuming CUSTOMERS topic in real-time"
  echo ""
  echo -e "${YELLOW}Test Data Commands:${NC}"
  echo "  insert-test          Insert test order and see CDC"
  echo "  update-test          Update order and see before/after"
  echo "  delete-test          Delete record and see tombstone"
  echo "  bulk-insert          Insert 10 orders in bulk"
  echo ""
  echo -e "${YELLOW}Management Commands:${NC}"
  echo "  status               Check connector and capture status"
  echo "  restart              Restart the connector"
  echo "  pause                Pause the connector"
  echo "  resume               Resume the connector"
  echo "  delete               Delete the connector"
  echo "  deploy               Deploy the connector"
  echo ""
  echo -e "${YELLOW}Monitoring Commands:${NC}"
  echo "  topics               List all ORDERMGMT topics"
  echo "  counts               Show message counts per topic"
  echo "  logs                 Show recent connector logs"
  echo "  capture-stats        Show Oracle XStream capture statistics"
  echo ""
  echo -e "${YELLOW}Examples:${NC}"
  echo "  $0 consume-orders    # Start consuming and leave running"
  echo "  $0 insert-test       # In another terminal, insert test data"
  echo "  $0 status            # Check health of entire pipeline"
}

case $ACTION in
  "consume-orders")
    echo -e "${GREEN}=== Consuming ORDERS topic in real-time (Ctrl+C to stop) ===${NC}"
    docker exec broker kafka-console-consumer \
      --bootstrap-server broker:29092 \
      --topic ORDERMGMT.ORDERS \
      --property print.key=true \
      --property print.timestamp=true
    ;;

  "consume-items")
    echo -e "${GREEN}=== Consuming ORDER_ITEMS topic in real-time (Ctrl+C to stop) ===${NC}"
    docker exec broker kafka-console-consumer \
      --bootstrap-server broker:29092 \
      --topic ORDERMGMT.ORDER_ITEMS \
      --property print.key=true \
      --property print.timestamp=true
    ;;

  "consume-customers")
    echo -e "${GREEN}=== Consuming CUSTOMERS topic in real-time (Ctrl+C to stop) ===${NC}"
    docker exec broker kafka-console-consumer \
      --bootstrap-server broker:29092 \
      --topic ORDERMGMT.CUSTOMERS \
      --property print.key=true \
      --property print.timestamp=true
    ;;

  "insert-test")
    echo -e "${YELLOW}=== Inserting test data into Oracle ===${NC}"
    RANDOM_ID=$((1000 + RANDOM % 9000))
    docker exec oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<SQL
INSERT INTO ORDERS VALUES ($RANDOM_ID, 'Test Customer', SYSTIMESTAMP, 9999.99, 'TEST', SYSTIMESTAMP, SYSTIMESTAMP);
COMMIT;
SELECT 'Inserted ORDER_ID: ' || ORDER_ID || ', Customer: ' || CUSTOMER_NAME || ', Amount: ' || TOTAL_AMOUNT FROM ORDERS WHERE ORDER_ID = $RANDOM_ID;
EXIT;
SQL
    echo -e "${GREEN}✓ Test order inserted with ID: $RANDOM_ID${NC}"
    echo -e "${BLUE}Check your consumer terminal - you should see the INSERT event!${NC}"
    ;;

  "update-test")
    echo -e "${YELLOW}=== Updating test data in Oracle ===${NC}"
    docker exec oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<SQL
UPDATE ORDERS SET STATUS = 'SHIPPED', TOTAL_AMOUNT = 1699.99, UPDATED_AT = SYSTIMESTAMP WHERE ORDER_ID = 1;
COMMIT;
SELECT 'Updated ORDER_ID: ' || ORDER_ID || ', New Status: ' || STATUS || ', New Amount: ' || TOTAL_AMOUNT FROM ORDERS WHERE ORDER_ID = 1;
EXIT;
SQL
    echo -e "${GREEN}✓ Order ID 1 updated${NC}"
    echo -e "${BLUE}Check your consumer - you should see UPDATE event with before/after values!${NC}"
    ;;

  "delete-test")
    echo -e "${YELLOW}=== Deleting test data from Oracle ===${NC}"
    # First check if record exists
    EXISTS=$(docker exec oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<SQL
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT COUNT(*) FROM ORDER_ITEMS WHERE ITEM_ID = 102;
EXIT;
SQL
)

    if [ "$EXISTS" -gt 0 ]; then
      docker exec oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<SQL
DELETE FROM ORDER_ITEMS WHERE ITEM_ID = 102;
COMMIT;
SELECT 'Deleted ORDER_ITEM_ID: 102' FROM DUAL;
EXIT;
SQL
      echo -e "${GREEN}✓ Order item 102 deleted${NC}"
      echo -e "${BLUE}Check your consumer - you should see DELETE event (tombstone)!${NC}"
    else
      echo -e "${YELLOW}⚠ Order item 102 already deleted. Inserting new one to delete...${NC}"
      docker exec oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<SQL
INSERT INTO ORDER_ITEMS VALUES (102, 1, 'Mouse', 2, 150.00, SYSTIMESTAMP);
COMMIT;
DELETE FROM ORDER_ITEMS WHERE ITEM_ID = 102;
COMMIT;
SELECT 'Inserted and deleted ORDER_ITEM_ID: 102' FROM DUAL;
EXIT;
SQL
      echo -e "${GREEN}✓ Created and deleted order item 102${NC}"
      echo -e "${BLUE}Check your consumer - you should see INSERT then DELETE event!${NC}"
    fi
    ;;

  "bulk-insert")
    echo -e "${YELLOW}=== Performing bulk insert (10 orders) ===${NC}"
    docker exec oracle21c sqlplus -s ordermgmt/kafka@XEPDB1 <<SQL
BEGIN
  FOR i IN 1..10 LOOP
    INSERT INTO ORDERS VALUES (
      2000 + i,
      'Bulk Customer ' || i,
      SYSTIMESTAMP,
      500.00 + (i * 100),
      'PENDING',
      SYSTIMESTAMP,
      SYSTIMESTAMP
    );
  END LOOP;
  COMMIT;
END;
/
SELECT 'Inserted ' || COUNT(*) || ' orders' FROM ORDERS WHERE ORDER_ID BETWEEN 2001 AND 2010;
EXIT;
SQL
    echo -e "${GREEN}✓ Bulk insert completed (10 orders)${NC}"
    echo -e "${BLUE}Check your consumer - you should see 10 INSERT events!${NC}"
    ;;

  "status")
    echo -e "${YELLOW}=== Connector Status ===${NC}"
    STATUS=$(curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status)
    CONNECTOR_STATE=$(echo "$STATUS" | jq -r '.connector.state')
    TASK_STATE=$(echo "$STATUS" | jq -r '.tasks[0].state')

    if [ "$CONNECTOR_STATE" == "RUNNING" ] && [ "$TASK_STATE" == "RUNNING" ]; then
      echo -e "${GREEN}✓ Connector: $CONNECTOR_STATE${NC}"
      echo -e "${GREEN}✓ Task:      $TASK_STATE${NC}"
    else
      echo -e "${RED}✗ Connector: $CONNECTOR_STATE${NC}"
      echo -e "${RED}✗ Task:      $TASK_STATE${NC}"
      echo ""
      echo "Error details:"
      echo "$STATUS" | jq '.tasks[0].trace' 2>/dev/null || echo "No error trace available"
    fi

    echo ""
    echo -e "${YELLOW}=== Oracle Capture Status ===${NC}"
    docker exec oracle21c sqlplus -s sys/confluent123@XEPDB1 as sysdba <<SQL
SET PAGESIZE 50 LINESIZE 150
COLUMN CAPTURE_NAME FORMAT A15
COLUMN STATE FORMAT A20
COLUMN STATUS FORMAT A10
SELECT CAPTURE_NAME, STATUS, STATE FROM DBA_CAPTURE WHERE CAPTURE_NAME='CAPTURE_XOUT';
EXIT;
SQL
    ;;

  "restart")
    echo -e "${YELLOW}=== Restarting connector ===${NC}"
    curl -X POST http://localhost:8083/connectors/oracle-xstream-cdc-source/restart
    echo ""
    sleep 3
    STATUS=$(curl -s http://localhost:8083/connectors/oracle-xstream-cdc-source/status)
    CONNECTOR_STATE=$(echo "$STATUS" | jq -r '.connector.state')
    TASK_STATE=$(echo "$STATUS" | jq -r '.tasks[0].state')
    echo -e "${GREEN}Connector State: $CONNECTOR_STATE${NC}"
    echo -e "${GREEN}Task State:      $TASK_STATE${NC}"
    ;;

  "pause")
    echo -e "${YELLOW}=== Pausing connector ===${NC}"
    curl -X PUT http://localhost:8083/connectors/oracle-xstream-cdc-source/pause
    echo ""
    echo -e "${GREEN}✓ Connector paused${NC}"
    ;;

  "resume")
    echo -e "${YELLOW}=== Resuming connector ===${NC}"
    curl -X PUT http://localhost:8083/connectors/oracle-xstream-cdc-source/resume
    echo ""
    echo -e "${GREEN}✓ Connector resumed${NC}"
    ;;

  "delete")
    echo -e "${RED}=== Deleting connector ===${NC}"
    read -p "Are you sure you want to delete the connector? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      curl -X DELETE http://localhost:8083/connectors/oracle-xstream-cdc-source
      echo ""
      echo -e "${GREEN}✓ Connector deleted${NC}"
    else
      echo "Cancelled"
    fi
    ;;

  "deploy")
    echo -e "${YELLOW}=== Deploying connector ===${NC}"
    if [ ! -f "oracle-xstream-cdc-config.json" ]; then
      echo -e "${RED}✗ Configuration file 'oracle-xstream-cdc-config.json' not found${NC}"
      echo "Please create the configuration file first"
      exit 1
    fi

    curl -X POST http://localhost:8083/connectors \
      -H "Content-Type: application/json" \
      -d @oracle-xstream-cdc-config.json
    echo ""
    echo -e "${GREEN}✓ Connector deployed${NC}"
    sleep 5
    $0 status
    ;;

  "topics")
    echo -e "${YELLOW}=== ORDERMGMT Topics ===${NC}"
    docker exec broker kafka-topics --bootstrap-server broker:29092 --list | grep ORDERMGMT
    ;;

  "counts")
    echo -e "${YELLOW}=== Message Counts per Topic ===${NC}"
    for topic in ORDERMGMT.ORDERS ORDERMGMT.ORDER_ITEMS ORDERMGMT.CUSTOMERS; do
      COUNT=$(docker exec broker kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list broker:29092 \
        --topic $topic 2>/dev/null | awk -F':' '{sum += $3} END {print sum}')
      echo -e "${GREEN}$topic: $COUNT messages${NC}"
    done
    ;;

  "logs")
    echo -e "${YELLOW}=== Recent Connector Logs (last 20 Oracle-related lines) ===${NC}"
    docker logs connect 2>&1 | grep -i "oracle" | tail -20
    ;;

  "capture-stats")
    echo -e "${YELLOW}=== Oracle XStream Capture Statistics ===${NC}"
    docker exec oracle21c sqlplus -s sys/confluent123@XEPDB1 as sysdba <<SQL
SET PAGESIZE 50 LINESIZE 200
COLUMN CAPTURE_NAME FORMAT A15
COLUMN STATE FORMAT A25
COLUMN TOTAL_MESSAGES_CAPTURED FORMAT 999999999
COLUMN TOTAL_MESSAGES_ENQUEUED FORMAT 999999999
COLUMN LATENCY_SECONDS FORMAT 999999

SELECT CAPTURE_NAME,
       STATE,
       TOTAL_MESSAGES_CAPTURED,
       TOTAL_MESSAGES_ENQUEUED,
       LATENCY_SECONDS
FROM V\$XSTREAM_CAPTURE
WHERE CAPTURE_NAME='CAPTURE_XOUT';

SELECT 'Current SCN: ' || CURRENT_SCN AS SCN_INFO FROM V\$DATABASE;
EXIT;
SQL
    ;;

  *)
    show_usage
    exit 1
    ;;
esac
