# Prototype DOCX déterministe

## Portée

Le prototype transforme un `CourseDocument` validé en package Office Open XML
local. Aucun modèle d'IA ne produit directement le fichier Word. Le renderer
écrit son résultat de façon atomique via Foundation.

Les tests du renderer construisent des modèles documentaires isolés pour vérifier
le package, les styles et la compatibilité Word sans exposer de générateur dans
l’application.

## Système visuel

Le prototype reprend le preset `compact_reference_guide` avec la variante nommée
`scrib_a4` :

- page A4 portrait (11906 × 16838 DXA), marges de 1273 DXA et largeur utile
  de 9360 DXA ;
- Calibri 11 pt, interligne 1,25 et espacement 6 pt ;
- titres 16/13/12 pt avec hiérarchie bleue ;
- vraies définitions OOXML de listes, sans puces tapées à la main ;
- encadrés à géométrie fixe 9360 DXA, retrait 120 DXA et marges de cellule
  explicites ;
- en-tête discret sans filet et pied de page numéroté ;
- accent Scrib `#355AF3` limité au bloc de titre et aux liens ;
- sommaire statique cliquable vers des signets internes ;
- tableaux bornés à six colonnes, largeurs explicites et ligne d'en-tête répétée ;
- figures PNG/JPEG incorporées, dimensionnées sans déformation et dotées d'un
  texte alternatif ;
- horodatages sensibles reliés au schéma local `scrib://audio?t=...` ;
- bibliographie avec autorité, URL HTTPS et date de vérification.

Les encadrés ont quatre rôles stables : information, passage incertain,
information médicale importante et mise à jour scientifique. Les deux premiers
types sensibles peuvent afficher un horodatage audio.

Le sommaire reste volontairement statique et sans numéros de page afin d'être
correct dès l'ouverture, y compris si Word n'actualise pas les champs. Une table
des matières paginée pourra être ajoutée quand la pagination finale aura été
validée sur le Mac cible.

## Déterminisme et sécurité

- entrées ZIP triées et datées de façon fixe ;
- CRC32 calculé localement ;
- texte et attributs XML échappés ;
- aucune macro, aucun objet OLE et aucun contenu distant incorporé ;
- liens externes déclarés comme relations explicites ;
- métadonnées auteur limitées à `Scrib` ;
- même modèle structuré et même date de génération donnent exactement les mêmes
  octets.

La validation automatisée vérifie la signature ZIP, les parties OOXML
obligatoires, le déterminisme, l'échappement XML et les horodatages. Il n’existe
plus de prévisualiseur DOCX dans le dépôt : la recette visuelle dans Word sur
macOS reste une vérification manuelle à réaliser avant d’exposer l’export dans
l’application.
