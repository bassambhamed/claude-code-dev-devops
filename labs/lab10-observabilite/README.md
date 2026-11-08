# Lab 10 · « Les commandes sont lentes »

> Partie 10 des supports · Mécanismes : MCP Aspire et Grafana, skill `/diagnostic-traces`, sous-agent `observabilite-analyste` · Prérequis : lab 9, Docker, .NET 10, CLI Aspire, `curl`, `jq`

## Pourquoi ce lab

Une commande répond 201 et met pourtant plusieurs secondes. Un code HTTP correct ne dit
rien du temps perdu entre Gateway, Ordering et Catalog. Une trace relie ces appels ; une
métrique métier indique leur effet dans le temps. L'agent rapproche mesures, traces et code,
et la seconde mesure permet de juger le correctif.

## Objectifs

- Collecter traces et métriques dans Grafana tout en conservant le dashboard Aspire.
- Diagnostiquer une latence avec une période UTC et des trace IDs réels.
- Instrumenter les commandes créées et leur montant, sans données personnelles.
- Exporter un tableau de bord et comparer avant/après sur le même scénario.

## Point de départ

Votre copie à la fin du lab 9, commitée. Travaillez sur `observabilite/commandes`.
Arrêtez Compose et les transferts de port Kubernetes : l'AppHost reprend les ports locaux.
Le cluster du lab 9 ne reçoit pas les changements de ce lab ; vous revenez à Aspire pour
isoler le diagnostic, sans changer la persistance PostgreSQL ni le contrat HTTP.
La CLI Aspire doit proposer `aspire agent mcp` ; vérifiez `aspire --version` et son aide.
Si elle manque, utilisez le dashboard manuellement jusqu'à l'installation de la CLI.

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/lab10-observabilite/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

## Mise en situation

Depuis la livraison « stock en temps réel », le support constate que les commandes les
plus longues ont plusieurs lignes. Il n'a ni trace ID ni mesure comparable. Votre mission
est de transformer cette observation en diagnostic vérifiable, puis de restaurer la latence.

## Étapes

### Étape 1 · Collecter sans perdre Aspire

Demandez à l'agent d'ajouter dans l'AppHost une ressource
`grafana/otel-lgtm:0.40.0`, ports hôte 3000 (Grafana) et 4317 (OTLP/gRPC).
Chaque projet reçoit `Grafana__OtlpEndpoint` via `lgtm.GetEndpoint("otlp")`.
Dans ServiceDefaults, remplacez `UseOtlpExporter()` par les exporteurs explicites de
traces, métriques et logs pour Aspire ; ajoutez un second exporteur **nommé `grafana`**
pour traces et métriques seulement, en gRPC, avec `Headers = string.Empty`.
Le jeton d'ingestion Aspire ne doit pas partir vers Grafana. Ne cumulez pas
`UseOtlpExporter()` et `AddOtlpExporter()` dans le même fournisseur.

```text
Ajoute la collecte locale Grafana en gardant les traces, métriques et logs d'Aspire.
Respecte le mécanisme facultatif Grafana:OtlpEndpoint décrit ci-dessus. Aucun endpoint
codé en dur dans les API. Construis puis montre uniquement les paramètres non sensibles.
```

Construisez, puis démarrez `dotnet run --project src/ECommerce.AppHost`.
Ouvrez Grafana sur `http://localhost:3000` (`admin`/`admin`, environnement de formation local).
LGTM est une pile de démonstration ; attendez sa disponibilité avant de mesurer.
Les logs restent dans Aspire ; les traces et métriques sont envoyées aux deux destinations.

### Étape 2 · Brancher les deux MCP

Comparez votre `.mcp.json` avec `ressources/.mcp.json`, puis copiez/fusionnez les serveurs
nouveaux en conservant les connexions ajoutées par vous. Le fichier fourni reprend aussi les deux serveurs PostgreSQL du lab 4 et
Playwright du lab 5. Le serveur Grafana utilise un compte **Viewer** et `--disable-write`.
Sur Linux, ajoutez `--add-host=host.docker.internal:host-gateway` dans ses arguments Docker.

Dans **votre terminal**, capturez le jeton sans l'afficher :

```bash
export GRAFANA_JETON_LECTURE="$(bash "$FORMATION"/labs/lab10-observabilite/ressources/jeton-grafana.sh)"
cp "$FORMATION"/labs/lab10-observabilite/ressources/.mcp.json ~/lab-ecommerce/.mcp.json
```

Démarrez Claude Code depuis ce terminal, puis contrôlez `/mcp`. Ne faites ni `echo` du
jeton ni copie d'environnement. Le jeton expire après 24 heures : recréez-le si nécessaire.
Demandez la liste des ressources Aspire et des sources Grafana ; ces lectures doivent réussir.

### Étape 3 · Mesurer la version saine, puis la livraison lente

Toutes les commandes suivantes partent de la racine de la copie :

