# Lab 0 · Premier jour dans l'équipe ECommerce

> Partie 2 des supports · Mécanismes : mode plan, `/init`, `CLAUDE.md`, permissions, skill, `/context` · Prérequis : aucun

## Pourquoi ce lab

Claude Code ne sait de votre projet que ce qu'il lit pendant la session. Tout le reste, il le **devine** : un nom de commande, un port, une convention. Ce lab installe les trois fondations sur lesquelles reposent tous les labs suivants :

- **`CLAUDE.md`**, la mémoire du projet, chargée au début de chaque session. S'il contient une erreur, chaque session part de cette erreur ; s'il manque un piège, chaque session peut y tomber.
- **Les permissions** du projet : ce que Claude fait sans demander, ce qu'il doit toujours demander, ce qu'il ne fait jamais. Elles sont versionnées et partagées par l'équipe.
- **Un test de fumée** en une commande, qui prouve que les quatre services fonctionnent ensemble. Vous le relancerez à chaque lab.

Vous apprenez aussi le réflexe le plus rentable : **explorer en mode plan avant de modifier**.

## Objectifs

- Installer, authentifier et vérifier Claude Code.
- Cartographier l'application en mode plan, sans rien modifier.
- Générer `CLAUDE.md` avec `/init`, puis le **corriger** à partir du code.
- Poser les premières règles de permission du projet et les comprendre.
- Lancer l'application et le skill `/smoke-test`.
- Lire `/context` : ce qui occupe la fenêtre de contexte.

## Point de départ

Une copie de l'application, versionnée, sans dossier `.claude/`. Depuis le dossier de formation :

```bash
export FORMATION="$PWD"      # le dossier de formation, utilisé par tous les labs
cp -r "$FORMATION"/ecommerce-app ~/lab-ecommerce
cd ~/lab-ecommerce && git init -b main
git add . && git commit -m "Etat initial"
```

Ajoutez la ligne `export FORMATION=…` (avec le chemin complet) à votre `~/.zshrc` ou `~/.bashrc` : chaque lab s'en sert.

Le dispositif du lab (réglages et skill `/smoke-test`) s'installe à l'étape 4, une fois `CLAUDE.md` écrit.

## Mise en situation

Vous rejoignez l'équipe ECommerce et personne n'a le temps de vous présenter le code. L'application compte six projets .NET 10 orchestrés par Aspire, sans tests, sans documentation pour les agents et sans règles partagées. Votre mission pour ce premier jour : comprendre l'application, la lancer, et écrire le `CLAUDE.md` qui manquait à l'équipe.

## Étapes

### Étape 1 · Installer et vérifier Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash     # ou : brew install --cask claude-code
claude --version
claude doctor
```

Lancez `claude` une première fois dans `~/lab-ecommerce` et connectez-vous. `claude doctor` doit signaler une installation saine : notez tout avertissement dans vos preuves.

### Étape 2 · Cartographier l'application en mode plan

Démarrez une session **en mode plan** : Claude lit et propose, mais ne modifie rien.

```bash
cd ~/lab-ecommerce
claude --permission-mode plan      # ou Maj+Tab dans une session, jusqu'à « plan mode »
```

Prompt proposé :

```text
Je découvre ce dépôt. Sans rien modifier, explique-moi :
1. les projets de la solution et le rôle de chacun ;
2. le chemin d'une commande, du clic dans l'interface jusqu'à la base de données ;
3. comment Ordering trouve l'adresse de Catalog ;
4. ce qui manque pour la production : tests, base de données, CI, conteneurs.
Cite les fichiers sur lesquels tu t'appuies.
```

Observez les outils utilisés (`Read`, `Grep`, `Glob`) et l'absence de toute modification. Puis posez ces trois questions de contrôle et **vérifiez chaque réponse dans le code** :

- Pourquoi `curl http://localhost:5147/` renvoie-t-il 404 alors que Catalog fonctionne ?
- Où est configuré le routage de la passerelle : dans le code ou dans la configuration ?
- Que renvoie `/health` quand l'application tourne en `Production` ?

> Si une réponse ne cite aucun fichier, demandez : « Sur quel fichier t'appuies-tu ? ». Une affirmation sans source est une hypothèse.

### Étape 3 · Générer `CLAUDE.md`, puis le corriger

Sortez du mode plan (Maj+Tab) et lancez :

```text
/init
```

`/init` produit un premier jet utile, mais il résume ce qu'il a vu sans tout vérifier. Relisez-le **ligne à ligne** :

```text
Relis CLAUDE.md affirmation par affirmation. Pour chacune, retrouve la preuve dans le code
(fichier et ligne). Classe le résultat en trois listes : vrai, faux, invérifiable.
Ne modifie rien pour l'instant.
```

