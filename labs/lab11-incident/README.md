# Lab 11 · Des totaux à 0 €

> Partie 11 des supports · Mécanismes : skill `/incident`, sous-agent `incident-diagnostic`, `git bisect run`, test de contrat et post-mortem · Prérequis : lab 10, Docker, .NET 10, Git, `curl`, `jq`, Perl, OpenSSL

## Pourquoi ce lab

Tout répond 200 ou 201, mais les montants valent zéro. La cause peut être dans un autre
service que celui qui affiche le symptôme. L'historique donne des candidats ; un script
reproductible fournit à Git le verdict qui permet de choisir le commit. L'agent explique
les faits, puis le test de contrat protège les prochains changements.

## Objectifs

- Reproduire une rupture silencieuse du contrat Catalog vers Ordering et Web.
- Trouver le premier commit fautif avec un oracle exécutable et `git bisect`.
- Corriger en préservant le contrat existant et tester les DTO réellement utilisés.
- Retirer une journalisation sensible, effectuer une rotation de formation et rédiger
  un post-mortem qui sépare faits, hypothèses et engagements à valider.

## Point de départ

Votre copie à la fin du lab 10, commitée, application arrêtée. Le script crée lui-même
la branche `incident` et le tag `incident-bon`. Gardez une copie des données utiles ; le
lab ne corrige pas automatiquement les anciennes commandes à total nul.
Les bases éphémères du script de contrat sont distinctes des bases de l'AppHost.

**Installer le dispositif du lab.** Depuis n'importe quel dossier :

```bash
cp -R "$FORMATION"/labs/lab11-incident/.claude/. ~/lab-ecommerce/.claude/
git -C ~/lab-ecommerce status --short .claude
git -C ~/lab-ecommerce diff .claude/settings.json
```

Le `settings.json` du lab reprend les règles de tous les labs précédents et remplace le vôtre : si `git diff` montre la suppression de règles que vous aviez ajoutées, remettez-les. Relancez ensuite Claude Code : les réglages et les hooks sont lus au démarrage.

> Votre copie n'est pas à la fin du lab précédent ? Voir « Rattraper un lab » dans [`labs/README.md`](../README.md#rattraper-un-lab).

Commitez le dispositif avant l'injection : le script refuse une copie modifiée.

## Mise en situation

Lundi, le support voit des prix et des commandes à zéro. Vingt commits séparent la
version actuelle de la dernière version saine. Un collègue a transmis un extrait de log
contenant une clé de paiement **factice**. Il faut restaurer les nouvelles commandes et
traiter la fuite, sans conclure que les anciennes commandes se réparent toutes seules.

## Étapes

### Étape 1 · Rejouer et observer

Dans votre terminal :

```bash
bash "$FORMATION"/labs/lab11-incident/ressources/rejouer-incident.sh ~/lab-ecommerce
cd ~/lab-ecommerce
git log --oneline incident-bon..HEAD
```

Le script ajoute vingt commits compilables et un extrait de log dans `incident/`, exclu
de Git. Il refuse de rejouer si sa branche ou son tag existent. Le journal brut n'est pas
à copier dans les preuves ni dans la conversation. Le participant l'inspecte dans son
terminal et ne transmet qu'une observation masquée.

Démarrez l'AppHost. Observez le JSON Catalog, puis créez une commande avec le produit 1.
Le produit est stocké avec son prix normal, mais ses consommateurs lisent zéro : notez
JSON, code HTTP et total observé, sans modifier les données. Arrêtez l'AppHost avant bisect.

```text
/incident Prix et totaux à zéro depuis la dernière livraison. Établis un plan, les
contrats attendus et un script de reproduction. Sépare le diagnostic métier du traitement
par l'humain de la clé factice exposée. Aucun effacement de commandes.
```

### Étape 2 · Construire un oracle fiable

