# Lab 8 · Une application dégradée

> Partie 10 des supports · Mécanismes : skill `/diagnostic-k8s`, hook `garde-kubectl`, permissions de lecture et actions bornées · Prérequis : lab 7 ; Docker, k3d, kubectl, Python 3 et jq

## Pourquoi ce lab

L'application fonctionne dans Compose ; son déploiement Kubernetes présente trois symptômes différents. Un redémarrage ne répare ni un nom d'image incorrect, ni une sonde qui vise une route absente, ni un nom de service erroné. Le rôle de l'agent est de relier chaque symptôme à un indice, puis à un changement précis du manifeste.

Le hook vérifie le contexte `k3d-formation` avant chaque commande directe `kubectl` ou `helm`. Les permissions distinguent les lectures des actions de modification. Ce dispositif pédagogique complète les contrôles humains ; il ne remplace pas un compte Kubernetes limité par RBAC et n'empêche pas tout accès indirect à l'API.

## Objectifs

- Créer un cluster local et y importer les quatre images du lab 7.
- Déployer PostgreSQL avec stockage persistant et des secrets fournis à l'exécution.
- Prouver trois causes distinctes avant de corriger les manifestes.
- Vérifier le retour au fonctionnement, y compris la création d'une commande.
- Démontrer qu'un contexte inattendu bloque les commandes de l'agent.

## Point de départ

Votre copie à la fin du lab 7, commitée, et les images `ecommerce/catalog:1.0`, `ordering:1.0`, `gateway:1.0`, `web:1.0`. Arrêtez le Compose (`docker compose down`, sans `-v`) pour libérer les ports 5067 et 5190. Les outils doivent être disponibles : `k3d version`, `kubectl version --client`, `python3 --version`, `jq --version`.

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/lab8-kubernetes/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

## Mise en situation

La recette ne peut plus passer une commande. Un collègue a préparé les manifestes et affirme que « tous les pods vont finir par démarrer ». Vous devez expliquer les états observés, remettre les ressources en état et rendre le diagnostic reproductible.

## Étapes

### Étape 1 · Préparer le cluster et les manifestes

Depuis la racine de votre copie, dans votre terminal :

```bash
git switch -c deploiement/kubernetes
k3d cluster create formation --agents 1 --wait
kubectl config current-context                     # k3d-formation
k3d image import -c formation ecommerce/catalog:1.0 ecommerce/ordering:1.0 ecommerce/gateway:1.0 ecommerce/web:1.0
cp -R "$FORMATION"/labs/lab8-kubernetes/ressources/k8s-degrade/. k8s/
kubectl apply -f k8s/00-namespace.yaml
```

La création du cluster et du namespace est une préparation humaine. Les commandes de diagnostic de l'agent doivent indiquer `-n ecommerce` ; le hook refuse une portée globale, un changement de connexion et les commandes shell composées contenant `kubectl` ou `helm`.

### Étape 2 · Fournir le secret à l'exécution

Dans votre terminal, générez un mot de passe et conservez-le pour le volume PostgreSQL de ce lab. Ne le collez pas dans la conversation :

```bash
export POSTGRES_PASSWORD="$(openssl rand -hex 24)"
bash "$FORMATION"/labs/lab8-kubernetes/ressources/creer-secret.sh ecommerce
unset POSTGRES_PASSWORD
kubectl apply -f k8s/10-postgres.yaml
kubectl rollout status statefulset/postgres -n ecommerce --timeout=180s
kubectl apply -f k8s/20-apps.yaml
```

Le script crée le Secret `ecommerce-db` avec les clés `POSTGRES_PASSWORD`, `ConnectionStrings__catalogdb` et `ConnectionStrings__orderingdb`. Les valeurs transitent dans un fichier temporaire de permissions restreintes et un pipe, puis sont supprimées. Le manifeste ne contient que des `secretKeyRef`. Un Secret Kubernetes doit rester hors de Git, même encodé en base64. Ne lancez pas `kubectl get secret -o yaml` et ne capturez pas de variables sensibles.

PostgreSQL monte un PVC ; les migrations de chaque API créent leur propre base au démarrage. L'image PostgreSQL standard initialise les droits du volume via son entrée de démarrage ; seuls les quatre services .NET sont configurés avec l'UID non-root 1654. Ce PostgreSQL singleton est un choix de lab local, sans haute disponibilité.

