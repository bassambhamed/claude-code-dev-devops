# Lab 7 · « Ça marche sur mon poste »

> Partie 9 des supports · Mécanismes : skill `/revue-docker`, sous-agent `docker-reviewer`, script de contrôle déterministe, scan d'images (`trivy` ou `docker scout`) · Prérequis : lab 6 ; Docker avec Compose, `trivy` ou `docker scout`

## Pourquoi ce lab

« Ça marche sur mon poste » vient de différences invisibles : version du SDK, certificats de développement, PostgreSQL lancé ou non. Sur votre poste, l'AppHost Aspire masque une bonne partie du problème : il démarre PostgreSQL, crée les bases, injecte les chaînes de connexion et la découverte de services, choisit les ports. Une image, elle, **fige l'environnement d'exécution** ; Docker Compose remplace l'AppHost pour lancer l'ensemble. Tout ce qu'Aspire faisait pour vous, il faut alors l'écrire.

Le lab répartit le travail entre trois mécanismes, chacun à sa place :

- un **skill**, `/revue-docker`, porte la liste de contrôle d'une image et lance un **script déterministe** : ce qui peut être vérifié par un programme ne dépend pas de l'humeur du modèle ;
- un **sous-agent**, `docker-reviewer`, lit les rapports de scan (des milliers de lignes) dans son propre contexte et ne renvoie que des correctifs priorisés ;
- le **scan** (`trivy` ou `docker scout`) fournit des faits, avant et après : on traite des vulnérabilités, pas des impressions.

## Objectifs

- Écrire un Dockerfile multi-étapes par service : image finale *chiseled*, épinglée par digest, exécutée sans root.
- Relire chaque image avec `/revue-docker` et `docker-reviewer`, puis arbitrer leurs recommandations.
- Lancer toute l'application avec `docker compose`, PostgreSQL compris, en fournissant à la main la découverte de services et les chaînes de connexion.
- Scanner les images avant et après, et traiter les vulnérabilités hautes.

## Point de départ

- Votre copie à la fin du lab 6, commitée, sur `main`. Une branche de travail : `git switch -c conteneurs/images-et-compose`.
- Docker avec Compose v2 (lab vérifié avec Docker 29.8.0 et Compose v5.5.1), et un scanner : `trivy` (vérifié avec 0.71.2 ; `brew install trivy`) ou `docker scout` (fourni avec Docker Desktop, connexion à un compte Docker requise). `jq`, comme depuis le lab 0.
- Le SDK .NET n'est pas nécessaire pour construire les images : le SDK est dans l'image de construction. C'est tout l'intérêt.

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/lab7-conteneurs/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

## Mise en situation

Inès rejoint l'équipe lundi. Elle a passé sa première matinée à installer le bon SDK, à faire confiance au certificat de développement et à comprendre pourquoi Ordering ne trouve pas sa base. L'équipe veut un lancement **reproductible en une commande**, avec des images sobres, exécutées sans root, et un rapport de vulnérabilités que l'on peut comparer d'une version à l'autre. Les images serviront aussi au déploiement sur Kubernetes, au lab suivant.

## Étapes

Toutes les commandes se lancent depuis la racine de votre copie (le dossier qui contient `ECommerce.slnx`).

### Étape 1 · L'image « avant »

Le modèle fourni est le Dockerfile naïf que l'on trouve partout : il fonctionne, et c'est tout. Construisez-le tel quel pour Catalog :

```bash
cp "$FORMATION"/labs/lab7-conteneurs/ressources/Dockerfile.modele src/ECommerce.Catalog.Api/Dockerfile
docker build -f src/ECommerce.Catalog.Api/Dockerfile -t ecommerce/catalog:avant .
docker image inspect --format 'User="{{.Config.User}}"' ecommerce/catalog:avant
```

Le contexte de construction est la **racine** de la copie (le `.` final) : Catalog a besoin du projet `ECommerce.ServiceDefaults`. `User=""` signifie que le conteneur tourne en **root**. Scannez cette image :

