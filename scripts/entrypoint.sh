#!/bin/bash
# ============================================================
#  entrypoint.sh – v4
#  FIX : wait_for utilise $HOSTNAME pour les WebUI
#        (NameNode/RM bindent sur le hostname par défaut,
#         même avec http-address=0.0.0.0 le temps de démarrer)
# ============================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] [$HOSTNAME] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] [$HOSTNAME] WARN: $*${NC}"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] [$HOSTNAME] ERROR: $*${NC}"; }

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}
export HADOOP_HOME=${HADOOP_HOME:-/opt/hadoop}
export HBASE_HOME=${HBASE_HOME:-/opt/hbase}
export ZOOKEEPER_HOME=${ZOOKEEPER_HOME:-/opt/zookeeper}
export ZEPPELIN_HOME=${ZEPPELIN_HOME:-/opt/zeppelin}
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export HADOOP_MAPRED_HOME=${HADOOP_HOME}
export HADOOP_COMMON_HOME=${HADOOP_HOME}
export HADOOP_HDFS_HOME=${HADOOP_HOME}
export HADOOP_YARN_HOME=${HADOOP_HOME}
export PATH=$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$ZEPPELIN_HOME/bin:$PATH
export HBASE_MANAGES_ZK=false

NODE_ROLE=${NODE_ROLE:-worker}
ZK_ID=${ZK_ID:-1}

log "=== Démarrage : $HOSTNAME | Rôle : $NODE_ROLE | ZK_ID : $ZK_ID ==="

# ── Permissions ──────────────────────────────────────────────
mkdir -p ${HADOOP_HOME}/data/{namenode,datanode,secondarynamenode,tmp} \
         ${HADOOP_HOME}/logs ${HBASE_HOME}/logs \
         ${ZOOKEEPER_HOME}/data ${ZOOKEEPER_HOME}/logs
chown -R hadoop:hadoop \
    ${HADOOP_HOME}/data ${HADOOP_HOME}/logs \
    ${HBASE_HOME}/logs ${ZOOKEEPER_HOME}/data ${ZOOKEEPER_HOME}/logs

# ── PID résiduels ────────────────────────────────────────────
rm -f /tmp/hadoop-hadoop-*.pid /tmp/mapred-hadoop-*.pid \
      /tmp/hbase-hadoop-*.pid ${ZOOKEEPER_HOME}/data/zookeeper_server.pid 2>/dev/null || true
pkill -f "proc_namenode\|proc_datanode\|proc_resourcemanager\|proc_nodemanager\|JobHistoryServer\|HMaster\|HRegionServer" 2>/dev/null || true
sleep 2

# ── FIX javax.activation (Hadoop < 3.3 + Java 11) ───────────
#PATCH_JAR1="${HADOOP_HOME}/share/hadoop/yarn/lib/javax.activation-api-1.2.0.jar"
#if [ ! -f "${PATCH_JAR1}" ]; then
#    log "[FIX] Téléchargement javax.activation-api..."
#    wget -q https://repo1.maven.org/maven2/javax/activation/javax.activation-api/1.2.0/javax.activation-api-1.2.0.jar \
#         -O "${PATCH_JAR1}" && log "[FIX] OK ✓" || warn "[FIX] Download échoué"
#    wget -q https://repo1.maven.org/maven2/javax/xml/bind/jaxb-api/2.3.1/jaxb-api-2.3.1.jar \
#         -O "${HADOOP_HOME}/share/hadoop/yarn/lib/jaxb-api-2.3.1.jar" || true
#    for dir in common hdfs mapreduce; do
#        mkdir -p ${HADOOP_HOME}/share/hadoop/${dir}/lib
#        cp -n "${PATCH_JAR1}" ${HADOOP_HOME}/share/hadoop/${dir}/lib/ 2>/dev/null || true
#       cp -n "${HADOOP_HOME}/share/hadoop/yarn/lib/jaxb-api-2.3.1.jar" \
#              ${HADOOP_HOME}/share/hadoop/${dir}/lib/ 2>/dev/null || true
#    done
#fi

# ── /etc/hosts ───────────────────────────────────────────────
for entry in \
    "192.168.100.100 srvmaster01" "192.168.100.200 srvmaster02" \
    "192.168.100.101 srvdata01"   "192.168.100.102 srvdata02"   \
    "192.168.100.103 srvdata03";  do
    grep -qF "$entry" /etc/hosts 2>/dev/null || echo "$entry" >> /etc/hosts
done

# ── SSH ──────────────────────────────────────────────────────
mkdir -p /var/run/sshd && /usr/sbin/sshd && sleep 1

# ── ZooKeeper ────────────────────────────────────────────────
log "Configuration ZooKeeper myid=$ZK_ID"
echo "${ZK_ID}" > ${ZOOKEEPER_HOME}/data/myid
chown hadoop:hadoop ${ZOOKEEPER_HOME}/data/myid
su hadoop -c "${ZOOKEEPER_HOME}/bin/zkServer.sh start"
sleep 4

# ── wait_for : vérification TCP ──────────────────────────────
wait_for() {
    local host=$1 port=$2 label=${3:-"$1:$2"} max=${4:-90} i=0
    log "Attente $label ($host:$port)..."
    while ! nc -z "$host" "$port" 2>/dev/null; do
        i=$((i+1)); [ $i -ge $max ] && { warn "$label non dispo après ${max}x2s"; return 1; }
        sleep 2
    done
    log "$label ✓ (${i}x2s)"; return 0
}

