# Lab 1 · Des commandes au total négatif

> Partie A : partie 3 des supports (prompting) · Partie B : partie 4 (commandes et skills)
> Mécanismes : anatomie du prompt, exemples et chaînage, mode plan, revue critique, commande `/revue-diff`, skill `/ship`, permissions Git · Prérequis : lab 0

## Pourquoi ce lab

« Corrige la validation des commandes » paraît clair. Pour Claude, c'est une spécification à trous : quels champs, quelles limites, quel format d'erreur, quels fichiers, quelle preuve ? Tout ce qui n'est pas dit est **deviné**, et chaque supposition est un risque de diff trop large, de contrat cassé ou de travail invérifiable.

- La **partie A** vous fait mesurer cet écart : le même bug, un prompt vague sur une branche, un prompt structuré sur une autre. Vous comparez les diffs.
- La **partie B** transforme la procédure de livraison de l'équipe (vérifier, relire, committer, ouvrir une PR) en un **skill** versionné, encadré par des permissions Git : Claude prépare tout, mais ne pousse jamais sans votre accord.

## Objectifs

- Reproduire un bug avec des preuves exécutables.
- Construire un prompt avec rôle, contexte, instruction, contraintes, exemples et format, puis le faire exécuter en mode plan.
- Vérifier un correctif critère par critère, puis faire relire le diff de manière critique.
- Lire et utiliser une commande personnalisée, étudier et adapter un skill.
- Livrer par une PR GitHub documentée, sous permissions `ask` et `deny`.

## Point de départ

- Votre copie avec le lab 0 terminé et commité, sur la branche `main`.
- L'application lancée dans un second terminal : `dotnet run --project src/ECommerce.AppHost`.
- Pour la partie B : un compte GitHub et `gh auth status` au vert. Sans compte GitHub, suivez la partie B jusqu'à `gh pr create` exclu, et mettez le corps de la PR dans vos preuves.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

## Mise en situation

Le support signale des commandes au total **négatif** et d'autres **sans client**. L'interface Web vérifie le nom du client, mais l'API accepte tout ce que l'interface laisse passer, et plus encore. Vous corrigez la validation côté serveur, puis vous livrez le correctif selon la procédure de l'équipe.

---

## Étapes

### Partie A · Corriger la validation

#### Étape A1 · Reproduire les anomalies

```bash
# Client vide : la commande est acceptée (201)
curl -i -X POST http://localhost:5067/ordering/api/orders -H 'Content-Type: application/json' \
  -d '{"customer":"","items":[{"productId":1,"quantity":2}]}'

# Quantité négative : le total est négatif
curl -s -X POST http://localhost:5067/ordering/api/orders -H 'Content-Type: application/json' \
  -d '{"customer":"Ada","items":[{"productId":1,"quantity":-3}]}' | jq .total
```

Copiez les sorties dans `preuves/lab1/README.md` : ce sont vos preuves « avant ».

#### Étape A2 · Le prompt vague

```bash
git switch -c essai/prompt-vague
claude
```

```text
Corrige la validation des commandes.
```

Laissez Claude travailler sans l'aider. Observez : quels fichiers a-t-il ouverts ? Qu'a-t-il supposé (champs, limites, format des erreurs, interface Web) ? A-t-il vérifié quoi que ce soit ?

```bash
git add -A && git commit -m "essai: prompt vague"
git switch main
```

Vous comparerez les deux diffs à l'étape A5.

#### Étape A3 · Le prompt structuré, en mode plan

```bash
git switch -c fix/validation-commandes
claude --permission-mode plan
```

Partez du modèle [`ressources/modele-prompt.md`](ressources/modele-prompt.md) : il contient un exemple rempli pour ce lab. Relisez-le, ajustez-le, puis envoyez-le. Claude explore et propose un **plan** sans rien modifier :

- Le plan respecte-t-il le périmètre (Ordering.Api uniquement) ?
- Le format des erreurs reste-t-il une chaîne simple ?
- Chaque critère d'acceptation a-t-il sa vérification ?

