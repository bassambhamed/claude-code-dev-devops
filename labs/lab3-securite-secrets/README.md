# Lab 3 · Sous-agents, sécurité et secrets

> Partie A : partie 6 des supports (sous-agents) · Partie B : suite de la partie 6 (sécurité)
> Mécanismes : sous-agents de revue, exécution séquentielle et parallèle, `deny`, hook `PreToolUse`, gitleaks, audit NuGet en CI · Prérequis : lab 2

## Pourquoi ce lab

Une revue demandée dans la session principale se fait **dans le même contexte** que le code qu'elle relit : mêmes hypothèses, mêmes angles morts, et un contexte qui se remplit. Un **sous-agent** part d'un contexte neuf, avec une mission, des outils minimaux et un format de sortie imposé ; deux sous-agents en parallèle donnent deux avis indépendants.

La sécurité est le terrain idéal pour le vérifier, parce que l'erreur y coûte cher et ne se rattrape pas : un secret poussé a pu être copié, et le supprimer ne le révoque pas. Le lab superpose les couches de défense : `deny` sur les fichiers sensibles, hook qui bloque un secret avant le commit, relecteur spécialisé, gitleaks et audit NuGet en CI.

## Objectifs

- Écrire deux sous-agents de revue (mission, outils, périmètre, format de sortie) et les faire travailler en séquence puis en parallèle.
- Détecter un secret commité de deux façons, et dérouler la procédure : rotation, retrait, historique, prévention.
- Rendre la récidive impossible sur le poste (hook) et en CI (gitleaks).
- Corriger des dépendances vulnérables, directes et transitives, et l'imposer en CI.

## Point de départ

