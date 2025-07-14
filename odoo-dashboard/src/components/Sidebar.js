import { Component, useState, xml } from "@odoo/owl";

export class Sidebar extends Component {
  static template = xml`
    <div class="sidebar-transition" t-att-class="props.sidebarCollapsed ? 'w-16' : 'w-64'">
      <div class="h-full bg-white border-r border-gray-200 shadow-sm">
        <!-- Toggle Button -->
        <div class="flex items-center justify-between p-4 border-b border-gray-200">
          <div t-if="!props.sidebarCollapsed" class="flex items-center space-x-2">
            <div class="w-8 h-8 bg-primary-500 rounded-lg flex items-center justify-center">
              <svg class="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20">
                <path d="M9 2a1 1 0 000 2h2a1 1 0 100-2H9z"/>
                <path fill-rule="evenodd" d="M4 5a2 2 0 012-2v1a1 1 0 001 1h6a1 1 0 001-1V3a2 2 0 012 2v6a2 2 0 01-2 2H6a2 2 0 01-2-2V5zm3 2a1 1 0 000 2h.01a1 1 0 100-2H7zm3 0a1 1 0 000 2h3a1 1 0 100-2h-3zm-3 4a1 1 0 100 2h.01a1 1 0 100-2H7zm3 0a1 1 0 100 2h3a1 1 0 100-2h-3z"/>
              </svg>
            </div>
            <span class="font-semibold text-gray-900">Clients</span>
          </div>
          <button 
            class="p-1.5 rounded-lg hover:bg-gray-100 transition-colors"
            t-on-click="props.onToggleSidebar"
          >
            <svg class="w-4 h-4 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 19l-7-7 7-7m8 14l-7-7 7-7"/>
            </svg>
          </button>
        </div>

        <!-- Filter Input -->
        <div t-if="!props.sidebarCollapsed" class="p-4 border-b border-gray-200">
          <input 
            type="text" 
            placeholder="Filter clients..."
            class="input w-full"
            t-model="state.filter"
          />
        </div>

        <!-- Client List -->
        <div class="overflow-y-auto h-full pb-20">
          <!-- Production Section -->
          <div class="p-2">
            <div 
              class="flex items-center justify-between p-2 text-sm font-medium text-gray-700 hover:bg-gray-50 rounded-lg cursor-pointer"
              t-on-click="() => this.toggleSection('production')"
            >
              <div class="flex items-center space-x-2">
                <span class="status-success"/>
                <span t-if="!props.sidebarCollapsed">PRODUCTION</span>
              </div>
              <svg 
                t-if="!props.sidebarCollapsed"
                class="w-4 h-4 transition-transform" 
                t-att-class="state.expandedSections.production ? 'rotate-90' : ''"
                fill="none" stroke="currentColor" viewBox="0 0 24 24"
              >
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
              </svg>
            </div>
            
            <div t-if="state.expandedSections.production || props.sidebarCollapsed" class="ml-4 mt-1 space-y-1">
              <t t-foreach="productionClients" t-as="client" t-key="client.name">
                <button 
                  class="client-item"
                  t-att-class="getClientItemClass(client)"
                  t-on-click="() => this.selectClient(client.name)"
                >
                  <div class="flex items-center space-x-3">
                    <span t-att-class="getStatusClass(client.status)"/>
                    <div t-if="!props.sidebarCollapsed" class="flex-1 text-left">
                      <div class="font-medium text-gray-900" t-esc="client.displayName"/>
                      <div class="text-xs text-gray-500" t-esc="client.lastActivity"/>
                    </div>
                  </div>
                </button>
              </t>
            </div>
          </div>

          <!-- Staging Section -->
          <div class="p-2">
            <div 
              class="flex items-center justify-between p-2 text-sm font-medium text-gray-700 hover:bg-gray-50 rounded-lg cursor-pointer"
              t-on-click="() => this.toggleSection('staging')"
            >
              <div class="flex items-center space-x-2">
                <span class="status-warning"/>
                <span t-if="!props.sidebarCollapsed">STAGING</span>
              </div>
              <svg 
                t-if="!props.sidebarCollapsed"
                class="w-4 h-4 transition-transform" 
                t-att-class="state.expandedSections.staging ? 'rotate-90' : ''"
                fill="none" stroke="currentColor" viewBox="0 0 24 24"
              >
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
              </svg>
            </div>
            
            <div t-if="state.expandedSections.staging || props.sidebarCollapsed" class="ml-4 mt-1 space-y-1">
              <t t-foreach="stagingClients" t-as="client" t-key="client.name">
                <button 
                  class="client-item"
                  t-att-class="getClientItemClass(client)"
                  t-on-click="() => this.selectClient(client.name)"
                >
                  <div class="flex items-center space-x-3">
                    <span t-att-class="getStatusClass(client.status)"/>
                    <div t-if="!props.sidebarCollapsed" class="flex-1 text-left">
                      <div class="font-medium text-gray-900" t-esc="client.displayName"/>
                      <div class="text-xs text-gray-500" t-esc="client.lastActivity"/>
                    </div>
                  </div>
                </button>
              </t>
            </div>
          </div>

          <!-- Development Section -->
          <div class="p-2">
            <div 
              class="flex items-center justify-between p-2 text-sm font-medium text-gray-700 hover:bg-gray-50 rounded-lg cursor-pointer"
              t-on-click="() => this.toggleSection('development')"
            >
              <div class="flex items-center space-x-2">
                <span class="status-info"/>
                <span t-if="!props.sidebarCollapsed">DEVELOPMENT</span>
              </div>
              <svg 
                t-if="!props.sidebarCollapsed"
                class="w-4 h-4 transition-transform" 
                t-att-class="state.expandedSections.development ? 'rotate-90' : ''"
                fill="none" stroke="currentColor" viewBox="0 0 24 24"
              >
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
              </svg>
            </div>
            
            <div t-if="state.expandedSections.development || props.sidebarCollapsed" class="ml-4 mt-1 space-y-1">
              <t t-foreach="developmentClients" t-as="client" t-key="client.name">
                <button 
                  class="client-item"
                  t-att-class="getClientItemClass(client)"
                  t-on-click="() => this.selectClient(client.name)"
                >
                  <div class="flex items-center space-x-3">
                    <span t-att-class="getStatusClass(client.status)"/>
                    <div t-if="!props.sidebarCollapsed" class="flex-1 text-left">
                      <div class="font-medium text-gray-900" t-esc="client.displayName"/>
                      <div class="text-xs text-gray-500" t-esc="client.lastActivity"/>
                    </div>
                  </div>
                </button>
              </t>
            </div>
          </div>
        </div>
      </div>
    </div>
  `;

