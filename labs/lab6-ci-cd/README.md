# Lab 6 · Des revues 100 % manuelles

> Partie 9 des supports · Mécanismes : `claude -p`, prompt versionné, JSON structuré, `/ci-local`, gate déterministe

## Pourquoi ce lab

Une revue humaine répétitive laisse passer des défauts et prend du temps. On rejoue les contrôles sur le poste et en CI, puis on ajoute une revue IA informative. La livraison dépend de résultats reproductibles : une réponse convaincante de l'agent ne suffit pas à ouvrir la gate.

## Objectifs

- Exécuter build, tests, format et sécurité localement puis sur GitHub.
- Produire une revue JSON conforme à un schéma versionné.
- Distinguer échec déterministe, indisponibilité d'un outil et avis IA.
- Démontrer qu'un défaut injecté ferme Gate.

## Point de départ

Copie à la fin du lab 5, atelier plugin réalisé, dépôt GitHub, Docker (tests PostgreSQL), gitleaks, `jq`, Claude Code actif. Branche `ci/quality-gate`. La revue GitHub utilise un secret `ANTHROPIC_API_KEY` configuré par le propriétaire dans les secrets Actions ; sa valeur ne passe pas par la session.

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/lab6-ci-cd/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

## Mise en situation

Une « simplification » du calcul des totaux est proposée. Les revues ne doivent pas dépendre de la disponibilité d'un modèle, et l'équipe veut retrouver la même cause d'échec en local et sur GitHub.

## Étapes

Toutes les commandes se lancent depuis la racine de votre copie, sauf indication contraire.

### Étape 1 · Relire la chaîne locale

```bash
bash .claude/skills/ci-local/ci-local.sh
```

Le script rend un tableau et conserve les journaux temporaires. Codes : `0` gate ouverte, `1` échec, `3` contrôle non exécuté, `2` usage. Une absence de Docker ou gitleaks n'est jamais un succès. Le format porte sur les fichiers C# modifiés depuis main ; les écarts historiques ne sont pas masqués si vous touchez ces fichiers.

### Étape 2 · Installer les workflows et leur gate

```text
Crée CI à partir du corrigé fourni : jobs build-tests, format sur fichiers modifiés,
sécurité réutilisable, puis Gate avec always(), needs et contrôle de tous les résultats
success. Conserve les droits contents:read. Le workflow sécurité doit exposer
workflow_call. Explique skipped, cancelled et failure dans la décision finale.
```

Vous pouvez copier `solution/.github/workflows/` pour rattraper. Lisez chaque fichier avant commit. Validez les workflows avec actionlint (binaire local ou conteneur indiqué dans les permissions du lab). Sur GitHub, configurez la protection de main pour exiger **Gate**. La protection de branche est une configuration externe au dépôt : une case cochée dans le README ne l'active pas.

### Étape 3 · Une revue structurée en local

Lisez `.claude/prompts/revue-pr.md` et `schema-revue.json`. Préparez le diff et envoyez-le comme données, jamais comme instructions :

```bash
git diff main...HEAD > /tmp/ecommerce-pr.diff
{ cat .claude/prompts/revue-pr.md; printf '\nDiff à lire :\n'; cat /tmp/ecommerce-pr.diff; } |   CLAUDE_SKIP_STOP_TESTS=1 claude -p --tools Read,Grep,Glob   --permission-mode dontAsk --max-turns 8 --max-budget-usd 1   --output-format json --json-schema "$(jq -c . .claude/prompts/schema-revue.json)"   > /tmp/ecommerce-revue.json
jq '.structured_output' /tmp/ecommerce-revue.json
```

L'enveloppe CLI contient `structured_output` : vérifiez la présence et la conformité de cette valeur, pas seulement la validité JSON de l'enveloppe. Le schéma de revue exige une preuve et un emplacement pour chaque constat. Aucun résultat de ce lab ne doit être annoncé sans l'avoir obtenu.

### Étape 4 · La revue GitHub

