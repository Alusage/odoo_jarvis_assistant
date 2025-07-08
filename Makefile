# Makefile pour la gestion des clients Odoo

.PHONY: help create-client list-clients update-client update-requirements add-module list-modules merge-pr clean diagnostics cache-status

# Variables
CLIENTS_DIR = clients
SCRIPTS_DIR = scripts

help: ## Afficher cette aide
	@echo "Commandes disponibles:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

create-client: ## Créer un nouveau client interactivement
	@./create_client.sh

list-clients: ## Lister tous les clients existants
	@echo "Clients existants:"
	@if [ -d "$(CLIENTS_DIR)" ]; then \
		ls -1 "$(CLIENTS_DIR)" 2>/dev/null | sed 's/^/  - /' || echo "  Aucun client trouvé"; \
	else \
		echo "  Aucun client trouvé"; \
	fi

update-client: ## Mettre à jour les submodules d'un client (usage: make update-client CLIENT=nom_client)
	@if [ -z "$(CLIENT)" ]; then \
		echo "❌ Usage: make update-client CLIENT=nom_client"; \
		exit 1; \
	fi
	@$(SCRIPTS_DIR)/update_client_submodules.sh $(CLIENT)

update-requirements: ## Mettre à jour le requirements.txt d'un client avec les dépendances des submodules OCA (usage: make update-requirements CLIENT=nom_client [CLEAN=true])
	@if [ -z "$(CLIENT)" ]; then \
		echo "❌ Usage: make update-requirements CLIENT=nom_client [CLEAN=true]"; \
		echo "Options:"; \
		echo "  CLEAN=true  Supprimer les fichiers de sauvegarde après la mise à jour"; \
		exit 1; \
	fi
	@if [ ! -d "$(CLIENTS_DIR)/$(CLIENT)" ]; then \
		echo "❌ Client '$(CLIENT)' non trouvé dans $(CLIENTS_DIR)/"; \
		echo "Clients disponibles:"; \
		ls -1 "$(CLIENTS_DIR)" 2>/dev/null | sed 's/^/  - /' || echo "  Aucun client trouvé"; \
		exit 1; \
	fi
	@if [ "$(CLEAN)" = "true" ]; then \
		$(SCRIPTS_DIR)/update_client_requirements.sh $(CLIENT) --clean; \
	else \
		$(SCRIPTS_DIR)/update_client_requirements.sh $(CLIENT); \
	fi

add-module: ## Ajouter un module OCA à un client (usage: make add-module CLIENT=nom_client MODULE=module_key)
	@if [ -z "$(CLIENT)" ] || [ -z "$(MODULE)" ]; then \
		echo "❌ Usage: make add-module CLIENT=nom_client MODULE=module_key"; \
		echo "Modules disponibles:"; \
		jq -r '.oca_repositories | to_entries[] | "  \(.key) - \(.value.description)"' config/templates.json; \
		exit 1; \
	fi
	@$(SCRIPTS_DIR)/add_oca_module.sh $(CLIENT) $(MODULE)

list-modules: ## Lister les modules disponibles pour un client (usage: make list-modules CLIENT=nom_client)
	@if [ -z "$(CLIENT)" ]; then \
		echo "❌ Usage: make list-modules CLIENT=nom_client"; \
		exit 1; \
	fi
	@$(SCRIPTS_DIR)/list_available_modules.sh $(CLIENT)

list-oca-modules: ## Lister tous les modules OCA disponibles (usage: make list-oca-modules [PATTERN=pattern])
	@$(SCRIPTS_DIR)/list_oca_modules.sh $(PATTERN)

merge-pr: ## Merger une Pull Request dans un submodule client (usage: make merge-pr CLIENT=nom_client SUBMODULE=chemin_submodule PR=numero [BRANCH=branche])
	@if [ -z "$(CLIENT)" ] || [ -z "$(SUBMODULE)" ] || [ -z "$(PR)" ]; then \
		echo "❌ Usage: make merge-pr CLIENT=nom_client SUBMODULE=chemin_submodule PR=numero [BRANCH=branche]"; \
		echo "Exemple: make merge-pr CLIENT=mon_client SUBMODULE=addons/partner-contact PR=1234 BRANCH=16.0"; \
		exit 1; \
	fi
	@if [ ! -d "$(CLIENTS_DIR)/$(CLIENT)" ]; then \
		echo "❌ Client '$(CLIENT)' non trouvé dans $(CLIENTS_DIR)/"; \
		echo "Clients disponibles:"; \
		ls -1 "$(CLIENTS_DIR)" 2>/dev/null | sed 's/^/  - /' || echo "  Aucun client trouvé"; \
		exit 1; \
	fi
	@echo "🔄 Merge de la PR #$(PR) dans $(SUBMODULE) pour le client $(CLIENT)..."
	@cd "$(CLIENTS_DIR)/$(CLIENT)" && \
	if [ -x "scripts/merge_pr.sh" ]; then \
		./scripts/merge_pr.sh "$(SUBMODULE)" "$(PR)" "$(BRANCH)"; \
	else \
		echo "❌ Script merge_pr.sh non trouvé dans le client $(CLIENT)"; \
		echo "💡 Régénérez le client ou ajoutez le script manuellement"; \
		exit 1; \
	fi

clean: ## Nettoyer les fichiers temporaires
	@echo "🧹 Nettoyage des fichiers temporaires..."
	@rm -rf tmp_pr_merge/
	@echo "✅ Nettoyage terminé"

manage-templates: ## Gérer les templates et modules OCA
	@./manage_templates.sh

