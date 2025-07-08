# Makefile pour la gestion des clients Odoo

.PHONY: help create-client list-clients update-client add-module list-modules clean diagnostics cache-status

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
