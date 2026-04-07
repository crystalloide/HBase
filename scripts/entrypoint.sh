#!/bin/bash
# entrypoint.sh – v5
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')] [$HOSTNAME] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] [$HOSTNAME] WARN: $*${NC}"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] [$HOSTNAME] ERROR: $*${NC}"; }
diag() { echo -e "${CYAN}[$(date '+%H:%M:%S')] [$HOSTNAME] DIAG: $*${NC}"; }

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
export HBASE_MANAGES_ZK=false
export PATH=$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$HBASE_HOME/bin:$ZOOKEEPER_HOME/bin:$ZEPPELIN_HOME/bin:$PATH

NODE_ROLE=${NODE_ROLE:-worker}
ZK_ID=${ZK_ID:-1}

# IPs fixes – utilisées dans wait_for pour éviter le flapping DNS
IP_MASTER01="192.168.100.100"
IP_MASTER02="192.168.100.200"
IP_DATA01="192.168.100.101"
IP_DATA02="192.168.100.102"
IP_DATA03="192.168.100.103"

log "=== Démarrage : $HOSTNAME | Rôle : $NODE_ROLE | ZK_ID : $ZK_ID ==="

# ── Permissions ──────────────────────────────────────────────
mkdir -p ${HADOOP_HOME}/data/{namenode,datanode,secondarynamenode,tmp} \
         ${HADOOP_HOME}/logs ${HBASE_HOME}/logs \
         ${ZOOKEEPER_HOME}/data ${ZOOKEEPER_HOME}/logs
chown -R hadoop:hadoop \
    ${HADOOP_HOME}/data ${HADOOP_HOME}/logs \
    ${HBASE_HOME}/logs ${ZOOKEEPER_HOME}/data ${ZOOKEEPER_HOME}/logs

