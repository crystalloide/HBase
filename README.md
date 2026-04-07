# Handlab Hadoop HBase – Cluster multi-nœuds avec docker compose

## Architecture du cluster

| Conteneur    | IP               | Rôles                                                    |
|-------------|------------------|----------------------------------------------------------|
| srvmaster01  | 192.168.100.100  | NameNode, ResourceManager, HBase Master, ZooKeeper, Zeppelin |
| srvmaster02  | 192.168.100.200  | Secondary NameNode, HBase Backup Master, ZooKeeper       |
| srvdata01    | 192.168.100.101  | DataNode, NodeManager, HBase RegionServer, ZooKeeper     |
| srvdata02    | 192.168.100.102  | DataNode, NodeManager, HBase RegionServer, ZooKeeper     |
| srvdata03    | 192.168.100.103  | DataNode, NodeManager, HBase RegionServer, ZooKeeper     |

## Versions logicielles

| Composant   | Version  | Notes                                    |
|------------|----------|------------------------------------------|
| Java       | OpenJDK 11 | ⚠ HBase 2.6.x exige Java ≥ 11 (voir §Note) |
| ZooKeeper  | 3.7.0    | Ensemble de 5 nœuds                      |
| Hadoop     | 3.1.0    | Non-HA (NameNode unique)                 |
| HBase      | 2.6.4    | ZooKeeper externe                        |
| Zeppelin   | 0.10.1   | Sur srvmaster01 uniquement               |

> **⚠ Note Java** : HBase 2.6.x requiert Java 11+.
- L'image utilise OpenJDK 11.
- Pour utiliser Java 8, remplacer HBase par la version 2.4.x.

## Prérequis

- Docker Engine ≥ 20.10
- Docker Compose v2 (`docker compose`)
- RAM disponible : ≥ 16 Go recommandés (3 Go/conteneur)
- Espace disque : ≥ 20 Go (build initial ~6 Go, Zeppelin ~1 Go)

#### Préparation de l'environnement

```bash
cd ~
# A ne pas faire en production évidemment : 
sudo systemctl stop apparmor
sudo systemctl stop ufw
sudo systemctl disable apparmor
sudo systemctl disable ufw
```

```bash
cd ~
sudo rm -Rf ~/HBase
PWD=~/HBase
```

## Démarrage rapide

```bash
# 1. Cloner/décompresser le projet
git clone https://github.com/crystalloide/HBase
cd ~/HBase/
```

```bash
# 2. Construire l'image (première fois, ~20-30 min selon le réseau)
docker compose build
```

```bash
# 3. Démarrer le cluster
docker compose up -d
```

```bash
# 4. Suivre les logs de srvmaster01
docker compose logs -f srvmaster01
```

```bash
# 5. Vérifier l'état du cluster (attendre ~3-5 min après le démarrage)
docker exec -it srvmaster01 /opt/scripts/cluster-status.sh
```

## Interfaces Web

| Service               | URL                          |
|----------------------|------------------------------|
| HDFS NameNode        | http://localhost:9870        |
| YARN ResourceManager | http://localhost:8088        |
| Secondary NameNode   | http://localhost:9868        |
| HBase Master         | http://localhost:16010       |
| MapReduce History    | http://localhost:19888       |
| Zeppelin             | http://localhost:8080        |

## Accès aux conteneurs

```bash
# Se connecter à srvmaster01
docker exec -it srvmaster01 bash

# Exécuter en tant qu'utilisateur hadoop
docker exec -it srvmaster01 su -l hadoop

# SSH entre conteneurs (depuis srvmaster01)
ssh hadoop@srvmaster01
ssh hadoop@srvmaster02
ssh hadoop@srvdata01
```

## Vérifications post-démarrage

```bash
# État HDFS
docker exec -it srvmaster01 hdfs dfsadmin -report

# Noeuds YARN
docker exec -it srvmaster01 yarn node -list

# État ZooKeeper
docker exec -it srvmaster01 bash -c \
  "echo ruok | nc srvmaster01 2181; echo ruok | nc srvdata01 2181"

# Shell HBase
docker exec -it srvmaster01 hbase shell
# Dans le shell :  status 'detailed'

# Lancer un job MapReduce de test
docker exec -it srvmaster01 bash -c \
  "hdfs dfs -mkdir -p /user/hadoop && \
   hadoop jar /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.1.0.jar \
   pi 2 100"
```

## Arrêt et nettoyage

```bash
# Arrêt propre (données conservées)
docker compose down

# Redémarrage
docker compose up -d

# Réinitialisation complète (SUPPRIME TOUTES LES DONNÉES)
bash scripts/clean-cluster.sh
```

## Structure du projet

```
hadoop-cluster/
├── Dockerfile                    # Image unique pour tous les nœuds
├── docker-compose.yml            # Orchestration des 5 conteneurs
├── conf/
│   ├── hadoop/
│   │   ├── core-site.xml         # URI NameNode, ZK quorum
│   │   ├── hdfs-site.xml         # Réplication, chemins NN/DN
│   │   ├── yarn-site.xml         # ResourceManager, NodeManager
│   │   ├── mapred-site.xml       # Framework MR, mémoire tâches
│   │   ├── hadoop-env.sh         # Variables d'environnement
│   │   └── workers               # Liste des DataNodes/NodeManagers
│   ├── hbase/
│   │   ├── hbase-site.xml        # rootdir HDFS, ZK externe
│   │   ├── hbase-env.sh          # HBASE_MANAGES_ZK=false
│   │   ├── regionservers         # Liste des RegionServers
│   │   └── backup-masters        # HBase backup master
│   └── zookeeper/
│       └── zoo.cfg               # Ensemble ZK 5 nœuds
└── scripts/
    ├── entrypoint.sh             # Démarrage des services par rôle
    ├── cluster-status.sh         # Vérification de l'état
    └── clean-cluster.sh          # Réinitialisation complète
```

## Personnalisation

### Mémoire YARN (yarn-site.xml)
Ajuster `yarn.nodemanager.resource.memory-mb` selon la RAM disponible :
- 8 Go RAM hôte → laisser 4096 MB par nœud
- 16 Go RAM hôte → augmenter à 6144 MB par nœud

### Ajout d'un nœud Data
1. Ajouter un service `srvdata04` dans `docker-compose.yml` (IP: 192.168.100.104, ZK_ID=6)
2. Ajouter `srvdata04` dans `conf/hadoop/workers` et `conf/hbase/regionservers`
3. Ajouter `server.6=srvdata04:2888:3888` dans `conf/zookeeper/zoo.cfg`
4. Reconstruire l'image et redémarrer

## Résolution de problèmes

| Symptôme | Cause probable | Solution |
|---------|----------------|----------|
| DataNodes absents du rapport HDFS | Démarrage trop rapide | `docker compose restart srvdata01 srvdata02 srvdata03` |
| HBase ne démarre pas | HDFS non prêt | Attendre 5 min après le démarrage du cluster |
| Zeppelin inaccessible | Long chargement initial | Attendre 3-5 min, vérifier les logs |
| ZooKeeper en mode standalone | Réseau non prêt | Redémarrer les conteneurs concernés |
