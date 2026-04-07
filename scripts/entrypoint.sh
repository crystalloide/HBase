#!/bin/bash
# ============================================================
#  entrypoint.sh – Point d'entrée commun à tous les conteneurs
#  Démarre les services selon la variable NODE_ROLE :
#    master01 | master02 | worker
# ============================================================

set -euo pipefail

# ── Couleurs pour les logs ───────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] [$HOSTNAME] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] [$HOSTNAME] WARN: $*${NC}"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] [$HOSTNAME] ERROR: $*${NC}"; exit 1; }

# ── Variables par défaut ─────────────────────────────────────
export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}
export HADOOP_HOME=${HADOOP_HOME:-/opt/hadoop}
export HBASE_HOME=${HBASE_HOME:-/opt/hbase}
export ZOOKEEPER_HOME=${ZOOKEEPER_HOME:-/opt/zookeeper}
export ZEPPELIN_HOME=${ZEPPELIN_HOME:-/opt/zeppelin}
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export PATH=$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$ZEPPELIN_HOME/bin:$PATH

NODE_ROLE=${NODE_ROLE:-worker}
ZK_ID=${ZK_ID:-1}

log "=== Démarrage du nœud : $HOSTNAME | Rôle : $NODE_ROLE | ZK_ID : $ZK_ID ==="

# ── Entrées /etc/hosts (résolution robuste) ──────────────────
add_hosts() {
    for entry in \
        "192.168.100.100 srvmaster01" \
        "192.168.100.200 srvmaster02" \
        "192.168.100.101 srvdata01"   \
        "192.168.100.102 srvdata02"   \
        "192.168.100.103 srvdata03";  do
        grep -qF "$entry" /etc/hosts || echo "$entry" >> /etc/hosts
    done
}
add_hosts

# ── Démarrage SSH ────────────────────────────────────────────
log "Démarrage du daemon SSH..."
mkdir -p /var/run/sshd
/usr/sbin/sshd
sleep 1

# ── Configuration ZooKeeper myid ─────────────────────────────
log "Configuration ZooKeeper myid=$ZK_ID"
mkdir -p $ZOOKEEPER_HOME/data $ZOOKEEPER_HOME/logs
echo "${ZK_ID}" > $ZOOKEEPER_HOME/data/myid

# ── Démarrage ZooKeeper ──────────────────────────────────────
log "Démarrage de ZooKeeper 3.7.0..."
su hadoop -c "$ZOOKEEPER_HOME/bin/zkServer.sh start"
sleep 3

# ── Fonction d'attente réseau ────────────────────────────────
wait_for() {
    local host=$1 port=$2 label=${3:-"$1:$2"} max=${4:-90} i=0
    log "Attente de $label..."
    while ! nc -z "$host" "$port" 2>/dev/null; do
        i=$((i+1))
        [ $i -ge $max ] && { warn "$label non disponible après ${max}s, on continue"; return; }
        sleep 2
    done
    log "$label est prêt ✓"
}

# ── Attente du quorum ZooKeeper ──────────────────────────────
log "Attente du quorum ZooKeeper (5 nœuds)..."
wait_for srvmaster01 2181 "ZK srvmaster01" 120
wait_for srvmaster02 2181 "ZK srvmaster02" 120
wait_for srvdata01   2181 "ZK srvdata01"   120
wait_for srvdata02   2181 "ZK srvdata02"   120
wait_for srvdata03   2181 "ZK srvdata03"   120
log "Quorum ZooKeeper établi ✓"

# ════════════════════════════════════════════════════════════
#  Démarrage selon le rôle
# ════════════════════════════════════════════════════════════

case "${NODE_ROLE}" in