```bash
bash "$FORMATION"/labs/lab7-conteneurs/ressources/scanner-images.sh ~/lab-ecommerce avant ecommerce/catalog:avant
```

Le script range le rapport JSON complet dans `preuves/lab7/scans/avant/`, affiche une ligne par gravité, puis le détail des vulnérabilités hautes et critiques ; il sort avec le code 1 s'il en trouve. Lors de notre vérification (base trivy du 8 novembre 2026) : `HIGH 2`, `MEDIUM 21`, `LOW 5`, et les deux hautes venaient de `apt` et `libapt-pkg6.0t64`. Vos chiffres seront différents, puisque la base de vulnérabilités change chaque jour : notez la date affichée par le script. Avec Docker Scout : `docker scout cves local://ecommerce/catalog:avant`.

Question pour vos preuves : que fait `apt`, un gestionnaire de paquets, dans une image qui ne fait qu'exécuter une API ?

### Étape 2 · Compléter le Dockerfile de Catalog

Lisez les cinq `TODO` du modèle, puis :

```text
Complète src/ECommerce.Catalog.Api/Dockerfile en traitant les TODO 1 à 5 de son en-tête,
et crée le .dockerignore à la racine. Contraintes :
- construction multi-étapes, image finale mcr.microsoft.com/dotnet/aspnet en variante
  noble-chiseled, utilisateur $APP_UID, port 8080 ;
- chaque image de base avec sa version exacte et son digest : vérifie-les avec
  docker buildx imagetools inspect, n'invente aucun numéro ;
- restore des .csproj avant la copie du code, puis dotnet publish --no-restore ;
- commentaires en anglais, comme le reste du dépôt ; retire les TODO traités.
Construis l'image ecommerce/catalog:1.0 et montre la commande de construction.
```

Vérifiez chaque digest proposé, comme Claude devait le faire :

```bash
docker buildx imagetools inspect mcr.microsoft.com/dotnet/aspnet:<version>-noble-chiseled | grep -m1 Digest
```

Lors de notre vérification, les images retenues étaient `sdk:10.0.403-noble` et `aspnet:10.0.14-noble-chiseled` ; des versions plus récentes existent peut-être aujourd'hui, et c'est justement pourquoi on épingle. Prouvez ensuite que l'image tourne sans root et sans shell :

```bash
docker image inspect --format 'User={{.Config.User}}' ecommerce/catalog:1.0     # User=1654
docker run --rm --entrypoint sh ecommerce/catalog:1.0 -c id                       # échoue : exec: "sh": executable file not found
```

L'utilisateur est **numérique** (1654) : c'est ce qui permettra à Kubernetes de vérifier `runAsNonRoot` au lab 8. Comparez les tailles avec `docker images ecommerce/catalog` (ici : 383 Mo avant, 198 Mo après, selon `verifier-image.sh`).

### Étape 3 · Relire l'image avec `/revue-docker`

Ouvrez `.claude/skills/revue-docker/SKILL.md` et `.claude/agents/docker-reviewer.md` avant de les utiliser : le skill porte la liste de contrôle et appelle le script `verifier-image.sh` ; le sous-agent lit le rapport de scan à la place de la session principale.

```text
/revue-docker catalog
```

Observez dans la session :

1. le tableau des huit critères, chacun avec une ligne du Dockerfile en preuve ;
2. la sortie de `verifier-image.sh` (le dernier mot est `IMAGE OK` ou `IMAGE KO`) ;
3. la délégation à `docker-reviewer` : il travaille dans son propre contexte et ne renvoie que son tableau priorisé. Comparez avec `/context` ce que la session principale a reçu.

Le script se lance aussi sans Claude, et c'est la même vérification :

```bash
bash .claude/skills/revue-docker/verifier-image.sh ecommerce/catalog:1.0 src/ECommerce.Catalog.Api/Dockerfile
bash .claude/skills/revue-docker/verifier-image.sh ecommerce/catalog:avant src/ECommerce.Catalog.Api/Dockerfile   # IMAGE KO, code 1
```

