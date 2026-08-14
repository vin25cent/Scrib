# Génération IA et banc d’essai

## État sûr par défaut

Scrib démarre sur `Simulation Scrib — gratuit`. La simulation reçoit les données
fictives, produit le contrat `1.0`, passe par le validateur réel et ne crée aucune
connexion réseau. Sélectionner un modèle réel ne suffit pas à lancer un appel :

1. une clé doit être enregistrée dans le Trousseau macOS ;
2. les appels payants doivent être activés explicitement ;
3. la version exacte de la transcription et des supports doit avoir passé la
   revue de confidentialité ;
4. le coût maximal projeté doit tenir dans le budget restant ;
5. seul le bouton « Tester ce modèle » déclenche la requête.

Le plafond opérationnel initial est de 8 USD pour garder une marge sous
l’enveloppe globale de 10 €. Le taux de change et les taxes devront être vérifiés
avec l’utilisateur juste avant les essais réels.

## Adaptateurs et modèles

Le protocole `AICloudGenerating` permet d’ajouter d’autres fournisseurs sans
modifier l’orchestrateur. Le premier adaptateur réel utilise l’API Responses
OpenAI et une sortie JSON Schema stricte. Le catalogue daté du 14 août 2026
prépare trois candidats :

- `gpt-5.6-luna` pour le coût minimal ;
- `gpt-5.6-terra` pour l’équilibre coût/qualité ;
- `gpt-5.6-sol` pour la qualité maximale.

Les identifiants, capacités et tarifs viennent de la
[documentation officielle OpenAI](https://developers.openai.com/api/docs/models/compare)
et doivent être revérifiés avant toute dépense. La disponibilité dépendra du
compte API utilisé.

## Traçabilité et comparaison

Chaque essai réussi conserve localement : fournisseur, modèle, clé d’idempotence,
identifiant de requête, jetons entrants et sortants, coût estimé, durée, nombre de
sections et de blocs. Relancer exactement le même contenu avec le même modèle
retourne le résultat persisté sans nouvel appel.

Les réponses brutes ne deviennent jamais directement des fichiers Word. Elles
sont d’abord décodées, vérifiées contre le contrat `1.0`, validées sémantiquement
et converties en modèles documentaires locaux. Une réponse mal formée, une source
non autorisée ou un horodatage obligatoire absent est rejeté.

## Procédure prévue au retour sur le Mac

1. lancer la simulation et contrôler le parcours complet ;
2. créer ou sélectionner un projet API séparé avec une limite fournisseur ;
3. enregistrer la clé dans Scrib, sans la copier dans un fichier ;
4. confirmer les prix et le budget opérationnel ;
5. tester Luna, Terra puis Sol sur le même jeu fictif ;
6. comparer validité, contenu, durée, jetons et coût avant de retenir un modèle ;
7. supprimer la clé du Trousseau à la fin si les essais sont terminés.