Corrigez le plan si besoin (« ne touche pas à l'interface Web »), puis acceptez-le pour passer à l'exécution. Vous pratiquez ici le **prompt chaining** : la sortie « plan » du premier échange devient l’entrée du suivant. Les paires entrée/sortie du modèle illustrent le **few-shot** ; gardez une quantité négative comme cas de vérification non montré.

#### Étape A4 · Vérifier critère par critère

Exigez la preuve de chaque critère, pas un « c'est corrigé ». Relancez l'AppHost (les services tournent avec `--no-build`), puis :

| Critère | Requête | Attendu |
|---|---|---|
| Client vide | `{"customer":"","items":[{"productId":1,"quantity":2}]}` | 400 |
| Client de 201 caractères | `{"customer":"<201 × A>","items":[...]}` | 400 |
| Quantité nulle ou négative | `{"customer":"Ada","items":[{"productId":1,"quantity":0}]}` | 400 |
| Commande valide | `{"customer":"Ada","items":[{"productId":1,"quantity":2}]}` | 201 |

```bash
long=$(printf 'A%.0s' {1..201})
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:5067/ordering/api/orders \
  -H 'Content-Type: application/json' -d "{\"customer\":\"$long\",\"items\":[{\"productId\":1,\"quantity\":1}]}"
```

Vérifiez aussi dans l'interface (`https://localhost:7218`) que le message d'erreur s'affiche lisiblement.

#### Étape A5 · La revue critique et la comparaison

Ouvrez une **nouvelle** session (`/clear`) : un relecteur qui n'a pas écrit le code voit mieux ses défauts.

```text
Relis le diff de la branche courante par rapport à main comme un reviewer exigeant.
Signale les défauts ou risques étayés, classés par gravité, avec leur emplacement.
Si aucun défaut n’est étayé, indique ce que tu as vérifié. Ne modifie rien.
```

Arbitrez chaque constat : retenu (vous corrigez) ou rejeté (vous expliquez pourquoi). Comparez enfin les deux diffs : `git diff main essai/prompt-vague --stat` et `git diff main fix/validation-commandes --stat`. Commitez le correctif sur `fix/validation-commandes`.

---

### Partie B · Livrer avec `/ship`

#### Étape B1 · Installer le dispositif et publier le dépôt

Restez sur `fix/validation-commandes` : le dispositif installé fera partie de la PR.

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/lab1-git-github/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

Puis, une seule fois, créez le dépôt GitHub privé et poussez `main` :

```bash
cd ~/lab-ecommerce
gh repo create lab-ecommerce --private --source . --remote origin
git push -u origin main
```

#### Étape B2 · La commande historique `/revue-diff`

Ouvrez `.claude/commands/revue-diff.md`. Repérez l'en-tête (`description`, `argument-hint`, `allowed-tools`), les lignes `` !`git ...` `` exécutées **avant** que Claude ne lise le prompt, et `$ARGUMENTS`. Relancez Claude Code, puis :

```text
/revue-diff validation des entrées et format des erreurs
```

Comparez avec la revue de l'étape A5 : qu'apporte une procédure écrite une fois pour toutes ?

#### Étape B3 · Étudier et adapter le skill `/ship`

Lisez `.claude/skills/ship/` : `SKILL.md`, le gabarit `modele-pr.md` et le script `verifier.sh`.

- Pourquoi `disable-model-invocation: true` ? Que se passerait-il sans ?
- Que couvre `allowed-tools`, et qu'est-ce qui demande quand même une confirmation ?
- Pourquoi `verifier.sh` ne contrôle-t-il le format que sur les fichiers modifiés ?

Adaptez le skill à **votre** équipe : au moins une modification justifiée (une étape, une rubrique du gabarit, une règle de message de commit…). Notez-la dans vos preuves.

#### Étape B4 · Mettre les permissions à l'épreuve

```text
Pousse la branche avec git push --force.
```

La règle `deny` bloque la commande. Lisez `.claude/settings.json` : `git push` et `gh pr create` sont en `ask`, `--force`, `-f` et `reset --hard` en `deny`. Pourquoi plusieurs règles pour le seul `--force` ? (Une règle compare la commande à un motif : `git push origin main --force` et `git push --force origin main` sont deux formes différentes. Le lab 2 ajoute un hook, plus robuste.)

#### Étape B5 · Livrer

```text
/ship Valider les commandes côté serveur
```

Suivez chaque étape. Claude vous demande confirmation avant le `git push`, puis avant `gh pr create` : faites une capture de la demande. Elle vient de la règle `ask` du projet, qui l'emporte sur le `allowed-tools: Bash(git *)` du skill. Ouvrez la PR sur GitHub et relisez-la comme si un collègue l'avait écrite.

> `/rewind` annule les modifications de fichiers d'une session, **pas** un `git push` : ce qui est poussé est partagé.

## Critères d'acceptation

- [ ] Les deux anomalies sont reproduites, avec leur sortie.
- [ ] Sur `fix/validation-commandes` : client vide, blanc ou de plus de 200 caractères → 400 ; quantité < 1 → 400 ; commande valide → 201.
- [ ] Le diff du correctif ne touche qu'Ordering.Api (plus `.claude/` et `preuves/`) ; les erreurs restent des chaînes simples.
- [ ] La PR est ouverte sur GitHub, décrite avec le gabarit, sans rubrique vide.
- [ ] `.claude/skills/ship/` fait partie de la PR, avec votre adaptation.
- [ ] Une demande de confirmation a précédé le push.

## Preuves à fournir

Dans `preuves/lab1/` :

- les deux prompts et la comparaison de leurs diffs ;
- un `curl` avant et après par critère d'acceptation ;
- la revue critique du diff et vos arbitrages ;
- l'URL de la PR, la capture de la confirmation avant le push, vos modifications du skill et leur raison.

## Aides progressives

<details>
<summary>Indice 1 · Le prompt structuré produit encore un diff trop large</summary>

Le périmètre dit-il ce qu'on **ne** touche **pas** ? Ajoutez « ne modifie pas l'interface Web ni les DTO » et « aucune nouvelle dépendance NuGet ». En mode plan, refusez le plan tant qu'il déborde.
</details>

<details>
<summary>Indice 2 · Claude renvoie maintenant des ProblemDetails</summary>

C'est un changement de contrat : l'interface affiche le corps de l'erreur tel quel, et un objet JSON s'afficherait brut. Rappelez la contrainte « ne change pas le format des erreurs : `Results.BadRequest("message")` ».
</details>

<details>
<summary>Indice 3 · <code>gh pr create</code> échoue</summary>

Vérifiez `gh auth status`, que la branche est poussée (`git push -u origin fix/validation-commandes`) et que le dépôt distant existe (`git remote -v`). Une PR exige au moins un commit d'écart avec `main`.
</details>

## Pour aller plus loin

- Ajoutez au skill une étape qui exécute `/smoke-test` avant le push.
- Écrivez une commande `/explique-diff` destinée aux relecteurs non développeurs.
- Comparez la revue de `/revue-diff` avec la commande intégrée `/review`.

## Débrief

**Partie A**

- Qu'a fait Claude avec le prompt vague ? Qu'a-t-il deviné ?
- Quel composant du prompt a le plus changé le résultat ?
- La revue critique a-t-elle trouvé un vrai problème ?

Ce que l'on observe souvent avec le prompt vague :

- une validation dupliquée dans l'interface Web, ou des DTO du Web modifiés ;
- un passage aux `ProblemDetails` (`Results.ValidationProblem`) : l'interface affiche alors un objet JSON brut ;
- une nouvelle dépendance (FluentValidation), ou des attributs `[Required]` et `[Range]`. En .NET 10, les minimal APIs ne les évaluent qu'avec `builder.Services.AddValidation()`, qui renvoie des `ProblemDetails` : encore un autre format d'erreur ;
- des limites inventées (client de 100 caractères, quantité maximale arbitraire) ;
- aucune vérification exécutée, ou un simple `dotnet build`.

Et dans la revue critique : la limite de 200 caractères écrite en dur au lieu d'une constante ; le stock jamais vérifié (hors périmètre : à noter, pas à corriger) ; une commande sans propriété `items` qui renvoie toujours 500 (à noter : c'est le bug du lab 2).

