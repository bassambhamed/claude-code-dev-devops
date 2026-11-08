# Les labs : développement agentique avec Claude Code

Chaque lab part d'un **problème réel** de l'application ECommerce et le résout avec un mécanisme de Claude Code. Les labs s'enchaînent : le dossier `.claude/` de votre copie s'enrichit d'un lab à l'autre, jusqu'au capstone, où une équipe d'agents livre une fonctionnalité complète sous une porte qualité que vous aurez construite.

Les supports de cours (`../slides/`) indiquent le moment exact de chaque bascule : la diapositive orange « À vous de jouer » présente le lab, puis le débrief qui suit en tire les leçons.

## Le parcours

| Étape | Dossier | Mise en situation | Mécanismes travaillés | Partie |
|---|---|---|---|---|
| Lab 0 | [`lab0-prise-en-main`](lab0-prise-en-main/) | Premier jour dans l'équipe ECommerce | `/init`, `CLAUDE.md`, mode plan, permissions, `/context` | 2 |
| Lab 1 | [`lab1-git-github`](lab1-git-github/) | Des commandes au total négatif | Prompt structuré, revue de diff, commande `/revue-diff`, skill `/ship` | 3 et 4 |
| Lab 2 | [`lab2-tests`](lab2-tests/) | Aucune couverture, une erreur 500 | Skill `/test-integration`, rouge puis vert, hook `Stop` | 5 |
| Lab 3 | [`lab3-securite-secrets`](lab3-securite-secrets/) | Un secret commité, des dépendances vulnérables | Sous-agents de revue, `deny`, hook `PreToolUse`, CI de sécurité | 6 |
| Lab 4 | [`lab4-postgresql`](lab4-postgresql/) | Les données disparaissent au redémarrage | Skill `/review-migration`, MCP en lecture seule, Testcontainers | 7 |
| Lab 5 | [`lab5-frontend`](lab5-frontend/) | Retrouver les commandes d'un client | Critères visuels, sous-agent `ui-verifier`, navigateur via MCP | 7 |
| Atelier | [`atelier-plugin-dotnet-team`](atelier-plugin-dotnet-team/) | Dix dépôts, un seul dispositif | Plugin, marketplace, `${CLAUDE_PLUGIN_ROOT}` | 8 |
| Lab 6 | [`lab6-ci-cd`](lab6-ci-cd/) | Des revues 100 % manuelles | `claude -p`, prompt versionné, sortie JSON, gate | 9 |
| Lab 7 | [`lab7-conteneurs`](lab7-conteneurs/) | « Ça marche sur mon poste » | Skill `/revue-docker`, sous-agent `docker-reviewer`, scan d'images | 9 |
| Lab 8 | [`lab8-kubernetes`](lab8-kubernetes/) | Une application dégradée | Skill `/diagnostic-k8s`, hook `garde-kubectl`, actions bornées | 10 |
| Lab 9 | [`lab9-helm`](lab9-helm/) | Deux environnements à servir | Skill `/revue-chart`, relecture des rendus | 10 |
| Lab 10 | [`lab10-observabilite`](lab10-observabilite/) | « Les commandes sont lentes » | MCP Aspire et Grafana, skill `/diagnostic-traces`, métrique métier | 10 |
| Lab 11 | [`lab11-incident`](lab11-incident/) | Des totaux à 0 € | Skill `/incident`, `git bisect run`, post-mortem | 11 |
| Capstone | [`capstone`](capstone/) | Date de livraison souhaitée | Orchestrateur, équipe d'agents, référentiel Code Health, porte qualité | 12 |