### Étape 3 · Diagnostiquer sans corriger au hasard

Lisez `.claude/skills/diagnostic-k8s/SKILL.md` et le hook, puis :

```text
/diagnostic-k8s La recette ne peut plus créer de commande. Collecte d'abord les indices
sur les pods, événements, sondes, Services et EndpointSlices. Pour chaque hypothèse,
cite l'indice qui la confirme ou l'écarte. Ne change rien tant que la cause n'est pas
prouvée. Ne lis aucune valeur de Secret. Code et commentaires de l'application en anglais.
```

Lectures utiles, une commande par appel :

```bash
kubectl get pods -n ecommerce
kubectl get events -n ecommerce --sort-by=.lastTimestamp
kubectl describe deployment ordering -n ecommerce
kubectl describe deployment catalog -n ecommerce
kubectl get endpointslices -n ecommerce
kubectl logs deployment/gateway -n ecommerce --tail=80
```

Trois pannes sont présentes. Résolvez d'abord le démarrage d'Ordering, puis la disponibilité de Catalog, puis le routage Gateway → Ordering. Si une commande `logs --previous` répond qu'aucun conteneur précédent n'existe, cela ne constitue pas une erreur du cluster : le pod n'a pas redémarré.

Pour la dernière panne, démarrez le port-forward dans un terminal séparé et laissez-le ouvert :

```bash
kubectl port-forward service/gateway -n ecommerce 5067:8080
```

Dans un autre terminal, interrogez le catalogue et la liste des commandes via la passerelle. Le statut HTTP, les logs YARP et la variable de découverte de services doivent désigner la même cause.

### Étape 4 · Corriger les sources et appliquer

```text
Pour chaque cause prouvée, corrige uniquement le champ concerné dans k8s/20-apps.yaml.
Explique le diff et l'indice qui justifie ce changement. Présente l'application du
manifeste au contrôle de permission puis vérifie le rollout et le symptôme initial.
```

```bash
kubectl apply -f k8s/20-apps.yaml
kubectl rollout status deployment/catalog -n ecommerce --timeout=180s
kubectl rollout status deployment/ordering -n ecommerce --timeout=180s
kubectl rollout status deployment/gateway -n ecommerce --timeout=180s
kubectl rollout status deployment/web -n ecommerce --timeout=180s
```

Le corrigé utilise des sondes TCP : en `Production`, le code du projet ne mappe ni `/health` ni `/alive`. La [documentation Kubernetes des sondes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) explique la différence entre démarrage, disponibilité et vie du conteneur. Ici TCP prouve que le processus écoute ; le parcours HTTP prouve les interactions métier.

### Étape 5 · Vérifier le parcours et la persistance

Avec le port-forward Gateway ouvert :

```bash
bash .claude/skills/smoke-test/smoke.sh
curl -fsS http://localhost:5067/ordering/api/orders | jq length
```

La passerelle doit déjà répondre : si `smoke.sh` tente de démarrer l'AppHost, interrompez-le et vérifiez le port-forward. Dans un troisième terminal :

```bash
kubectl port-forward service/web -n ecommerce 5190:8080
```

Ouvrez `http://localhost:5190`, vérifiez `/_framework/blazor.web.js` et créez une commande. Notez le nombre de commandes, puis redémarrez les API avec `kubectl rollout restart deployment/catalog -n ecommerce` et `kubectl rollout restart deployment/ordering -n ecommerce`. Attendez les rollouts : le nombre de commandes reste identique. Ne supprimez ni PVC ni cluster pour ce contrôle.

### Étape 6 · Mettre le hook à l'épreuve

Ce test ne modifie pas votre vrai contexte : on place un faux exécutable `kubectl` en tête d'un `PATH` temporaire. Utilisez le test fourni depuis la copie :

```bash
bash "$FORMATION"/labs/lab8-kubernetes/ressources/tester-garde.sh ~/lab-ecommerce
```

Il doit afficher `GARDE OK` : lectures ciblées autorisées dans le contexte attendu, autre contexte et surcharges refusés. Exécutez également une lecture réelle depuis Claude ; le hook doit la laisser passer. Le test du hook ne remplace pas l'inspection des permissions de votre compte.

### Étape 7 · Livrer

