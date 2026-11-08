# Contrat du chart à construire

- Dossier `charts/ecommerce` ; `Chart.yaml`, `values.yaml`, `values.schema.json`, `templates/`.
- Quatre Deployments et Services ; PostgreSQL singleton avec PVC, désactivable pour un serveur externe.
- `existingSecret` référence un Secret déjà créé ; aucun template Secret, aucun mot de passe dans les valeurs.
- Noms et sélecteurs incluent la release ; découverte de services cohérente avec les Services rendus.
- `environment`, `replicas`, `resources`, `images.registry/tag/pullPolicy/digests` et `postgres` paramétrables.
- Dev : un réplica par service, `/health` et `/alive`. Prod : trois réplicas d'API et Gateway, un Web, sondes TCP.
- `values-dev.yaml` et `values-prod.yaml` à la racine. Les images locales gardent `1.0` ; digests vérifiés exigés avant publication réelle.
- Ne pas installer la release Helm dans le namespace lab8 : elle gère ses propres ressources dans `ecommerce-helm`.
