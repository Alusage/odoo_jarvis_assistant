# Changelog

Toutes les modifications notables de ce projet seront documentées dans ce fichier.

## [Unreleased]

### Changed

- fix: remove duplicate entries in CHANGELOG after post-commit run (1d8dd6b)
- test: commit pour tester le hook post-commit (5703a5b)
- docs: add git hooksPath configuration in README and include update_changelog hook (b065659)
- docs: add relase and update CHANGELOG after release 0.2.0 (8b52ee5)

## [0.2.0] - 2025-07-08

### Added

- Infrastructure pour gérer et ajouter des dépôts externes non-OCA (`add_external_module.sh`, `manage_external_repositories.sh`, `templates.json`)

### Fixed

- Correction de la détection et gestion des branches lors de l'ajout de submodules externes

## [0.1.0] - 2025-07-08

- Première release avec gestion des dépôts OCA et externes via URL et clé
