import { Component, useState, onMounted, xml } from "@odoo/owl";
import { Navbar } from "./Navbar.js";
import { Sidebar } from "./Sidebar.js";
import { Dashboard } from "./Dashboard.js";
import { Settings } from "./Settings.js";
import { CreateClientModal } from "./CreateClientModal.js";
import { ClientsOverview } from "./ClientsOverview.js";
import { dataService } from "../services/dataService.js";

export class App extends Component {
  static template = xml`
    <div class="h-screen flex flex-col bg-gray-50">
      <!-- Top Navigation -->
      <Navbar 
        currentClient="state.selectedBaseClient"
        user="state.user"
        onClientChange="(client) => this.onClientChange(client)"
        onSettingsClick="() => this.openSettings()"
        onCreateClientClick="() => this.openCreateClientModal()"
        onNavbarReady="(navbarComponent) => this.setNavbarRef(navbarComponent)"
      />
      
      <!-- MCP Server Error Banner -->
      <div t-if="state.mcpServerError" class="fixed top-16 left-0 right-0 bg-red-500 text-white px-4 py-2 z-50">
        <div class="flex items-center justify-between max-w-7xl mx-auto">
          <div class="flex items-center space-x-2">
            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
            </svg>
            <span class="font-medium">MCP Server Error:</span>
            <span t-esc="state.mcpServerError"/>
          </div>
          <button class="text-white hover:text-gray-200" t-on-click="() => this.loadClients()">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
            </svg>
          </button>
        </div>
      </div>

      <!-- Main Layout -->
      <div class="flex flex-1 overflow-hidden">
        <!-- Sidebar (only when client is selected) -->
        <Sidebar 
          t-if="state.selectedClientData"
          clients="state.clients"
          selectedBaseClient="state.selectedBaseClient"
          selectedClient="state.selectedClient"
          selectedBranch="state.selectedBranch"
          sidebarCollapsed="state.sidebarCollapsed"
          onClientSelect="(client) => this.onClientSelect(client)"
          onToggleSidebar="() => this.onToggleSidebar()"
          onRefreshClients="() => this.loadClients()"
          onSidebarReady="(sidebarComponent) => this.setSidebarRef(sidebarComponent)"
        />
        
        <!-- Main Content -->
        <main class="flex-1 overflow-hidden pt-16" t-att-style="state.mcpServerError ? 'margin-top: 48px;' : ''">
          <div t-if="state.selectedClientData" class="h-full">
            <Dashboard 
              client="state.selectedClientData"
              currentTab="state.currentTab"
              onTabChange="(tab) => this.onTabChange(tab)"
              onClientCreated="() => this.loadClients()"
              onDockerStatusChange="() => this.refreshDockerStatuses()"
            />
          </div>
          
          <!-- Clients Overview (No client selected) -->
          <div t-else="" class="h-full">
            <ClientsOverview 
              onClientSelect="(client) => this.onClientSelect(client)"
              refreshKey="state.clientsRefreshKey"
            />
          </div>
        </main>
      </div>
      
      <!-- Loading Overlay -->
      <div t-if="state.loading" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div class="bg-white rounded-lg p-6 max-w-sm w-full mx-4">
          <div class="flex items-center space-x-3">
            <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-primary-500"></div>
            <span class="text-gray-700">Loading...</span>
          </div>
        </div>
      </div>
      
      <!-- Settings Modal -->
      <Settings 
        isOpen="state.settingsOpen"
        onClose="() => this.closeSettings()"
      />
      
      <!-- Create Client Modal -->
      <CreateClientModal 
        isOpen="state.createClientModalOpen"
        onClose="() => this.closeCreateClientModal()"
        onClientCreated="() => this.loadClients()"
      />
    </div>
  `;
  
  static components = { Navbar, Sidebar, Dashboard, Settings, CreateClientModal, ClientsOverview };

  setup() {
    this.navbarRef = null;
    this.sidebarRef = null;
    this.state = useState({
      currentProject: 'odoo-alusage',
      user: {
        name: 'Admin User',
        avatar: 'https://ui-avatars.com/api/?name=Admin&background=7D6CA8&color=fff',
        email: 'admin@odoo-alusage.com'
      },
      clients: [],
      selectedBaseClient: null, // Le nom du client de base (pour le dropdown)
      selectedClient: null, // Le nom complet du client actuel (avec branche)
      selectedClientData: null,
      selectedBranch: null, // La branche actuellement sélectionnée
      sidebarCollapsed: false,
      currentTab: 'HISTORY',
      loading: true,
      settingsOpen: false,
      createClientModalOpen: false,
      mcpServerError: null,
      clientsRefreshKey: 0
    });

    onMounted(async () => {
      await this.loadClients();
    });
  }

  async loadClients() {
    try {
      this.state.loading = true;
      this.state.mcpServerError = null;
      
      const clients = await dataService.getClients();
      this.state.clients = clients;
      
      // Vérifier le statut du serveur MCP
      const mcpStatus = dataService.getMCPStatus();
      if (mcpStatus.status === 'error') {
        this.state.mcpServerError = mcpStatus.error;
      }
      
      // Rafraîchir aussi la liste des clients dans le Navbar
      if (this.navbarRef && this.navbarRef.refreshClients) {
        await this.navbarRef.refreshClients();
      }
      
      // Auto-select the Git current branch for existing clients
      if (this.state.selectedBaseClient && clients.length > 0) {
        this.autoSelectGitCurrentBranch(clients);
      }
      
      // Increment refresh key to trigger ClientsOverview reload
      this.state.clientsRefreshKey++;
    } catch (error) {
      console.error('Error loading clients:', error);
      const mcpStatus = dataService.getMCPStatus();
      this.state.mcpServerError = mcpStatus.error || error.message;
    } finally {
      this.state.loading = false;
    }
  }

