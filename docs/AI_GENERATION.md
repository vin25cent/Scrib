# Génération IA

## État sûr par défaut

L’infrastructure de génération structurée est conservée, mais aucun déclencheur
n’envoie actuellement la transcription ou les supports depuis l’interface.
Configurer un modèle ne suffit pas à lancer un appel :

1. une clé doit être enregistrée dans le Trousseau macOS ;
2. les appels payants doivent être activés explicitement ;
3. la version exacte de la transcription et des supports doit avoir passé la
   revue de confidentialité ;
4. le coût maximal projeté doit tenir dans le budget restant ;
5. un futur parcours de génération réel devra fournir une action explicite.

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

## Procédure prévue avant activation

1. raccorder l’orchestrateur au parcours réel de cours ;
2. vérifier que seuls la transcription et les supports explicitement sélectionnés
   sont inclus ;
3. créer ou sélectionner un projet API séparé avec une limite fournisseur ;
4. confirmer les prix, le budget et la revue de confidentialité ;
5. valider la sortie structurée et le rendu Word sur le Mac cible ;
6. supprimer la clé du Trousseau à la fin si les essais sont terminés.
