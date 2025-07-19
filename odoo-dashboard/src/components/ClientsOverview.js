import { Component, useState, onMounted, xml } from "@odoo/owl";
import { dataService } from "../services/dataService.js";

export class ClientsOverview extends Component {
  static template = xml`
    <div class="min-h-full bg-gray-50">
      <!-- Header -->
      <div class="bg-white shadow-sm border-b border-gray-200">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="py-6">
            <h1 class="text-3xl font-bold tracking-tight text-gray-900">Odoo Clients</h1>
            <p class="mt-2 text-sm text-gray-600">Manage your Odoo client environments</p>
          </div>
        </div>
      </div>

      <!-- Content -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Loading State -->
        <div t-if="state.loading" class="flex items-center justify-center py-16">
          <div class="flex items-center space-x-3">
            <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-600"></div>
            <span class="text-lg text-gray-600">Loading clients...</span>
          </div>
        </div>

        <!-- Error State -->
        <div t-if="state.error" class="rounded-lg bg-red-50 border border-red-200 p-6 text-center">
          <svg class="w-12 h-12 text-red-400 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"/>
          </svg>
          <h3 class="text-lg font-medium text-red-800 mb-2">Error loading clients</h3>
          <p class="text-red-600 mb-4" t-esc="state.error"/>
          <button class="btn-primary" t-on-click="loadClients">
            Try Again
          </button>
        </div>

        <!-- Empty State -->
        <div t-if="!state.loading &amp;&amp; !state.error &amp;&amp; state.clients.length === 0" class="text-center py-16">
          <svg class="w-24 h-24 text-gray-300 mx-auto mb-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"/>
          </svg>
          <h3 class="text-xl font-medium text-gray-900 mb-2">No clients found</h3>
          <p class="text-gray-500 mb-6">Get started by creating your first Odoo client</p>
          <button class="btn-primary">
            <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
            </svg>
            Create Client
          </button>
        </div>

        <!-- Clients Grid -->
        <div t-if="!state.loading &amp;&amp; !state.error &amp;&amp; state.clients.length > 0" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          <div t-foreach="state.clients" t-as="client" t-key="client.name" class="relative">
            <!-- Client Card -->
            <div class="bg-white rounded-lg shadow-sm border border-gray-200 hover:shadow-md transition-shadow duration-200 cursor-pointer"
                 t-on-click="() => this.selectClient(client)">
              
              <!-- Card Header -->
              <div class="p-6 pb-4">
                <div class="flex items-start justify-between mb-3">
                  <h3 class="text-lg font-semibold text-gray-900 truncate" t-esc="client.name"/>
                  <div class="flex items-center space-x-2 ml-3">
                    <!-- Docker Status Badge -->
                    <div t-if="client.dockerStatus === 'running'" 
                         class="flex items-center px-2 py-1 text-xs font-medium bg-green-100 text-green-800 rounded-full">
                      <div class="w-2 h-2 bg-green-500 rounded-full mr-1"></div>
                      Running
                    </div>
                    <div t-elif="client.dockerStatus === 'stopped'" 
                         class="flex items-center px-2 py-1 text-xs font-medium bg-red-100 text-red-800 rounded-full">
                      <div class="w-2 h-2 bg-red-500 rounded-full mr-1"></div>
                      Stopped
                    </div>
                    <div t-else=""
                         class="flex items-center px-2 py-1 text-xs font-medium bg-gray-100 text-gray-600 rounded-full">
                      <div class="w-2 h-2 bg-gray-500 rounded-full mr-1"></div>
                      Unknown
                    </div>
                  </div>
                </div>

                <!-- Client Info -->
                <div class="space-y-2">
                  <!-- Odoo Version -->
                  <div class="flex items-center text-sm text-gray-600">
                    <svg class="w-4 h-4 mr-2 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"/>
                    </svg>
                    <span class="font-medium">Odoo</span>
                    <span class="ml-1 px-2 py-0.5 text-xs bg-blue-100 text-blue-800 rounded" t-esc="client.odooVersion || '18.0'"/>
                  </div>

                  <!-- Current Branch -->
                  <div class="flex items-center text-sm text-gray-600">
                    <svg class="w-4 h-4 mr-2 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"/>
                    </svg>
                    <span class="font-medium">Branch</span>
                    <span class="ml-1 px-2 py-0.5 text-xs bg-gray-100 text-gray-700 rounded font-mono" t-esc="client.currentBranch || 'main'"/>
                  </div>

                  <!-- Last Updated -->
                  <div t-if="client.lastUpdated" class="flex items-center text-sm text-gray-500">
                    <svg class="w-4 h-4 mr-2 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                    </svg>
                    <span t-esc="getRelativeTime(client.lastUpdated)"/>
                  </div>
                </div>
              </div>

              <!-- Card Actions -->
              <div class="px-6 py-4 bg-gray-50 border-t border-gray-100 rounded-b-lg">
                <div class="flex items-center justify-between">
                  <!-- Start Docker Button -->
                  <button t-if="client.dockerStatus === 'stopped'" 
                          class="flex items-center px-3 py-2 text-sm font-medium text-white bg-green-600 hover:bg-green-700 rounded-md transition-colors duration-150"
                          t-on-click.stop="(ev) => this.startDocker(client, ev)">
                    <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.828 14.828a4 4 0 01-5.656 0M9 10h1m4 0h1m-6 4h8m2-10v.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                    </svg>
                    Start Docker
                  </button>
                  
                  <!-- View Button -->
                  <button t-if="client.dockerStatus === 'running'" 
                          class="flex items-center px-3 py-2 text-sm font-medium text-primary-600 bg-primary-50 hover:bg-primary-100 rounded-md transition-colors duration-150"
                          t-on-click.stop="(ev) => this.openClient(client, ev)">
                    <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/>
                    </svg>
                    Open
                  </button>

                  <!-- Select Button -->
                  <button class="flex items-center px-3 py-2 text-sm font-medium text-gray-600 hover:text-gray-800 transition-colors duration-150">
                    <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
                    </svg>
                    Select
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  `;

