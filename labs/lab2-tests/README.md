# Lab 2 · Aucune couverture, une erreur 500

> Partie 5 des supports · Mécanismes : skill `/test-integration`, boucle rouge-vert, hooks `Stop`, `PostToolUse` et `PreToolUse` · Prérequis : lab 1 fusionné

## Pourquoi ce lab

Demander à Claude « vérifie que les tests passent avant de conclure » fonctionne… **souvent**. Une consigne dans un prompt ou dans `CLAUDE.md` est une intention ; un **hook** est un programme exécuté à chaque fois, quoi qu'en pense le modèle. Ce lab vous fait passer de l'un à l'autre :

- un **skill** porte la recette des tests d'intégration du dépôt, avec ses pièges (deux `Program`, base partagée, appel à Catalog) ;
- la boucle **rouge-vert** prouve que le bug est compris avant d'être corrigé, et empêche de « corriger » en affaiblissant un test ;
- un **hook `Stop`** interdit à Claude de conclure tant que des tests échouent, avec une échappatoire et une limite de tentatives.

## Objectifs

- Créer les projets de tests avec le skill `/test-integration`.
- Écrire les 9 tests des scénarios fournis.
- Reproduire le bug 500 en **rouge**, le figer par un commit, puis passer au **vert** sans toucher au test.
- Voir le hook `Stop` bloquer une conclusion, puis vérifier son échappatoire et sa limite.

## Point de départ

- La PR du lab 1 est fusionnée : `git switch main && git pull`.
- Une branche de travail : `git switch -c test/couverture-integration`.
- `jq` installé : les hooks du lab s'en servent.

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/lab2-tests/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

Copiez aussi les scénarios dans la copie :

```bash
mkdir -p ~/lab-ecommerce/tests
cp "$FORMATION"/labs/lab2-tests/ressources/scenarios.md ~/lab-ecommerce/tests/scenarios.md
```

## Mise en situation

L'application n'a aucun test. Un client a reçu une **erreur 500** en envoyant une commande mal formée, et personne ne sait si le correctif du lab 1 tient toujours. Vous créez la couverture d'intégration et rendez automatique la règle « pas de conclusion avec des tests rouges ».

## Étapes

### Étape 1 · Comprendre le dispositif

Relancez Claude Code dans votre copie, puis tapez `/hooks` : trois hooks sont déclarés.

| Événement | Script | Rôle |
|---|---|---|
| `PreToolUse` (`Bash`) | `garde-git.sh` | Bloque `git push --force`, `-f` et `git reset --hard`, quelle que soit la place de l'option. |
| `PostToolUse` (`Edit\|Write`) | `formater.sh` | Reformate les espaces du fichier C# modifié. Ne bloque jamais. |
| `Stop` | `stop-tests-verts.sh` | Lance `dotnet test` quand Claude veut conclure ; code 2 si un test échoue. |

Lisez `stop-tests-verts.sh` et répondez dans vos preuves : que reçoit le script sur son entrée standard ? Que voit Claude quand le script renvoie 2 ? Pourquoi une empreinte de l'arbre de travail ? Pourquoi un compteur ?

> Un hook se teste **sans Claude**, avec un JSON d'entrée :
> ```bash
> echo '{"tool_input":{"command":"git push -f"}}' | .claude/hooks/garde-git.sh; echo "code $?"
> ```

### Étape 2 · Créer les projets et les scénarios 1 à 8

```text
/test-integration Crée les projets de tests et écris les scénarios 1 à 8 de
@tests/scenarios.md (Catalog : 1 à 3 ; Ordering : 4 à 8). Lance-les et montre le résumé.
```

Observez : le skill est chargé, puis les fichiers de tests apparaissent (le hook de formatage passe après chaque écriture). Quand Claude conclut, le hook `Stop` lance les tests : tout est vert, il laisse conclure.

Relisez les tests : chaque scénario est-il couvert par un test qui échouerait si le comportement changeait ? Commitez :

```bash
git add tests ECommerce.slnx .claude && git commit -m "test: couverture d'intégration de Catalog et Ordering"
```

### Étape 3 · Le rouge : reproduire l'erreur 500