Les recommandations du relecteur sont des avis. Remplissez le tableau d'arbitrage dans vos preuves :

| Recommandation | Source (skill, script, sous-agent) | Retenue ? | Justification |
|---|---|---|---|
| … | … | oui / non | … |

Une recommandation fréquente mérite un refus argumenté : ajouter un `HEALTHCHECK` avec `curl`. L'image *chiseled* n'a ni shell ni `curl`, et `/health` n'est de toute façon mappé qu'en `Development` (`MapDefaultEndpoints`, déjà noté dans `CLAUDE.md`). La santé se vérifie depuis l'extérieur.

### Étape 4 · Les trois autres services

```text
Sur le modèle de src/ECommerce.Catalog.Api/Dockerfile, écris les Dockerfile d'Ordering.Api,
de Gateway et de Web, dans leur dossier de projet. Mêmes règles. Construis les images
ecommerce/ordering:1.0, ecommerce/gateway:1.0 et ecommerce/web:1.0, puis lance
/revue-docker web.
```

Vérifiez les quatre images d'un coup :

```bash
for s in Catalog.Api:catalog Ordering.Api:ordering Gateway:gateway Web:web; do
  bash .claude/skills/revue-docker/verifier-image.sh ecommerce/${s#*:}:1.0 src/ECommerce.${s%:*}/Dockerfile | tail -n 1
done
```

Vous devez lire quatre fois `IMAGE OK`. Le Web cache un piège que ni le script ni le scan ne voient ; vous le découvrirez à l'étape 6.

### Étape 5 · Compléter `docker-compose.yml`

```bash
cp "$FORMATION"/labs/lab7-conteneurs/ressources/docker-compose.modele.yml docker-compose.yml
```

Le mot de passe de PostgreSQL ne passe ni par Git ni par la session de Claude. Créez-le **vous-même**, dans votre terminal, dans un fichier `.env` que Compose lit automatiquement :

```bash
printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 16)" > .env
git check-ignore .env        # affiche .env : le fichier est ignoré par Git
```

Claude ne peut pas le lire : la règle `deny` `Read(./.env)` du lab 0 l'en empêche. Puis :

```text
Complète docker-compose.yml en traitant les TODO A à E. Rappel : hors de l'AppHost, personne
n'injecte la découverte de services ni les chaînes de connexion (relis CLAUDE.md, sections
sur la découverte de services et sur le lancement d'un service seul). Les services écoutent
sur le port 8080, en HTTP seulement. Le mot de passe vient de ${POSTGRES_PASSWORD}, jamais
d'une valeur écrite. Vérifie la version de l'image postgres et son digest. Valide avec
docker compose config --quiet, sans afficher la configuration résolue.
```

Relisez le résultat : à quelle variable correspond `https+http://catalog` ? Quel nom de base lit `AddNpgsqlDbContext<CatalogDbContext>("catalogdb")` ? Pourquoi le healthcheck est-il possible pour PostgreSQL et pas pour les services .NET ? Pourquoi `docker compose config` sans option est-il refusé par les réglages du lab ?

### Étape 6 · Lancer et prouver