- Le lab 2 fusionné dans `main` ; une branche `securite/secrets-et-dependances`.
- Pour la partie B : gitleaks (`brew install gitleaks`, ou l'archive de la [page des versions](https://github.com/gitleaks/gitleaks/releases)).

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/lab3-securite-secrets/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

---

## Mise en situation

Une clé de paiement factice a été commitée et des dépendances sont vulnérables. Avant l’audit, vous construisez deux relecteurs spécialisés puis arbitrez leurs constats et mettez en place des contrôles reproductibles.

## Étapes

### Partie A · Atelier : deux relecteurs spécialisés

#### Contexte de la partie

Avant l'audit de sécurité, l'équipe veut deux relecteurs automatiques et reproductibles : un expert .NET et un expert sécurité. Vous les créez, puis vous les faites travailler sur le diff du lab 2, l'un après l'autre puis en parallèle.

#### Étape A1 · Lire (ou écrire) les deux sous-agents

Relancez Claude Code et tapez `/agents` : `dotnet-reviewer` et `security-reviewer` apparaissent. Ouvrez `.claude/agents/*.md` :

- la **description** dit à Claude *quand* déléguer : elle est lue à chaque session ;
- `tools: Read, Grep, Glob, Bash` : pas d'`Edit` ni de `Write`, un relecteur ne corrige pas ;
- `model: sonnet` : un modèle rapide suffit pour une revue ciblée ;
- le corps est le prompt système du sous-agent : périmètre, liste de contrôle, format de sortie.

> **Mode autonome** : écrivez d'abord vos propres versions avec `/agents` (« Create new agent »), puis comparez avec celles du lab.

#### Étape A2 · En séquence

Repérez le commit qui précède le lab 2 (`git log --oneline`), puis :

```text
Utilise le sous-agent dotnet-reviewer pour relire git diff <commit>..main.
Ensuite, utilise security-reviewer sur le même diff.
```

Observez dans la session : chaque sous-agent travaille dans son propre contexte et ne renvoie que son rapport. Que coûte la délégation en contexte, comparée à une revue dans la session principale (`/context`) ?

#### Étape A3 · En parallèle

```text
Lance en parallèle dotnet-reviewer et security-reviewer sur git diff <commit>..main,
puis présente leurs deux rapports côte à côte, sans les fusionner.
```

#### Étape A4 · Arbitrer

Les sous-agents donnent des avis ; vous décidez. Remplissez le tableau d'arbitrage dans vos preuves :

| Constat | Relecteur | Retenu ? | Justification |
|---|---|---|---|
| … | … | oui / non | … |

---

### Partie B · Un secret commité, des dépendances vulnérables

#### Contexte de la partie

Un script simule l'erreur d'un collègue : une clé de paiement « de production » a été commitée dans la configuration d'Ordering. En parallèle, l'audit NuGet signale des dépendances vulnérables. Vous détectez, corrigez et rendez la récidive impossible.

#### Étape B1 · Rejouer l'erreur du collègue

```bash
bash "$FORMATION"/labs/lab3-securite-secrets/ressources/injecter-secret.sh ~/lab-ecommerce
```

Un commit « chore: configure payment provider for go-live » ajoute un bloc `Payment` à `src/ECommerce.Ordering.Api/appsettings.json`. La clé est factice, mais traitez-la comme une vraie.

#### Étape B2 · Détecter, de deux façons

Avec le relecteur :

```text
Utilise security-reviewer pour auditer tout le dépôt, historique Git compris.
```

Avec gitleaks, d'abord avec ses seules règles standard, puis avec la règle maison qui connaît le préfixe des clés de paiement :

```bash
gitleaks git --redact --verbose .                       # règles standard
cp "$FORMATION"/labs/lab3-securite-secrets/ressources/.gitleaks.toml .
gitleaks git --config .gitleaks.toml --redact --verbose .
```

Sans la règle maison, gitleaks trouve la clé grâce à sa règle générique `generic-api-key`, parce que la propriété s'appelle `ApiKey`. Avec elle, il la signale deux fois : `generic-api-key` et `ecommerce-cle-paiement`. Qui a trouvé le secret ? Avec quelle certitude ? Quelle règle la trouverait encore si elle apparaissait au milieu d'un message de log, sans nom de propriété autour ?

#### Étape B3 · Dérouler la procédure, dans l'ordre

1. **Compromis** : le secret est considéré comme exposé dès qu'il est commité.
2. **Révoquer** : la rotation se fait chez le fournisseur ; elle reste une action humaine. Ici, elle est simulée : notez dans vos preuves l'heure de la révocation et l'identifiant (masqué) de la nouvelle clé.
3. **Retirer** : la configuration lit la clé à l'exécution.

   ```text
   Retire Payment:ApiKey de appsettings.json (garde Provider et Endpoint, qui ne sont pas
   secrets) et initialise dotnet user-secrets pour Ordering.Api. Ne fixe aucune valeur.
   ```

   Puis, **vous**, dans un autre terminal (la valeur ne doit pas passer par la session) :

   ```bash
   dotnet user-secrets set "Payment:ApiKey" "<nouvelle clé>" --project src/ECommerce.Ordering.Api
   ```

   Les user-secrets ne sont lus qu'en `Development` ; ailleurs, la clé arrive par une variable d'environnement (`Payment__ApiKey`) ou un coffre-fort.
4. **Historique** : `git log -p -S ecpk_live_ --all` montre que la clé reste dans l'historique. Le dépôt est privé et la clé révoquée : une purge (`git filter-repo` puis un push forcé coordonné, interdit à Claude par vos garde-fous) n'apporte plus rien ici. Décidez, et justifiez. Si vous ne purgez pas, ajoutez les empreintes (`Fingerprint`) affichées par gitleaks dans un fichier `.gitleaksignore` à la racine, une par ligne, avec un commentaire (`# …`) qui donne la raison et la date de révocation : il y en a deux, une par règle. La CI ne doit pas échouer à vie sur un secret révoqué. Vérifiez : `gitleaks git --config .gitleaks.toml .` ne trouve plus rien.
5. **Prévenir** : étapes B4 et B6.

#### Étape B4 · Le hook qui bloque un secret

Le hook `bloquer-secrets.sh` est installé (`/hooks`). Mettez-le à l'épreuve :

```text
Ajoute dans appsettings.Development.json la clé de test ecpk_test_0123456789abcdef0123456789abcdef.
```

L'écriture est bloquée, et Claude reçoit un message qui explique quoi faire, sans recopier la valeur. Essayez aussi de committer un fichier qui contient une clé : le commit est bloqué. Retirer un secret, en revanche, n'est jamais bloqué : pourquoi est-ce important ?

#### Étape B5 · Les dépendances vulnérables

```bash
dotnet list ECommerce.slnx package --vulnerable --include-transitive
```

```text
Corrige les dépendances vulnérables de gravité haute. Pour chaque paquet : dis s'il est
direct ou transitif, préfère mettre à jour le paquet parent, et vérifie sur nuget.org que
la version proposée existe et corrige l'avis. Montre l'audit avant et après.
```

Vérifiez vous-même chaque version proposée : un agent peut inventer un numéro de version. Puis : build sans avertissement `NU1902`/`NU1903`, `/smoke-test` au vert, et `http://localhost:5147/openapi/v1.json` qui répond toujours.

#### Étape B6 · Le contrôle en CI

Copiez `ressources/ci-securite.yml` dans `.github/workflows/securite.yml` et `.gitleaks.toml` à la racine, puis livrez avec `/ship`. Sur la PR, les deux contrôles doivent passer : gitleaks (grâce à votre décision de l'étape B3) et l'audit NuGet.

## Critères d'acceptation

- [ ] `.claude/agents/` contient les deux relecteurs ; leurs rapports respectent le format imposé.
- [ ] Le secret est détecté par `security-reviewer` **et** par gitleaks avec la règle maison.
- [ ] `appsettings.json` ne contient plus de clé ; la clé est lue depuis user-secrets en local.
- [ ] Le hook bloque l'écriture et le commit d'une clé, et laisse passer son retrait.
- [ ] L'audit NuGet ne signale plus de vulnérabilité haute ; l'application démarre et `/openapi/v1.json` répond.
- [ ] La PR passe les deux contrôles du workflow `Sécurité`.

## Preuves à fournir

Dans `preuves/lab3/` :

- **partie A** : les rapports des deux modes d'exécution et le tableau d'arbitrage ;
- **partie B** : la détection reproductible (rapport et sortie gitleaks), la procédure suivie avec ses heures, l'audit NuGet avant et après, l'extrait de session où le hook bloque, et le lien vers la PR avec ses contrôles.

## Aides progressives

<details>
<summary>Indice 1 · gitleaks ne trouve rien, ou pas la règle maison</summary>

Vérifiez que vous analysez l'historique (`gitleaks git`) et pas seulement les fichiers actuels (`gitleaks dir`) : la clé n'est plus dans `appsettings.json` une fois retirée. Si la règle `ecommerce-cle-paiement` n'apparaît pas, `.gitleaks.toml` n'est pas chargé : il doit être à la racine du dépôt (gitleaks l'y lit tout seul) ou passé par `--config`.
</details>

<details>
<summary>Indice 2 · Corriger un paquet transitif</summary>

Deux stratégies. La meilleure : mettre à jour le paquet **direct** qui l'apporte (`dotnet list package --include-transitive` montre qui tire quoi). Sinon : ajouter une référence directe au paquet transitif, dans une version corrigée, avec un commentaire qui explique pourquoi. Dans ce dépôt, il y a un cas de chaque.
</details>

<details>
<summary>Indice 3 · La configuration ne trouve plus la clé</summary>

`dotnet user-secrets init` ajoute un `UserSecretsId` au `.csproj` d'Ordering. Les secrets sont lus en `Development` seulement : c'est le cas sous l'AppHost. Vérifiez le nom de la clé : `Payment:ApiKey` dans user-secrets, `Payment__ApiKey` en variable d'environnement.
</details>

## Pour aller plus loin

- Un hook `SessionStart` qui rappelle les règles de sécurité du dépôt à chaque session.
- `/security-review`, la revue de sécurité intégrée à Claude Code : comparez-la avec votre sous-agent.
- `<NuGetAuditMode>all</NuGetAuditMode>` et `<WarningsAsErrors>NU1903;NU1904</WarningsAsErrors>` dans un `Directory.Build.props` : le build lui-même échoue sur une vulnérabilité haute.

## Débrief

**Partie A**

- Les deux modes ont-ils trouvé les mêmes problèmes ?
- Quel désaccord avez-vous dû arbitrer ?
- Le format de sortie imposé a-t-il été respecté ?

À retenir : un sous-agent = un contexte neuf + une mission + des outils minimaux ; la description de la tâche doit être **autosuffisante** ; le parallèle donne des avis **indépendants**, et l'humain arbitre.

**Partie B**

- Qui a trouvé le secret en premier : le sous-agent, gitleaks, le hook ?
- Pourquoi la rotation passe-t-elle avant la purge de l'historique ?
- Comment avez-vous corrigé un paquet transitif ?

Ce que l'on observe souvent :

- Les deux modes d'exécution de la partie A trouvent rarement exactement les mêmes constats. C'est le but : deux avis indépendants, que l'humain arbitre.
- À l'étape B5, l'agent propose parfois une version qui n'existe pas, ou une mise à jour majeure (une version d'Aspire plus récente) : vérifier chaque paquet suggéré n'est pas une formalité.
- Supprimer le fichier ou réécrire l'historique ne révoque rien : l'ordre de la procédure compte.
- Sans décision sur l'historique (purge ou `.gitleaksignore`), le contrôle gitleaks échoue sur la PR. C'est voulu : la CI rend la décision visible.

À retenir : un secret commité est **compromis**, on le révoque d'abord ; plusieurs couches : `deny`, hook, scan en CI ; les alertes NuGet du build sont de vraies alertes ; on vérifie chaque paquet suggéré par l'agent.

## Les fichiers du lab

### `.claude/`

| Fichier | Rôle |
|---|---|
| `agents/dotnet-reviewer.md` | Relecteur .NET : justesse, conventions du dépôt, contrats copiés, async, EF Core, HTTP, tests. Lecture seule. |
| `agents/security-reviewer.md` | Relecteur sécurité : secrets (code, configuration, historique), dépendances vulnérables, données sensibles dans les logs. Ne recopie jamais un secret. |
| `hooks/bloquer-secrets.sh` | Hook `PreToolUse` : bloque l'écriture d'un secret (`Write`, `Edit`) et un `git commit` qui en ajouterait un. Seules les lignes ajoutées comptent. |
| `settings.json` | Les règles des labs 0 à 3. Nouveautés de ce lab : le hook, et des `deny` sur la lecture des user-secrets, `dotnet user-secrets list` et `set` (une valeur secrète ne passe pas par la session), et la configuration de production. |

### `ressources/`

| Fichier | Rôle |
|---|---|
| `injecter-secret.sh` | Rejoue l'erreur du collègue : ajoute une clé de paiement factice à la configuration d'Ordering et la commite. Relancé, il ne fait rien. |
| `.gitleaks.toml` | La configuration gitleaks de l'équipe : les règles standard, plus la règle maison `ecommerce-cle-paiement`. |
| `ci-securite.yml` | Le workflow `Sécurité` : gitleaks sur l'historique et audit NuGet. |

### `solution/`

L'état de la copie à la fin du lab, à partir de la fin du lab 2 et du script d'injection :

- `src/ECommerce.Ordering.Api/appsettings.json` sans la clé (`Provider` et `Endpoint` restent) ;
- `ECommerce.Ordering.Api.csproj` avec un `UserSecretsId` (le vôtre, créé par `dotnet user-secrets init`, sera différent) ;
- les dépendances corrigées : `Microsoft.AspNetCore.OpenApi` 10.0.14 dans Catalog et Ordering (le paquet parent, qui tire `Microsoft.OpenApi` 2.12.2), et `MessagePack` 2.5.307 épinglé dans l'AppHost, avec un commentaire ;
- `.gitleaks.toml` et `.github/workflows/securite.yml`.

Résultat vérifié : build sans avertissement NuGet, audit vide, 9 tests verts. `.gitleaksignore` n'est pas fourni : les empreintes contiennent le hash de **votre** commit. Pour rattraper le lab, voir [`labs/README.md`](../README.md#rattraper-un-lab).