# ── Quorum ZK ────────────────────────────────────────────────
for h in srvmaster01 srvmaster02 srvdata01 srvdata02 srvdata03; do
    wait_for $h 2181 "ZK $h" 60 || true
done

# ════════════════════════════════════════════════════════════
case "${NODE_ROLE}" in

"master01")
    # ── NameNode ──────────────────────────────────────────
    if [ ! -d "${HADOOP_HOME}/data/namenode/current" ]; then
        log "Formatage NameNode..."
        su hadoop -c "${HADOOP_HOME}/bin/hdfs namenode \
            -format -force -nonInteractive -clusterid hadoop-lab-cluster" 2>&1 | tail -5 \
            || { err "Formatage échoué !"; exit 1; }
    fi
    log "Démarrage NameNode..."
    su hadoop -c "${HADOOP_HOME}/bin/hdfs --daemon start namenode"
    # FIX : on vérifie le port RPC (9000) ET le WebUI (9870)
    # Le RPC est disponible avant le WebUI → séquencement correct
    wait_for srvmaster01 9000  "NameNode RPC"   60
    wait_for srvmaster01 9870  "NameNode WebUI" 60 || warn "WebUI lent, on continue..."

    # ── ResourceManager ───────────────────────────────────
    log "Démarrage ResourceManager..."
    su hadoop -c "${HADOOP_HOME}/bin/yarn --daemon start resourcemanager"
    wait_for srvmaster01 8032  "RM RPC"    90
    wait_for srvmaster01 8088  "RM WebUI"  90 || warn "RM WebUI lent, on continue..."

    # ── JobHistory ────────────────────────────────────────
    su hadoop -c "${HADOOP_HOME}/bin/mapred --daemon start historyserver" || warn "JobHistory non démarré"

    # ── Attente DataNodes enregistrés ─────────────────────
    log "Attente DataNodes (40s min)..."
    sleep 40

    # ── Répertoires HDFS ──────────────────────────────────
    log "Création répertoires HDFS..."
    su hadoop -c "hdfs dfs -mkdir -p /hbase /user/hadoop /tmp /mr-history/tmp /mr-history/done" 2>/dev/null || true
    su hadoop -c "hdfs dfs -chmod 1777 /tmp"                  2>/dev/null || true
    su hadoop -c "hdfs dfs -chown hadoop:hadoop /user/hadoop"  2>/dev/null || true
    su hadoop -c "hdfs dfs -chown hadoop:hadoop /hbase"        2>/dev/null || true

    # ── HBase Master ──────────────────────────────────────
    log "Démarrage HBase Master..."
    su hadoop -c "JAVA_HOME=${JAVA_HOME} ${HBASE_HOME}/bin/hbase master start &>> ${HBASE_HOME}/logs/hbase-master.log" &
    wait_for srvmaster01 16000 "HBase Master RPC"   120 || warn "HBase Master RPC non dispo"
    wait_for srvmaster01 16010 "HBase Master WebUI" 120 || warn "HBase Master WebUI non dispo"

    # ── Zeppelin ─────────────────────────────────────────
    log "Démarrage Zeppelin..."
    su hadoop -c "${ZEPPELIN_HOME}/bin/zeppelin-daemon.sh start" \
        && log "Zeppelin → http://srvmaster01:8080 ✓" \
        || warn "Zeppelin non démarré - voir ${ZEPPELIN_HOME}/logs/"
    ;;

"master02")
    wait_for srvmaster01 9870  "NameNode WebUI" 120 || true
    log "Démarrage Secondary NameNode..."
    su hadoop -c "${HADOOP_HOME}/bin/hdfs --daemon start secondarynamenode" || warn "SNN non démarré"
    wait_for srvmaster01 16000 "HBase Master RPC" 240
    log "Démarrage HBase Master (backup)..."
    su hadoop -c "JAVA_HOME=${JAVA_HOME} ${HBASE_HOME}/bin/hbase master start &>> ${HBASE_HOME}/logs/hbase-master-backup.log" &
    ;;

"worker")
    wait_for srvmaster01 9000  "NameNode RPC" 120
    wait_for srvmaster01 8032  "RM RPC"       120

    log "Démarrage DataNode..."
    su hadoop -c "${HADOOP_HOME}/bin/hdfs --daemon start datanode"
    wait_for localhost 9864 "DataNode" 60

    log "Démarrage NodeManager..."
    su hadoop -c "${HADOOP_HOME}/bin/yarn --daemon start nodemanager"
    wait_for localhost 8042 "NodeManager" 60

    wait_for srvmaster01 16000 "HBase Master RPC" 240
    log "Démarrage HBase RegionServer..."
    su hadoop -c "JAVA_HOME=${JAVA_HOME} ${HBASE_HOME}/bin/hbase regionserver start \
        &>> ${HBASE_HOME}/logs/hbase-regionserver.log" &
    ;;

*)  err "NODE_ROLE invalide : '${NODE_ROLE}'"; exit 1 ;;
esac

log "=== Tous services démarrés : $HOSTNAME (rôle: $NODE_ROLE) ==="
exec tail -f /dev/null