# ── PID résiduels ────────────────────────────────────────────
rm -f /tmp/*.pid ${ZOOKEEPER_HOME}/data/zookeeper_server.pid 2>/dev/null || true
pkill -9 -f "proc_namenode\|proc_datanode\|proc_resourcemanager\|proc_nodemanager\|JobHistoryServer\|HMaster\|HRegionServer" 2>/dev/null || true
sleep 2


# ── /etc/hosts (filet de sécurité si DNS Docker lent) ────────
for entry in \
    "${IP_MASTER01} srvmaster01" "${IP_MASTER02} srvmaster02" \
    "${IP_DATA01} srvdata01"     "${IP_DATA02} srvdata02"     \
    "${IP_DATA03} srvdata03";    do
    grep -qF "$(echo $entry | awk '{print $2}')" /etc/hosts 2>/dev/null \
        || echo "$entry" >> /etc/hosts
done

# ── SSH ──────────────────────────────────────────────────────
mkdir -p /var/run/sshd && /usr/sbin/sshd && sleep 1

# ── ZooKeeper ────────────────────────────────────────────────
log "ZooKeeper myid=$ZK_ID"
echo "${ZK_ID}" > ${ZOOKEEPER_HOME}/data/myid
chown hadoop:hadoop ${ZOOKEEPER_HOME}/data/myid
su hadoop -c "${ZOOKEEPER_HOME}/bin/zkServer.sh start"
sleep 4

# ════════════════════════════════════════════════════════════
# wait_for : TOUJOURS sur IP fixe pour éviter le flapping DNS
#   $1=IP  $2=port  $3=label  $4=max_retries (défaut: 150=5min)
# ════════════════════════════════════════════════════════════
wait_for() {
    local ip=$1 port=$2 label=${3:-"$1:$2"} max=${4:-150} i=0
    log "Attente $label (${ip}:${port})..."
    while ! nc -z -w 2 "$ip" "$port" 2>/dev/null; do
        i=$((i+1))
        if [ $i -ge $max ]; then
            warn "$label non dispo après $((max*2))s"
            diag "Test réseau: ping ${ip}=$(ping -c1 -W1 ${ip} 2>/dev/null | grep -c '1 received') | port=${port}"
            return 1
        fi
        # Log de progression toutes les 30 tentatives (~1 min)
        [ $((i % 30)) -eq 0 ] && diag "$label : toujours en attente (${i}x2s)..."
        sleep 2
    done
    log "$label ✓ (${i}x2s)"; return 0
}

# ── Quorum ZK : IP fixes ─────────────────────────────────────
for ip in $IP_MASTER01 $IP_MASTER02 $IP_DATA01 $IP_DATA02 $IP_DATA03; do
    wait_for $ip 2181 "ZK $ip" 60 || true
done
log "Quorum ZooKeeper OK ✓"

# ════════════════════════════════════════════════════════════
case "${NODE_ROLE}" in

"master01")
    if [ ! -d "${HADOOP_HOME}/data/namenode/current" ]; then
        log "Formatage NameNode HDFS..."
        su hadoop -c "${HADOOP_HOME}/bin/hdfs namenode \
            -format -force -nonInteractive -clusterid hadoop-lab-cluster" \
            2>&1 | tail -5 || { err "Formatage NN échoué !"; exit 1; }
    fi
    log "Démarrage NameNode..."
    su hadoop -c "${HADOOP_HOME}/bin/hdfs --daemon start namenode"
    sleep 5
    # Vérifier sur l'IP locale (127.0.0.1) ET l'IP publique
    wait_for 127.0.0.1     9000 "NameNode RPC (local)"  60 \
        || wait_for ${IP_MASTER01} 9000 "NameNode RPC (IP)" 30 \
        || { err "NameNode RPC non dispo !"; cat ${HADOOP_HOME}/logs/hadoop-hadoop-namenode-*.log 2>/dev/null | tail -20; }

    log "Démarrage ResourceManager..."
    su hadoop -c "${HADOOP_HOME}/bin/yarn --daemon start resourcemanager"
    sleep 5
    wait_for 127.0.0.1 8032 "RM RPC"    90 || warn "RM RPC non dispo (voir logs)"
    wait_for 127.0.0.1 8088 "RM WebUI"  60 || warn "RM WebUI non dispo"

    su hadoop -c "${HADOOP_HOME}/bin/mapred --daemon start historyserver" \
        || warn "JobHistory non démarré"

    log "Attente DataNodes (45s)..."
    sleep 45

    log "Répertoires HDFS..."
    for dir in /hbase /user/hadoop /tmp /mr-history/tmp /mr-history/done; do
        su hadoop -c "hdfs dfs -mkdir -p $dir" 2>/dev/null || true
    done
    su hadoop -c "hdfs dfs -chmod 1777 /tmp" 2>/dev/null || true
    su hadoop -c "hdfs dfs -chown hadoop:hadoop /user/hadoop /hbase" 2>/dev/null || true

    log "Démarrage HBase Master..."
    su hadoop -c "HBASE_MANAGES_ZK=false ${HBASE_HOME}/bin/hbase master start \
        >> ${HBASE_HOME}/logs/hbase-master.log 2>&1" &
    wait_for 127.0.0.1 16000 "HBase Master RPC"   120 || warn "HBase Master RPC non dispo"
    wait_for 127.0.0.1 16010 "HBase Master WebUI" 60  || warn "HBase Master WebUI non dispo"

    log "Démarrage Zeppelin..."
    su hadoop -c "${ZEPPELIN_HOME}/bin/zeppelin-daemon.sh start" \
        && log "Zeppelin ✓ → http://srvmaster01:8080" \
        || warn "Zeppelin non démarré"
    ;;

"master02")
    wait_for ${IP_MASTER01} 9870 "NameNode WebUI" 180 || true
    su hadoop -c "${HADOOP_HOME}/bin/hdfs --daemon start secondarynamenode" \
        || warn "SNN non démarré"
    wait_for ${IP_MASTER01} 16000 "HBase Master RPC" 300 || true
    su hadoop -c "HBASE_MANAGES_ZK=false ${HBASE_HOME}/bin/hbase master start \
        >> ${HBASE_HOME}/logs/hbase-master-backup.log 2>&1" &
    ;;

"worker")
    # Attente sur IP fixes → aucune dépendance DNS
    wait_for ${IP_MASTER01} 9000  "NameNode RPC" 300 \
        || { warn "NameNode injoignable, on démarre quand même DataNode"; }
    wait_for ${IP_MASTER01} 8032  "RM RPC"       300 \
        || { warn "ResourceManager injoignable, NodeManager risque d'échouer"; }

    log "Démarrage DataNode..."
    su hadoop -c "${HADOOP_HOME}/bin/hdfs --daemon start datanode"
    wait_for 127.0.0.1 9864 "DataNode local" 60

    log "Démarrage NodeManager..."
    su hadoop -c "${HADOOP_HOME}/bin/yarn --daemon start nodemanager"
    wait_for 127.0.0.1 8042 "NodeManager local" 60

    wait_for ${IP_MASTER01} 16000 "HBase Master RPC" 300 || true
    log "Démarrage HBase RegionServer..."
    su hadoop -c "HBASE_MANAGES_ZK=false ${HBASE_HOME}/bin/hbase regionserver start \
        >> ${HBASE_HOME}/logs/hbase-regionserver.log 2>&1" &
    ;;

*)  err "NODE_ROLE invalide : '${NODE_ROLE}'"; exit 1 ;;
esac

log "=== Services démarrés : $HOSTNAME (${NODE_ROLE}) ==="
exec tail -f /dev/null
