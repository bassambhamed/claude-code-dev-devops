---
name: revue-chart
description: Relire les rendus Helm de développement et de production avant déploiement.
disable-model-invocation: true
---

1. Lis `charts/ecommerce`, `values-dev.yaml` et `values-prod.yaml` ; exécute `helm lint` avec chaque fichier de valeurs.
2. Lance `bash .claude/skills/revue-chart/verifier.sh`. Il produit les rendus sous `preuves/lab9/` sans contacter le cluster. Inspecte les deux fichiers, puis leur diff.
3. Pour chaque environnement, cite les preuves : image et politique de tirage, réplicas par service, ressources, exécution non-root, références de Secret existant sans données de Secret, découverte de services, sondes compatibles avec l'environnement.
4. Le fichier prod est un profil de configuration à relire, pas une plateforme de production prête : PostgreSQL local singleton et Web interactif à un réplica. Signale l'absence de TLS, haute disponibilité, stockage et clés DataProtection partagées. N'invente pas de digest pour des images locales ; relève les digests des images publiées avant un vrai déploiement.
5. Ne déploie qu'après une synthèse des rendus et le contrôle de permission prévu. Sur k3d, utilise exclusivement namespace `ecommerce-helm` et contexte `k3d-formation`.

Rends un tableau : critère, dev, prod, preuve fichier/ligne, décision. Une sonde TCP garantit un port ouvert ; vérifie le parcours de commande séparément.
