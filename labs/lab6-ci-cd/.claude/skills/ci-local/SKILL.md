---
name: ci-local
description: Rejoue en local la chaîne de CI de l'équipe (build, tests, format des fichiers modifiés, audit NuGet, gitleaks) avec les mêmes commandes que les workflows, puis donne le verdict de la gate. À utiliser avant de pousser une branche, ou pour comprendre pourquoi la CI est rouge.
argument-hint: "[étapes : build tests format audit secrets] [--base <réf>]"
allowed-tools: Bash(bash *.claude/skills/ci-local/ci-local.sh*), Bash(git status *), Bash(git diff *), Bash(git log *)
---
# Rejouer la CI en local

## État actuel
- Branche : !`git branch --show-current`
- Fichiers non commités : !`git status --short`

## Lancer la chaîne

Depuis la racine du dépôt (le dossier qui contient `ECommerce.slnx`), lance le script du
skill avec un délai d'attente de 10 minutes : un premier build et le démarrage des
conteneurs PostgreSQL des tests prennent du temps.

```bash
bash ${CLAUDE_SKILL_DIR}/ci-local.sh $ARGUMENTS
```

Sans argument, le script exécute les cinq étapes. Il ne modifie aucun fichier suivi par Git.
Ne lance pas toi-même les commandes une à une : le script est la définition locale de la
chaîne, aligné sur `.github/workflows/ci.yml` et `.github/workflows/securite.yml`.

## Restitution

1. Recopie tel quel le tableau des étapes, puis la dernière ligne : `GATE OUVERTE`,
   `GATE FERMÉE` ou `GATE INCOMPLÈTE`.
2. Pour chaque étape en `ÉCHEC`, donne la cause en citant l'extrait affiché : test en échec
   avec valeurs attendue et obtenue, erreur de compilation, fichier et ligne de format,
   paquet vulnérable, règle gitleaks (jamais la valeur d'un secret). Indique la commande qui
   permet de rejouer cette étape seule (`ci-local.sh tests`, par exemple).
3. Pour chaque étape `NON EXÉCUTÉ`, dis ce qui manque. Une étape non exécutée n'est pas une
   étape réussie : la gate reste incomplète.
4. Si le script signale des fichiers non commités, rappelle que la CI ne verra que les
   commits.

## Interdits

- Ne corrige rien pendant ce skill : tu constates et tu expliques. La correction est une
  demande séparée de l'utilisateur.
- Ne contourne jamais une étape (option, suppression d'un test, `.gitleaksignore`,
  exclusion du format) pour ouvrir la gate.