  async onClientSelect(clientInput) {
    try {
      // Handle both string and object inputs
      let clientName, clientData;
      if (typeof clientInput === 'string') {
        clientName = clientInput;
        clientData = null;
      } else if (typeof clientInput === 'object' && clientInput.name) {
        clientName = clientInput.name;
        clientData = clientInput;
      } else {
        console.error('Invalid client input:', clientInput);
        return;
      }

      this.state.selectedClient = clientName;
      
      // Extraire le nom de base du client et la branche
      let baseClientName;
      let branchName = null;
      
      // Si le nom contient des tirets, c'est probablement un nom avec branche
      if (clientName.includes('-')) {
        const parts = clientName.split('-');
        baseClientName = parts[0];
        branchName = parts.slice(1).join('-');
      } else {
        baseClientName = clientName;
      }
      
      // Si on a déjà les données du client, les utiliser directement
      if (clientData) {
        this.state.selectedClientData = clientData;
        this.state.selectedBaseClient = baseClientName;
        this.state.selectedBranch = clientData.branch || branchName;
        
        // Pour ClientsOverview, on doit construire le nom complet du client
        // car clientData.name est le nom de base mais on veut sélectionner la branche courante
        if (clientData.branch && clientData.branch !== '18.0' && clientData.branch !== 'master') {
          const fullClientName = `${baseClientName}-${clientData.branch}`;
          this.state.selectedClient = fullClientName;
          console.log(`Updated selectedClient to full name: ${fullClientName}`);
        }
        return;
      }
      
      // Mettre à jour les états séparément
      this.state.selectedBaseClient = baseClientName;
      this.state.selectedBranch = branchName;
      
      // Si c'est juste un nom de client de base (sans branche spécifique), 
      // essayer de trouver la branche Git courante en priorité
      let targetClientName = clientName;
      if (!branchName) {
        // C'est un nom de base, essayer de trouver la branche Git courante
        const allClients = await dataService.getClients();
        
        // Priorité 1: Branche Git courante
        const gitCurrentClient = allClients.find(c => 
          c.name.startsWith(baseClientName) && c.isGitCurrent
        );
        
        if (gitCurrentClient) {
          targetClientName = gitCurrentClient.name;
          this.state.selectedClient = targetClientName;
          this.state.selectedBranch = gitCurrentClient.branch;
          console.log(`Selected Git current branch: ${gitCurrentClient.branch}`);
        } else {
          // Fallback: version production par défaut
          const prodClient = allClients.find(c => 
            c.name === baseClientName && c.environment === 'production'
          );
          if (prodClient) {
            targetClientName = prodClient.name;
            this.state.selectedClient = targetClientName;
            this.state.selectedBranch = prodClient.branch;
          }
        }
      }
      
      this.state.selectedClientData = await dataService.getClient(targetClientName);
    } catch (error) {
      console.error(`Error selecting client ${clientInput}:`, error);
      // Fallback: essayer de trouver n'importe quel client avec ce nom
      try {
        const clientName = typeof clientInput === 'string' ? clientInput : clientInput.name;
        const allClients = await dataService.getClients();
        const fallbackClient = allClients.find(c => c.name.startsWith(clientName.split('-')[0]));
        if (fallbackClient) {
          this.state.selectedClientData = fallbackClient;
          this.state.selectedBaseClient = fallbackClient.name.split('-')[0];
          this.state.selectedBranch = fallbackClient.branch;
        }
      } catch (fallbackError) {
        console.error(`Fallback failed for client ${clientInput}:`, fallbackError);
      }
    }
  }

  onClientChange(clientName) {
    this.onClientSelect(clientName);
  }

  autoSelectGitCurrentBranch(clients) {
    if (!this.state.selectedBaseClient) return;
    
    // Find the Git current branch for the selected base client
    const gitCurrentClient = clients.find(client => {
      return client.name.startsWith(this.state.selectedBaseClient) && client.isGitCurrent;
    });
    
    if (gitCurrentClient) {
      console.log(`Auto-selecting Git current branch: ${gitCurrentClient.name} (${gitCurrentClient.branch})`);
      this.onClientSelect(gitCurrentClient.name);
    }
  }

  onToggleSidebar() {
    this.state.sidebarCollapsed = !this.state.sidebarCollapsed;
  }

  onTabChange(tabName) {
    this.state.currentTab = tabName;
  }

  openSettings() {
    this.state.settingsOpen = true;
  }

  closeSettings() {
    this.state.settingsOpen = false;
  }

  openCreateClientModal() {
    this.state.createClientModalOpen = true;
  }

  closeCreateClientModal() {
    this.state.createClientModalOpen = false;
  }

  setNavbarRef(navbarComponent) {
    this.navbarRef = navbarComponent;
  }

  setSidebarRef(sidebarComponent) {
    this.sidebarRef = sidebarComponent;
  }

  async refreshDockerStatuses() {
    if (this.sidebarRef && this.sidebarRef.refreshDockerStatuses) {
      await this.sidebarRef.refreshDockerStatuses();
    }
  }
}