  setup() {
    this.state = useState({
      clients: [],
      loading: true,
      error: null
    });

    onMounted(() => {
      this.loadClients();
    });
  }

  async loadClients() {
    this.state.loading = true;
    this.state.error = null;

    try {
      const clients = await dataService.getClientsOverview();
      
      // Enrich client data with additional info
      const enrichedClients = await Promise.all(
        clients.map(async (client) => {
          try {
            // Get Docker status
            const dockerStatus = await this.getDockerStatus(client.name);
            
            // Get current branch
            const gitStatus = await dataService.getClientGitStatus(client.name);
            const currentBranch = gitStatus?.current_branch || 'main';
            
            // Get Odoo version from config or default
            const odooVersion = client.odoo_version || '18.0';
            
            return {
              ...client,
              dockerStatus,
              currentBranch,
              odooVersion,
              lastUpdated: new Date().toISOString() // TODO: Get real last updated time
            };
          } catch (error) {
            console.warn(`Failed to enrich client ${client.name}:`, error);
            return {
              ...client,
              dockerStatus: 'unknown',
              currentBranch: 'main',
              odooVersion: '18.0',
              lastUpdated: null
            };
          }
        })
      );

      this.state.clients = enrichedClients;
    } catch (error) {
      console.error('Error loading clients:', error);
      this.state.error = error.message || 'Failed to load clients';
    } finally {
      this.state.loading = false;
    }
  }

  async getDockerStatus(clientName) {
    try {
      // Try to get the default branch status first
      const response = await fetch('http://mcp.localhost/tools/call', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: 'get_client_status',
          arguments: {
            client: clientName
          }
        })
      });

      const result = await response.json();
      if (result.success && result.content) {
        // Parse the status response
        const status = result.content.status || 'unknown';
        return status === 'running' ? 'running' : 'stopped';
      }
      
      return 'unknown';
    } catch (error) {
      console.error(`Error getting Docker status for ${clientName}:`, error);
      return 'unknown';
    }
  }

  selectClient(client) {
    if (this.props.onClientSelect) {
      this.props.onClientSelect(client);
    }
  }

  async startDocker(client, event) {
    event?.stopPropagation();
    
    try {
      console.log(`Starting Docker for client: ${client.name}`);
      
      const response = await fetch('http://mcp.localhost/tools/call', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: 'start_client',
          arguments: {
            client: client.name
          }
        })
      });

      const result = await response.json();
      if (result.success) {
        console.log(`✅ Docker started successfully for ${client.name}`);
        // Refresh the client data to show updated status
        await this.loadClients();
      } else {
        console.error(`❌ Failed to start Docker for ${client.name}:`, result.error);
        // TODO: Show error notification to user
      }
    } catch (error) {
      console.error(`Error starting Docker for ${client.name}:`, error);
      // TODO: Show error notification to user
    }
  }

  async openClient(client, event) {
    event?.stopPropagation();
    
    // Generate client URL and open in new tab
    const clientUrl = client.url || `http://${client.name}.localhost`;
    window.open(clientUrl, '_blank');
  }

  getRelativeTime(dateString) {
    if (!dateString) return '';
    
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now - date;
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    const diffDays = Math.floor(diffHours / 24);

    if (diffDays > 0) {
      return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`;
    } else if (diffHours > 0) {
      return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
    } else {
      return 'Recently';
    }
  }
}