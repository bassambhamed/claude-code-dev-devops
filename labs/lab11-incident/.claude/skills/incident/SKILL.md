---
name: incident
description: Piloter l'incident ECommerce, reproduire le contrat rompu, utiliser git bisect et réunir les faits du post-mortem.
argument-hint: "[symptôme et période]"
allowed-tools: Read, Grep, Glob, Bash, Agent
---
# Incident ECommerce

Mission : $ARGUMENTS

1. Stabiliser : noter l'impact connu, le dernier commit sain et les actions autorisées.
   Ne pas effacer de commandes ni réécrire l'historique. Ne pas confondre symptômes et impact mesuré.
2. Tenir preuves/lab11/journal.md, horodatage UTC pour chaque commande et constat. Masquer
   toute clé. Ne jamais lire incident/journal-ordering.log, réservé à la rotation par l'humain.
3. Expliquer le contrat attendu à partir des vrais DTO consommateurs. Préparer un script
   vérifiant la vraie réponse Catalog (pas grep du seul code). 0=sain, 1=rompu,
   125=build impossible à ce commit, 255=infrastructure indisponible (arrêt de bisect).
4. Exécuter le script sur mauvais puis bon état. Copier le script HORS de l'arbre Git pour
   qu'il survive aux checkouts. Sauver les changements avant bisect, ne jamais forcer un checkout.
5. Lancer git bisect entre incident-bon et HEAD. Si 255 ou tests sans environnement,
   arrêter et réparer le dispositif, sans désigner un faux mauvais commit. Sauver le résultat,
   faire git bisect reset même en cas d'échec, puis déléguer l'explication à incident-diagnostic.
6. Ajouter un test qui utilise les DTO des consommateurs, montrer le rouge, corriger au plus
   juste et montrer le vert. Le contrat historique price doit rester compatible.
7. Demander à l'humain d'exécuter lui-même la rotation de formation ; cette étape appartient
   à son terminal. Retirer la journalisation de la clé et vérifier qu'aucune nouvelle fuite
   n'apparaît. Ne pas afficher la clé, les user-secrets ou les variables d'environnement.
8. Rédiger le post-mortem selon le modèle. Chaque fait a une source ; toute inconnue reste
   une inconnue. L'humain valide impact, responsabilités et échéances. Les horodatages du
   scénario ne sont pas ceux d'une véritable production.