```bash
mkdir -p preuves/lab10
bash .claude/skills/diagnostic-traces/mesurer.sh 5 | tee preuves/lab10/reference.txt
```

Le script crée des commandes de formation à 1, 3 et 5 lignes. Commitez votre dispositif
et votre code avant d'injecter la livraison (le script refuse une copie modifiée), puis :

```bash
bash "$FORMATION"/labs/lab10-observabilite/ressources/livrer-version-lente.sh ~/lab-ecommerce
```

Redémarrez l'AppHost pour reconstruire et déployer cette révision. Relancer une ressource
dans le dashboard ne reconstruit pas le code. Mesurez :

```bash
bash .claude/skills/diagnostic-traces/mesurer.sh 5 | tee preuves/lab10/avant.txt
```

Le simulateur attend 800 ms par lecture de produit ; n'utilisez pas cette valeur comme
mesure. Les lignes répétées restent des lignes distinctes, il ne s'agit pas de cinq produits
nécessairement différents.

### Étape 4 · Laisser les traces choisir la cause

```text
/diagnostic-traces Création de commande lente, période UTC du fichier preuves/lab10/avant.txt.
Utilise observabilite-analyste pour les traces volumineuses. Donne un trace ID, les spans
coupables, le fichier et la ligne, puis une hypothèse à confirmer. Ne corrige pas encore.
```

Dans Grafana Explore, choisissez Tempo et retrouvez la période de mesure. Une requête
TraceQL possible : `{ resource.service.name = "ordering" }` ; si ce nom ne donne rien,
cherchez les valeurs réellement présentes de `resource.service.name` (le SDK peut utiliser
`ECommerce.Ordering.Api`). Ouvrez une trace complète depuis Gateway et repérez les appels
Catalog successifs. Comparez leurs durées avec le nombre de lignes. Notez la durée totale
et les enfants, sans additionner les deux. Si MCP est indisponible, faites ce parcours
manuellement et indiquez-le dans les preuves.

### Étape 5 · Une métrique métier utile

```text
Ajoute Telemetry/OrderingTelemetry.cs : Meter ECommerce.Ordering, compteur
"ecommerce.orders.created", compteur de montant "ecommerce.orders.amount" avec le seul
label currency=EUR, histogramme "ecommerce.orders.duration" en secondes. Enregistre après
SaveChangesAsync réussi uniquement. Aucun client, identifiant de commande ou nom de
produit dans les labels. Enregistre le Meter dans ServiceDefaults avec AddMeter.
Ajoute une activité CreateOrder dont la source est ECommerce.Ordering.Api.
```

Redémarrez l'AppHost et créez des commandes valides, puis une demande invalide (quantité 0).
Attendez au moins un intervalle d'export métrique (60 s par défaut). Dans Explore/Prometheus,
cherchez `ecommerce_orders_created_total`. Le rejet ne doit pas augmenter ce compteur.
Comparez des échantillons après export ; la création du premier instrument peut intervenir
après la première collecte. Le montant est un cumul en EUR et ne représente ni un paiement
encaissé ni le solde du système. Un redémarrage remet ces compteurs en mémoire à zéro.

### Étape 6 · Corriger, mesurer, exporter

Le compromis retenu pour ce lab : le chemin de lecture utilise à nouveau le stock
persisté ; la fraîcheur du stock relève d'une synchronisation distincte, non demandée ici.
Retirez l'appel à WarehouseClient du GET de produit et son enregistrement DI ; ne masquez
pas le problème en mettant `Warehouse:LatencyMs` à zéro. Le simulateur peut rester inactif.

```bash
dotnet build ECommerce.slnx
dotnet test ECommerce.slnx
# Après redémarrage de l'AppHost :
bash .claude/skills/diagnostic-traces/mesurer.sh 5 | tee preuves/lab10/apres.txt
```

Importez `solution/observabilite/dashboard-commandes.json` depuis le dossier de formation,
ou construisez les trois panneaux (nombre, montant EUR, p95). À l'import, choisissez la
source Prometheus existante. Vérifiez les noms réellement exposés : le tableau emploie
`ecommerce_orders_duration_seconds_bucket`. Conservez un export JSON de votre tableau et
une capture de données réelles dans `preuves/lab10/`. Le p95 nécessite des observations
dans la fenêtre de cinq minutes ; « No data » n'est pas un temps nul.

### Étape 7 · Livrer

Complétez la fiche `ressources/fiche-diagnostic.md` dans vos preuves. Faites relire les
changements de télémétrie par `security-reviewer`, puis `/ship Diagnostic et métriques des commandes`.

## Critères d'acceptation

- [ ] Les ressources sont lisibles via MCP Aspire ; Grafana utilise un compte Viewer.
- [ ] Les mêmes traces sont retrouvables dans Aspire et Tempo, avec un identifiant réel.
- [ ] Le diagnostic relie latence, appels Catalog successifs et WarehouseClient.
- [ ] Les trois instruments sont exportés ; une requête rejetée n'incrémente pas les créations.
- [ ] Aucun label à cardinalité non bornée ni donnée personnelle dans les métriques.
- [ ] Le stock persisté est relu, les tests passent, les mesures 1/3/5 lignes sont comparables.
- [ ] Le tableau exporté affiche les données de la session.

