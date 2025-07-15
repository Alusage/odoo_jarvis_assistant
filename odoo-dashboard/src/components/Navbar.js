import { Component, useState, onMounted, xml } from "@odoo/owl";
import { dataService } from "../services/dataService.js";

export class Navbar extends Component {
  static template = xml`
    <nav class="fixed top-0 left-0 right-0 bg-white border-b border-gray-200 shadow-sm z-50">
      <div class="px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16">
          <!-- Left side -->
          <div class="flex items-center space-x-4">
            <!-- Logo -->
            <div class="flex items-center space-x-3">
              <div class="w-8 h-8 bg-primary-500 rounded-lg flex items-center justify-center">
                <svg class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M3 4a1 1 0 011-1h12a1 1 0 011 1v2a1 1 0 01-1 1H4a1 1 0 01-1-1V4zM3 10a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H4a1 1 0 01-1-1v-6zM14 9a1 1 0 00-1 1v6a1 1 0 001 1h2a1 1 0 001-1v-6a1 1 0 00-1-1h-2z"/>
                </svg>
              </div>
              <span class="text-xl font-bold text-gray-900">Odoo Dashboard</span>
            </div>

            <!-- Client Selector and Create Button -->
            <div class="flex items-center space-x-3">
              <div class="relative">
                <button 
                  class="flex items-center space-x-2 px-3 py-1.5 text-sm font-medium text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
                  t-on-click="toggleClientDropdown"
                >
                  <span t-esc="props.currentClient || 'Select Client'"/>
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
                  </svg>
                </button>
                
                <div t-if="state.clientDropdownOpen" class="absolute top-full left-0 mt-1 w-48 bg-white border border-gray-200 rounded-lg shadow-lg z-10">
                  <button 
                    t-foreach="state.clients" 
                    t-as="client" 
                    t-key="client"
                    class="block w-full px-4 py-2 text-left text-sm text-gray-700 hover:bg-gray-50"
                    t-on-click="() => this.selectClient(client)"
                  >
                    <t t-esc="client"/>
                  </button>
                </div>
              </div>
              
              <!-- Create Client Button -->
              <button 
                class="flex items-center space-x-2 px-3 py-1.5 text-sm font-medium text-white bg-primary-500 rounded-lg hover:bg-primary-600 transition-colors"
                t-on-click="openCreateClientModal"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                </svg>
                <span>New Client</span>
              </button>
            </div>
          </div>

          <!-- Right side -->
          <div class="flex items-center space-x-4">
            <!-- User Menu -->
            <div class="relative">
              <button 
                class="flex items-center space-x-2 p-1.5 rounded-lg hover:bg-gray-100 transition-colors"
                t-on-click="toggleUserDropdown"
              >
                <img class="w-8 h-8 rounded-full" t-att-src="props.user.avatar" t-att-alt="props.user.name"/>
                <svg class="w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
                </svg>
              </button>
              
              <div t-if="state.userDropdownOpen" class="absolute top-full right-0 mt-1 w-48 bg-white border border-gray-200 rounded-lg shadow-lg z-10">
                <a href="#" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50">Profile</a>
                <button 
                  class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50"
                  t-on-click="openSettings"
                >
                  Settings
                </button>
                <hr class="my-1"/>
                <a href="#" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50">Sign out</a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </nav>
  `;

  setup() {
    this.state = useState({
      activeNav: 'branches',
      clientDropdownOpen: false,
      userDropdownOpen: false,
      mobileMenuOpen: false,
      clients: []
    });

    onMounted(async () => {
      await this.loadClients();
    });
  }

  async loadClients() {
    try {
      // Récupérer la liste unique des noms de clients pour la dropdown
      this.state.clients = await dataService.getUniqueClientNames();
      console.log('Clients loaded in Navbar:', this.state.clients);
    } catch (error) {
      console.error('Error loading clients:', error);
      // Fallback avec des clients par défaut
      this.state.clients = ['bousbotsbar', 'sudokeys', 'testclient'];
    }
  }

  setActiveNav(navItem) {
    this.state.activeNav = navItem;
  }

  toggleClientDropdown() {
    this.state.clientDropdownOpen = !this.state.clientDropdownOpen;
    this.state.userDropdownOpen = false;
  }

  toggleUserDropdown() {
    this.state.userDropdownOpen = !this.state.userDropdownOpen;
    this.state.clientDropdownOpen = false;
  }

  selectClient(client) {
    this.props.onClientChange(client);
    this.state.clientDropdownOpen = false;
  }

  toggleMobileMenu() {
    this.state.mobileMenuOpen = !this.state.mobileMenuOpen;
  }

  closeMobileMenu() {
    this.state.mobileMenuOpen = false;
  }

  openSettings() {
    this.state.userDropdownOpen = false;
    if (this.props.onSettingsClick) {
      this.props.onSettingsClick();
    }
  }

  openCreateClientModal() {
    this.state.clientDropdownOpen = false;
    if (this.props.onCreateClientClick) {
      this.props.onCreateClientClick();
    }
  }

  // Public method to refresh clients list
  async refreshClients() {
    await this.loadClients();
  }
}