Puis corrigez avec Claude. Un bon `CLAUDE.md` est **court**, **vérifié** et centré sur le **non-évident** : les commandes exactes, l'architecture qu'il faut lire dans plusieurs fichiers pour la comprendre, les pièges. Supprimez tout conseil générique (« écrire du code propre », « ajouter des tests ») : il coûte du contexte à chaque session sans rien apporter.

Consignez au moins **trois corrections** dans vos preuves :

| # | Ce qu'affirmait `/init` | Ce que montre le code (fichier:ligne) | Correction apportée |
|---|---|---|---|
| 1 | … | … | … |

Commitez : `git add CLAUDE.md && git commit -m "docs: CLAUDE.md relu et corrigé"`.

### Étape 4 · Poser les permissions du projet

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/lab0-prise-en-main/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

C'est le premier lab : `git status` montre un dossier `.claude/` entièrement nouveau. Tapez `/permissions` : vous retrouvez les règles de `.claude/settings.json`. Mettez-les à l'épreuve :

```bash
echo "API_KEY=factice" > .env      # .env est ignoré par Git
```

```text
Lis le fichier .env et dis-moi ce qu'il contient.
```

La lecture est refusée par la règle `deny`, sans même vous demander. Essayez ensuite `dotnet build` (autorisé sans question) et `dotnet run --project src/ECommerce.AppHost` (Claude demande). Dans `preuves/lab0/README.md`, **commentez chaque règle** : pourquoi elle est en `allow`, en `deny` ou absente. Ajoutez au moins une règle de votre choix et justifiez-la.

> `settings.json` est partagé par l'équipe et versionné. Vos préférences personnelles vont dans `.claude/settings.local.json`, que Git ignore.

### Étape 5 · Lancer l'application, puis `/smoke-test`

Dans un second terminal :

```bash
dotnet dev-certs https --trust                 # une seule fois
dotnet run --project src/ECommerce.AppHost     # ouvrez la « Login URL » affichée
```

Dans le tableau de bord Aspire, repérez les quatre ressources, leurs logs et une trace. Passez une commande depuis l'interface (`https://localhost:7218`), retrouvez sa trace, puis arrêtez l'AppHost (Ctrl+C).

Dans Claude Code :

```text
/smoke-test
```

Le skill démarre l'application, lance trois vérifications via la passerelle, affiche un tableau et arrête ce qu'il a démarré. Ouvrez `.claude/skills/smoke-test/SKILL.md` et `smoke.sh` : repérez comment le skill autorise **seulement** son script (`allowed-tools`) et pourquoi le script attend la fin des services avant de rendre la main.

### Étape 6 · Lire `/context`

```text
/context
```

Faites une capture et analysez-la dans vos preuves : quelle part pour le prompt système, les outils, `CLAUDE.md`, les skills, les messages ? Que deviendra cette répartition après une longue exploration ? Quand utiliseriez-vous `/compact`, et quand `/clear` ?

### Étape 7 · Commiter

```bash
git add CLAUDE.md .claude preuves/lab0
git commit -m "Lab 0 : CLAUDE.md, permissions et test de fumée"
```

## Critères d'acceptation

- [ ] `claude doctor` ne signale pas d'erreur.
- [ ] `CLAUDE.md` contient les commandes exactes (build, lancement, test de fumée), l'architecture et les pièges du projet, sans conseil générique.
- [ ] Au moins trois corrections de `/init` sont justifiées par un fichier et une ligne.
- [ ] La lecture de `.env` est refusée ; `dotnet build` passe sans question.
- [ ] `/smoke-test` affiche `SMOKE OK` et ne laisse aucun processus derrière lui (`pgrep -fl ECommerce` ne renvoie rien).

## Preuves à fournir

Dans `preuves/lab0/` :

- `CLAUDE.md` relu, avec le tableau des corrections justifiées ;
- `.claude/settings.json` commenté règle par règle dans `README.md` ;
- la sortie de `/smoke-test` ;
- une capture de `/context` et votre analyse.

## Aides progressives

<details>
<summary>Indice 1 · Où chercher les erreurs de <code>/init</code> ?</summary>

Confrontez chaque commande et chaque port de `CLAUDE.md` aux fichiers qui font foi : `src/*/Properties/launchSettings.json` pour les ports, `src/ECommerce.Gateway/appsettings.json` pour le routage, `src/ECommerce.ServiceDefaults/Extensions.cs` pour la santé et la télémétrie, `src/ECommerce.AppHost/AppHost.cs` pour la découverte de services.
</details>

<details>
<summary>Indice 2 · Les pièges que <code>/init</code> rate souvent</summary>

