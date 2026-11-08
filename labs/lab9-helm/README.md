# Lab 9 · Deux environnements à servir

> Partie 10 des supports · Mécanismes : skill `/revue-chart`, revue des rendus, contrôles déterministes · Prérequis : lab 8 ; Helm et cluster k3d conservé

## Pourquoi ce lab

Dupliquer les manifestes du lab 8 pour chaque environnement multiplie les écarts invisibles. Un chart décrit les mêmes ressources et laisse les valeurs exprimer les différences. Mais un template valide peut produire un déploiement incorrect : on relit et contrôle donc chaque rendu complet.

## Objectifs

- Transformer les manifestes corrigés du lab 8 en chart paramétrable.
- Expliciter les différences entre Development et Production.
- Référencer des secrets existants sans les embarquer dans les valeurs ou la release.
- Tester les deux profils, puis installer la version dev dans un namespace distinct.

## Point de départ

Votre copie à la fin du lab 8, commitée ; contexte courant `k3d-formation`. Les quatre images `ecommerce/*:1.0` sont déjà importées. Vérifiez `helm version --short`. Le chart est compatible avec les commandes de base Helm 3/4 ; les vérifications du support utilisent `helm lint` et `helm template`.

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/lab9-helm/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

## Mise en situation

Le développement utilise une seule instance et les endpoints de santé du mode Development ; le profil Production nécessite des ressources plus importantes, plusieurs réplicas des API et des sondes compatibles. L'équipe veut comparer ces choix avant d'envoyer une ressource au cluster.

## Étapes

### Étape 1 · Définir les valeurs et leurs invariants

```bash
git switch -c deploiement/chart-helm
mkdir -p charts/ecommerce/templates
cp "$FORMATION"/labs/lab9-helm/ressources/Chart.modele.yaml charts/ecommerce/Chart.yaml
```

Lisez le [cahier du chart](ressources/cahier-chart.md), puis demandez :

```text
À partir de k8s/, propose le plan d'un chart charts/ecommerce. Sépare les invariants
des paramètres d'environnement. Réutilise les quatre images du lab 7 et la découverte
de services. Aucun mot de passe ni template Secret : existingSecret doit référencer
un Secret créé séparément. Identifie le traitement des sondes en Production.
```

Le nom de chaque ressource inclut la release ; les sélecteurs de ses Services et Deployments doivent correspondre. Les chaînes de connexion du Secret doivent viser le nom PostgreSQL du chart, pas celui du lab 8.

### Étape 2 · Construire le chart et les deux profils

```text
Implémente le plan avec Chart.yaml, values.yaml, values.schema.json et templates/.
Ajoute values-dev.yaml et values-prod.yaml à la racine. Expose environment, images
(registry, tag, pullPolicy, digests), replicas, resources, existingSecret et postgres.
PostgreSQL reste un singleton local avec PVC, désactivable pour un hôte externe.
Dev utilise /health et /alive ; Production des sondes TCP, avec startupProbe.
Ne fabrique aucun digest d'image. Code et commentaires en anglais.
```

Le corrigé utilise un réplica par service en dev ; trois pour Catalog, Ordering et Gateway en prod, un pour Web. Blazor Interactive Server conserve des circuits côté serveur : multiplier Web exige une stratégie de sessions et des clés DataProtection partagées qui dépassent ce lab.

Le profil `values-prod.yaml` sert à relire une configuration Production. Il n'est pas une plateforme de production complète : les tags locaux, PostgreSQL singleton, l'absence de TLS et de sauvegardes restent explicites. Avant une publication réelle, poussez les images puis renseignez `images.digests.<service>` avec leurs digests vérifiés. Le chart sait les rendre sous forme `repository@sha256:…`.

### Étape 3 · Relire les rendus, pas seulement les templates

```bash
bash .claude/skills/revue-chart/verifier.sh
```

