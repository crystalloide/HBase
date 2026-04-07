#!/bin/bash
# ============================================================
#  cluster-status.sh – Affiche l'état du cluster
#  À exécuter depuis srvmaster01 :
#    docker exec -it srvmaster01 /opt/scripts/cluster-status.sh
# ============================================================

export HADOOP_HOME=/opt/hadoop
export HBASE_HOME=/opt/hbase
export ZOOKEEPER_HOME=/opt/zookeeper
export PATH=$HADOOP_HOME/bin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$PATH

echo "════════════════════════════════════════"
echo " ÉTAT DU CLUSTER HADOOP LAB"
echo "════════════════════════════════════════"

echo ""
echo "── ZooKeeper (tous les nœuds) ──────────"
for host in srvmaster01 srvmaster02 srvdata01 srvdata02 srvdata03; do
    status=$(echo ruok | nc -w 2 $host 2181 2>/dev/null)
    [ "$status" = "imok" ] \
        && echo "  ✓ $host:2181 → $status" \
        || echo "  ✗ $host:2181 → non disponible"
done

echo ""
echo "── HDFS ────────────────────────────────"
hdfs dfsadmin -report 2>/dev/null | grep -E "^(Name|Hostname|Live|Dead|Configured|DFS)" || \
    echo "  NameNode non disponible"

echo ""
echo "── YARN ────────────────────────────────"
yarn node -list 2>/dev/null | head -20 || echo "  ResourceManager non disponible"

echo ""
echo "── HBase ───────────────────────────────"
echo "status 'simple'" | hbase shell 2>/dev/null | tail -10 || \
    echo "  HBase Master non disponible"

echo ""
echo "── Zeppelin ────────────────────────────"
curl -s -o /dev/null -w "  HTTP %{http_code}\n" http://localhost:8080/ 2>/dev/null || \
    echo "  Zeppelin non disponible"

echo ""
echo "── Interfaces Web ──────────────────────"
echo "  HDFS NameNode   : http://localhost:9870"
echo "  YARN            : http://localhost:8088"
echo "  Secondary NN    : http://srvmaster02:9868"
echo "  HBase Master    : http://localhost:16010"
echo "  MapReduce Hist  : http://localhost:19888"
echo "  Zeppelin        : http://localhost:8080"
echo "════════════════════════════════════════"