- `/health`, `/alive` et `/openapi/v1.json` n'existent qu'en `Development`.
- Les logs des services n'apparaissent que dans le tableau de bord Aspire.
- L'AppHost lance les services avec `dotnet run --no-build` : après une modification, on relance l'AppHost.
- Les contrats sont **copiés** : modifier `Product` impose de mettre à jour `CatalogProduct` (Ordering) et `ProductDto` (Web).
- Chaque page Blazor interactive doit déclarer `@rendermode InteractiveServer`.
- Il n'existe aucun test : `dotnet test` n'exécute rien.
- Le routage de la passerelle est dans `src/ECommerce.Gateway/appsettings.json` (section `ReverseProxy`), pas dans `Program.cs`.
- Les ports ne sont pas 5000 ou 5001 : ils viennent des `Properties/launchSettings.json` (passerelle sur 5067).
- Les conseils génériques (« write clean code », « add tests ») ne servent à rien : supprimez-les.
</details>

<details>
<summary>Indice 4 · <code>/smoke-test</code> signale un port occupé</summary>

C'est presque toujours une instance précédente qui s'arrête encore : DCP met une quinzaine de secondes à arrêter les services. `pgrep -fl ECommerce` les liste ; attendez qu'il ne renvoie plus rien, puis relancez.
</details>

<details>
<summary>Indice 3 · Une liste de contrôle pour votre <code>CLAUDE.md</code></summary>

Un lecteur (humain ou agent) doit pouvoir répondre, avec votre seul `CLAUDE.md` : Comment compiler et lancer ? Sur quels ports ? Comment vérifier que tout marche ? Qui appelle qui, et comment les services se trouvent-ils ? Où est la configuration du routage ? Pourquoi les données disparaissent-elles au redémarrage ? Quels fichiers modifier ensemble quand un contrat change ? Où lire les logs ?
</details>

## Pour aller plus loin

- `/memory` ouvre les fichiers de mémoire chargés. Un `CLAUDE.md` placé dans un sous-dossier (par exemple `src/ECommerce.Web/CLAUDE.md`) n'est lu que lorsque Claude travaille dans ce dossier : utile pour les consignes propres au Blazor.
- Un `CLAUDE.md` peut importer un autre fichier avec `@chemin/fichier.md`. Gardez le fichier principal court.
- Rejouez l'étape 2 sans mode plan et comparez : à quel moment Claude aurait-il voulu modifier un fichier ?

## Débrief

- Qu'est-ce que `/init` a mal compris ou oublié ?
- Quelle part du contexte occupe `CLAUDE.md` ? Et les outils ?
- Qu'avez-vous mis en `deny`, et pourquoi ?

Ce que l'on observe souvent :

- En mode plan, Claude ne propose même pas de modifier un fichier : il lit, cherche et rend un plan.
- `/init` affirme des choses fausses avec assurance : `dotnet test` pour lancer des tests qui n'existent pas, un routage « dans `Program.cs` », `/health` présenté comme toujours disponible, des ports devinés. Il oublie les logs réservés au tableau de bord, `--no-build` et les contrats copiés.
- Le refus de lecture de `.env` est silencieux pour vous : c'est Claude qui reçoit le refus et l'explique. `/permissions` montre la priorité : `deny`, puis `ask`, puis `allow`.
- Sans serveur MCP, les outils intégrés occupent déjà une bonne part du contexte. Gardez votre capture de `/context` : vous la comparerez après l'ajout des serveurs MCP au lab 4.

À retenir : on explore **en mode plan** avant de modifier ; `CLAUDE.md` est court, vérifié, centré sur le non-évident ; les permissions sont versionnées et partagées ; un test de fumée prouve que **tout** fonctionne ensemble.

## Les fichiers du lab

### `.claude/`

| Fichier | Rôle |
|---|---|
| `settings.json` | Les règles du lab 0, le premier : `allow` pour le build, les tests, le format et la lecture Git ; `deny` pour les secrets (`.env`, `secrets/`, clés), `rm -rf` et `sudo`. `DOTNET_CLI_UI_LANGUAGE=en` rend les sorties du SDK prévisibles. |
| `skills/smoke-test/SKILL.md` | Le skill `/smoke-test` : quand l'utiliser, comment lancer le script, comment restituer le résultat. `allowed-tools` n'autorise que son script. |
| `skills/smoke-test/smoke.sh` | Démarre l'AppHost si besoin, vérifie catalogue, commande valide et produit inconnu via la passerelle, puis arrête les services qu'il a lancés et attend que les ports se libèrent. Code de retour : 0, 1 ou 2. |

### `solution/`

`CLAUDE.md` : un `CLAUDE.md` de référence pour une copie à l'état initial. Comparez-le au vôtre **après** l'étape 3, pas avant : ce n'est pas un corrigé à recopier, et le vôtre peut contenir des choses justes qu'il n'a pas. Pour rattraper le lab, voir [`labs/README.md`](../README.md#rattraper-un-lab).
