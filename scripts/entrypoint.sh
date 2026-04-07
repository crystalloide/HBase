#!/bin/bash
# ============================================================
#  entrypoint.sh – v2 (corrections permissions + PID stales)
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] [$HOSTNAME] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] [$HOSTNAME] WARN: $*${NC}"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] [$HOSTNAME] ERROR: $*${NC}"; exit 1; }

# ── Variables ────────────────────────────────────────────────
export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}
export HADOOP_HOME=${HADOOP_HOME:-/opt/hadoop}
export HBASE_HOME=${HBASE_HOME:-/opt/hbase}
export ZOOKEEPER_HOME=${ZOOKEEPER_HOME:-/opt/zookeeper}
export ZEPPELIN_HOME=${ZEPPELIN_HOME:-/opt/zeppelin}
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export PATH=$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$ZEPPELIN_HOME/bin:$PATH

NODE_ROLE=${NODE_ROLE:-worker}
ZK_ID=${ZK_ID:-1}

log "=== Démarrage : $HOSTNAME | Rôle : $NODE_ROLE | ZK_ID : $ZK_ID ==="

# ════════════════════════════════════════════════════════════
#  FIX 1 – Permissions sur les volumes (root → hadoop)
#  Les volumes Docker sont créés avec owner root.
#  On corrige au démarrage, avant tout su hadoop.
# ════════════════════════════════════════════════════════════
log "[FIX1] Correction des permissions sur les répertoires de données..."
mkdir -p \
    ${HADOOP_HOME}/data/namenode \
    ${HADOOP_HOME}/data/datanode \
    ${HADOOP_HOME}/data/secondarynamenode \
    ${HADOOP_HOME}/data/tmp \
    ${HADOOP_HOME}/logs \
    ${HBASE_HOME}/logs \
    ${ZOOKEEPER_HOME}/data \
    ${ZOOKEEPER_HOME}/logs

chown -R hadoop:hadoop \
    ${HADOOP_HOME}/data \
    ${HADOOP_HOME}/logs \
    ${HBASE_HOME}/logs \
    ${ZOOKEEPER_HOME}/data \
    ${ZOOKEEPER_HOME}/logs
log "[FIX1] Permissions corrigées ✓"

# ════════════════════════════════════════════════════════════
#  FIX 2 – Nettoyage des fichiers PID résiduels
#  Docker restart ne recrée pas le conteneur → PID stales
#  dans /tmp font croire à Hadoop qu'un daemon tourne encore.
# ════════════════════════════════════════════════════════════
log "[FIX2] Nettoyage des fichiers PID résiduels..."
rm -f \
    /tmp/hadoop-hadoop-namenode.pid \
    /tmp/hadoop-hadoop-datanode.pid \
    /tmp/hadoop-hadoop-secondarynamenode.pid \
    /tmp/hadoop-hadoop-resourcemanager.pid \
    /tmp/hadoop-hadoop-nodemanager.pid \
    /tmp/mapred-hadoop-historyserver.pid \
    /tmp/hbase-hadoop-master.pid \
    /tmp/hbase-hadoop-regionserver.pid \
    /tmp/hbase-hadoop-zookeeper.pid \
    ${ZOOKEEPER_HOME}/data/zookeeper_server.pid 2>/dev/null || true

# Tuer les éventuels processus zombies Java restants
pkill -f "proc_namenode"          2>/dev/null || true
pkill -f "proc_datanode"          2>/dev/null || true
pkill -f "proc_secondarynamenode" 2>/dev/null || true
pkill -f "proc_resourcemanager"   2>/dev/null || true
pkill -f "proc_nodemanager"       2>/dev/null || true
pkill -f "JobHistoryServer"       2>/dev/null || true
pkill -f "HMaster"                2>/dev/null || true
pkill -f "HRegionServer"          2>/dev/null || true
sleep 2
log "[FIX2] Nettoyage PID terminé ✓"

# ── /etc/hosts ───────────────────────────────────────────────
for entry in \
    "192.168.100.100 srvmaster01" \
    "192.168.100.200 srvmaster02" \
    "192.168.100.101 srvdata01"   \
    "192.168.100.102 srvdata02"   \
    "192.168.100.103 srvdata03";  do
    grep -qF "$entry" /etc/hosts 2>/dev/null || echo "$entry" >> /etc/hosts
done

# ── SSH ──────────────────────────────────────────────────────
log "Démarrage du daemon SSH..."
mkdir -p /var/run/sshd
/usr/sbin/sshd
sleep 1

# ── ZooKeeper myid ───────────────────────────────────────────
log "Configuration ZooKeeper myid=$ZK_ID"
echo "${ZK_ID}" > ${ZOOKEEPER_HOME}/data/myid
chown hadoop:hadoop ${ZOOKEEPER_HOME}/data/myid