Le scénario 9 doit d'abord **échouer**, et ce test rouge doit être commité **avant** le correctif : il devient la spécification. Le hook `Stop` obligerait Claude à corriger tout de suite : c'est le cas légitime de son échappatoire.

```bash
CLAUDE_SKIP_STOP_TESTS=1 claude
```

```text
/test-integration Écris le test du scénario 9 (propriété items absente : 400 attendu).
Lance-le et montre l'échec. Ne modifie pas le code de production.
```

Vous devez lire `Expected: BadRequest` et `Actual: InternalServerError`. Quittez Claude, puis :

```bash
git add tests && git commit -m "test: reproduire l'erreur 500 quand items est absent"
```

### Étape 4 · Le vert : corriger sans toucher au test

Relancez `claude` **sans** la variable d'environnement.

```text
Le test MissingItemsProperty_Returns400 est rouge. Explique la cause de l'erreur 500,
puis corrige le code de production pour qu'il passe, sans modifier aucun test.
```

Quand Claude conclut, le hook relance les tests : 9 verts. Vérifiez que le correctif ne touche aucun test, puis commitez :

```bash
git diff --stat          # aucun fichier sous tests/
git add -A && git commit -m "fix: refuser une commande sans items (400 au lieu de 500)"
```

### Étape 5 · Voir le hook bloquer, puis lâcher prise

Le métier change d'avis : les commandes doivent désormais être créées au statut `Pending`.

```text
Les commandes doivent désormais être créées au statut Pending : la confirmation sera
faite plus tard par un autre service. Fais la modification.
```

Le test du scénario 4 attend `Confirmed` : il passe au rouge. Observez le hook bloquer la conclusion, et la réaction de Claude : corrige-t-il le code, modifie-t-il le test, ou s'arrête-t-il pour expliquer le conflit ? Après trois blocages, le hook laisse conclure et vous prévient par un message. Copiez l'extrait de session dans vos preuves, puis annulez : `git restore .`

> La bonne issue n'est pas « faire passer le test » : c'est de vous signaler que la demande contredit la spécification. C'est à vous de trancher.

### Étape 6 · Livrer

```text
/ship Couverture d'intégration et correctif de l'erreur 500
```

## Critères d'acceptation

- [ ] `dotnet test ECommerce.slnx` : 9 tests, 9 réussis (3 pour Catalog, 6 pour Ordering).
- [ ] Les projets de tests sont dans `ECommerce.slnx`, un par API ; l'API n'a pas de `public partial class Program`.
- [ ] L'historique montre le test rouge **avant** le correctif, et le commit du correctif ne modifie aucun test (`git show --stat`).
- [ ] Le hook a bloqué au moins une conclusion ; l'échappatoire et la limite de trois blocages ont été observées.

## Preuves à fournir

Dans `preuves/lab2/` :

- la sortie de `dotnet test` : 9 tests verts ;
- les deux commits, le test rouge puis le correctif (`git log --oneline -3`) ;
- l'extrait de session où le hook bloque Claude, et le message final après trois blocages ;
- le hook et le skill versionnés dans `.claude/`, et vos réponses de l'étape 1.

## Aides progressives

<details>
<summary>Indice 1 · Tous les tests Ordering échouent sur la résolution de « catalog »</summary>

Hors de l'AppHost, personne n'injecte l'adresse de Catalog. La fabrique doit fournir `services:catalog:http:0` (voir `modeles.md` dans le skill) ; le faux gestionnaire HTTP répond à la place du réseau.
</details>

<details>
<summary>Indice 2 · Les tests passent un par un, mais échouent ensemble</summary>

Ils partagent la base en mémoire `"ordering"` : tous les hôtes du processus de test voient les mêmes données. Donnez à chaque fabrique une base au nom unique, et créez une fabrique par test.
</details>

<details>
<summary>Indice 3 · Le projet de tests ne compile pas : « Program » est ambigu</summary>

Un même projet de tests ne peut pas référencer les deux API : chacune a sa classe `Program`. C'est pourquoi le skill impose un projet par API. Inutile en revanche d'ajouter `public partial class Program` : depuis .NET 10, le `Program` généré est public.
</details>