update-oca-repos: ## Mettre à jour automatiquement la liste des dépôts OCA depuis GitHub
	@$(SCRIPTS_DIR)/update_oca_repositories.sh --clean

update-oca-repos-fast: ## Mise à jour rapide des dépôts OCA (sans vérification des addons)
	@$(SCRIPTS_DIR)/update_oca_repositories.sh --clean --no-verify

update-oca-repos-en: ## Mettre à jour la liste des dépôts OCA avec descriptions anglaises
	@$(SCRIPTS_DIR)/update_oca_repositories.sh --lang en --clean

# Gestion des descriptions multilingues
descriptions-list: ## Lister toutes les descriptions OCA
	@$(SCRIPTS_DIR)/manage_oca_descriptions.sh list

descriptions-missing: ## Lister les descriptions manquantes (usage: make descriptions-missing LANG=fr|en)
	@$(SCRIPTS_DIR)/manage_oca_descriptions.sh missing $(LANG)

descriptions-stats: ## Afficher les statistiques des descriptions OCA
	@$(SCRIPTS_DIR)/manage_oca_descriptions.sh stats

descriptions-validate: ## Valider le fichier de descriptions OCA
	@$(SCRIPTS_DIR)/manage_oca_descriptions.sh validate

descriptions-auto: ## Compléter automatiquement les descriptions (usage: make descriptions-auto LANG=fr|en)
	@$(SCRIPTS_DIR)/manage_oca_descriptions.sh auto-complete $(LANG)

edit-descriptions: ## Éditer le fichier de descriptions OCA
	@if command -v code >/dev/null 2>&1; then \
		code config/oca_descriptions.json; \
	elif command -v nano >/dev/null 2>&1; then \
		nano config/oca_descriptions.json; \
	elif command -v vim >/dev/null 2>&1; then \
		vim config/oca_descriptions.json; \
	else \
		echo "❌ Aucun éditeur trouvé (code, nano, vim)"; \
	fi

test: ## Exécuter les tests du générateur
	@./test.sh

demo: ## Lancer une démonstration complète
	@./demo.sh

install-deps: ## Installer les dépendances système requises
	@echo "📦 Installation des dépendances..."
	@if command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get update && sudo apt-get install -y jq git; \
	elif command -v yum >/dev/null 2>&1; then \
		sudo yum install -y jq git; \
	elif command -v brew >/dev/null 2>&1; then \
		brew install jq git; \
	else \
		echo "❌ Gestionnaire de paquets non supporté. Installez manuellement: jq, git"; \
	fi
	@echo "✅ Dépendances installées"

# Commandes avancées
backup-client: ## Sauvegarder un client (usage: make backup-client CLIENT=nom_client)
	@if [ -z "$(CLIENT)" ]; then \
		echo "❌ Usage: make backup-client CLIENT=nom_client"; \
		exit 1; \
	fi
	@echo "💾 Sauvegarde du client $(CLIENT)..."
	@tar -czf "backup_$(CLIENT)_$(shell date +%Y%m%d_%H%M%S).tar.gz" -C $(CLIENTS_DIR) $(CLIENT)
	@echo "✅ Sauvegarde créée: backup_$(CLIENT)_$(shell date +%Y%m%d_%H%M%S).tar.gz"

status: ## Afficher le statut de tous les clients
	@echo "📊 Statut des clients:"
	@for client in $(shell ls $(CLIENTS_DIR) 2>/dev/null || echo ""); do \
		echo ""; \
		echo "🏢 Client: $$client"; \
		if [ -d "$(CLIENTS_DIR)/$$client/.git" ]; then \
			cd $(CLIENTS_DIR)/$$client && \
			echo "  📍 Branche: $$(git branch --show-current 2>/dev/null || echo 'N/A')"; \
			echo "  📊 Submodules: $$(git submodule status 2>/dev/null | wc -l || echo '0')"; \
			echo "  🔗 Modules liés: $$(ls extra-addons/ 2>/dev/null | wc -l || echo '0')"; \
		else \
			echo "  ❌ Pas un dépôt Git valide"; \
		fi; \
	done

diagnostics: ## Exécuter le diagnostic complet du système
	@./diagnostics.sh --full

check-client: ## Vérifier un client spécifique (usage: make check-client CLIENT=nom_client)
	@if [ -z "$(CLIENT)" ]; then \
		echo "❌ Usage: make check-client CLIENT=nom_client"; \
		exit 1; \
	fi
	@./diagnostics.sh $(CLIENT)

cache-status: ## Afficher le statut du cache des dépôts OCA
	@$(SCRIPTS_DIR)/repository_optimizer.sh cache-status

clean-cache: ## Nettoyer le cache des dépôts OCA
	@$(SCRIPTS_DIR)/repository_optimizer.sh clean-cache

build: ## Construire l'image Docker Odoo personnalisée (usage: make build [VERSION=18.0] [TAG=odoo-custom:18.0])
	@echo "🐳 Construction de l'image Docker Odoo personnalisée..."
	@$(SCRIPTS_DIR)/build_docker_image.sh $(VERSION) $(TAG)

# Versioning and changelog
release:
	@echo "Créer une release GitHub avec un changelog propre"
	@read -p "Nouvelle version (ex: 0.1.0): " VERSION; \
	git tag -a v$$VERSION -m "Release v$$VERSION"; \
	git push origin v$$VERSION; \
	@sed -i "s/## \[Unreleased\]/## \[Unreleased\]\n\n## [$$VERSION] - $(shell date +'%Y-%m-%d')/" CHANGELOG.md; \
	@echo "Release v$$VERSION créée avec succès"
