import { Component, useState, onMounted, xml } from "@odoo/owl";
import { Navbar } from "./Navbar.js";
import { Sidebar } from "./Sidebar.js";
import { Dashboard } from "./Dashboard.js";
import { Settings } from "./Settings.js";
import { CreateClientModal } from "./CreateClientModal.js";
import { dataService } from "../services/dataService.js";

export class App extends Component {
  static template = xml`
    <div class="h-screen flex flex-col bg-gray-50">
      <!-- Top Navigation -->
      <Navbar 
        currentClient="state.selectedClient"
        user="state.user"
        onClientChange="(client) => this.onClientChange(client)"
        onSettingsClick="() => this.openSettings()"
        onCreateClientClick="() => this.openCreateClientModal()"
        onNavbarReady="(navbarComponent) => this.setNavbarRef(navbarComponent)"
      />
      
      <!-- Main Layout -->
      <div class="flex h-screen pt-16">
        <!-- Sidebar -->
        <Sidebar 
          clients="state.clients"
          selectedClient="state.selectedClient"
          sidebarCollapsed="state.sidebarCollapsed"
          onClientSelect="(client) => this.onClientSelect(client)"
          onToggleSidebar="() => this.onToggleSidebar()"
        />
        
        <!-- Main Content -->
        <main class="flex-1 overflow-hidden">
          <div t-if="state.selectedClientData" class="h-full">
            <Dashboard 
              client="state.selectedClientData"
              currentTab="state.currentTab"
              onTabChange="(tab) => this.onTabChange(tab)"
              onClientCreated="() => this.loadClients()"
            />
          </div>
          
          <!-- Welcome Screen -->
          <div t-else="" class="h-full flex items-center justify-center">
            <div class="text-center">
              <div class="w-24 h-24 mx-auto mb-6 bg-primary-100 rounded-full flex items-center justify-center">
                <svg class="w-12 h-12 text-primary-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
                </svg>
              </div>
              <h2 class="text-2xl font-bold text-gray-900 mb-2">Welcome to Odoo Dashboard</h2>
              <p class="text-gray-600 max-w-md">Select a client from the sidebar to view detailed information, manage builds, and monitor your Odoo instances.</p>
            </div>
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
  
  static components = { Navbar, Sidebar, Dashboard, Settings, CreateClientModal };

  setup() {
    this.navbarRef = null;
    this.state = useState({
      currentProject: 'odoo-alusage',
      user: {
        name: 'Admin User',
        avatar: 'https://ui-avatars.com/api/?name=Admin&background=7D6CA8&color=fff',
        email: 'admin@odoo-alusage.com'
      },
      clients: [],
      selectedClient: null,
      selectedClientData: null,
      sidebarCollapsed: false,
      currentTab: 'HISTORY',
      loading: true,
      settingsOpen: false,
      createClientModalOpen: false
    });

    onMounted(async () => {
      await this.loadClients();
    });
  }

  async loadClients() {
    try {
      this.state.loading = true;
      const clients = await dataService.getClients();
      this.state.clients = clients;
      
      // Rafraîchir aussi la liste des clients dans le Navbar
      if (this.navbarRef && this.navbarRef.refreshClients) {
        await this.navbarRef.refreshClients();
      }
      
      // Ne pas sélectionner automatiquement un client
      // L'utilisateur devra choisir depuis la dropdown
    } catch (error) {
      console.error('Error loading clients:', error);
    } finally {
      this.state.loading = false;
    }
  }

  async onClientSelect(clientName) {
    try {
      this.state.selectedClient = clientName;
      
      // Si c'est un nom de client de base (sans environnement), 
      // essayer de trouver la version production par défaut
      let targetClientName = clientName;
      if (!clientName.includes('-')) {
        // C'est un nom de base, essayer de trouver la version production
        const allClients = await dataService.getClients();
        const prodClient = allClients.find(c => 
          c.name === clientName && c.environment === 'production'
        );
        if (prodClient) {
          targetClientName = prodClient.name;
        }
      }
      
      this.state.selectedClientData = await dataService.getClient(targetClientName);
    } catch (error) {
      console.error(`Error selecting client ${clientName}:`, error);
      // Fallback: essayer de trouver n'importe quel client avec ce nom
      try {
        const allClients = await dataService.getClients();
        const fallbackClient = allClients.find(c => c.name.startsWith(clientName));
        if (fallbackClient) {
          this.state.selectedClientData = fallbackClient;
        }
      } catch (fallbackError) {
        console.error(`Fallback failed for client ${clientName}:`, fallbackError);
      }
    }
  }

  onClientChange(clientName) {
    this.onClientSelect(clientName);
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
}