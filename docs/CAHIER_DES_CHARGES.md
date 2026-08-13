# Cahier des charges — Scrib

Version de cadrage : 0.2 — 14 août 2026

## 1. Objet

Scrib est une application macOS native, destinée en premier lieu à un seul
étudiant en IFSI. Elle enregistre les cours depuis le microphone du MacBook,
permet la prise de notes parallèle dans Microsoft Word, transcrit l'audio en
local après le cours et transforme les sources disponibles en deux documents
DOCX immédiatement utilisables et modifiables.

La priorité absolue est la fidélité au contenu du cours. La rapidité est
secondaire : le traitement doit rester presque imperceptible pendant l'usage du
Mac et peut prendre autant de temps que nécessaire.

## 2. Contexte et contraintes

- machine cible : MacBook Neo, puce A18 Pro, 8 Go de mémoire unifiée et SSD de
  512 Go ;
- charge prévue : plus de 30 heures de cours enregistrées par semaine ;
- l'utilisateur saisit beaucoup de notes dans Word pendant l'enregistrement ;
- Word est fourni par la licence Microsoft 365 de l'IFSI ;
- application autonome, sans commandes techniques ni dépendances à installer ;
- ouverture manuelle de Scrib, sans lancement automatique avec macOS ;
- distribution initiale sur un seul MacBook ;
- coût minimal : infrastructure gratuite autant que possible, hors API d'IA ;
- code public sous licence Apache 2.0, sans donnée personnelle, contenu de cours
  ni clé ;
- test comparatif initial des fournisseurs d'IA plafonné à 10 € ;
- validation de la V1 après une semaine complète de cours réels.

## 3. Parcours nominal

1. L'utilisateur ouvre Scrib.
2. Il renseigne les cinq champs obligatoires : semestre, UE, titre, enseignant et
   durée prévue (1 h, 2 h, 4 h ou journée).
3. Au premier cours associé à un enseignant, il confirme disposer de
   l'autorisation d'enregistrer. Scrib mémorise cette confirmation dans la fiche
   de l'enseignant.
4. Scrib vérifie le microphone et l'espace libre nécessaire.
5. L'utilisateur démarre l'enregistrement puis ouvre lui-même son document Word.
6. Scrib affiche en permanence la durée et le niveau sonore.
7. Pause/Reprendre crée des segments techniques séparés, rattachés au même cours
   et ordonnés chronologiquement. Chaque nouvelle date crée un cours distinct.
8. À la fin, le cours entre dans une file d'attente persistante.
9. Le traitement démarre lorsque le Mac est branché et qu'Internet est disponible.
10. Scrib transcrit localement, génère le cours et la fiche, puis synchronise les
   deux DOCX dans iCloud Drive.
11. Une notification de fin demande si l'audio local doit être conservé ou
    supprimé. La transcription reste associée au cours.

## 4. Exigences fonctionnelles

### 4.1 Préparation et classement

- La liste des UE IFSI est préchargée depuis le
  [référentiel fourni](REFERENTIEL_UE.md) et reste modifiable. Les doublons du
  semestre 4 sont conservés volontairement. L'intitulé de l'UE 5.7 optionnelle
  sera défini ultérieurement.
- Un cours est distinct pour chaque date, même si l'UE et le titre sont identiques.
- La liste des enseignants mémorise leur nom et la date de confirmation de
  l'autorisation d'enregistrer. La confirmation n'est demandée qu'au premier
  cours associé à cet enseignant ; modifier son identité invalide la confirmation.
- Le dossier est nommé `Semestre – UE – titre – date` après normalisation des
  caractères interdits.
- Le document de notes personnelles est le DOCX du dossier qui n'est ni le cours
  final ni la fiche finale.
- Si plusieurs DOCX correspondent à cette règle, Scrib demande lequel utiliser
  et ne choisit jamais arbitrairement.
- S'il est ouvert au moment du traitement, Scrib demande de l'enregistrer et
  attend une confirmation.
- En l'absence de notes personnelles, le traitement continue automatiquement.

### 4.2 Enregistrement

- La source principale est le microphone sélectionné du MacBook.
- L'enregistrement est local, mono, dans un format compressé adapté à la parole.
- Un indicateur permanent montre le temps écoulé et le niveau sonore.
- Un niveau nul ou trop faible pendant plusieurs secondes déclenche une alerte
  visuelle discrète.
- Si un microphone externe disparaît, Scrib bascule immédiatement sur le micro
  interne, journalise et signale l'incident.
- Pendant l'enregistrement, Scrib empêche la veille et garde l'écran allumé.
- Pause/Reprendre finalise le segment courant puis en crée un nouveau, sans créer
  un nouveau cours.
- Un point de reprise exploitable est créé au plus toutes les dix minutes afin de
  limiter la perte en cas de fermeture brutale ou d'arrêt du Mac.
