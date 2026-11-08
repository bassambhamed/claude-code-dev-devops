# Anatomie d'un prompt : modèle pour le lab 1

Le chapitre prompting distingue les **composants** d'un prompt et les **techniques** qui aident à résoudre une tâche. La grille ci-dessous reprend les composants : rôle, contexte, instruction, contraintes, exemples et format de sortie. Les critères d'acceptation précisent l'instruction ; la vérification et les preuves font partie du travail demandé.

Un rôle n'est pas une garantie de compétence. Pour une petite tâche, quelques phrases suffisent ; ajoutez les informations nécessaires à une réalisation vérifiable.

## Modèle à adapter

```markdown
## Rôle
<!-- La mission et l'angle utile : développement, revue, diagnostic... -->

## Contexte
<!-- Fichiers (@chemin), symptôme, contrat, conventions pertinentes. -->

## Instruction et critères de réussite
<!-- Action attendue, avec comportements observables : entrée X -> sortie Y. -->

## Périmètre et contraintes
<!-- Fichiers modifiables, compatibilité, dépendances, langue du code. -->

## Exemples attendus
<!-- Cas représentatifs : un cas valide, un rejet, une limite si utile. -->

## Vérification et format de restitution
<!-- Commandes à exécuter ; rubriques attendues et limites à signaler. -->
```

## Exemple rempli : validation des commandes

```markdown
## Rôle
Tu interviens comme développeur .NET chargé d'un correctif ciblé.

## Contexte
@src/ECommerce.Ordering.Api/Endpoints/OrderingEndpoints.cs
Le support signale des commandes sans client et des totaux négatifs.
Le Web affiche les erreurs renvoyées comme chaînes simples par l'API.
Le code et les messages de l'application sont en anglais.

## Instruction et critères de réussite
Corrige la validation côté serveur :
- customer vide, blanc ou de plus de 200 caractères -> 400 ;
- quantity < 1 sur une ligne -> 400 ;
- commande valide -> 201 (inchangé) ;
- liste items vide -> 400 (inchangé).

## Périmètre et contraintes
Ordering.Api uniquement. Aucune nouvelle dépendance.
Garde les erreurs en chaînes simples et le contrat JSON existant.

## Exemples attendus
- {"customer":"","items":[{"productId":1,"quantity":1}]} -> 400.
- {"customer":"Ada","items":[{"productId":1,"quantity":2}]} -> 201.
Ces exemples décrivent la spécification, pas des résultats déjà exécutés.

## Vérification et format de restitution
Propose d'abord un plan sans modifier le code. Après accord, applique-le.
Lance dotnet build ECommerce.slnx, puis, l'application démarrée,
un curl par critère via http://localhost:5067/ordering/api/orders.
Rends trois rubriques : fichiers modifiés ; commandes et résultats,
critère par critère ; limites et hypothèses restantes.
```

## Choisir une technique

- **Zero-shot** : demande explicite sans exemple, pour obtenir une référence de comparaison.
- **Few-shot** : ajouter quelques paires entrée/sortie pour clarifier les cas et le format. Vérifier aussi un cas non montré, par exemple une quantité négative.
- **CoT / résolution en étapes** : demander les étapes utiles d'un calcul, ou des hypothèses et contrôles pour un diagnostic. Une explication ne remplace pas une vérification ; les modèles à raisonnement peuvent gérer la réflexion sans longue narration demandée.
- **Prompt chaining** : un premier échange produit le plan ; vous le relisez ; le suivant utilise ce plan pour produire le diff ; un dernier utilise le diff et les critères pour vérifier. Chaque transition transmet une sortie explicite.
- **Critique et révision** : demander des défauts étayés, arbitrer, puis corriger. Ne pas imposer un nombre de défauts à trouver.

## Avant d'envoyer

- [ ] L'instruction et les contraintes sont assez précises pour un collègue découvrant le projet.
- [ ] Les exemples sont cohérents avec les critères et couvrent plusieurs cas.
- [ ] Une commande vérifie chaque critère ; un cas non montré sera aussi testé.
- [ ] Le compte rendu distingue attendu, obtenu et vérification non exécutée.
