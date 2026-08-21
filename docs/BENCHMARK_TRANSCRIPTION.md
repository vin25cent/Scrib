# Benchmark de transcription locale - protocole v1

## Objectif

Choisir sur le MacBook cible un moteur de transcription française qui préserve
les termes médicaux tout en laissant macOS et Word utilisables avec 8 Go de
mémoire. Scrib sera utilisé dès le semestre 1 ; le corpus priorise les UE 2.1,
2.2, 2.4 et 2.11.

La décision finale ne sera pas prise sur un runner GitHub. Les mesures de RAM,
température, autonomie et interaction avec Word doivent provenir de la machine
cible.

## Candidats

### 1. WhisperKit / Core ML

Intégration Swift native et modèles Core ML, distribuée sous licence MIT. C'est
le candidat principal pour une application autonome et une utilisation possible
de l'Apple Neural Engine.

WhisperKit 1.0.0 est épinglé exactement. Small multilingue est la baseline des
cours réels. Tiny n'est plus présenté dans l'interface normale. Medium est un
mode qualité facultatif dont le bénéfice doit être établi sur le même audio avant
toute recommandation.

Source : <https://github.com/argmaxinc/argmax-oss-swift>

### 2. whisper.cpp / Core ML + Metal

Implémentation C/C++ légère avec quantification, accélération Apple Silicon,
Metal et encodeur Core ML. Ce candidat offre davantage de contrôle sur la
mémoire et l'empaquetage, au prix d'un adaptateur Swift/C supplémentaire.

Source : <https://github.com/ggml-org/whisper.cpp>

### Référence de recherche : MLX Whisper

Le projet officiel MLX propose actuellement son exemple Whisper via Python et
demande notamment `mlx-whisper` et `ffmpeg`. Il peut servir de plafond de qualité
pendant les essais, mais ne satisfait pas l'exigence V1 « aucune installation
Python ou Homebrew sur le Mac cible ».

Source : <https://github.com/ml-explore/mlx-examples/tree/main/whisper>

## Corpus et droits

Le manifeste `Benchmarks/Transcription/corpus.json` est la source de vérité. Il
combine :

- un petit sous-ensemble français Common Voice CC0 pour la robustesse générale ;
- des conférences scientifiques Canal-U explicitement sous Creative Commons ;
- des extraits de cours réels uniquement après autorisation de l'enseignant ;
- des lectures contrôlées et consenties pour combler les UE sans source ouverte.

Les cours IFSI 2013 de traumatologie sur Canal-U sont très pertinents pour
l'UE 2.4, mais la page indique le droit commun de la propriété intellectuelle.
Ils restent donc bloqués et ne sont pas téléchargés automatiquement.

Sources des droits :

- <https://commonvoice.mozilla.org/en/datasets>
- <https://www.canal-u.tv/chaines/canal-uved/un-ocean-de-ressources/les-biotechnologies-marines>
- <https://www.canal-u.tv/chaines/cemu/ifsi-2013-les-processus-traumatiques-05-traumatologie-de-l-avant-bras-et-de-la-main>

## Références humaines

Préparer 20 à 30 minutes de référence, soit environ 5 à 8 minutes par UE. Une
seconde lecture relit chaque extrait avec le son ralenti si nécessaire.

Règles :

1. transcription verbatim, sans corriger la formulation du locuteur ;
2. nombres écrits en toutes lettres lorsqu'ils sont prononcés ainsi ;
3. ponctuation non évaluée ;
4. accents conservés pour la métrique stricte ;
5. termes critiques listés séparément ;
6. horodatages relevés sur les termes importants et passages incertains ;
7. passages réellement inaudibles exclus et consignés, jamais inventés.

## Mesures

Le cœur Swift calcule, uniquement lorsqu'une véritable référence humaine est
fournie :

- WER strict, sensible aux accents ;
- WER relâché, insensible aux accents ;
- CER relâché ;
- rappel des termes médicaux critiques, y compris les expressions de plusieurs
  mots ;
- erreur moyenne des horodatages ;
- facteur temps réel à partir de la durée audio et du temps de traitement.

Sans référence humaine, WER et CER sont absents du JSON ; le rappel d'une liste
de termes critiques reste calculable. L’adaptateur ajoute l’identifiant et la
version du moteur, la variante exacte du modèle, les paramètres de décodage, le
durée de traitement murale, la taille installée, un échantillonnage du pic de
mémoire résidente, les états thermiques initial/maximal et les informations de
machine (modèle matériel, mémoire physique, macOS, architecture). Le rapport JSON
est encodé avec clés triées et dates ISO 8601. Une métrique absente reste `null` :
les profils détaillés et la consommation énergétique doivent être relevés avec
Instruments et ne sont jamais estimés par Scrib.

Sur le Mac, chaque exécution ajoute : pic de mémoire résidente, taille du modèle,
état thermique initial et maximal, comportement après pause/reprise, et
observation de la réactivité de Word. Instruments servira aux profils détaillés,
conformément à la documentation Apple :
<https://developer.apple.com/documentation/CoreAI/analyzing-model-runtime-performance-with-instruments>.

## Procédure reproductible

1. Brancher le Mac au secteur et fermer les tâches non nécessaires.
2. Démarrer Word avec un document de cours de 30 pages.
3. Laisser la température revenir à l'état nominal.
4. Télécharger volontairement Small, puis éventuellement Medium. Aucun benchmark
   ne déclenche de téléchargement automatique.
5. Exécuter le même fichier avec Small sans contexte, Small avec contexte, puis
   Medium avec le même contexte et les mêmes paramètres.
6. Relever métriques automatiques et réactivité Word.
7. Répéter trois fois ; conserver la médiane et le pire pic mémoire.
8. Tester d’abord 1 minute puis 10 à 30 minutes. Le test de quatre
   heures avec checkpoints reste un jalon ultérieur.
9. Forcer une interruption, relancer Scrib et vérifier la reprise sans doublon.

## Seuils de décision V1

Un candidat est éliminé s'il dépasse l'un de ces seuils :

- rappel des termes critiques inférieur à 95 % ;
- WER relâché supérieur à 15 % sur la médiane du corpus ;
- pic de mémoire Scrib supérieur à 4 Go ;
- état thermique critique ou absence de suspension à l'état sérieux ;
- échec de reprise, duplication de texte ou crash sur quatre heures ;
- temps supérieur à la durée audio, soit facteur temps réel supérieur à 1.

Parmi les candidats restants, la qualité médicale prime. Le classement pondère
la fidélité à 60 %, la mémoire et la stabilité à 20 %, la vitesse à 10 % et les
horodatages à 10 %. La diarisation est évaluée seulement après le choix du moteur
et ne peut jamais modifier les mots reconnus.

## Livrables du jalon

- corpus local documenté et non versionné ;
- rapports JSON reproductibles ;
- tableau comparatif des moteurs et modèles ;
- décision d'architecture signée avec versions et empreintes des modèles ;
- procédure d'empaquetage autonome sans Python sur le Mac cible.