Le script ne contacte pas Kubernetes. Il contrôle les deux jeux de valeurs et écrit `preuves/lab9/rendu-dev.yaml`, `rendu-prod.yaml` et `ecarts.diff`. Lancez ensuite :

```text
/revue-chart Compare les deux rendus, explique les écarts et cite les lignes qui
prouvent sondes, ressources, réplicas, non-root, références de Secret et découverte
de services. Distingue les propriétés vérifiées des limites du profil local.
```

Vous pouvez reproduire individuellement les contrôles :

```bash
helm lint charts/ecommerce -f values-dev.yaml --strict
helm lint charts/ecommerce -f values-prod.yaml --strict
helm template formation charts/ecommerce -n ecommerce-helm -f values-dev.yaml
helm template formation charts/ecommerce -n ecommerce-helm -f values-prod.yaml
```

Les [valeurs Helm](https://helm.sh/docs/chart_template_guide/values_files/) se superposent : les fichiers `-f` remplacent les défauts de `values.yaml`. Vérifiez aussi les valeurs effectives des champs omis dans les profils. Le test est réussi seulement si les deux profils sont corrects.

### Étape 4 · Préparer un namespace et un secret propres à la release

Dans votre terminal, pour préserver le déploiement du lab 8 :

```bash
kubectl create namespace ecommerce-helm
export POSTGRES_PASSWORD="$(openssl rand -hex 24)"
bash "$FORMATION"/labs/lab8-kubernetes/ressources/creer-secret.sh ecommerce-helm formation-ecommerce-postgres
unset POSTGRES_PASSWORD
```

Le nom `formation-ecommerce-postgres` vient de la release `formation` et des helpers du corrigé. Si vous choisissez une autre convention, adaptez le nom transmis au script et vérifiez le rendu avant installation. Gardez le même Secret et le même mot de passe tant que ce volume PostgreSQL existe. Le chart ne gère pas la rotation du mot de passe SQL.

### Étape 5 · Installer et vérifier dev

```text
Présente la synthèse du rendu dev et la commande d'installation pour la release
formation dans ecommerce-helm. Le contexte doit rester k3d-formation. Une fois le
contrôle de permission passé, attends les ressources et vérifie le parcours métier.
```

```bash
helm upgrade --install formation charts/ecommerce -n ecommerce-helm -f values-dev.yaml --wait --timeout 5m
helm status formation -n ecommerce-helm
kubectl get pods -n ecommerce-helm
```

Fermez les port-forwards du lab 8. Dans deux terminaux séparés, laissez ouverts :

```bash
kubectl port-forward service/formation-ecommerce-gateway -n ecommerce-helm 5067:8080
kubectl port-forward service/formation-ecommerce-web -n ecommerce-helm 5190:8080
```

Exécutez `bash .claude/skills/smoke-test/smoke.sh`, vérifiez la création d'une commande dans l'interface et le chargement de `/_framework/blazor.web.js`. Le lab ne demande pas d'installer le profil prod sur le cluster local.

### Étape 6 · Contrôler un défaut et livrer

Dans une copie temporaire de `values-prod.yaml`, mettez `environment: Staging` et lancez le lint : le schéma doit le refuser. Ne commitez pas ce fichier de test. Expliquez ce que le schéma ne peut pas vérifier : disponibilité du registre, existence et contenu du Secret, état du volume et comportement métier.

Archivez les preuves puis `/ship Chart Helm dev et prod, rendus relus et installation dev vérifiée`. Conservez les ressources pour la suite. Une désinstallation ou la suppression de PVC est une opération séparée ; elle ne fait pas partie de ce contrôle.

## Critères d'acceptation

- [ ] `helm lint --strict` réussit pour dev et prod ; environnement invalide refusé.
- [ ] Deux rendus complets et un diff expliqué.
- [ ] Quatre Deployments et Services, noms et sélecteurs isolés par release.
- [ ] Aucun Secret contenant des données dans le chart ou les valeurs.
- [ ] Sondes HTTP uniquement en Development, sondes TCP en Production.
- [ ] UID 1654, capacités supprimées, ressources et réplicas définis.
- [ ] Installation dev dans `ecommerce-helm`, test de fumée et interface vérifiés.
- [ ] Limites du profil Production et politique de digests documentées.

## Preuves à fournir

Sous `preuves/lab9/` : les deux rendus et leur diff, sorties de lint, tableau d'arbitrage `/revue-chart`, échec du profil invalide, état de la release et des pods, résultat du test de fumée et capture du parcours Web. Ne fournissez aucune sortie affichant des valeurs de Secret.

## Aides progressives

<details><summary>Indice 1 · Le Service ne voit aucun pod</summary>

Comparez tous les labels de son sélecteur avec ceux du template de Deployment ; la release et le service doivent correspondre. Un nom de Deployment correct ne suffit pas.
</details>

<details><summary>Indice 2 · La base du chart ne répond pas aux API</summary>

Le Secret du lab 8 vise `postgres`, celui du chart doit viser `formation-ecommerce-postgres`. Un Secret est propre à un namespace ; le chart ne le copie pas automatiquement.
</details>

<details><summary>Indice 3 · Le rendu prod contient /health</summary>

La condition doit porter sur la valeur effective de `environment`, pas sur le nom du fichier `values-prod.yaml`. Relisez le YAML rendu, puis corrigez la condition du template.
</details>

<details><summary>Indice 4 · Helm refuse de prendre en charge les ressources existantes</summary>

Les manifestes du lab 8 sont hors release Helm. Installez le chart dans `ecommerce-helm` avec ses propres noms ; ne tentez pas d'adopter ou supprimer les ressources du lab 8.
</details>

## Pour aller plus loin

- Ajouter `kubeconform` ou une validation serveur des rendus sur le cluster prévu.
- Publier les images et activer les digests, puis contrôler la reproductibilité des rendus.
- Brancher PostgreSQL externe avec `postgres.enabled=false`, adapter le Secret et tester une sauvegarde/restauration.
- Définir une stratégie Web à plusieurs réplicas et une vraie exploitation Production avant de généraliser le profil.

## Débrief

Quel défaut le lint a-t-il trouvé ? Quel défaut exigeait une lecture du rendu ? Pourquoi les Secrets de deux namespaces doivent-ils être préparés séparément ? Quelles garanties supplémentaires faut-il avant d'appeler ce profil une installation de production ?

**Ce que l'on observe souvent.** Un template recopie les noms fixes du lab 8, une sonde de développement fuit en prod ou les chaînes de connexion visent l'autre PostgreSQL. Une revue de templates seule laisse passer ces défauts ; le rendu et le parcours métier les rendent visibles.

**À retenir.** Un chart est vérifié pour chaque jeu de valeurs. L'installation du profil dev et la revue du profil prod sont deux preuves différentes.

## Les fichiers du lab

| Fichier | Rôle |
|---|---|
| `.claude/settings.json` | Règles cumulées et permissions Helm ; conserve `garde-kubectl` du lab 8. |
| `.claude/skills/revue-chart/SKILL.md` | Revue des rendus et limites du profil local. |
| `.claude/skills/revue-chart/verifier.sh` | Lint, rendus, contrôles élémentaires et diff dev/prod. |
| `ressources/Chart.modele.yaml` | Métadonnées de départ à compléter. |
| `ressources/cahier-chart.md` | Paramètres et invariants attendus. |
| `solution/charts/ecommerce/Chart.yaml` | Métadonnées du chart corrigé. |
| `solution/charts/ecommerce/values.yaml` | Valeurs communes sans secret. |
| `solution/charts/ecommerce/values.schema.json` | Validation des paramètres métier du chart. |
| `solution/charts/ecommerce/templates/*` | Noms de ressources, quatre services et PostgreSQL/PVC. |
| `solution/values-dev.yaml`, `solution/values-prod.yaml` | Deux profils relus, hors valeurs sensibles. |