# ── Démarrage ZooKeeper ──────────────────────────────────────
log "Démarrage de ZooKeeper 3.7.0..."
su hadoop -c "${ZOOKEEPER_HOME}/bin/zkServer.sh start"
sleep 3

# ── Fonction d'attente réseau ────────────────────────────────
wait_for() {
    local host=$1 port=$2 label=${3:-"$1:$2"} max=${4:-90} i=0
    log "Attente de $label..."
    while ! nc -z "$host" "$port" 2>/dev/null; do
        i=$((i+1))
        [ $i -ge $max ] && { warn "$label non disponible après ${max}x2s"; return; }
        sleep 2
    done
    log "$label prêt ✓"
}

# ── Quorum ZooKeeper ─────────────────────────────────────────
log "Attente du quorum ZooKeeper..."
wait_for srvmaster01 2181 "ZK srvmaster01" 120
wait_for srvmaster02 2181 "ZK srvmaster02" 120
wait_for srvdata01   2181 "ZK srvdata01"   120
wait_for srvdata02   2181 "ZK srvdata02"   120
wait_for srvdata03   2181 "ZK srvdata03"   120
log "Quorum ZooKeeper établi ✓"

# ════════════════════════════════════════════════════════════
#  Démarrage par rôle
# ════════════════════════════════════════════════════════════
case "${NODE_ROLE}" in

"master01")
    # Formatage HDFS (première fois uniquement)
    if [ ! -d "${HADOOP_HOME}/data/namenode/current" ]; then
        log "Formatage du NameNode HDFS..."
        su hadoop -c "${HADOOP_HOME}/bin/hdfs namenode \
            -format -force -nonInteractive \
            -clusterid hadoop-lab-cluster" 2>&1 | tail -5 \
            || err "Échec du formatage NameNode !"
        log "Formatage terminé ✓"
    else
        log "NameNode déjà formaté → pas de reformatage."
    fi

    log "Démarrage du NameNode HDFS..."
    su hadoop -c "${HADOOP_HOME}/bin/hdfs --daemon start namenode"
    wait_for localhost 9870 "NameNode WebUI" 60

    log "Démarrage du ResourceManager YARN..."
    su hadoop -c "${HADOOP_HOME}/bin/yarn --daemon start resourcemanager"
    wait_for localhost 8088 "ResourceManager WebUI" 60

    log "Démarrage du JobHistory Server..."
    su hadoop -c "${HADOOP_HOME}/bin/mapred --daemon start historyserver"

    log "Attente des DataNodes (30s)..."
    sleep 30

    log "Création des répertoires HDFS..."
    su hadoop -c "hdfs dfs -mkdir -p /hbase /user/hadoop /tmp" 2>/dev/null || true
    su hadoop -c "hdfs dfs -chmod 1777 /tmp"                  2>/dev/null || true
    su hadoop -c "hdfs dfs -chown hadoop:hadoop /user/hadoop"  2>/dev/null || true

    log "Démarrage du HBase Master (actif)..."
    su hadoop -c "${HBASE_HOME}/bin/hbase master start" &
    wait_for localhost 16010 "HBase Master WebUI" 90

    log "Démarrage de Zeppelin..."
    su hadoop -c "${ZEPPELIN_HOME}/bin/zeppelin-daemon.sh start"
    log "Zeppelin → http://srvmaster01:8080 ✓"
    ;;

"master02")
    wait_for srvmaster01 9870 "NameNode srvmaster01" 120
    log "Démarrage du Secondary NameNode..."
    su hadoop -c "${HADOOP_HOME}/bin/hdfs --daemon start secondarynamenode"
    wait_for localhost 9868 "Secondary NameNode" 60

    wait_for srvmaster01 16000 "HBase Master srvmaster01" 120
    log "Démarrage du HBase Master (backup)..."
    su hadoop -c "${HBASE_HOME}/bin/hbase master start" &
    ;;

"worker")
    wait_for srvmaster01 9000 "NameNode RPC"        120
    wait_for srvmaster01 8032 "ResourceManager RPC" 120

    log "Démarrage du DataNode HDFS..."
    su hadoop -c "${HADOOP_HOME}/bin/hdfs --daemon start datanode"
    wait_for localhost 9864 "DataNode" 60

    log "Démarrage du NodeManager YARN..."
    su hadoop -c "${HADOOP_HOME}/bin/yarn --daemon start nodemanager"
    wait_for localhost 8042 "NodeManager" 60

    wait_for srvmaster01 16000 "HBase Master RPC" 120
    log "Démarrage du HBase RegionServer..."
    su hadoop -c "${HBASE_HOME}/bin/hbase regionserver start" &
    ;;

*)
    err "NODE_ROLE invalide : '${NODE_ROLE}'. Valeurs : master01 | master02 | worker"
    ;;
esac

log "=== Services démarrés pour $HOSTNAME (rôle: $NODE_ROLE) ==="
exec tail -f /dev/null