Les trois premières phases (labs 0 à 5 et l'atelier) forment un socle autonome. Les labs 6 à 11 constituent l'extension consacrée à l'industrialisation, au déploiement, à l'observabilité et aux incidents.

## Avant le premier lab

Le poste de travail :

| À partir de | Outils |
|---|---|
| Lab 0 | SDK .NET 10, Git, Claude Code avec un compte actif, `jq` |
| Lab 1 | Un compte GitHub et la CLI `gh` (`gh auth login`) |
| Lab 4 | Docker (PostgreSQL, Testcontainers, serveurs MCP en conteneur) |
| Lab 5 | Node.js 20 ou plus (serveur MCP Playwright) |
| Lab 7 | Un scanner d'images : `trivy` ou `docker scout` |
| Labs 8 et 9 | `k3d`, `kubectl`, `helm` |
| Lab 10 | Le conteneur `grafana/otel-lgtm` |

```bash
dotnet --version                 # 10.x
git --version && gh auth status
claude --version && claude doctor
jq --version
```

Tous les labs désignent le dossier de formation par la variable `FORMATION`. Définissez-la une fois pour toutes dans votre `~/.zshrc` ou `~/.bashrc` :

```bash
export FORMATION="<chemin complet du dossier de formation>"
```

Travaillez **toujours dans votre copie** de l'application, jamais dans le dossier de formation :

```bash
cp -r "$FORMATION"/ecommerce-app ~/lab-ecommerce
cd ~/lab-ecommerce && git init -b main
git add . && git commit -m "Etat initial"
```

## Ce que contient chaque lab

```
labN-…/
├── README.md     les étapes du lab, à suivre dans l'ordre
├── .claude/      le dispositif Claude Code du lab : skills, commandes, sous-agents, hooks, settings.json
├── ressources/   ce que le lab utilise en plus : scripts de préparation, modèles, .mcp.json… (si besoin)
└── solution/     l'état de la copie à la fin du lab, pour rattraper un lab manqué (si besoin)
```

Formateur et participants ont les mêmes fichiers : le formateur déroule le README avec le groupe.

Chaque README suit le même plan :

1. **Pourquoi ce lab** : le problème réel, et ce que le mécanisme change.
2. **Objectifs** et **point de départ** : l'état attendu de votre copie, les outils, l'installation du dispositif.
3. **Mise en situation**.
4. **Étapes guidées**, avec les prompts proposés et ce qu'il faut observer.
5. **Critères d'acceptation** et **preuves à fournir**.
6. **Aides progressives** : indice 1, 2, 3…, à ouvrir seulement si vous bloquez.
7. **Pour aller plus loin**.
8. **Débrief** : les questions posées en salle, ce que l'on observe souvent, ce qu'il faut retenir.
9. **Les fichiers du lab** : `.claude/`, `ressources/` et `solution/`, fichier par fichier.

## Installer le dispositif d'un lab

Chaque README le rappelle au moment voulu, avec la même commande :

```bash
cp -R "$FORMATION"/labs/<lab>/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

- Les skills, commandes, sous-agents et hooks du lab **s'ajoutent** à ceux des labs précédents.
- Le `settings.json` du lab est **cumulé** : il contient les règles de tous les labs précédents, plus celles du lab. Il remplace donc le vôtre. Si `git diff` montre la suppression de règles que vous aviez ajoutées vous-même, remettez-les. Le `.mcp.json` des labs qui en fournissent un (dans `ressources/`) est cumulé de la même façon.
- Les réglages et les hooks sont lus au démarrage : relancez Claude Code après l'installation.
- Relisez ce que vous installez avant de le commiter : c'est votre dispositif d'équipe.

Les scripts de `ressources/` (injection d'un secret, d'un défaut, d'un historique d'incident…) se lancent depuis n'importe quel dossier, en leur passant votre copie :

```bash
bash "$FORMATION"/labs/<lab>/ressources/<script>.sh ~/lab-ecommerce
```

## Rattraper un lab

Les labs s'enchaînent : chacun part de l'état où le précédent a laissé votre copie. Si vous avez manqué un lab, ou s'il n'est pas terminé, appliquez dans l'ordre le dispositif **et** la solution de chaque lab manqué, puis commitez :

```bash
cp -R "$FORMATION"/labs/<lab>/.claude/. ~/lab-ecommerce/.claude/
cp -R "$FORMATION"/labs/<lab>/solution/. ~/lab-ecommerce/
git -C ~/lab-ecommerce add -A && git -C ~/lab-ecommerce commit -m "Rattrapage : <lab>"
```

`solution/` ne contient que les fichiers que le lab ajoute ou modifie, dans leur état final. La copie écrase vos versions de ces fichiers : commitez votre travail avant, pour pouvoir comparer avec `git diff HEAD~1`. Les recettes des labs permettent de produire les preuves propres à votre poste. Les preuves, elles, ne se rattrapent pas.

## Deux façons de travailler

- **Mode guidé** : installez le `.claude/` du lab, lisez chaque fichier, puis utilisez-le. Les étapes du README vous font comprendre pourquoi il est écrit ainsi.
- **Mode autonome** : construisez vous-même vos skills, sous-agents et hooks à partir de l'énoncé, puis comparez avec le `.claude/` du lab. C'est plus long, et c'est là qu'on apprend le plus.

Les deux modes produisent les mêmes preuves.

## Vos preuves

Rangez les preuves de chaque lab dans votre copie, sous `preuves/labN/` : un `README.md` (vos réponses, vos arbitrages, les commandes lancées et leur sortie), plus les captures. Commitez-les avec le lab : elles servent au débrief et à l'évaluation du capstone.

## Conventions

- Les prompts proposés sont en français. Le code, les commentaires et les messages d'erreur de l'application restent **en anglais**, comme dans le reste du dépôt : précisez-le à Claude si besoin.
- Un lab se termine par un commit propre, ou par une PR à partir du lab 1.
- Les commandes `dotnet` se lancent depuis la racine de votre copie (le dossier qui contient `ECommerce.slnx`).
- Sur un poste en français, le SDK affiche certains messages en français. Les scripts testent des codes de retour, jamais du texte ; les réglages des labs définissent `DOTNET_CLI_UI_LANGUAGE=en` pour les commandes lancées par Claude.
- Les secrets utilisés dans les labs (préfixe `ecpk_`) sont **factices** : ils ne donnent accès à rien, mais on les traite comme de vrais secrets.