Demandez un script lisant la réponse **réelle** de Catalog et les champs attendus par
les records CatalogProduct et ProductDto. Les codes doivent être : 0 sain, 1 rompu,
125 compilation impossible à ce commit, 255 infrastructure impossible (bisect doit s'arrêter).
Comparez avec `solution/scripts/verifier-contrat.sh` seulement après votre proposition.
Ce script lance son PostgreSQL jetable et Catalog sur des ports libres ; il nettoie ses
ressources en sortie. Il ne se contente pas de chercher un attribut dans le code.

Gardez l'oracle hors de l'arbre Git pour qu'il survive aux changements de révision :

```bash
cp "$FORMATION"/labs/lab11-incident/solution/scripts/verifier-contrat.sh /tmp/verifier-contrat-lab11.sh
bash /tmp/verifier-contrat-lab11.sh  # 1 attendu sur incident
```

Vérifiez aussi le bon état sur une copie de travail séparée :

```bash
git worktree add --detach /tmp/ecommerce-incident-bon incident-bon
(cd /tmp/ecommerce-incident-bon && bash /tmp/verifier-contrat-lab11.sh)  # 0 attendu
git worktree remove /tmp/ecommerce-incident-bon
```

Si ce chemin temporaire existe déjà, choisissez-en un autre. Ne contournez pas un code
255 ; assurez-vous que Docker tourne et que les paquets peuvent être restaurés.

### Étape 3 · Laisser Git choisir le commit

```bash
mkdir -p preuves/lab11
git bisect start
git bisect bad HEAD
git bisect good incident-bon
git bisect run bash /tmp/verifier-contrat-lab11.sh > /tmp/bisect-lab11.txt 2>&1
cat /tmp/bisect-lab11.txt
git bisect log > /tmp/bisect-lab11.log
git bisect reset
cp /tmp/bisect-lab11.txt /tmp/bisect-lab11.log preuves/lab11/
```

Même après échec, revenez avec `git bisect reset`. Demandez à `incident-diagnostic`
d'expliquer le diff du commit indiqué. Il doit relier le nouveau champ JSON à l'ancien
champ attendu par les consommateurs, pas simplement citer le dernier commit.
Consignez le hash **de votre historique** : le script crée des horodatages et donc des
hashes différents à chaque session. Le commit attendu porte le message
`feat(catalog): align the product JSON with the partner API naming`.

### Étape 4 · Un test rouge, puis le correctif compatible

Ajoutez des tests de contrat qui désérialisent le JSON réel avec les DTO des deux
consommateurs. Référencer les deux API comme assemblies produirait deux classes `Program` ;
le corrigé compile les fichiers sources des clients comme liens dans les tests de Catalog.
Ainsi les DTO testés sont ceux du code consommateur, sans troisième copie du contrat.

Pour comparer au corrigé, copiez **d'abord uniquement les tests et leur projet** :

```bash
cp "$FORMATION"/labs/lab11-incident/solution/tests/ECommerce.Catalog.Api.Tests/ECommerce.Catalog.Api.Tests.csproj tests/ECommerce.Catalog.Api.Tests/
cp "$FORMATION"/labs/lab11-incident/solution/tests/ECommerce.Catalog.Api.Tests/ProductContractTests.cs tests/ECommerce.Catalog.Api.Tests/
dotnet test tests/ECommerce.Catalog.Api.Tests --filter FullyQualifiedName~ProductContractTests
```

Les deux tests doivent échouer sur le prix, pas sur Docker ou la compilation. Ensuite,
restaurez le contrat JSON historique `price` de Catalog : retirez le renommage `unitPrice`.
Les tests Catalog adaptés par l'incident à ce nouveau nom doivent revenir à `Price` aussi.
Changer seulement les clients rendrait incompatibles d'autres consommateurs historiques.
Le prix stocké et les migrations ne changent pas.

```bash
dotnet test ECommerce.slnx
bash /tmp/verifier-contrat-lab11.sh
```

Le compteur de commandes du lab 10 compte aussi une commande enregistrée à zéro ; il
n'a pas prétendu vérifier le contrat. Ne supprimez pas cette télémétrie en corrigeant.

### Étape 5 · Traiter le secret exposé

La fuite vient d'un autre commit : le log de démarrage d'Ordering ajoute `key {ApiKey}`.
Retirez ce paramètre et sa valeur dans `Program.cs`, en gardant les informations provider
et endpoint non sensibles. Un retour arrière n'invalide pas la clé déjà exposée.

**Vous**, dans votre terminal, lancez :

```bash
bash "$FORMATION"/labs/lab11-incident/ressources/rotation-cle.sh ~/lab-ecommerce
```

Ce script simule le portail du fournisseur : il consigne la révocation de la clé de
formation, crée une nouvelle valeur et la range dans user-secrets sans l'afficher.
`incident/rotation.log` contient uniquement préfixes masqués et empreintes. Ce n'est pas
une révocation chez un véritable fournisseur ; en production il faut son API ou portail.
Ne demandez pas à l'agent de lire la nouvelle valeur, les user-secrets ou le journal brut.
Relancez Ordering et confirmez dans les logs de démarrage que la clé n'est plus écrite.
Les copies de logs déjà émises relèvent d'une politique de rétention/assainissement à décider.

### Étape 6 · Tester le rétablissement et documenter

Redémarrez l'AppHost sur le correctif, refaites une commande : pour le produit 1 de la
fixture, quantité 2, le total attendu est 239.98. Vérifiez aussi le prix dans le Web.
Les commandes déjà enregistrées avec zéro gardent leur instantané : proposez une méthode
d'identification et une validation métier pour leur traitement, sans réécriture automatique.

Copiez `ressources/modele-post-mortem.md` dans `preuves/lab11/post-mortem.md` et complétez
avec votre journal UTC, le hash identifié, le rouge/vert, les trace IDs éventuels et les
inconnues. La cause et le temps de diagnostic se prouvent ; responsables et échéances
restent des engagements humains à convenir. Terminez par `/ship Rétablissement du contrat Catalog`.

## Critères d'acceptation

- [ ] Oracle 1 sur la version incidente, 0 sur incident-bon ; infrastructure distincte des bases du participant.
- [ ] `git bisect` désigne le commit de renommage JSON ; `git bisect reset` a restauré la branche.
- [ ] Tests de contrat des vrais consommateurs rouges avant, verts après ; suite complète verte.
- [ ] `price` et total non nul restaurés pour les nouvelles commandes, sans migration métier inutile.
- [ ] Le log ne contient plus la clé ; rotation de formation réalisée par le participant.
- [ ] Aucun journal brut ni secret dans les preuves commitées.
- [ ] Post-mortem sourcé, chronologie de session et impact réellement observé.

## Preuves à fournir

Dans `preuves/lab11/` : journal UTC, sorties oracle sur bon/mauvais état, bisect et hash,
rouge/vert des tests de contrat, tests complets, vérification de la nouvelle commande,
confirmation masquée de rotation et post-mortem. Aucun hash, nombre de commandes affectées
ou temps de diagnostic fourni dans le corrigé ne remplace votre mesure.

## Aides progressives

<details><summary>Indice 1 · Aucun 500 mais un decimal nul</summary>
System.Text.Json ne trouve plus price dans la réponse ; le decimal non nullable du record
reçoit sa valeur par défaut. Vérifiez les clés de l'objet JSON, pas seulement l'entité EF.
</details>

<details><summary>Indice 2 · Bisect désigne un commit de test ou saute tout</summary>
L'oracle doit utiliser l'API et le contrat, sans lancer une suite que les commits de
l'incident ont adaptée au renommage. Un environnement absent n'est pas un mauvais commit.
Gardez le script hors du dépôt, testez 0 et 1 avant de lancer la dichotomie.
</details>

<details><summary>Indice 3 · Les tests Ordering étaient verts</summary>
Le faux Catalog renvoyait encore price. Les tests validaient correctement Ordering face
à ce faux, sans prouver que le vrai Catalog envoie le même JSON. Le test de contrat
réel comble ce manque.
</details>

## Pour aller plus loin

Exécutez les tests de contrat dans la CI existante (elle lance déjà `dotnet test`), ajoutez
un contrôle de journalisation et proposez une alerte sur les montants suspects. Comparez
retour arrière et compatibilité additive pour de véritables clients partenaires. Écrivez
une procédure de réparation de données séparée, avec validation métier.

## Débrief

Combien de révisions ont été testées ? Pourquoi un grep sur la présence de Price dans
le C# n'aurait-il rien prouvé ? Quelle protection a manqué au faux Catalog ? Quelle preuve
distingue retrait de log et rotation ? Quelles phrases du post-mortem restent des hypothèses ?

**Ce que l'on observe souvent.** L'agent accuse le service qui affiche le zéro, propose
de changer les DTO sans penser aux autres clients, ou confond rollback et réparation
des commandes historiques. À retenir : le même oracle sert au diagnostic, au bisect et
à la non-régression ; les faits s'horodatent et les contrats copiés se testent.

## Les fichiers du lab

| Fichier | Rôle |
|---|---|
| `.claude/settings.json` | Permissions cumulées, lecture du journal brut refusée et rotation réservée au participant. |
| `.claude/skills/incident/SKILL.md` | Méthode, journal UTC, bisect et restitution factuelle. |
| `.claude/agents/incident-diagnostic.md` | Explication en lecture seule du commit identifié. |
| `ressources/rejouer-incident.sh` | Historique synthétique de vingt commits, tag sain et journal exclu de Git. |
| `ressources/rotation-cle.sh` | Simulation de révocation/émission ; user-secrets, sans affichage de la clé. |
| `ressources/modele-post-mortem.md` | Trame à remplir avec les preuves de session. |
| `solution/scripts/verifier-contrat.sh` | Oracle API réel, PostgreSQL jetable, codes adaptés à bisect. |
| `solution/src/ECommerce.Catalog.Api/Models/Product.cs` | Contrat price restauré. |
| `solution/src/ECommerce.Ordering.Api/Program.cs`, `Payment/PaymentOptions.cs` | Configuration de paiement et log sûr. |
| `solution/tests/ECommerce.Catalog.Api.Tests/` | Projet liant les vrais clients, tests de contrat et tests produits rétablis. |
| `solution/src/*/README.md` | Documentation du contrat et du paiement. |

Le corrigé peut être copié sur la fin du lab 10 pour un rattrapage, ou sur l'incident
rejoué pour le corriger. Il ne supprime aucun fichier. Le bisect, les preuves, la rotation
et la validation métier restent à réaliser sur le poste. Les métriques du lab 10 sont conservées.