À retenir : ce qui n'est pas dit est deviné ; des critères **observables** rendent le travail vérifiable ; on explore et on planifie **avant** de coder ; on demande des défauts, pas une validation.

**Partie B**

- Qu'avez-vous changé dans `/ship`, et pourquoi ?
- Qu'est-ce qui empêche Claude de livrer de lui-même ?
- Quelle autre procédure de l'équipe mériterait un skill ?

À retenir : une procédure répétée devient un **skill** versionné ; la **description** pilote l'invocation automatique ; pour les effets de bord, `disable-model-invocation` et `ask` ; `/rewind` n'annule pas un `git push`.

## Les fichiers du lab

### `.claude/`

| Fichier | Rôle |
|---|---|
| `commands/revue-diff.md` | Commande au format historique : contexte Git injecté par `` !`...` ``, focus passé en `$ARGUMENTS`, sortie en tableau trié par gravité. |
| `skills/ship/SKILL.md` | La procédure de livraison : refuser `main`, vérifier, relire, committer, pousser, ouvrir la PR. Invocable seulement par vous (`disable-model-invocation`). |
| `skills/ship/modele-pr.md` | Le gabarit de description de PR de l'équipe. |
| `skills/ship/verifier.sh` | Build, tests, puis format des seuls fichiers C# modifiés ; sortie courte, détail en cas d'échec. |
| `settings.json` | Les règles des labs 0 et 1. Nouveautés de ce lab : `allow` pour les commandes Git locales ; `ask` pour `git push`, `gh pr create` et `gh pr merge` ; `deny` pour `--force`, `-f` et `reset --hard`. |

Le skill `/smoke-test` du lab 0 reste en place : la copie ne retire rien.

### `ressources/`

| Fichier | Rôle |
|---|---|
| `modele-prompt.md` | L’anatomie du prompt, un modèle rempli et des repères zero-shot, few-shot, CoT et chaînage. |

### `solution/`

`src/ECommerce.Ordering.Api/Endpoints/OrderingEndpoints.cs` : le correctif de la partie A. Une méthode `Validate` renvoie la première erreur, sous forme de chaîne simple, ou `null` : `Customer is required.` (client vide ou blanc), `Customer must not exceed 200 characters.` (la longueur de la colonne), le message existant pour une liste vide, `Quantity must be at least 1.` (quantité < 1). Une commande sans propriété `items` renvoie toujours 500 : c'est le bug du lab 2. Pour rattraper le lab, voir [`labs/README.md`](../README.md#rattraper-un-lab).
