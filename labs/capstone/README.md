# Capstone · Date de livraison souhaitée, sous porte qualité

> Partie 12 · Mécanismes : équipe orchestrée, skills `/capstone` et `/code-health`, référentiel Roslyn, hook `Stop`, revues indépendantes · Prérequis : labs 0 à 11 et atelier plugin, SDK .NET 10, Docker, Git, `jq`, cluster local du lab 9.

## Pourquoi ce lab

Une fonctionnalité transverse touche le modèle, le stockage, le contrat, l'interface, les tests et l'exploitation. Le capstone demande une livraison complète avec des preuves, et une répartition explicite du travail. Un analyseur syntaxique apporte des mesures reproductibles ; l'humain et les relecteurs jugent le besoin, l'interface et les limites de ces mesures.

## Objectifs

- Ajouter une date souhaitée facultative aux commandes, visible et filtrable.
- Faire évoluer PostgreSQL sans perdre les commandes existantes.
- Déléguer par étapes à des agents spécialisés avec des contrats et fichiers attribués.
- Franchir une porte qualité sans régression par fichier et expliquer les décisions.

## Point de départ

La copie à la fin du lab 11, corrigée et commitée. Le compte de paiement de formation a été renouvelé par vos soins et aucun secret ne figure dans les preuves. Sur `main`, créez `git switch -c feat/requested-delivery-date`.

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/capstone/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

Le plugin `dotnet-team` de l'atelier est une variante de distribution du socle : évitez d'activer deux exemplaires des mêmes hooks. Pour ce capstone, utilisez les fichiers locaux cumulatifs ; le plugin peut être installé pour l'essai de l'atelier puis désactivé. Le hook `Stop` du capstone **remplace** le hook de tests du lab 2 : il lance build, tests et Code Health ; les hooks de formatage, Git, secrets et kubectl restent actifs.

## Mise en situation

Le service client veut connaître la date souhaitée pour une livraison. Le client peut la laisser vide ou choisir une date entre **demain et J+90 inclus**. « Aujourd'hui » désigne la date UTC du serveur ; ce choix évite qu'une machine hébergée dans un autre fuseau change la règle. La date reste un `DateOnly`, sans heure ni conversion de fuseau. Le formulaire explique la convention.

Les commandes existantes gardent une date nulle. Le service client peut combiner le filtre client du lab 5 avec une date exacte ; effacer les filtres retrouve toutes les commandes. Une date demandée n'est pas une promesse de disponibilité ni un créneau de transport.

## Étapes

### 1 · Lire le référentiel et mesurer

Depuis la copie :

```bash
mkdir -p preuves/capstone capstone
dotnet run .claude/skills/code-health/codehealth.cs -- src --format md --sortie preuves/capstone/avant.md
dotnet run .claude/skills/code-health/codehealth.cs -- src --gate --base main
cp "$FORMATION"/labs/capstone/ressources/JOURNAL.modele.md capstone/JOURNAL.md
```

Le premier lancement restaure le package Roslyn. Le contrôle de l’analyseur lui-même est rejouable : `bash "$FORMATION"/labs/capstone/ressources/verifier-analyseur.sh` (12 cas dans des dépôts temporaires). Lire le [référentiel](.claude/skills/code-health/REFERENTIEL.md), notamment les exclusions et les faux positifs. Le score local n'est pas un score CodeScene commercial. CH12, Razor, configuration et secrets exigent une revue supplémentaire.

### 2 · Échauffement : assainir la dette injectée

Sur une branche d'exercice séparée et une copie commitée :

```bash
git switch -c exercice/code-health
bash "$FORMATION"/labs/capstone/ressources/injecter-dette.sh ~/lab-ecommerce
dotnet build ECommerce.slnx
dotnet run .claude/skills/code-health/codehealth.cs -- src --gate --base main
```

Prédisez les règles qui se déclenchent avant d'observer le rapport. Le service injecté compile, mais **n'est pas enregistré ni exécuté** : il montre des formes dangereuses sans appeler son URL factice. Demandez à `codescene` de préserver le calcul tout en supprimant les blocages synchrones, le client créé directement, le `async void` et le `catch` vide. Build, tests et rapport après chaque changement. Cette branche reste un exercice distinct ; revenez ensuite sur `feat/requested-delivery-date`. Ne copiez pas le service injecté dans la fonctionnalité.

### 3 · Cadrer avec l'orchestrateur

```bash
claude --agent orchestrateur
```

