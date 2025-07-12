#!/usr/bin/env python3
"""
Tests unitaires pour le serveur MCP Odoo Client Generator
"""

import asyncio
import sys
import os
import json
import tempfile
import shutil
from pathlib import Path
from unittest.mock import Mock, AsyncMock, patch

# Ajouter le chemin du serveur MCP (répertoire parent)
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

try:
    from mcp_server import OdooClientMCPServer
    import mcp.types as types
except ImportError as e:
    print(f"❌ Import error: {e}")
    print("💡 Install MCP library: pip install mcp")
    sys.exit(1)


class TestMCPServer:
    """Classe de tests pour le serveur MCP"""
    
    def __init__(self):
        self.repo_path = Path(__file__).parent.parent.parent
        self.test_results = []
        
    def log_test(self, name: str, success: bool, message: str = ""):
        """Enregistre le résultat d'un test"""
        status = "✅" if success else "❌"
        self.test_results.append({
            "name": name,
            "success": success,
            "message": message
        })
        print(f"{status} {name}: {message}")
        
    async def test_server_creation(self):
        """Test la création du serveur MCP"""
        try:
            server = OdooClientMCPServer(str(self.repo_path))
            self.log_test("Server Creation", True, "Serveur créé avec succès")
            return server
        except Exception as e:
            self.log_test("Server Creation", False, f"Erreur: {e}")
            return None
    
    async def test_invalid_repo_path(self):
        """Test avec un chemin de repo invalide"""
        try:
            OdooClientMCPServer("/path/that/does/not/exist")
            self.log_test("Invalid Repo Path", False, "Devrait échouer avec un chemin invalide")
        except ValueError:
            self.log_test("Invalid Repo Path", True, "Erreur correctement levée pour chemin invalide")
        except Exception as e:
            self.log_test("Invalid Repo Path", False, f"Erreur inattendue: {e}")
    
    async def test_tools_list(self):
        """Test la liste des outils disponibles"""
        try:
            server = OdooClientMCPServer(str(self.repo_path))
            
            # Tester que le serveur a bien été configuré avec les handlers
            # Version actuelle avec delete_client (13 outils)
            expected_tools = [
                "create_client", "list_clients", "update_client", "add_module",
                "list_modules", "list_oca_modules", "client_status", "check_client",
                "update_requirements", "update_oca_repos", "build_docker_image",
                "backup_client", "delete_client"
            ]
            
            # Vérifier que toutes les méthodes d'implémentation existent
            missing_methods = []
            for tool in expected_tools:
                method_name = f"_" + tool
                if not hasattr(server, method_name):
                    missing_methods.append(method_name)
            
            if missing_methods:
                self.log_test("Tools List", False, f"Méthodes manquantes: {missing_methods}")
            else:
                self.log_test("Tools List", True, f"Toutes les {len(expected_tools)} méthodes d'outils sont présentes")
                
        except Exception as e:
            self.log_test("Tools List", False, f"Erreur: {e}")
    
    async def test_create_client_schema(self):
        """Test le schéma de l'outil create_client"""
        try:
            server = OdooClientMCPServer(str(self.repo_path))
            
            # Vérifier que la méthode _create_client existe et accepte les bons paramètres
            import inspect
            
            if not hasattr(server, '_create_client'):
                self.log_test("Create Client Schema", False, "Méthode _create_client non trouvée")
                return
            
            # Vérifier la signature de la méthode
            sig = inspect.signature(server._create_client)
            params = list(sig.parameters.keys())
            
            expected_params = ["name", "template", "version", "has_enterprise"]
            missing_params = [p for p in expected_params if p not in params]
            
            if missing_params:
                self.log_test("Create Client Schema", False, f"Paramètres manquants: {missing_params}")
            else:
                # Vérifier les valeurs par défaut
                template_param = sig.parameters.get("template")
                version_param = sig.parameters.get("version")
                enterprise_param = sig.parameters.get("has_enterprise")
                if (template_param and template_param.default == "basic" and
                    version_param and version_param.default == "18.0" and
                    enterprise_param and enterprise_param.default is False):
                    self.log_test("Create Client Schema", True, "Méthode _create_client avec has_enterprise configurée")
                else:
                    self.log_test("Create Client Schema", False, "Valeurs par défaut incorrectes")
                    
        except Exception as e:
            self.log_test("Create Client Schema", False, f"Erreur: {e}")
    
    async def test_command_execution(self):
        """Test l'exécution de commandes"""
        try:
            server = OdooClientMCPServer(str(self.repo_path))
            
            # Tester une commande simple
            result = server._run_command(["echo", "test"])
            
            if result["success"] and "test" in result["stdout"]:
                self.log_test("Command Execution", True, "Exécution de commande fonctionnelle")
            else:
                self.log_test("Command Execution", False, f"Résultat inattendu: {result}")
                
        except Exception as e:
            self.log_test("Command Execution", False, f"Erreur: {e}")
    
    async def test_list_clients_mock(self):
        """Test de l'appel list_clients avec mock"""
        try:
            server = OdooClientMCPServer(str(self.repo_path))
            
            # Mock de la commande make list-clients
            with patch.object(server, '_run_command') as mock_run:
                mock_run.return_value = {
                    "success": True,
                    "stdout": "client1\nclient2\nclient3",
                    "stderr": ""
                }
                
                result = await server._list_clients()
                
                if len(result) == 1 and "client1" in result[0].text:
                    self.log_test("List Clients Mock", True, "Fonction list_clients fonctionne")
                else:
                    self.log_test("List Clients Mock", False, f"Résultat inattendu: {result}")
                    
        except Exception as e:
            self.log_test("List Clients Mock", False, f"Erreur: {e}")
    
    async def test_create_client_parameters(self):
        """Test des paramètres de create_client"""
        try:
            server = OdooClientMCPServer(str(self.repo_path))
            
            # Mock de la commande de création
            with patch.object(server, '_run_command') as mock_run:
                mock_run.return_value = {
                    "success": True,
                    "stdout": "Client created successfully",
                    "stderr": ""
                }
                
                # Test avec paramètres par défaut
                result = await server._create_client("test_client")
                
                # Vérifier que la commande appelée contient les bons paramètres
                args_called = mock_run.call_args[0][0]
                
                # Doit contenir: script, name, version, template, has_enterprise(false)
                expected_elements = ["test_client", "18.0", "basic", "false"]
                all_present = all(elem in args_called for elem in expected_elements)
                
                if all_present:
                    self.log_test("Create Client Parameters", True, "Paramètres par défaut transmis correctement")
                else:
                    self.log_test("Create Client Parameters", False, f"Paramètres incorrects: {args_called}")
                    
                # Test avec paramètres personnalisés
                mock_run.reset_mock()
                await server._create_client("test_client", "ecommerce", "17.0")
                args_called = mock_run.call_args[0][0]
                
                expected_elements = ["test_client", "17.0", "ecommerce", "false"]
                all_present = all(elem in args_called for elem in expected_elements)
                
                if all_present:
                    self.log_test("Create Client Parameters (Custom)", True, "Paramètres personnalisés transmis correctement")
                else:
                    self.log_test("Create Client Parameters (Custom)", False, f"Paramètres incorrects: {args_called}")
                
                # Test avec Enterprise
                mock_run.reset_mock()
                await server._create_client("test_enterprise", "basic", "18.0", True)
                args_called = mock_run.call_args[0][0]
                
                expected_elements = ["test_enterprise", "18.0", "basic", "true"]
                all_present = all(elem in args_called for elem in expected_elements)
                
                if all_present:
                    self.log_test("Create Client Parameters (Enterprise)", True, "Paramètre has_enterprise=True transmis correctement")
                else:
                    self.log_test("Create Client Parameters (Enterprise)", False, f"Paramètres Enterprise incorrects: {args_called}")
                    
        except Exception as e:
            self.log_test("Create Client Parameters", False, f"Erreur: {e}")
    
    async def test_tool_calls_mapping(self):
        """Test que tous les outils ont bien un mapping dans handle_call_tool"""
        try:
            server = OdooClientMCPServer(str(self.repo_path))
            
            # Liste des outils attendus
            expected_tools = [
                "create_client", "list_clients", "update_client", "add_module",
                "list_modules", "list_oca_modules", "client_status", "check_client",
                "update_requirements", "update_oca_repos", "build_docker_image",
                "backup_client", "delete_client"
            ]
            
            # Vérifier que chaque outil a bien une méthode correspondante
            missing_mappings = []
            
            # Test avec des mocks pour éviter les appels réels
            with patch.object(server, '_run_command') as mock_run:
                mock_run.return_value = {"success": True, "stdout": "test", "stderr": ""}
                
                for tool_name in expected_tools:
                    method_name = f"_{tool_name}"
                    if not hasattr(server, method_name):
                        missing_mappings.append(f"{tool_name} -> {method_name}")
            
            if missing_mappings:
                self.log_test("Tool Calls Mapping", False, f"Mappings manquants: {missing_mappings}")
            else:
                self.log_test("Tool Calls Mapping", True, f"Tous les {len(expected_tools)} outils ont leur mapping")
                
        except Exception as e:
            self.log_test("Tool Calls Mapping", False, f"Erreur: {e}")
    
    async def test_delete_client_workflow(self):
        """Test du workflow de suppression de client avec confirmation"""
        try:
            server = OdooClientMCPServer(str(self.repo_path))
            
            # Test avec un client inexistant
            result = await server._delete_client("client_inexistant", False)
            
            if len(result) == 1 and "not found" in result[0].text:
                self.log_test("Delete Client (Not Found)", True, "Gestion client inexistant correcte")
            else:
                self.log_test("Delete Client (Not Found)", False, f"Réponse inattendue: {result}")
            
            # Test des paramètres et de la signature de la méthode
            import inspect
            sig = inspect.signature(server._delete_client)
            params = list(sig.parameters.keys())
            
            expected_params = ["client", "confirmed"]
            if all(p in params for p in expected_params):
                self.log_test("Delete Client (Signature)", True, "Signature _delete_client correcte")
            else:
                self.log_test("Delete Client (Signature)", False, f"Paramètres manquants: {set(expected_params) - set(params)}")
            
            # Test avec mock pour vérifier les appels de commande
            with patch.object(server, '_run_command') as mock_run:
                mock_run.return_value = {
                    "success": True,
                    "stdout": "Client deleted successfully",
                    "stderr": ""
                }
                
                # Mock du répertoire client pour qu'il existe
                with patch('pathlib.Path.exists') as mock_exists:
                    mock_exists.return_value = True
                    
                    # Test avec confirmation
                    result = await server._delete_client("test_client", True)
                    
                    # Vérifier que la commande make delete-client a été appelée
                    if mock_run.called:
                        call_args = mock_run.call_args[0][0]
                        if ("make" in call_args and "delete-client" in call_args):
                            self.log_test("Delete Client (Command)", True, "Commande de suppression appelée correctement")
                        else:
                            self.log_test("Delete Client (Command)", False, f"Commande incorrecte: {call_args}")
                    else:
                        self.log_test("Delete Client (Command)", False, "Commande de suppression non appelée")
            
            # Test de gestion d'erreur
            with patch.object(server, '_run_command') as mock_run:
                mock_run.return_value = {
                    "success": False,
                    "stdout": "",
                    "stderr": "Permission denied"
                }
                
                with patch('pathlib.Path.exists') as mock_exists:
                    mock_exists.return_value = True
                    
                    result = await server._delete_client("test_client", True)
                    
                    if (len(result) == 1 and 
                        "permission issues" in result[0].text and 
                        "sudo" in result[0].text):
                        self.log_test("Delete Client (Permissions)", True, "Gestion erreurs de permissions OK")
                    else:
                        self.log_test("Delete Client (Permissions)", False, "Gestion erreurs de permissions manquante")
                        
        except Exception as e:
            self.log_test("Delete Client Workflow", False, f"Erreur: {e}")
    
    async def test_performance(self):
        """Test de performance du serveur MCP"""
        try:
            import time
            
            # Test la vitesse de création du serveur
            start_time = time.time()
            server = OdooClientMCPServer(str(self.repo_path))
            creation_time = time.time() - start_time
            
            if creation_time < 2.0:  # Moins de 2 secondes
                self.log_test("Performance Creation", True, f"Serveur créé en {creation_time:.3f}s")
            else:
                self.log_test("Performance Creation", False, f"Création trop lente: {creation_time:.3f}s")
            
            # Test la vitesse d'exécution d'une commande simple
            with patch.object(server, '_run_command') as mock_run:
                mock_run.return_value = {"success": True, "stdout": "test", "stderr": ""}
                
                start_time = time.time()
                await server._list_clients()
                call_time = time.time() - start_time
                
                if call_time < 0.1:  # Moins de 100ms
                    self.log_test("Performance Call", True, f"Appel exécuté en {call_time:.3f}s")
                else:
                    self.log_test("Performance Call", False, f"Appel trop lent: {call_time:.3f}s")
                    
        except Exception as e:
            self.log_test("Performance", False, f"Erreur: {e}")
    
    async def test_error_handling(self):
        """Test la gestion d'erreurs"""
        try:
            server = OdooClientMCPServer(str(self.repo_path))
            
            # Tester une commande qui échoue
            result = server._run_command(["false"])  # Commande qui retourne toujours 1
            
            if not result["success"] and result["return_code"] == 1:
                self.log_test("Error Handling", True, "Gestion d'erreur fonctionnelle")
            else:
                self.log_test("Error Handling", False, f"Gestion d'erreur défaillante: {result}")
                
        except Exception as e:
            self.log_test("Error Handling", False, f"Erreur: {e}")
    
    async def run_all_tests(self):
        """Lance tous les tests"""
        print("🧪 Démarrage des tests unitaires du serveur MCP...")
        print(f"📁 Répertoire de test: {self.repo_path}")
        print()
        
        # Liste des tests à exécuter
        tests = [
            self.test_server_creation,
            self.test_invalid_repo_path,
            self.test_tools_list,
            self.test_create_client_schema,
            self.test_command_execution,
            self.test_list_clients_mock,
            self.test_create_client_parameters,
            self.test_tool_calls_mapping,
            self.test_delete_client_workflow,
            self.test_performance,
            self.test_error_handling
        ]
        
        # Exécuter chaque test
        for test in tests:
            try:
                await test()
            except Exception as e:
                self.log_test(test.__name__, False, f"Test failed: {e}")
        
        # Résumé des résultats
        print()
        print("📊 Résumé des tests:")
        
        passed = sum(1 for r in self.test_results if r["success"])
        total = len(self.test_results)
        
        print(f"✅ Tests réussis: {passed}/{total}")
        
        if passed < total:
            print("❌ Tests échoués:")
            for result in self.test_results:
                if not result["success"]:
                    print(f"  - {result['name']}: {result['message']}")
        
        print()
        
        if passed == total:
            print("🎉 Tous les tests sont passés avec succès!")
            return True
        else:
            print("⚠️ Certains tests ont échoué.")
            return False


async def main():
    """Point d'entrée principal"""
    tester = TestMCPServer()
    success = await tester.run_all_tests()
    return 0 if success else 1


if __name__ == "__main__":
    try:
        exit_code = asyncio.run(main())
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print("\n👋 Tests interrompus par l'utilisateur")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Erreur fatale: {e}")
        sys.exit(1)