<details>
<summary>Indice 4 · Le hook <code>Stop</code> ne se déclenche pas</summary>

`/hooks` le liste-t-il ? Le script est-il exécutable (`chmod +x .claude/hooks/*.sh`) ? `jq` est-il installé ? Les hooks sont lus au démarrage : relancez la session. `claude --debug` affiche l'exécution des hooks. Vérifiez aussi que `CLAUDE_SKIP_STOP_TESTS` n'est pas restée définie dans votre terminal.
</details>

## Pour aller plus loin

- Ajoutez les cas limites du lab 1 : client de 201 caractères, quantité négative.
- Écrivez un test de **contrat** : le JSON de Catalog désérialisé avec le DTO `CatalogProduct` d'Ordering. Il vous servira au lab 11.
- Testez `garde-git.sh` et `stop-tests-verts.sh` avec des JSON d'entrée, dans un script de tests des hooks.

## Débrief

- Le hook a-t-il bloqué Claude ? Qu'a-t-il fait ensuite ?
- Claude a-t-il tenté de modifier un test pour le faire passer ?
- Quel test vous semble le plus fragile, et pourquoi ?

Ce que l'on observe souvent :

- Sur l'application d'origine, Catalog passe 3 tests sur 3 et Ordering 3 sur 6 (client vide, quantité nulle et `items` absent échouent). Avec le correctif du lab 1, il ne reste que `items` absent : System.Text.Json laisse `Items` à `null` quand la propriété manque, même si le type n'est pas nullable.
- À l'étape 5, les réactions de Claude varient d'une session à l'autre : il modifie le test, refuse en argumentant, ou demande confirmation. Le hook garantit qu'on ne conclut pas au rouge ; il ne garantit pas que la correction est la bonne.
- Contourner le hook à l'étape 3 n'est pas une faiblesse : l'échappatoire est un cas d'usage prévu, explicite et visible.
- Ces tests passent par un hôte en mémoire : ils ne détectent ni un problème de routage de la passerelle, ni un contrat cassé entre services. Le test de contrat du lab 11 comble ce manque.

À retenir : une consigne est suivie **souvent**, un hook **toujours** ; code 2 = blocage, et stderr devient une consigne pour Claude ; toujours prévoir une **sortie** (compteur, échappatoire) ; le test rouge prouve qu'on a compris le bug.

## Les fichiers du lab

### `.claude/`

| Fichier | Rôle |
|---|---|
| `skills/test-integration/SKILL.md` | La recette des tests d'intégration du dépôt et ses pièges ; les règles du rouge-vert. |
| `skills/test-integration/modeles.md` | Fabriques, faux Catalog et test d'exemple, vérifiés sur ce dépôt. Chargé seulement quand le skill en a besoin. |
| `hooks/stop-tests-verts.sh` | Hook `Stop` : tests relancés seulement si l'arbre a changé, code 2 avec un extrait des échecs, au plus 3 blocages par session, échappatoire `CLAUDE_SKIP_STOP_TESTS=1`. |
| `hooks/formater.sh` | Hook `PostToolUse` : `dotnet format whitespace --folder` sur le fichier C# modifié. |
| `hooks/garde-git.sh` | Hook `PreToolUse` : bloque la réécriture d'historique, avec un message qui propose une alternative. |
| `settings.json` | Les règles des labs 0 à 2. Nouveautés de ce lab : la déclaration des trois hooks (délai de 300 s pour les tests) et les commandes de création de projet autorisées. |

### `ressources/`

| Fichier | Rôle |
|---|---|
| `scenarios.md` | Les 9 scénarios à couvrir, à copier dans `tests/` de votre copie. |

### `solution/`

L'état de la copie à la fin du lab, à partir de la fin du lab 1 : les deux projets de tests (`tests/`, 3 tests Catalog et 6 tests Ordering), `ECommerce.slnx` qui les référence, et `OrderingEndpoints.cs` avec le correctif de l'erreur 500 (`request.Items is null || …`). Pour rattraper le lab, voir [`labs/README.md`](../README.md#rattraper-un-lab).