- Une durée dépassée n'interrompt pas l'enregistrement tant que l'espace libre
  demeure suffisant.
- Avant le départ, Scrib réserve une marge calculée d'après la durée prévue. En
  cas d'espace insuffisant, il propose l'audio traité non protégé le plus ancien ;
  un refus empêche le nouvel enregistrement. Un audio non traité n'est jamais
  proposé à l'écrasement.

### 4.3 Orchestration après le cours

- Une seule étape lourde s'exécute à la fois et un seul cours est traité à la fois.
- La file suit l'ordre du plus ancien au plus récent.
- Un nouvel enregistrement suspend les traitements précédents et devient
  prioritaire.
- Le traitement ne démarre que sur secteur et avec une connexion Internet.
- Si le Mac est débranché, l'étape en cours se termine puis la file est suspendue.
- La transcription locale peut garder le Mac éveillé ; les autres étapes doivent
  accepter la suspension et reprendre au réveil.
- La puissance est limitée à un profil bas fixe. En cas de pression mémoire,
  charge importante ou état thermique défavorable, le travail se suspend puis
  reprend automatiquement.
- Fermer la fenêtre ne coupe pas la file : Scrib reste disponible dans la barre des
  menus.
- Chaque étape écrit un checkpoint durable pour permettre une reprise sans
  recommencer le travail déjà validé.

### 4.4 Pipeline de transformation

Ordre logique de la V1 :

1. valider et fusionner les segments ;
2. normaliser l'audio et réduire le bruit de façon prudente ;
3. transcrire localement avec horodatage ;
4. distinguer si possible « Enseignant » et « Étudiant 1, 2… » ;
5. appliquer le vocabulaire des supports, un glossaire médical modifiable et le
   glossaire appris à partir des corrections ;
6. intégrer les notes personnelles comme compléments clairement identifiés ;
7. intégrer sur demande les PDF, PowerPoint, Word, images/scans et tableurs ;
8. détecter localement les données pouvant identifier un patient et bloquer
   l'envoi tant qu'une vérification manuelle n'a pas levé l'alerte ;
9. demander au fournisseur cloud une sortie structurée, fidèle et traçable ;
10. vérifier les références scientifiques selon la politique autorisée ;
11. rendre localement les deux DOCX de manière déterministe ;
12. publier les DOCX dans iCloud Drive et nettoyer les temporaires.

L'audio ne quitte jamais le Mac. La transcription complète peut être envoyée au
fournisseur cloud, conformément au choix exprimé, sous réserve de la confirmation
du droit d'enregistrer et de l'absence vérifiée de données identifiantes de
patients.

### 4.5 Transcription

- La transcription n'est jamais affichée en direct ; elle commence après le cours.
- Les mots anglais, latins ou d'une autre langue sont détectés et conservés dans
  leur langue originale.
- Les termes médicaux, médicaments et sigles sont aidés par trois sources :
  glossaire préchargé modifiable, corrections antérieures et supports du cours.
- Les passages incertains et les informations médicales importantes comportent
  un renvoi vers l'horodatage audio.
- La transcription peut être corrigée dans Scrib, puis le cours et la fiche sont
  régénérés sans retranscrire l'audio.
- Le choix final du moteur et du modèle dépend d'un benchmark sur le Mac cible.

### 4.6 Cours complet DOCX

- Réécriture pédagogique détaillée, sans perte d'information.
- Plan de l'enseignant conservé et amélioré.
- Contradictions entre oral et supports conservées et signalées.
- Images, schémas et tableaux utiles insérés lorsque lisibles, avec renvoi vers le
  support original. Un élément illisible est signalé et ignoré.
- Sommaire automatique cliquable, titres hiérarchisés, volet de navigation Word,
  pagination et liens vers les supports.
- En-tête ou pied de page : semestre, UE, titre, enseignant et date du cours.
- Encadrés dédiés aux notes personnelles, contradictions/incertitudes et mises à
  jour scientifiques.
- Chaque encadré de mise à jour scientifique affiche directement l'autorité, le
  lien canonique et la date de vérification. Une bibliographie finale récapitule
  ces références.
- Style équilibré : fond sobre, encadrés colorés et document modifiable.

### 4.7 Fiche de révision DOCX

Longueur adaptative. Elle doit inclure selon la matière :

- notions et définitions essentielles ;
- tableaux comparatifs ;
- rôle et surveillances infirmières ;
- valeurs normales et seuils importants ;
- pièges et erreurs fréquentes ;
- moyens mnémotechniques.

### 4.8 Vérification scientifique

- Une note externe ne remplace jamais le propos original : elle apparaît à sa
  suite, clairement séparée, datée et sourcée.
- Le contrôle porte au minimum sur toutes les informations cliniques sensibles,
  notamment les dosages, médicaments, valeurs, seuils, contre-indications,
  recommandations et conduites de soins.
