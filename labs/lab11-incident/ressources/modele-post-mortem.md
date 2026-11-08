# Post-mortem — commandes à total nul

Document à compléter avec les faits de votre session. Ne pas y copier une clé, un jeton
ou le journal brut. Les commits du scénario sont synthétiques ; ne pas leur attribuer
un impact de production réel.

## Résumé et impact

Symptômes observés, périmètre confirmé, durée mesurée ; impact non mesuré à expliciter.
Séparer commandes de démonstration, données préexistantes et hypothèses.

## Chronologie UTC

| Heure | Fait observé ou action | Source (commit, trace, commande, capture) |
|---|---|---|

## Cause et facteurs contributifs

Commit retourné par bisect :
Contrat producteur / consommateurs :
Mécanisme du decimal nul sans erreur :
Pourquoi les contrôles existants sont restés verts :
Fuite de clé : commit distinct, sans valeur de clé dans ce document.

## Détection et rétablissement

Test rouge / vert, versions exécutées, temps jusqu'au diagnostic :
Commandes historiques affectées : méthode d'identification proposée, sans correction de données automatique.
Rotation de formation : date, empreinte masquée et preuve hors Git ; révocation fournisseur réelle non applicable.

## Ce qui a fonctionné et ce qui a freiné

Faits observés, limites du scénario et des outils utilisés.

## Actions proposées (à valider humainement)

| Action concrète | Responsable à désigner | Échéance à convenir | Preuve de réalisation |
|---|---|---|---|
| Test de contrat dans la CI | | | |
| Interdiction et revue de logs de secrets | | | |
| Contrôle des commandes historiques | | | |

## Inconnues et décisions

Ce qui reste non prouvé, arbitrages et références. Aucun responsable ni délai fictif.
