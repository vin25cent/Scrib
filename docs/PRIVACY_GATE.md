# Barrière locale de confidentialité

Avant tout envoi de texte vers un fournisseur cloud, Scrib recherche localement
des indices d'identification d'un patient : adresse électronique, téléphone,
numéro de sécurité sociale français, date de naissance contextualisée, adresse
postale, nom de patient contextualisé et identifiant de dossier médical.

La règle de décision est stricte :

1. aucun indice détecté : l'envoi peut continuer ;
2. au moins un indice : l'envoi est bloqué et une prévisualisation masquée est
   présentée ;
3. seule une approbation manuelle liée à l'empreinte exacte du contenu autorise
   cet envoi ;
4. toute modification du texte invalide automatiquement l'approbation.

Le détecteur est une barrière de réduction du risque, pas une garantie absolue.
Il peut produire des faux positifs ou manquer une formulation inhabituelle. Les
textes transmis doivent rester minimaux, les journaux ne doivent jamais conserver
la valeur détectée et le traitement local reste préféré.