Puis :

```text
/capstone
Ajoute la date de livraison souhaitée : facultative, demain à J+90 inclus en UTC.
Préserve les commandes existantes et les clients qui n'envoient pas ce champ.
Expose et filtre cette date dans les commandes ; combine avec le filtre client.
Avant toute modification, explore les contrats copiés, propose le plan et fais-le valider.
Délègue avec des fichiers disjoints. Tiens capstone/JOURNAL.md, conserve les métriques,
exécute tests, revues et porte qualité, puis prépare les preuves de livraison locale.
```

L'orchestrateur reste le fil principal : il peut appeler les sous-agents. Un sous-agent spécialisé ne doit pas porter la délégation d'une autre équipe. Examinez les fichiers d'agents avant de leur confier un rôle.

### 4 · Base, API et tests

Le contrat de référence du corrigé :

- POST `/api/orders` : `requestedDeliveryDate` absent, `null` ou chaîne ISO `yyyy-MM-dd` ; invalide → 400, sans commande enregistrée.
- GET `/api/orders/{id}` : champ nullable retourné.
- GET `/api/orders?deliveryDate=2026-12-01` : égalité exacte filtrée en SQL, pas de résultat → liste vide, date mal formée → 400.
- PostgreSQL : colonne nullable de type `date` et index ; aucun remplissage arbitraire de l'historique.

Demandez à `testeur` une preuve rouge puis verte et les bornes fixées dans le temps. Le corrigé ajoute un test qui applique l'ancienne migration, insère une commande puis applique la nouvelle migration. Il vérifie la conservation des données et l'absence de différence entre modèle et snapshot.

```bash
dotnet build ECommerce.slnx
dotnet test ECommerce.slnx
dotnet ef migrations script --idempotent --project src/ECommerce.Ordering.Api --output preuves/capstone/migration.sql
```

Relisez le SQL avec `/review-migration`. Définissez clairement qui met à jour les DTO Web : les contrats sont copiés, ils ne se synchronisent pas seuls. Les migrations et leur snapshot générés sont fournis dans le corrigé.

### 5 · Interface et télémétrie

Formulaire catalogue : champ date avec label associé, facultatif, bornes visibles, message serveur anglais, panier préservé en cas d'erreur. Liste : date ou « Not specified », filtre date exact combiné au client, bouton « All dates », états vide, chargement et erreur conservés. Le corrigé filtre côté client les commandes déjà chargées ; l'API expose aussi le filtre serveur pour les autres consommateurs.

Utilisez `ui-verifier` pour le clavier, le focus, la réinitialisation et une panne de la passerelle. Conservez les captures réelles. Une compilation Razor ne prouve pas le fonctionnement interactif.

La télémétrie conserve les instruments du lab 10 et ajoute `ecommerce.orders.delivery` avec le seul attribut booléen `delivery_requested`. Ni nom du client, ni date, ni identifiant dans les métriques. Vérifiez dans Grafana que les commandes acceptées incrémentent les compteurs et qu'un rejet ne les incrémente pas.

### 6 · Santé, revues et porte

```bash
dotnet run .claude/skills/code-health/codehealth.cs -- src --format md --sortie preuves/capstone/apres.md
dotnet run .claude/skills/code-health/codehealth.cs -- src --gate --base main
```

La porte échoue sur un constat bloquant, une baisse de score par fichier existant ou un fichier nouveau sous 9. Une référence Git absente est une erreur, jamais un succès. Corrigez les défauts introduits ; documentez les limites de mesure et la revue CH12. Faites relire .NET et sécurité indépendamment, puis arbitrez chaque constat. Le hook `Stop` relance une fois au maximum pour éviter une boucle ; une relance laissée conclure n'autorise pas la livraison. La CI doit exécuter les mêmes commandes de manière bloquante.

### 7 · Déployer localement et livrer

Reconstruisez les images modifiées avec un nouveau tag, importez-les dans k3d, mettez à jour les valeurs Helm, rendez et relisez le chart avant `helm upgrade`. Utilisez les procédures du lab 9 : `helm upgrade` seul n'importe pas une image locale. Ne remplacez pas silencieusement une image `1.0` déjà en cache.

Vérifiez une commande avec et sans date, le redémarrage d'Ordering et les filtres. Lancez le smoke du lab 0 et les tests de contrat du lab 11. Préparez `/ship` avec les résultats, les captures et le journal. Si Docker, le cluster, GitHub ou un MCP est indisponible, marquez la preuve manquante au lieu de la déclarer obtenue.