# ─────────────────────────────────────────────────────────────
#  MASTER01 : NameNode | ResourceManager | HBase Master | Zeppelin
# ─────────────────────────────────────────────────────────────
"master01")
    # Formatage HDFS (première fois seulement)
    if [ ! -d "${HADOOP_HOME}/data/namenode/current" ]; then
        log "Formatage du NameNode HDFS (première initialisation)..."
        su hadoop -c "$HADOOP_HOME/bin/hdfs namenode -format -force -nonInteractive \
            -clusterid hadoop-lab-cluster" 2>&1 | tail -5
        log "Formatage terminé ✓"
    else
        log "NameNode déjà formaté, pas de reformatage."
    fi

    # NameNode
    log "Démarrage du NameNode HDFS..."
    su hadoop -c "$HADOOP_HOME/bin/hdfs --daemon start namenode"
    wait_for localhost 9870 "NameNode WebUI" 60

    # ResourceManager
    log "Démarrage du ResourceManager YARN..."
    su hadoop -c "$HADOOP_HOME/bin/yarn --daemon start resourcemanager"
    wait_for localhost 8088 "ResourceManager WebUI" 60

    # JobHistory Server
    log "Démarrage du JobHistory Server..."
    su hadoop -c "$HADOOP_HOME/bin/mapred --daemon start historyserver"

    # Attente des DataNodes
    log "Attente des DataNodes (30s)..."
    sleep 30

    # Création des répertoires HDFS
    log "Création des répertoires HDFS..."
    su hadoop -c "hdfs dfs -mkdir -p /hbase /user/hadoop /tmp" 2>/dev/null || true
    su hadoop -c "hdfs dfs -chmod 1777 /tmp" 2>/dev/null || true
    su hadoop -c "hdfs dfs -chown hadoop:hadoop /user/hadoop" 2>/dev/null || true
    log "Répertoires HDFS créés ✓"

    # HBase Master (actif)
    log "Démarrage du HBase Master (actif)..."
    su hadoop -c "$HBASE_HOME/bin/hbase master start" &
    wait_for localhost 16010 "HBase Master WebUI" 90

    # Zeppelin
    log "Démarrage de Zeppelin 0.10.1..."
    su hadoop -c "$ZEPPELIN_HOME/bin/zeppelin-daemon.sh start"
    log "Zeppelin disponible sur http://srvmaster01:8080 ✓"
    ;;

# ─────────────────────────────────────────────────────────────
#  MASTER02 : Secondary NameNode | HBase Master (backup)
# ─────────────────────────────────────────────────────────────
"master02")
    # Attente du NameNode principal
    wait_for srvmaster01 9870 "NameNode srvmaster01" 120

    # Secondary NameNode
    log "Démarrage du Secondary NameNode..."
    su hadoop -c "$HADOOP_HOME/bin/hdfs --daemon start secondarynamenode"
    wait_for localhost 9868 "Secondary NameNode" 60

    # HBase Master (backup — s'enregistre comme standby via ZooKeeper)
    log "Démarrage du HBase Master (backup)..."
    wait_for srvmaster01 16000 "HBase Master srvmaster01" 120
    su hadoop -c "$HBASE_HOME/bin/hbase master start" &
    log "HBase Backup Master démarré (standby via ZooKeeper) ✓"
    ;;

# ─────────────────────────────────────────────────────────────
#  WORKER : DataNode | NodeManager | HBase RegionServer
# ─────────────────────────────────────────────────────────────
"worker")
    # Attente du NameNode et ResourceManager
    wait_for srvmaster01 9000 "NameNode RPC srvmaster01" 120
    wait_for srvmaster01 8032 "ResourceManager RPC srvmaster01" 120

    # DataNode
    log "Démarrage du DataNode HDFS..."
    su hadoop -c "$HADOOP_HOME/bin/hdfs --daemon start datanode"
    wait_for localhost 9864 "DataNode" 60

    # NodeManager
    log "Démarrage du NodeManager YARN..."
    su hadoop -c "$HADOOP_HOME/bin/yarn --daemon start nodemanager"
    wait_for localhost 8042 "NodeManager" 60

    # HBase RegionServer
    log "Démarrage du HBase RegionServer..."
    wait_for srvmaster01 16000 "HBase Master RPC" 120
    su hadoop -c "$HBASE_HOME/bin/hbase regionserver start" &
    log "HBase RegionServer démarré ✓"
    ;;

*)
    err "NODE_ROLE invalide : '${NODE_ROLE}'. Valeurs attendues : master01 | master02 | worker"
    ;;
esac

log "=== Tous les services démarrés pour $HOSTNAME (rôle: $NODE_ROLE) ==="

# ── Maintien du conteneur actif ──────────────────────────────
exec tail -f /dev/null
