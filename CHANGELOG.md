# Changelog

Toutes les modifications notables de ce projet seront documentées dans ce fichier.

## [Unreleased]
### Changed
- feat: enhance client templates with granular module control (9b4a0cf)
- feat: add automatic module linking options to add_oca_module.sh and add_external_module.sh (d4f8499)
- fix: remove old config file for templates (ae603a3)
- fix: prevent CONFIG_DIR override in repository_optimizer.sh (b47e100)
- refactor: update OCA repository updater script (f7af2c8)
- refactor: update external repository management scripts (5ef3a12)
- refactor: update OCA module scripts for new config structure (5802ebd)
- refactor: update generate_client_repo.sh to use new config files (b7fcc4a)
- refactor: split templates.json into separate config files (9504408)
- fix: link enterprise modules automatically (4f915ac)
- fix: améliorations infrastructure Docker (f65c217)
- fix: éviter duplication de ### Changed dans update_changelog.sh (ab82c35)
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