## Preuves à fournir

Dans `preuves/lab10/` : référence, avant, après, fiche diagnostic, trace IDs et captures,
requêtes réellement exécutées, export du tableau et résumé des tests. Si une vérification
n'a pas pu être exécutée, indiquez son obstacle ; les corrigés ne fournissent pas de chiffres
ni de traces fictifs à recopier.

## Aides progressives

<details><summary>Indice 1 · La métrique n'apparaît pas</summary>
Le nom du Meter doit correspondre exactement à AddMeter. Créez au moins une commande
valide, attendez l'export et contrôlez le endpoint gRPC 4317. Le nom Prometheus est
normalisé (points en underscores, suffixes d'unité et _total).
</details>

<details><summary>Indice 2 · Les traces sont plus longues à cinq lignes</summary>
Ordering effectue un appel Catalog par ligne dans un foreach séquentiel. Le GET Catalog
attend lui-même WarehouseClient. Un span HttpClient englobe l'attente distante ; son parent
ne représente pas une seconde attente indépendante.
</details>

<details><summary>Indice 3 · Une seule destination reçoit les traces</summary>
Contrôlez séparément le endpoint Aspire et Grafana:OtlpEndpoint ; ne remplacez pas l'un par
l'autre. Les exporteurs de la seconde destination sont nommés et n'utilisent pas le header
d'autorisation Aspire. Le protocole gRPC va sur 4317, HTTP/protobuf sur 4318.
</details>

## Pour aller plus loin

Proposez un rafraîchissement du stock hors du chemin critique avec un contrat de fraîcheur
et un test. Ajoutez un objectif de latence mesurable et une alerte sur une fenêtre suffisante.
Comparez un quantile calculé sur une population avec la médiane des cinq essais : ils ne
portent ni sur le même échantillon ni sur la même statistique.

## Débrief

Quel indice a éliminé le navigateur ? Pourquoi trois appels de 800 ms ne font-ils pas
800 ms ? Quelle vérification manque à une revue du code seule ? Pourquoi exporter le
nom du client dans un label serait-il un problème de confidentialité et de coût ?

**Ce que l'on observe souvent.** Le Meter est créé mais jamais enregistré, l'export est
observé trop tôt, ou la correction cache la simulation au lieu de retirer la dépendance.
À retenir : mesurer le même scénario, relier chaque hypothèse à une trace, puis remesurer.

## Les fichiers du lab

| Fichier | Rôle |
|---|---|
| `.claude/settings.json` | Permissions cumulées ; lectures Aspire/Grafana, actions de ressources à confirmer. |
| `.claude/skills/diagnostic-traces/SKILL.md`, `mesurer.sh` | Procédure et mesure 1/3/5 lignes avec bornes UTC. |
| `.claude/agents/observabilite-analyste.md` | Analyse bornée, en lecture seule. |
| `ressources/.mcp.json` | Aspire, Grafana en lecture seule, PostgreSQL et Playwright conservés. |
| `ressources/jeton-grafana.sh` | Compte Viewer et jeton 24 h, à capturer dans le terminal. |
| `ressources/livrer-version-lente.sh` | Commit injectant l'attente dans Catalog ; usage sur copie propre uniquement. |
| `ressources/fiche-diagnostic.md` | Trame de preuves, sans résultat inventé. |
| `solution/src/ECommerce.AppHost/AppHost.cs` | LGTM et endpoints injectés. |
| `solution/src/ECommerce.ServiceDefaults/Extensions.cs` | Meter et exporteurs pour les deux destinations. |
| `solution/src/ECommerce.Ordering.Api/Telemetry/OrderingTelemetry.cs`, `Endpoints/OrderingEndpoints.cs` | Télémétrie des commandes enregistrées. |
| `solution/src/ECommerce.Catalog.Api/Program.cs`, `Endpoints/CatalogEndpoints.cs`, `Services/WarehouseClient.cs` | Lecture rapide restaurée ; simulateur conservé inactif pour permettre le rattrapage par copie. |
| `solution/src/*/README.md` | Documentation des évolutions. |
| `solution/observabilite/dashboard-commandes.json` | Trois panneaux importables en choisissant la source Prometheus. |

Le corrigé s'applique à la fin du lab 9 ou après l'injection de la livraison lente. Aucun
fichier n'est à supprimer. Les preuves et le jeton Grafana restent à produire sur le poste.

Sources : [pile LGTM](https://grafana.com/docs/opentelemetry/docker-lgtm/),
[exporteurs .NET](https://github.com/open-telemetry/opentelemetry-dotnet/blob/main/src/OpenTelemetry.Exporter.OpenTelemetryProtocol/README.md),
[télémétrie Aspire](https://aspire.dev/fundamentals/telemetry/).