Le workflow `revue-ia.yml` lit consigne et schéma depuis la branche cible et limite l'agent à Read/Grep/Glob. Il valide le résultat puis un job séparé publie le commentaire. La première PR qui ajoute la consigne est ignorée côté IA ; les suivantes l'utilisent. Les PR de forks ne reçoivent pas le secret Actions : leur revue IA peut rester indisponible, la gate déterministe doit rester exploitable.

Sur votre dépôt privé de formation, configurez le secret puis ouvrez une PR de test. Conservez la version de la consigne, le SHA relu et la sortie JSON, sans jeton.

### Étape 5 · Prouver le blocage

Terminez d'abord la branche CI et revenez sur main à jour. Puis :

```bash
bash "$FORMATION"/labs/lab6-ci-cd/ressources/injecter-defaut.sh ~/lab-ecommerce
bash .claude/skills/ci-local/ci-local.sh
```

Le défaut oublie la quantité dans Total ; le test correspondant doit échouer, Gate doit fermer. Ouvrez une PR sur votre dépôt de formation et relevez les résultats CI. Réparez la formule sans affaiblir le test et observez le passage au vert.

Une seconde expérience, `injecter-defaut.sh ~/lab-ecommerce --invisible`, introduit un Catalog en localhost. Les factories le masquent : tests verts possibles, relecture nécessaire. Comparez l'avis IA, le diff et l'architecture de `CLAUDE.md` ; aucun avis n'est une preuve d'absence de défaut.

### Étape 6 · Livrer les règles

Documentez la seule vérification obligatoire Gate, les causes d'indisponibilité de la revue et les commandes locales. `/ship Chaîne de validation et revue structurée`.

## Critères d'acceptation

- [ ] Même build/tests/format/audit/secrets en local et en CI.
- [ ] Gate traite tous les résultats, y compris skipped et cancelled ; protection main configurée.
- [ ] Revue JSON validée, consigne depuis la branche cible, droits et budget bornés.
- [ ] La revue IA informe ; elle n'appartient pas aux needs de Gate.
- [ ] Défaut quantité : tests rouges et gate fermée, correctif puis verts.

## Preuves à fournir

Dans `preuves/lab6/` : sorties `/ci-local` avant/après, URLs des exécutions CI et de la PR, capture de la protection main, diff injecté, JSON de revue validé, comparaison des constats et arbitrage humain. Signalez explicitement les actions GitHub non exécutées.

## Aides progressives

<details><summary>Indice 1 · Sécurité réutilisable refusée</summary>Le workflow appelé avec uses doit déclarer on.workflow_call.</details>

<details><summary>Indice 2 · Gate reste ignorée</summary>Un job qui dépend d'un échec est ignoré sans if: always(). Vérifiez ensuite que chaque résultat vaut success.</details>

<details><summary>Indice 3 · L'IA ne relit pas la première PR</summary>La consigne n'existe pas encore sur main. Fusionnez son installation, puis testez une nouvelle PR.</details>

## Pour aller plus loin

Épinglez les actions par SHA vérifié et automatisez leur mise à jour. Ajoutez les rendus Helm à la validation quand ils existent. Définissez une politique de rétention pour les rapports.

## Débrief

Quelle différence entre fail et non exécuté ? Quel défaut échappe aux tests ? **À retenir :** la gate décide à partir de contrôles déterministes ; la revue apporte une lecture supplémentaire, avec ses limites.

## Les fichiers du lab

- `.claude/settings.json` : règles cumulées ; `.claude/prompts/revue-pr.md`, `schema-revue.json` : contrat de revue.
- `.claude/skills/ci-local/SKILL.md`, `ci-local.sh` : chaîne locale et codes de sortie.
- `ressources/injecter-defaut.sh` : deux branches de défauts, sans push.
- `solution/.github/workflows/ci.yml` : contrôles et Gate ; `securite.yml` : workflow réutilisable ; `revue-ia.yml` : revue informative et publication séparée.