Dans votre terminal (l'AppHost ne doit pas tourner : il utilise aussi le port 5067) :

```bash
docker compose up -d --build
docker compose ps                              # cinq services ; postgres « healthy »
bash .claude/skills/smoke-test/smoke.sh        # PASSERELLE vaut http://localhost:5067 par défaut
```

Le test de fumée doit afficher `L'application tourne déjà`, trois `OK` et `SMOKE OK`. S'il annonce `Démarrage de l'AppHost`, c'est que la passerelle des conteneurs ne répond pas : arrêtez-le (Ctrl+C) et regardez `docker compose ps` et `docker compose logs gateway`.

Ouvrez ensuite l'interface sur `http://localhost:5190`, ajoutez un produit au panier et passez une commande. Si le panier ne réagit pas :

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:5190/_framework/blazor.web.js    # 200 attendu
```

Un `404` ici est le piège du Web : voir l'indice 2. Corrigez, reconstruisez (`docker compose up -d --build web`), vérifiez.

Enfin, la persistance :

```bash
curl -s http://localhost:5067/ordering/api/orders | jq length
docker compose restart
curl -s http://localhost:5067/ordering/api/orders | jq length    # même nombre
```

### Étape 7 · Scanner après, traiter les vulnérabilités hautes

```bash
bash "$FORMATION"/labs/lab7-conteneurs/ressources/scanner-images.sh ~/lab-ecommerce apres \
  ecommerce/catalog:1.0 ecommerce/ordering:1.0 ecommerce/gateway:1.0 ecommerce/web:1.0
```

Lors de notre vérification : `HIGH 0` et `MEDIUM 2` pour chacune des quatre images (deux vulnérabilités de `libc6`, sans correctif publié), et le script sortait avec le code 0. Puis :

```text
Utilise le sous-agent docker-reviewer pour comparer les rapports de preuves/lab7/scans/avant/
et preuves/lab7/scans/apres/ : origine de chaque vulnérabilité haute ou critique, correctif
disponible ou non, action proposée. Vérifie toute version d'image ou de paquet proposée.
```

S'il reste des vulnérabilités hautes **avec** correctif publié, traitez-les : nouvelle version de l'image de base (et nouveau digest), ou mise à jour du paquet NuGet direct qui les apporte. Reconstruisez, rescannez, jusqu'au code 0. Une vulnérabilité **sans** correctif publié ne se corrige pas : documentez-la dans vos preuves (identifiant, paquet, raison, date de réexamen).

### Étape 8 · Livrer

```bash
docker compose down              # garde le volume pgdata ; « down -v » effacerait les données
git status --short               # .env ne doit pas apparaître
```

```text
/ship Images chiseled, docker-compose et rapports de scan
```

Gardez les quatre images `ecommerce/*:1.0` : le lab 8 les importe dans le cluster Kubernetes.

## Critères d'acceptation

- [ ] Quatre Dockerfile multi-étapes, un par service, et un `.dockerignore` à la racine.
- [ ] `verifier-image.sh` affiche `IMAGE OK` pour les quatre images `1.0` : utilisateur `1654`, pas de shell, pas de SDK, port 8080, images de base épinglées par digest, aucun secret.
- [ ] Le scan `apres` ne montre aucune vulnérabilité haute ou critique corrigible ; celles qui restent sont documentées.
- [ ] `docker compose up -d` démarre cinq services, PostgreSQL `healthy`, et `smoke.sh` affiche `SMOKE OK`.
- [ ] `/_framework/blazor.web.js` répond 200 et une commande passe depuis l'interface.
- [ ] Les commandes survivent à `docker compose restart`.
- [ ] Aucun mot de passe dans Git : `git grep -n -i password -- docker-compose.yml` ne montre que `${POSTGRES_PASSWORD}`, et `git check-ignore .env` affiche `.env`.

## Preuves à fournir

Dans `preuves/lab7/` :

- `scans/avant/` et `scans/apres/` (écrits par le script), et les deux tableaux de synthèse avec la date de la base de vulnérabilités ;
- la sortie de `verifier-image.sh` pour les quatre images, et `docker image inspect --format '{{.Config.User}}'` pour chacune ;
- la revue `/revue-docker` d'au moins deux services, le rapport de `docker-reviewer` et votre tableau d'arbitrage ;
- `docker compose ps`, la sortie de `smoke.sh`, le code HTTP de `blazor.web.js` et le test de persistance ;
- les vulnérabilités restantes documentées, et vos réponses aux questions des étapes 1 et 5.

## Aides progressives

<details>
<summary>Indice 1 · <code>COPY</code> échoue, ou <code>dotnet restore</code> ne trouve pas ServiceDefaults</summary>

Le contexte de construction est la racine de la copie, et le Dockerfile est désigné par `-f` : `docker build -f src/ECommerce.Catalog.Api/Dockerfile -t ecommerce/catalog:1.0 .`. Lancée depuis `src/ECommerce.Catalog.Api`, la même commande n'a pas accès à `src/ECommerce.ServiceDefaults`. Dans le Dockerfile, les chemins des `COPY` sont donc relatifs à la racine.
</details>

<details>
<summary>Indice 2 · L'interface s'affiche, mais le panier ne réagit pas</summary>

`/_framework/blazor.web.js` répond 404 : la page est rendue côté serveur, mais le script qui active le mode interactif manque. En .NET 10, ce fichier vient d'un paquet que le SDK ne restaure que si le projet contient des fichiers `.razor`. Or la couche de restore ne copie que les `.csproj`. Dans le Dockerfile du Web, ajoutez `-p:RequiresAspNetWebAssets=true` au `dotnet restore`, puis vérifiez la présence du fichier : `docker create` puis `docker export <id> | tar -t | grep blazor.web.js`. L'optimisation du cache a eu un effet de bord : aucun scan ni contrôle de l'image ne le voit, seul un test de l'interface le révèle.
</details>

<details>
<summary>Indice 3 · Ordering ou Catalog redémarre en boucle</summary>

`docker compose logs ordering` : `28P01: password authentication failed for user "postgres"`. PostgreSQL ne lit `POSTGRES_PASSWORD` qu'à la **création** du volume. Si vous avez changé le mot de passe depuis (nouveau `.env`, autre terminal), la base garde l'ancien. Remettez l'ancien mot de passe, ou repartez d'un volume vide avec `docker compose down -v` (les données sont perdues ; la commande est refusée à Claude par les réglages du lab). Au premier démarrage, une ligne `fail: ... An error occurred using the connection to database 'catalogdb'` est en revanche normale : la base n'existe pas encore, et `Migrate()` la crée.
</details>

<details>
<summary>Indice 4 · La passerelle répond 502, ou la commande échoue alors que le catalogue répond</summary>

Il manque une variable de découverte de services. Chaque appelant a besoin de la sienne, comme le ferait `.WithReference(...)` dans l'AppHost : la passerelle `services__catalog__http__0` et `services__ordering__http__0`, Ordering `services__catalog__http__0`, le Web `services__gateway__http__0`. La valeur est `http://<service>:8080` : le nom du service Compose, et le port 8080 des images .NET, pas 80.
</details>

<details>
<summary>Indice 5 · <code>docker compose config</code> affiche le mot de passe</summary>

Compose remplace `${POSTGRES_PASSWORD}` par sa valeur dans la configuration résolue, et `docker inspect` d'un conteneur montre aussi ses variables d'environnement. Pour valider le fichier sans rien afficher : `docker compose config --quiet`. Pour relire le fichier sans substitution : `docker compose config --no-interpolate`.
</details>

## Pour aller plus loin

- Durcir le Compose : `read_only: true`, `cap_drop: [ALL]`, `security_opt: ["no-new-privileges:true"]` et un `tmpfs` pour `/tmp`. Que dit l'application au démarrage, et pourquoi ?
- Transmettre le mot de passe par un fichier (`secrets:` de Compose et `POSTGRES_PASSWORD_FILE`) plutôt que par une variable d'environnement visible dans `docker inspect`.
- Ajouter le scan au workflow du lab 6, en étape bloquante sur les vulnérabilités hautes corrigibles (`trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`).
- Comparer les variantes `noble-chiseled`, `noble-chiseled-extra` et `noble-chiseled-composite` : taille, scan, globalisation (`DOTNET_SYSTEM_GLOBALIZATION_INVARIANT` vaut `true` dans les images chiseled).

## Débrief

- Qu'est-ce qu'Aspire faisait pour vous et qu'il a fallu refaire ?
- Quelle différence de scan entre l'image complète et l'image *chiseled* ? D'où venaient les vulnérabilités hautes ?
- Quelle recommandation de la revue avez-vous refusée, et pourquoi ?
- Qu'a vérifié le script que Claude aurait pu mal juger ? Qu'a vu le sous-agent que le script ne voit pas ?

**Ce que l'on observe souvent.** Claude propose des tags plausibles mais inexistants, ou recopie un digest d'un autre tag : d'où l'obligation de vérifier avec `docker buildx imagetools inspect`. Le piège de `blazor.web.js` passe toutes les revues, script compris ; seul le test de l'interface le révèle. Le relecteur recommande un `HEALTHCHECK` impossible dans une image sans shell. Enfin, un changement de mot de passe après la première exécution mène presque toujours à l'indice 3.

À retenir : une image fige l'environnement d'exécution ; multi-étapes, non root, image épinglée ; ce qui se vérifie par un script ne se confie pas au jugement du modèle ; hors d'Aspire, la découverte de services et les chaînes de connexion se configurent à la main.

## Les fichiers du lab

### `.claude/`

| Fichier | Rôle |
|---|---|
| `skills/revue-docker/SKILL.md` | La revue d'une image : huit critères prouvés par une ligne du Dockerfile, contrôle déterministe, scan rangé dans `preuves/lab7/scans/revue/`, délégation du rapport à `docker-reviewer`. Ne modifie rien. |
| `skills/revue-docker/verifier-image.sh` | Contrôles déterministes d'une image et de son Dockerfile : utilisateur non root numérique, port 8080, ni shell ni SDK, aucun secret dans l'environnement, l'historique, `ENV` ou `ARG`, multi-étapes, digests, image finale chiseled, `USER`. Code 0, 1 ou 2. |
| `agents/docker-reviewer.md` | Sous-agent en lecture seule : lit un Dockerfile, un Compose ou un rapport de scan, classe les vulnérabilités par origine (système, runtime, NuGet) et propose des correctifs priorisés, avec des versions vérifiées. |
| `settings.json` | Les règles des labs 0 à 7. Nouveautés de ce lab : construction, inspection d'images et scan autorisés ; `docker compose up`, `down`, `restart`, `docker run` et `docker inspect` soumis à confirmation ; suppression de volumes, `docker system prune` et `docker compose config` sans option refusés. |

### `ressources/`

| Fichier | Rôle |
|---|---|
| `Dockerfile.modele` | Le Dockerfile naïf (image complète, root, tag flottant, `COPY . .`) qui construit Catalog tel quel, avec les cinq `TODO` à traiter. |
| `docker-compose.modele.yml` | Le squelette du Compose : services, images et ports donnés ; PostgreSQL, chaînes de connexion, découverte de services et ordre de démarrage à compléter (`TODO A` à `E`). |
| `scanner-images.sh` | `scanner-images.sh <copie> <libellé> <image>...` : scan `trivy` de chaque image, rapports JSON dans `preuves/lab7/scans/<libellé>/`, synthèse par gravité, détail des vulnérabilités hautes et critiques. Code 0 si aucune, 1 sinon, 2 si le scan ne peut pas tourner. |

### `solution/`

L'état de la copie à la fin du lab, à partir de la fin du lab 6 : les quatre `src/<Projet>/Dockerfile` (SDK `10.0.403-noble` et runtime `10.0.14-noble-chiseled`, épinglés par digest ; restore du Web avec `RequiresAspNetWebAssets`), le `.dockerignore` et le `docker-compose.yml` (PostgreSQL 17.11 épinglé, healthcheck, chaînes de connexion, découverte de services, ports 5067 et 5190). Pour rattraper le lab, voir [`labs/README.md`](../README.md#rattraper-un-lab), puis créez votre `.env` (étape 5) et reconstruisez les images (`docker compose build`).
