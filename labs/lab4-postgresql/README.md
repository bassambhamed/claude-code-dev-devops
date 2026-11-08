# Lab 4 · Les données disparaissent au redémarrage

> Partie 7 des supports · Mécanismes : `/review-migration`, MCP PostgreSQL, Testcontainers

## Pourquoi ce lab

Chaque redémarrage efface le catalogue et les commandes : les API utilisent EF Core en mémoire. Passer à PostgreSQL révèle aussi ce que masque une base vide : migrations, contraintes et données existantes. Le skill relit le SQL, un essai éphémère le vérifie, et MCP explore avec un rôle dont les droits sont imposés par PostgreSQL.

## Objectifs

- Persister les deux services dans deux bases logiques PostgreSQL.
- Ajouter une catégorie aux produits en préservant les lignes existantes.
- Relire et essayer une migration avant de démarrer le code qui l'applique.
- Porter les tests sur PostgreSQL et prouver la lecture seule du compte MCP.

## Point de départ

Copie à la fin du lab 3, propre et commitée ; .NET 10, Docker démarré et `jq`. Créez `feat/postgresql-categories`. Installez l'outil EF de la même version majeure que les paquets du projet (`dotnet tool install --global dotnet-ef --version 10.0.9` pour le corrigé). Vérifiez `dotnet ef --version`.

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/lab4-postgresql/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

## Mise en situation

Le support a perdu les commandes de démonstration après un redémarrage. L'équipe veut les garder et classer les produits, sans transformer les catégories des anciennes lignes en chaînes vides.

## Étapes

Toutes les commandes se lancent depuis la racine de votre copie, sauf indication contraire.

### Étape 1 · Faire le plan de la persistance

```text
Explore les DbContext, Program.cs, l'AppHost et les factories de test. Propose un plan
pour PostgreSQL : catalogdb et orderingdb sur un même serveur Aspire avec volume.
Préserve les noms des services et leurs références. Ne modifie rien avant le plan.
```

Faites identifier `EnsureCreated`, `UseInMemoryDatabase` et les paquets EF InMemory. Les données en mémoire déjà perdues ne peuvent pas être migrées : conservez un petit jeu de démonstration reproductible.

### Étape 2 · Une première migration par API

```text
Remplace EF InMemory par Aspire.Npgsql.EntityFrameworkCore.PostgreSQL et les paquets
Design EF Core compatibles. Déclare PostgreSQL dans AppHost, port local 5433, volume
persistant, une base par API. Enregistre AddNpgsqlDbContext avec les mêmes noms.
Génère InitialCreate dans Data/Migrations pour chaque API. Remplace EnsureCreated
par Migrate. Recale la séquence Products après les graines HasData afin que le premier
POST ne réutilise pas un identifiant 1 à 4. Code et erreurs en anglais.
```

Relisez les `.csproj` : `UserSecretsId` du lab 3 doit rester. Lancez `dotnet build ECommerce.slnx`. Relisez chaque migration avant de démarrer l'AppHost (`Migrate()` les applique).

### Étape 3 · Comparer la catégorie naïve et la catégorie métier

Le champ `Category` a au plus 100 caractères ; il est obligatoire. Les quatre graines reçoivent `Peripherals`, `Peripherals`, `Displays`, `Accessories`. Toute autre ligne existante reçoit `Uncategorized`. Une création sans catégorie ou avec une catégorie blanche reçoit aussi cette valeur. Une catégorie trop longue doit donner 400, jamais une exception PostgreSQL 500.

```text
Ajoute Category au modèle Catalog, au DbContext et au POST, puis génère AddProductCategory.
Ne lance pas l'application. Utilise /review-migration src/ECommerce.Catalog.Api
AddProductCategory et confronte le SQL aux critères ci-dessus.
```

Comparez les deux SQL de `ressources/`. Expliquez le `DEFAULT ''` naïf, les `UpdateData` qui écrasent les graines et la différence entre réversibilité du schéma et conservation des données de la colonne supprimée. Le défaut métier doit être configuré dans le modèle, puis la migration régénérée tant qu'elle n'a été appliquée nulle part.

```bash
bash .claude/skills/review-migration/essai-ephemere.sh src/ECommerce.Catalog.Api AddProductCategory
dotnet ef migrations has-pending-model-changes --project src/ECommerce.Catalog.Api
```

Le script travaille sur son propre conteneur : il ne touche pas la base de l'AppHost. Gardez le SQL et la comparaison avant/après ; n'inventez pas un résultat si Docker manque.

### Étape 4 · Tester sur la vraie technologie

```text
Porte les factories xUnit sur Testcontainers.PostgreSql. Chaque test doit obtenir
sa propre base et appliquer les migrations réelles ; le faux Catalog d'Ordering reste
un HttpMessageHandler. Couvre les catégories, longueurs limites, valeur par défaut,
et la création d'un produit après les graines. Conserve les scénarios du lab 2.
```

```bash
dotnet test ECommerce.slnx
dotnet run --project src/ECommerce.AppHost
```

Créez un produit et une commande ; arrêtez puis redémarrez l'AppHost, sans supprimer son volume. Vérifiez qu'ils existent encore.

### Étape 5 · Brancher MCP sans compte administrateur