Archivez les preuves, relisez `git diff`, puis `/ship Déploiement Kubernetes et diagnostic de trois pannes`. Fermez les port-forwards avec Ctrl+C. Conservez le cluster, les PVC et les images pour le lab 9.

## Critères d'acceptation

- [ ] Les cinq charges de travail sont disponibles dans `ecommerce`.
- [ ] Trois diagnostics comportent chacun symptôme, indice cité, cause, diff minimal et résultat après.
- [ ] Les quatre services .NET tournent avec `runAsNonRoot` et UID 1654, sans shell ajouté.
- [ ] Sondes compatibles avec `Production`, demandes et limites de ressources définies.
- [ ] Secret créé à l'exécution ; aucune donnée de Secret ni mot de passe en Git.
- [ ] Test de fumée, interface interactive et persistance des commandes vérifiés.
- [ ] Hook bloquant sur un autre contexte, sans changer votre configuration réelle.

## Preuves à fournir

Sous `preuves/lab8/` : tableau des trois diagnostics, extraits de commandes sans secrets, diff des manifestes, état des pods avant/après, résultats du test de fumée et de persistance, capture du parcours Web et sortie `GARDE OK`. Distinguez ce que le hook a testé de ce que le cluster a réellement exécuté.

## Aides progressives

<details><summary>Indice 1 · Ordering ne démarre jamais</summary>

Comparez exactement le tag demandé dans les événements et celui des images importées. Un caractère visuellement proche peut suffire ; ne changez pas la politique de tirage pour masquer une faute dans le nom.
</details>

<details><summary>Indice 2 · Catalog est Running mais pas Ready</summary>

La sonde utilise `/health` alors que `ASPNETCORE_ENVIRONMENT=Production`. Relisez `MapDefaultEndpoints` dans ServiceDefaults ; corrigez la sonde sans passer l'application en Development.
</details>

<details><summary>Indice 3 · Le catalogue fonctionne, les commandes renvoient 502</summary>

Comparez `services__ordering__http__0` avec le nom réel du Service. Une résolution DNS invalide côté Gateway est indépendante des sondes des API.
</details>

<details><summary>Indice 4 · PostgreSQL refuse le mot de passe</summary>

Le mot de passe initialise le volume une seule fois. Le remplacement du Secret ne change pas celui d'un volume existant. Rétablissez la valeur d'origine ou suivez une procédure SQL de rotation ; effacer le PVC perdrait les données.
</details>

## Pour aller plus loin

- Créer un compte RBAC limité à la lecture du namespace, sans `secrets`, pour la phase de diagnostic.
- Introduire des endpoints de santé permanents et appropriés avant de remplacer les sondes TCP.
- Séparer les migrations du démarrage, externaliser PostgreSQL, sauvegarder et tester une restauration.

## Débrief

Quelle panne était visible dans les événements ? Laquelle demandait une requête métier ? Pourquoi un port ouvert ne prouve-t-il pas la disponibilité des dépendances ? Quelle différence entre une règle de permission, un hook local et RBAC ?

**Ce que l'on observe souvent.** L'agent propose de redémarrer les pods avant de lire les événements, confond une image introuvable avec une erreur applicative, ou suppose que `/health` existe dans tous les environnements. La correction doit survivre au prochain `apply` : elle appartient au manifeste source.

**À retenir.** L'agent lit des indices dans un contexte borné, relie les symptômes au code et à la configuration, puis vérifie la même requête après correction.

## Les fichiers du lab

| Fichier | Rôle |
|---|---|
| `.claude/settings.json` | Permissions et hooks cumulés, lectures Kubernetes ciblées, mutations contrôlées. |
| `.claude/hooks/garde-kubectl.sh` | Vérification du contexte et de la portée des commandes directes. |
| `.claude/skills/diagnostic-k8s/SKILL.md` | Méthode de diagnostic fondée sur les indices. |
| `ressources/k8s-degrade/*.yaml` | Manifeste de départ avec trois pannes. |
| `ressources/creer-secret.sh` | Création du Secret sans valeur enregistrée dans la copie. |
| `ressources/tester-garde.sh` | Cas de contrôle du hook avec un faux contexte. |
| `solution/k8s/*.yaml` | Namespace, PostgreSQL/PVC, Services et Deployments corrigés. |
| `solution/scripts/creer-secret-k8s.sh` | Copie pérenne du script de création du Secret. |
