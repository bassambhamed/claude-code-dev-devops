# Atelier · Dix dépôts, un seul dispositif

> Partie 8 des supports · Mécanismes : plugin, marketplace locale, `${CLAUDE_PLUGIN_ROOT}`

## Pourquoi ce lab

Copier .claude dans dix dépôts fait diverger les procédures. Un plugin versionne les composants communs et une marketplace les distribue. Les règles propres à l'application restent près de son code.

## Objectifs

- Choisir les composants communs et les paramètres propres au dépôt.
- Empaqueter skills, commandes, agents et hooks dans dotnet-team 1.0.0.
- Valider le plugin, sa marketplace et son exécution depuis une copie propre.

## Point de départ

Copie à la fin du lab 5, commitée. Claude Code avec prise en charge des plugins, Git, .NET et jq. Branche `chore/team-plugin`. L'atelier ne change pas le comportement de l'application.

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/atelier-plugin-dotnet-team/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

## Mise en situation

L'équipe maintient dix services .NET. Une correction du hook de secrets doit atteindre chaque dépôt et sa version doit être identifiable. Il faut prouver que le plugin fonctionne même quand les anciens fichiers locaux n'existent plus.

## Étapes

Toutes les commandes se lancent depuis la racine de votre copie, sauf indication contraire.

### Étape 1 · Faire l'inventaire

Listez les skills, commandes, agents, hooks, permissions, MCP et CLAUDE.md. Décidez ce qui est partageable. Gardez permissions et connexions MCP dans le projet : une URL de base, un chemin de poste ou des droits de déploiement ne sont pas une pratique universelle.

### Étape 2 · Construire le paquet

```text
Extrais nos skills et leurs fichiers annexes, les agents et hooks dans
outillage/dotnet-team. Le manifeste est .claude-plugin/plugin.json ; skills,
commands, agents et hooks sont à la racine du plugin. Déclare les hooks dans
hooks/hooks.json avec ${CLAUDE_PLUGIN_ROOT}. Garde ${CLAUDE_SKILL_DIR} pour les
scripts des skills. Version 1.0.0, guide d'utilisation et changelog.
```

Le corrigé `solution/outillage/` contient le paquet complet. Inspectez les chemins absolus, les permissions allowed-tools qui mentionnent encore `.claude/skills`, et les scripts annexes souvent oubliés. Les hooks du plugin se lancent avec bash pour rester exécutables après distribution.

### Étape 3 · Déclarer une marketplace

Créez `outillage/.claude-plugin/marketplace.json`, nom `formation-dotnet`, propriétaire `Équipe ECommerce`, entrée `dotnet-team`, source `./dotnet-team` relative à la racine d'outillage.

```bash
claude plugin validate ./outillage/dotnet-team
claude plugin validate ./outillage
```

Une validation réussie prouve la structure, pas l'exécution des hooks ou des skills.

### Étape 4 · Tester dans une copie propre

Créez une copie temporaire de l'application de travail **sans son .claude**, hors de la formation ; initialisez Git et commitez. Conservez uniquement `permissions` et `env` dans un nouveau `.claude/settings.json`, sans les hooks locaux. Gardez CLAUDE.md et le MCP si vous testez l'UI. Depuis cette copie :

```bash
claude --plugin-dir /chemin/absolu/vers/lab-ecommerce/outillage/dotnet-team
```

Vérifiez `/help`, `/agents`, `/hooks` puis `/dotnet-team:smoke-test`. Sur une branche, testez `/dotnet-team:ship` jusqu'aux vérifications locales. Un push/une PR exige un dépôt distant configuré et la décision explicite de la personne ; n'inventez pas d'URL.

Démontrez le hook de secrets avec une écriture contenant une clé factice `ecpk_test_` suivie de 32 chiffres hexadécimaux. Le hook doit refuser sans écrire le fichier. Gardez le code de retour et le message, pas la valeur. Vérifiez qu'une écriture anodine passe.

### Étape 5 · Installer depuis la marketplace

Toujours dans la copie de test :

```bash
claude plugin marketplace add /chemin/absolu/vers/lab-ecommerce/outillage
claude plugin install dotnet-team@formation-dotnet
```

Relancez Claude, vérifiez `/plugin` et les commandes. Retirez l'option `--plugin-dir` lors de ce test pour éviter un double chargement. Le cache du plugin n'est pas le dossier source : modifiez la source, pas le cache.

### Étape 6 · Documenter et poursuivre

Consignez version, commandes, fichiers laissés dans le projet et procédure de mise à jour. Commitez outillage. **Les labs suivants continuent avec les fichiers locaux cumulés** : désactivez le plugin installé sur la copie principale ou gardez son installation limitée à la copie de test, sinon les hooks seront exécutés deux fois.

## Critères d'acceptation

- [ ] Plugin valide en version 1.0.0, composants et fichiers annexes présents.
- [ ] Marketplace valide, installation visible dans /plugin.
- [ ] Un skill et un hook démontrés depuis une copie sans composants locaux.
- [ ] Aucun chemin personnel ni secret dans le paquet.
- [ ] Permissions, CLAUDE.md et connexions restent propres au dépôt ; aucun hook doublé.

## Preuves à fournir

Dans `preuves/atelier-plugin/` : inventaire et arbitrages, sorties de validation, version installée, skill exécuté, hook accepté/refusé, guide et procédure de mise à jour. Les captures de /plugin sont à produire lors de l'installation réelle.

## Aides progressives

<details><summary>Indice 1 · Aucun skill visible</summary>skills est au même niveau que .claude-plugin, pas à l'intérieur.</details>

<details><summary>Indice 2 · Script introuvable</summary>Le chemin du plugin installé diffère de celui du dépôt. Utilisez CLAUDE_PLUGIN_ROOT pour hooks et CLAUDE_SKILL_DIR pour les ressources d'un skill.</details>

<details><summary>Indice 3 · Les tests tournent deux fois</summary>Vérifiez /hooks : les hooks du projet et du plugin se cumulent. Testez dans une copie sans hooks locaux.</details>

## Pour aller plus loin

Publiez la marketplace dans un dépôt Git privé de l'équipe, avec revue des modifications et versionnement. Testez une mise à jour 1.0.1 avant diffusion.

## Débrief

Qu'est-ce qui dépend encore de l'application ? Quel oubli n'apparaît que dans la copie propre ? **À retenir :** le plugin distribue une pratique versionnée ; l'installation réelle doit être vérifiée sans dépendance implicite aux fichiers locaux.

## Les fichiers du lab

- `.claude/settings.json` : réglages cumulés du lab 5, sans activer le plugin dans la copie principale.
- `solution/outillage/.claude-plugin/marketplace.json` : catalogue local.
- `solution/outillage/dotnet-team/.claude-plugin/plugin.json` : identité et version.
- `solution/outillage/dotnet-team/skills/`, `commands/`, `agents/`, `hooks/` : composants complets et hooks.json.
- `solution/outillage/dotnet-team/README.md` : usage, limites, mise à jour et changelog.

## Références

[Manifeste et chemins des plugins](https://code.claude.com/docs/en/plugins-reference) · [Créer une marketplace](https://code.claude.com/docs/en/plugin-marketplaces).
