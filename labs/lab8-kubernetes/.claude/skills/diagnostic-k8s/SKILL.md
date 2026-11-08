---
name: diagnostic-k8s
description: Diagnostiquer une panne du cluster k3d de formation avec des indices vérifiables.
disable-model-invocation: true
---

Travaille uniquement dans le contexte `k3d-formation`, namespace `ecommerce` (ou `ecommerce-helm` au lab 9). Lis d'abord `CLAUDE.md`, les manifestes et les permissions ; ne lis aucune valeur de Secret.

1. Reformule le symptôme, note l'heure et le parcours affecté.
2. Lis le contexte puis `kubectl get pods -n ecommerce`, les événements, les descriptions et les logs ciblés. Exécute une commande simple par appel. Pour une panne de routage, compare Service, sélecteurs, EndpointSlices et variables de découverte de services.
3. Dresse un tableau : hypothèse, commande de lecture, indice exact, conclusion. Cite les noms des ressources et messages, sans secret.
4. Ne propose un correctif qu'une fois la cause prouvée. Modifie le manifeste source, explique le changement et présente l'action d'application au contrôle de permission configuré. Pas d'`exec`, de suppression de namespace, de lecture de Secret ni de changement de contexte.
5. Vérifie le rollout, la disponibilité et le parcours HTTP d'origine. Pour chaque panne, livre symptôme → indice → cause → correction → preuve après.

Les images chiseled n'ont pas de shell. En Production `/health` et `/alive` sont absents : une sonde HTTP vers ces routes échoue même si le service fonctionne. Une sonde TCP prouve seulement que le port écoute ; le test de fumée complète cette preuve.