  setup() {
    this.state = useState({
      filter: '',
      expandedSections: {
        production: true,
        staging: false,
        development: true
      }
    });
  }

  get filteredClients() {
    if (!this.props.clients) return [];
    
    const filter = this.state.filter.toLowerCase();
    return this.props.clients.filter(client => 
      client.name.toLowerCase().includes(filter) || 
      client.displayName.toLowerCase().includes(filter)
    );
  }

  get productionClients() {
    if (this.props.selectedClient) {
      // Si un client est sélectionné, afficher seulement ses environnements
      const selectedClientName = this.props.selectedClient;
      return this.filteredClients.filter(client => 
        client.name.startsWith(selectedClientName) && 
        (client.environment === 'production' || client.name.includes('-prod'))
      );
    }
    return this.filteredClients.filter(client => client.environment === 'production');
  }

  get stagingClients() {
    if (this.props.selectedClient) {
      // Si un client est sélectionné, afficher seulement ses environnements
      const selectedClientName = this.props.selectedClient;
      return this.filteredClients.filter(client => 
        client.name.startsWith(selectedClientName) && 
        (client.environment === 'staging' || client.name.includes('-staging'))
      );
    }
    return this.filteredClients.filter(client => client.environment === 'staging');
  }

  get developmentClients() {
    if (this.props.selectedClient) {
      // Si un client est sélectionné, afficher seulement ses environnements
      const selectedClientName = this.props.selectedClient;
      return this.filteredClients.filter(client => 
        client.name.startsWith(selectedClientName) && 
        (client.environment === 'development' || client.name.includes('-dev'))
      );
    }
    return this.filteredClients.filter(client => client.environment === 'development');
  }

  toggleSection(section) {
    this.state.expandedSections[section] = !this.state.expandedSections[section];
  }

  selectClient(clientName) {
    this.props.onClientSelect(clientName);
  }

  filterClients() {
    // Filter is already reactive through t-model
  }

  getClientItemClass(client) {
    const baseClass = 'client-item';
    const selectedClass = this.props.selectedClient === client.name ? 'selected' : '';
    return `${baseClass} ${selectedClass}`.trim();
  }

  getStatusClass(status) {
    const statusClasses = {
      'healthy': 'status-success',
      'warning': 'status-warning',
      'error': 'status-error',
      'critical': 'status-error'
    };
    return statusClasses[status] || 'status-info';
  }
}