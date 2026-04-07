#!/bin/bash
# ============================================================
#  clean-cluster.sh – Réinitialise complètement le cluster
#  ⚠ ATTENTION : supprime toutes les données persistantes !
#  À exécuter depuis le répertoire HBase/ sur l'hôte
# ============================================================

echo "⚠ Arrêt et suppression de tous les conteneurs..."
docker compose down -v --remove-orphans

echo "Suppression des volumes nommés..."
docker volume rm -f \
    hadoop-cluster_namenode-data \
    hadoop-cluster_secondarynamenode-data \
    hadoop-cluster_datanode1-data \
    hadoop-cluster_datanode2-data \
    hadoop-cluster_datanode3-data \
    hadoop-cluster_zk1-data \
    hadoop-cluster_zk2-data \
    hadoop-cluster_zk3-data \
    hadoop-cluster_zk4-data \
    hadoop-cluster_zk5-data 2>/dev/null || true

echo "Suppression de l'image..."
docker rmi hadoop-lab:latest 2>/dev/null || true

echo "✓ Cluster réinitialisé. Relancer avec : docker compose up --build -d"