## Critères d'acceptation

- [ ] Date facultative ; demain et J+90 acceptés ; passé, aujourd'hui et J+91 refusés avec 400.
- [ ] Ancien JSON et anciennes commandes compatibles ; SQL sans perte de données.
- [ ] Date persistée et retournée après redémarrage ; filtre API exact et filtre UI combinable.
- [ ] Interface accessible au clavier avec états de chargement, erreur et vide.
- [ ] Tests historiques et nouveaux tests verts, modèle EF sans migration manquante.
- [ ] Instruments du lab 10 conservés, métrique additionnelle sans données personnelles.
- [ ] Porte franchie, revue manuelle CH12 et arbitrages consignés.
- [ ] Déploiement local vérifié et PR accompagnée des preuves.

## Preuves à fournir

Dans `preuves/capstone/` : plan validé, rapports avant/après et code de retour de la porte, test rouge puis vert, SQL commenté, preuve de migration avec données, captures clavier et erreurs, trace et compteur, version déployée, smoke, rapports indépendants et arbitrages. `capstone/JOURNAL.md` contient les décisions ; pas de secrets. Présentation de cinq minutes et revue croisée par un autre binôme.

## Aides progressives

<details><summary>Indice 1 · Choisir le type et la règle temporelle</summary>

`DateOnly?` se mappe sur PostgreSQL `date`. Utiliser la date UTC d'un `TimeProvider` injecté. Une propriété nullable ajoutée au JSON préserve les anciens clients. La règle de validation appartient au serveur, même si le navigateur a `min` et `max`.
</details>

<details><summary>Indice 2 · La porte baisse malgré une meilleure moyenne</summary>

La porte compare chaque fichier, pas seulement la moyenne. Évitez d'allonger la lambda de création : séparez validation et service applicatif avec des responsabilités cohérentes, puis couvrez ce découpage par les tests métier. N'excluez pas un fichier produit pour gagner des points.
</details>

<details><summary>Indice 3 · Un compteur manque après extraction du service</summary>

Déplacer la création de commande peut supprimer les appels à `OrderingTelemetry.RecordCreated`. Gardez-les après la sauvegarde, une seule fois par succès. Le nouveau compteur doit utiliser le meter déjà exporté `ECommerce.Ordering`.
</details>

## Pour aller plus loin

Comparer filtrage client et serveur sur un catalogue de commandes plus grand ; ajouter une pagination avant de charger toute la table. Étudier une zone métier différente d'UTC et les tests autour de minuit. Ajouter la porte au workflow CI avec référence Git explicitement récupérée, sans exécuter du code non approuvé avec des secrets.

## Débrief

Quels contrats ont dû être négociés entre agents ? Quel constat automatique était discutable ? Quelle preuve ne pouvait pas être remplacée par une revue de code ? Le binôme suivant peut-il reprendre la PR sans votre explication orale ?

**Ce que l'on observe souvent.** Le DTO oublié rend la date invisible ; une date avec heure introduit des conversions de fuseau inutiles ; une extraction perd un compteur. Une moyenne flatteuse peut cacher une régression locale. Une équipe efficace borne ses responsabilités et relit les interfaces.

Évaluation : besoin 25 %, tests et preuves 25 %, code et périmètre 20 %, usage justifié des mécanismes 20 %, décisions et supervision 10 %.

## Les fichiers du lab

- `.claude/agents/` : orchestrateur du fil principal, développeur, testeur et relecteur Code Health ; les autres relecteurs viennent des labs précédents.
- `.claude/skills/capstone/SKILL.md` : déroulé, délégations et journal.
- `.claude/skills/code-health/` : référentiel, skill et analyseur Roslyn autonome `codehealth.cs`.
- `.claude/hooks/porte-qualite.sh`, `settings.json` : porte build/tests/santé et réglages cumulatifs.
- `ressources/injecter-dette.sh` : exercice isolé de dette ; `JOURNAL.modele.md` : décisions à renseigner ; `verifier-analyseur.sh` : douze cas déterministes de l’analyseur et de sa porte.
- `solution/` : modèle, migration et snapshot, validation, service de création, API, métrique, DTO, formulaire, filtres, tests PostgreSQL et contrôles de CI. Overlay à appliquer après le lab 11 ; aucune preuve d'exécution n'est inventée dans le corrigé.