- La recherche est limitée à une liste de domaines d'autorités : sources
  françaises et européennes, OMS, NICE et CDC. La liste précise est configurable.
- Si des autorités fiables divergent, Scrib présente le désaccord et cite les
  recommandations concernées.
- Aucun contenu trouvé hors liste blanche ne peut servir de référence finale.
- Scrib n'est pas un dispositif médical ; les documents produits restent des
  supports pédagogiques à vérifier.

### 4.9 Fichiers, Word et iCloud

- Fichiers générés : cours complet DOCX et fiche de révision DOCX.
- La transcription horodatée reste uniquement locale avec le cours.
- L'audio reste uniquement local et fait l'objet d'une décision à la notification
  de fin.
- Seuls le cours complet et la fiche sont publiés dans iCloud Drive pour être
  accessibles sur iPhone.
- Si iCloud est indisponible, les fichiers restent dans une zone locale de sortie
  et la synchronisation est retentée plus tard.
- Les temporaires sont supprimés après succès.
- Une régénération crée d'abord un fichier temporaire. Si Word verrouille le
  document, Scrib propose le remplacement quand il redevient possible.
- L'ancienne version est remplacée définitivement après confirmation.

### 4.10 File, erreurs et relances

La fenêtre principale et le menu affichent : état et progression, UE/titre/date,
erreur nécessitant une action et cumul mensuel estimé de l'API.

Actions disponibles :

- relancer toute la chaîne ;
- relancer uniquement la transcription ;
- régénérer uniquement le cours ;
- régénérer uniquement la fiche.

Une panne de transcription, d'Internet, d'API ou d'iCloud conserve les données et
déclenche une reprise automatique dès que les préconditions sont rétablies. Si le
fournisseur principal est indisponible, Scrib attend et réessaie ; il ne bascule
pas silencieusement vers un autre fournisseur.

### 4.11 Coûts, confidentialité et journalisation

- L'API est choisie d'abord sur la qualité après comparaison plafonnée à 10 €.
- Le meilleur modèle retenu est utilisé pour tous les cours.
- L'interface affiche le cumul mensuel estimé, sans plafond bloquant en V1.
- Les clés sont stockées dans le Trousseau macOS et jamais dans le dépôt.
- La protection locale repose sur la session macOS ; FileVault reste fortement
  recommandé mais n'est pas imposé par Scrib.
- Les journaux contiennent les états et codes d'erreur. De courts extraits de
  contenu ne sont permis qu'en cas d'erreur, avec une durée de conservation
  limitée et une action explicite de suppression.

## 5. Critères d'acceptation V1

- Trente heures hebdomadaires peuvent entrer dans la file sans perte ni doublon.
- Le premier cours d'un enseignant ne peut pas démarrer sans confirmation de
  l'autorisation ; les cours suivants réutilisent cette confirmation.
- Après arrêt forcé, la perte audio maximale est inférieure ou égale à dix minutes
  et la file reprend au dernier checkpoint valide.
- Aucun audio n'est envoyé sur le réseau.
- Une alerte de donnée patient bloque tout envoi cloud jusqu'à validation
  manuelle.
- Aucun traitement lourd ne démarre sur batterie et l'enregistrement préempte la
  file en cours.
- Une correction de transcription permet de régénérer séparément chaque DOCX.
- Les deux DOCX s'ouvrent et restent modifiables dans Word Microsoft 365.
- Les passages incertains, contradictions et ajouts scientifiques sont visuellement
  distincts du contenu de l'enseignant.
- Les passages incertains et informations médicales importantes permettent de
  retrouver l'horodatage audio correspondant.
- Une semaine réelle de cours est traitée avec moins de cinq minutes de vérification
  manuelle par cours normal.
- Les clés, audios, transcriptions et documents ne figurent jamais dans Git.

## 6. Hors périmètre V1

- transcription en direct ;
- application iPhone dédiée ;
- QCM et cartes Anki ;
- LLM local de génération ;
- collaboration multi-utilisateur ;
- publication sur le Mac App Store ;
- substitution automatique d'un fournisseur cloud ;
- suppression automatique d'audios sans confirmation ;
- conseil médical ou validation clinique.

## 7. Risques principaux

- qualité du micro interne pendant une frappe intensive ;
- diarisation imparfaite en amphithéâtre ;
- pression mémoire d'un grand modèle Whisper sur 8 Go ;
- variabilité et coût des réponses cloud ;
- complexité du rendu DOCX (sommaire, images, tableaux et champs Word) ;
- règles de consentement de l'IFSI et présence possible de données patient ;
- comportements de verrouillage Word et délais propres à iCloud Drive.

Ces risques sont traités par des benchmarks, une architecture à adaptateurs, des
checkpoints persistants et une semaine de recette réelle avant validation.
