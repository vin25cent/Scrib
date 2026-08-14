# Feuille de route

## Phase 0 — Cadrage et socle (terminée le 14 août 2026)

- consolider le cahier des charges ;
- définir les frontières de modules et la machine d'états ;
- créer le package Swift et les types métier initiaux ;
- ne brancher aucun traitement lourd ni fournisseur payant.

Sortie : dépôt documenté, ouvrable dans Xcode et prêt pour des prototypes isolés.

## Phase 1 — Prototype fiable d'enregistrement (validation MacBook en attente)

- formulaire et liste d'UE ;
- capture AVFoundation, vu-mètre et segments récupérables ;
- détection de périphérique et bascule micro interne ;
- estimation du stockage et restauration après incident ;
- tests de frappe intensive sur le Mac cible.

Jalon : quatre heures d'enregistrement continu sans perte, avec récupération
validée après arrêt forcé.

## Phase 2 — File persistante et conditions système (socle implémenté)

- SwiftData, machine d'états et checkpoints ;
- secteur, réseau, thermique, mémoire, sommeil et reprise ;
- menu macOS, progression, erreurs et notifications ;
- préemption par un nouvel enregistrement.

Jalon : une file simulée de 30 heures traverse arrêts, veille et pannes réseau sans
doublon.

État : la persistance SwiftData, les checkpoints, l'ordre FIFO, l'anti-doublon,
la reprise après interruption, le backoff, les conditions système et la
préemption sont implémentés. Une simulation automatisée de 30 cours d'une heure
passe ; la veille réelle et les changements secteur/réseau seront validés sur le
MacBook.

## Phase 3 — Benchmark de transcription locale

- corpus de conférences médicales publiques et échantillons contrôlés ;
- comparaison des moteurs et tailles de modèles ;
- mesure de fidélité médicale, RAM, impact sur Word et température ;
- choix et empaquetage du moteur gagnant ;
- horodatage, glossaires puis expérimentation de diarisation.

Jalon : décision documentée du moteur compatible avec 8 Go.

## Phase 4 — Génération structurée et DOCX

- comparer des fournisseurs dans la limite totale de 10 € ;
- définir et valider le schéma JSON ;
- créer le renderer OOXML et les modèles visuels ;
- intégrer notes personnelles, correction et régénération ciblée ;
- suivre le coût mensuel.

Jalon : cours et fiche s'ouvrant correctement dans Word, avec fidélité évaluée sur
un jeu de référence.

## Phase 5 — Supports et vérification scientifique

- extraction PDF, Office, images et scans ;
- insertion d'illustrations et signalement des éléments illisibles ;
- recherche bornée par liste blanche ;
- citations vérifiées, divergences d'autorités et notes datées.

Jalon : aucune citation finale hors domaine autorisé dans les tests adversariaux.

## Phase 6 — iCloud, empaquetage et recette

- publication fiable des deux DOCX dans iCloud Drive ;
- gestion des conflits Word et remplacement confirmé ;
- application autonome et procédure d'installation sans terminal ;
- une semaine complète de cours réels ;
- corrections jusqu'à moins de cinq minutes de contrôle manuel par cours normal.

## Après V1

- utilitaire de mise à jour manuelle ;
- signature/notarisation si un compte Apple Developer devient justifié ;
- QCM et cartes Anki ;
- éventuelle application iPhone ou partage multi-utilisateur.