Dans votre terminal personnel, pendant que l'AppHost tourne :

```bash
bash "$FORMATION"/labs/lab4-postgresql/ressources/creer-role-lecture-seule.sh ~/lab-ecommerce
cp "$FORMATION"/labs/lab4-postgresql/ressources/.mcp.json .mcp.json
```

Le mot de passe est généré hors du dépôt dans `~/.config/lab-ecommerce/postgres-lecture.env`, droits 600. Le wrapper utilise `docker run --env-file` : aucune valeur dans `.mcp.json`. Il démarre Postgres MCP Pro en mode `restricted`, avec le rôle `lecteur_mcp`. L’image MCP est épinglée par digest vérifié et configurable par `IMAGE_POSTGRES_MCP`. Le wrapper construit DATABASE_URI uniquement dans le conteneur à partir de PGPASSWORD : l’image publiée attend une URI, contrairement aux nouvelles options de connexion du code source. [Le serveur documente le mode restricted et les paramètres de connexion](https://github.com/crystaldba/postgres-mcp).

Relancez Claude, consultez `/mcp`, puis demandez :

```text
Avec postgres-catalog, affiche le schéma de Products et le nombre de produits par
catégorie. Avec postgres-ordering, affiche le nombre de commandes. Aucune donnée client.
```

Dans votre terminal, vérifiez les droits du rôle indépendamment de MCP : remplacez `<conteneur>` par le nom affiché par le script.

```bash
docker exec -i --env-file "$HOME/.config/lab-ecommerce/postgres-lecture.env" <conteneur>   psql -X -h 127.0.0.1 -U lecteur_mcp -d catalogdb   -c 'SELECT count(*) FROM "Products";'
docker exec -i --env-file "$HOME/.config/lab-ecommerce/postgres-lecture.env" <conteneur>   psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U lecteur_mcp -d catalogdb   -c 'BEGIN; UPDATE "Products" SET "Category" = "Category" WHERE false; ROLLBACK;'
```

La seconde commande doit échouer avec `permission denied`, même sans modifier une ligne. Le rôle n'a pas de privilège d'écriture sur les tables de l'application ; cette protection vient de la base, pas du prompt.

### Étape 6 · Livrer

Mettez à jour `CLAUDE.md` : Docker devient requis pour les tests, migrations au démarrage et données persistantes. `/ship Persistance PostgreSQL et catégories` ; consignez les commandes et leurs résultats.

## Critères d'acceptation

- [ ] PostgreSQL persistant, deux bases distinctes, aucune chaîne secrète en Git.
- [ ] InitialCreate par service, AddProductCategory et snapshot cohérents.
- [ ] Anciennes lignes non graines à `Uncategorized`, graines aux catégories attendues.
- [ ] POST sans catégorie accepté ; longueur > 100 rejetée avec 400 ; identités sans collision.
- [ ] Tests PostgreSQL verts, persistance après redémarrage prouvée.
- [ ] MCP fonctionne avec lecteur_mcp et UPDATE refusé par PostgreSQL.

## Preuves à fournir

Dans `preuves/lab4/` : plan arbitré, SQL naïf/corrigé commenté, rapport `/review-migration`, essai montée/descente, sortie des tests, identifiants conservés après redémarrage, requête MCP et refus UPDATE (sans secret).

## Aides progressives

<details><summary>Indice 1 · La base repart vide</summary>Vérifiez WithDataVolume et que vous relancez le même AppHost ; ne supprimez pas le volume.</details>

<details><summary>Indice 2 · POST produit en conflit</summary>HasData fournit les identifiants sans avancer la séquence PostgreSQL. Le générateur SQL Npgsql émet setval après les graines : relisez le SQL généré de InitialCreate et ne supprimez pas cette instruction.</details>

<details><summary>Indice 3 · MCP ne se connecte pas</summary>AppHost doit écouter PostgreSQL sur 5433, le rôle doit exister et le wrapper doit être copié dans .claude/mcp. Docker atteint le poste par host.docker.internal.</details>

## Pour aller plus loin

Remplacez l'application automatique des migrations par un bundle exécuté avant les réplicas. Préparez une stratégie expand/contract pour un renommage de colonne.

## Débrief

Pourquoi une migration qui compile peut-elle perdre des données ? Qu'est-ce qui prouve les droits SQL ? Que perd Down ? **À retenir :** relire le SQL sur des données existantes, tester avec le fournisseur réel et donner à chaque outil les seuls droits nécessaires.

## Les fichiers du lab

- `.claude/settings.json` : réglages cumulés jusqu'au lab 4.
- `.claude/skills/review-migration/SKILL.md`, `essai-ephemere.sh` : procédure et essai SQL isolé.
- `.claude/mcp/postgres-lecture.sh` : lanceur MCP sans secret dans les arguments.
- `ressources/.mcp.json` : deux connexions SQL ; `creer-role-lecture-seule.sh`, `role-lecture-seule.sql` : rôle et vérifications.
- `ressources/migration-{naive,corrigee}-AddProductCategory.sql` : comparaison pédagogique.
- `solution/src/` : AppHost, projets, modèle, endpoints et migrations des deux API.
- `solution/tests/` : factories Testcontainers et tests PostgreSQL.
