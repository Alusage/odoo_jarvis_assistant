import { Component, useState, xml } from "@odoo/owl";
import { BranchSwitchProgress } from "./BranchSwitchProgress.js";

export class Sidebar extends Component {
  static template = xml`
    <div class="sidebar-transition flex-shrink-0" t-att-class="props.sidebarCollapsed ? 'w-16' : 'w-72'">
      <div class="h-full bg-gradient-to-b from-slate-50 to-white border-r border-slate-200/60 shadow-lg backdrop-blur-sm">
        <!-- Toggle Button -->
        <div class="flex items-center justify-between p-4 border-b border-slate-200/60 bg-white/50">
          <div t-if="!props.sidebarCollapsed" class="flex items-center space-x-3">
            <div class="w-8 h-8 bg-gradient-to-br from-blue-500 to-indigo-600 rounded-xl flex items-center justify-center shadow-sm">
              <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 7h14m0 0v12a2 2 0 01-2 2H7a2 2 0 01-2-2V7m0 0V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V7z"/>
              </svg>
            </div>
            <span class="font-semibold text-slate-700 text-sm">Branches</span>
          </div>
          <button 
            class="p-2 rounded-xl hover:bg-slate-100/80 transition-all duration-200 hover:shadow-sm"
            t-on-click="props.onToggleSidebar"
          >
            <svg class="w-4 h-4 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 19l-7-7 7-7m8 14l-7-7 7-7"/>
            </svg>
          </button>
        </div>

        <!-- Filter Input -->
        <div t-if="!props.sidebarCollapsed" class="p-4 border-b border-slate-200/60">
          <input 
            type="text" 
            placeholder="Filter branches..."
            class="w-full px-3 py-2 text-sm bg-slate-50 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 transition-all duration-200"
            t-model="state.filter"
          />
        </div>

        <!-- Client List -->
        <div class="overflow-y-auto h-full pb-20">
          <!-- Production Section -->
          <div class="p-2">
            <div 
              class="flex items-center justify-between p-2 text-xs font-semibold text-slate-600 hover:bg-slate-50/80 rounded-xl cursor-pointer transition-all duration-200 hover:shadow-sm"
              t-on-click="() => this.toggleSection('production')"
            >
              <div class="flex items-center space-x-3">
                <div class="w-2 h-2 bg-green-500 rounded-full shadow-sm"/>
                <span t-if="!props.sidebarCollapsed" class="uppercase tracking-wide">Production</span>
              </div>
              <svg 
                t-if="!props.sidebarCollapsed"
                class="w-3 h-3 transition-transform duration-200 text-slate-400" 
                t-att-class="state.expandedSections.production ? 'rotate-90' : ''"
                fill="none" stroke="currentColor" viewBox="0 0 24 24"
              >
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
              </svg>
            </div>
            
            <div t-if="state.expandedSections.production || props.sidebarCollapsed" class="ml-4 mt-1 space-y-1">
              <t t-foreach="productionClients" t-as="client" t-key="client.name">
                <button 
                  class="w-full flex items-center justify-between p-2 text-left rounded-lg hover:bg-white/80 hover:shadow-sm transition-all duration-200 group border border-transparent hover:border-slate-200/50"
                  t-att-class="getClientItemClass(client)"
                  t-on-click="() => this.selectClient(client)"
                  draggable="true"
                  t-on-dragstart="(ev) => this.handleDragStart(ev, client)"
                  t-on-dragend="(ev) => this.handleDragEnd(ev)"
                >
                  <div class="flex items-center space-x-2 flex-1">
                    <div t-att-class="getStatusClass(client.status)" class="w-2 h-2 rounded-full"/>
                    <div t-if="!props.sidebarCollapsed" class="flex-1 text-left">
                      <div class="flex items-center justify-between">
                        <!-- Display mode -->
                        <div t-if="state.editingBranch !== client.name" class="flex items-center justify-between w-full">
                          <div class="font-mono text-sm font-medium text-gray-900" t-esc="client.branch || client.currentBranch || 'main'"/>
                          <button 
                            class="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-gray-600 p-1 transition-opacity" 
                            t-on-click.stop="(ev) => this.startEditingBranch(client, ev)"
                            title="Rename branch">
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/>
                            </svg>
                          </button>
                        </div>
                        
                        <!-- Edit mode -->
                        <div t-if="state.editingBranch === client.name" class="flex items-center space-x-1 w-full">
                          <input 
                            type="text" 
                            class="text-xs border border-gray-300 rounded px-1 py-0.5 font-medium text-gray-900 flex-1"
                            t-model="state.newBranchName"
                            t-on-keydown="onBranchNameKeydown"
                            placeholder="Branch name"/>
                          <button 
                            class="text-green-600 hover:text-green-700 p-0.5" 
                            t-on-click.stop="() => this.saveBranchName(client)"
                            title="Save">
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                            </svg>
                          </button>
                          <button 
                            class="text-red-600 hover:text-red-700 p-0.5" 
                            t-on-click.stop="() => this.cancelEditingBranch()"
                            title="Cancel">
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                            </svg>
                          </button>
                        </div>
                      </div>
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
              class="flex items-center justify-between p-2 text-xs font-semibold text-slate-600 hover:bg-slate-50/80 rounded-xl cursor-pointer transition-all duration-200 hover:shadow-sm"
              t-att-class="state.stagingDropZone ? 'bg-yellow-50/80 border-2 border-dashed border-yellow-300/60' : ''"
              t-on-click="() => this.toggleSection('staging')"
              t-on-dragover="(ev) => this.handleDragOver(ev, 'staging')"
              t-on-dragleave="(ev) => this.handleDragLeave(ev, 'staging')"
              t-on-drop="(ev) => this.handleDrop(ev, 'staging')"
            >
              <div class="flex items-center space-x-3">
                <div class="w-2 h-2 bg-yellow-500 rounded-full shadow-sm"/>
                <span t-if="!props.sidebarCollapsed" class="uppercase tracking-wide">Staging</span>
                <span t-if="state.stagingDropZone and !props.sidebarCollapsed" class="text-xs text-yellow-600 font-medium">Drop here</span>
              </div>
              <svg 
                t-if="!props.sidebarCollapsed"
                class="w-3 h-3 transition-transform duration-200 text-slate-400" 
                t-att-class="state.expandedSections.staging ? 'rotate-90' : ''"
                fill="none" stroke="currentColor" viewBox="0 0 24 24"
              >
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
              </svg>
            </div>
            
            <div t-if="state.expandedSections.staging || props.sidebarCollapsed" class="ml-4 mt-1 space-y-1">
              <t t-foreach="stagingClients" t-as="client" t-key="client.name">
                <button 
                  class="w-full flex items-center justify-between p-2 text-left rounded-lg hover:bg-white/80 hover:shadow-sm transition-all duration-200 group border border-transparent hover:border-slate-200/50"
                  t-att-class="getClientItemClass(client)"
                  t-on-click="() => this.selectClient(client)"
                >
                  <div class="flex items-center space-x-2 flex-1">
                    <div t-att-class="getStatusClass(client.status)" class="w-2 h-2 rounded-full"/>
                    <div t-if="!props.sidebarCollapsed" class="flex-1 text-left">
                      <div class="flex items-center justify-between">
                        <!-- Display mode -->
                        <div t-if="state.editingBranch !== client.name" class="flex items-center justify-between w-full">
                          <div class="font-mono text-sm font-medium text-gray-900" t-esc="client.branch || client.currentBranch || 'main'"/>
                          <button 
                            class="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-gray-600 p-1 transition-opacity" 
                            t-on-click.stop="(ev) => this.startEditingBranch(client, ev)"
                            title="Rename branch">
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/>
                            </svg>
                          </button>
                        </div>
                        
                        <!-- Edit mode -->
                        <div t-if="state.editingBranch === client.name" class="flex items-center space-x-1 w-full">
                          <input 
                            type="text" 
                            class="text-xs border border-gray-300 rounded px-1 py-0.5 font-medium text-gray-900 flex-1"
                            t-model="state.newBranchName"
                            t-on-keydown="onBranchNameKeydown"
                            placeholder="Branch name"/>
                          <button 
                            class="text-green-600 hover:text-green-700 p-0.5" 
                            t-on-click.stop="() => this.saveBranchName(client)"
                            title="Save">
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                            </svg>
                          </button>
                          <button 
                            class="text-red-600 hover:text-red-700 p-0.5" 
                            t-on-click.stop="() => this.cancelEditingBranch()"
                            title="Cancel">
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                            </svg>
                          </button>
                        </div>
                      </div>
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
              class="flex items-center justify-between p-2 text-xs font-semibold text-slate-600 hover:bg-slate-50/80 rounded-xl cursor-pointer transition-all duration-200 hover:shadow-sm"
              t-att-class="state.developmentDropZone ? 'bg-blue-50/80 border-2 border-dashed border-blue-300/60' : ''"
              t-on-click="() => this.toggleSection('development')"
              t-on-dragover="(ev) => this.handleDragOver(ev, 'development')"
              t-on-dragleave="(ev) => this.handleDragLeave(ev, 'development')"
              t-on-drop="(ev) => this.handleDrop(ev, 'development')"
            >
              <div class="flex items-center space-x-3">
                <div class="w-2 h-2 bg-blue-500 rounded-full shadow-sm"/>
                <span t-if="!props.sidebarCollapsed" class="uppercase tracking-wide">Development</span>
                <span t-if="state.developmentDropZone and !props.sidebarCollapsed" class="text-xs text-blue-600 font-medium">Drop here</span>
              </div>
              <svg 
                t-if="!props.sidebarCollapsed"
                class="w-3 h-3 transition-transform duration-200 text-slate-400" 
                t-att-class="state.expandedSections.development ? 'rotate-90' : ''"
                fill="none" stroke="currentColor" viewBox="0 0 24 24"
              >
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
              </svg>
            </div>
            
            <div t-if="state.expandedSections.development || props.sidebarCollapsed" class="ml-4 mt-1 space-y-1">
              <t t-foreach="developmentClients" t-as="client" t-key="client.name">
                <button 
                  class="w-full flex items-center justify-between p-2 text-left rounded-lg hover:bg-white/80 hover:shadow-sm transition-all duration-200 group border border-transparent hover:border-slate-200/50"
                  t-att-class="getClientItemClass(client)"
                  t-on-click="() => this.selectClient(client)"
                >
                  <div class="flex items-center space-x-2 flex-1">
                    <div t-att-class="getStatusClass(client.status)" class="w-2 h-2 rounded-full"/>
                    <div t-if="!props.sidebarCollapsed" class="flex-1 text-left">
                      <div class="flex items-center justify-between">
                        <!-- Display mode -->
                        <div t-if="state.editingBranch !== client.name" class="flex items-center justify-between w-full">
                          <div class="font-mono text-sm font-medium text-gray-900" t-esc="client.branch || client.currentBranch || 'main'"/>
                          <button 
                            class="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-gray-600 p-1 transition-opacity" 
                            t-on-click.stop="(ev) => this.startEditingBranch(client, ev)"
                            title="Rename branch">
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/>
                            </svg>
                          </button>
                        </div>
                        
                        <!-- Edit mode -->
                        <div t-if="state.editingBranch === client.name" class="flex items-center space-x-1 w-full">
                          <input 
                            type="text" 
                            class="text-xs border border-gray-300 rounded px-1 py-0.5 font-medium text-gray-900 flex-1"
                            t-model="state.newBranchName"
                            t-on-keydown="onBranchNameKeydown"
                            placeholder="Branch name"/>
                          <button 
                            class="text-green-600 hover:text-green-700 p-0.5" 
                            t-on-click.stop="() => this.saveBranchName(client)"
                            title="Save">
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                            </svg>
                          </button>
                          <button 
                            class="text-red-600 hover:text-red-700 p-0.5" 
                            t-on-click.stop="() => this.cancelEditingBranch()"
                            title="Cancel">
                            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                            </svg>
                          </button>
                        </div>
                      </div>
                      <div class="text-xs text-gray-500" t-esc="client.lastActivity"/>
                    </div>
                  </div>
                </button>
              </t>
            </div>
          </div>
        </div>
      </div>

      <!-- Branch Switch Confirmation Dialog -->
      <div t-if="state.showBranchSwitchDialog" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div class="bg-white rounded-lg p-6 w-96 max-w-full mx-4">
          <h3 class="text-lg font-semibold mb-4">Confirm Branch Switch</h3>
          
          <div class="mb-4">
            <p class="text-gray-700">
              You have uncommitted changes. What would you like to do before switching branches?
            </p>
          </div>
          
          <div class="flex flex-col space-y-3">
            <button 
              class="btn-primary w-full"
              t-on-click="commitAndProceed"
            >
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3-3m0 0l-3 3m3-3v12"/>
              </svg>
              Commit Changes and Switch
            </button>
            <button 
              class="btn-warning w-full"
              t-on-click="discardAndProceed"
            >
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
              </svg>
              Discard Changes and Switch
            </button>
            <button 
              class="btn-secondary w-full"
              t-on-click="cancelBranchSwitch"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Branch Switch Progress Dialog -->
    <BranchSwitchProgress 
      t-if="state.showProgressDialog"
      targetBranch="state.progressTargetBranch"
      onClose="closeProgressDialog"
      onRetry="retryBranchSwitch"
      onMount="(comp) => this.progressDialog = comp"
    />
  `;

  static components = { BranchSwitchProgress };

  setup() {
    this.state = useState({
      filter: '',
      expandedSections: {
        production: true,
        staging: false,
        development: true
      },
      draggedClient: null,
      stagingDropZone: false,
      developmentDropZone: false,
      showBranchSwitchDialog: false,
      pendingBranchSwitch: null,
      showProgressDialog: false,
      progressTargetBranch: '',
      currentProgressParams: null,
      editingBranch: null,
      newBranchName: '',
      editingClient: null
    });

    // Reference to progress dialog component
    this.progressDialog = null;
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
    if (this.props.selectedBaseClient) {
      // Si un client de base est sélectionné, afficher seulement ses environnements
      const selectedBaseClientName = this.props.selectedBaseClient;
      return this.filteredClients.filter(client => 
        client.name.startsWith(selectedBaseClientName) && 
        (client.environment === 'production' || client.name.includes('-prod'))
      );
    }
    return this.filteredClients.filter(client => client.environment === 'production');
  }

  get stagingClients() {
    if (this.props.selectedBaseClient) {
      // Si un client de base est sélectionné, afficher seulement ses environnements
      const selectedBaseClientName = this.props.selectedBaseClient;
      return this.filteredClients.filter(client => 
        client.name.startsWith(selectedBaseClientName) && 
        (client.environment === 'staging' || client.name.includes('-staging'))
      );
    }
    return this.filteredClients.filter(client => client.environment === 'staging');
  }

  get developmentClients() {
    if (this.props.selectedBaseClient) {
      // Si un client de base est sélectionné, afficher seulement ses environnements
      const selectedBaseClientName = this.props.selectedBaseClient;
      return this.filteredClients.filter(client => 
        client.name.startsWith(selectedBaseClientName) && 
        (client.environment === 'development' || client.name.includes('-dev'))
      );
    }
    return this.filteredClients.filter(client => client.environment === 'development');
  }

  toggleSection(section) {
    this.state.expandedSections[section] = !this.state.expandedSections[section];
  }

  async selectClient(client) {
    if (!client) return;
    
    // Extract base client name and branch from client object
    const baseName = client.name.split('-')[0];
    const branchName = client.branch;
    const clientName = client.name;
    
    // If switching to a different branch, check for uncommitted changes first
    if (this.props.selectedClient && this.props.selectedClient !== clientName) {
      try {
        const currentClient = this.getAllClients().find(c => c.name === this.props.selectedClient);
        const currentBaseName = currentClient ? currentClient.name.split('-')[0] : this.props.selectedClient.split('-')[0];
        
        if (currentBaseName === baseName) {
          // Same client, different branch - check for uncommitted changes
          const { dataService } = await import('../services/dataService.js');
          const gitStatus = await dataService.getClientGitStatus(baseName);
          
          if (gitStatus.success && gitStatus.has_uncommitted_changes) {
            // Show confirmation dialog
            this.state.pendingBranchSwitch = {
              clientName: clientName,
              baseName: baseName,
              branchName: branchName
            };
            this.state.showBranchSwitchDialog = true;
            return; // Don't proceed with switch until user confirms
          } else {
            // No uncommitted changes, proceed with switch
            await this.commitAndSwitchBranch(baseName, branchName);
            // After successful branch switch, select the client
            this.props.onClientSelect(clientName);
            return;
          }
        }
      } catch (error) {
        console.error('Error during branch switch:', error);
      }
    }
    
    this.props.onClientSelect(clientName);
  }

  getAllClients() {
    return [...this.productionClients, ...this.stagingClients, ...this.developmentClients];
  }

  async commitAndSwitchBranch(clientName, targetBranch) {
    try {
      // Import dataService here to avoid circular imports
      const { dataService } = await import('../services/dataService.js');
      
      // Get current Git status
      const gitStatus = await dataService.getClientGitStatus(clientName);
      
      // If there are uncommitted changes, commit them first
      if (gitStatus.success && gitStatus.has_uncommitted_changes) {
        const commitResult = await dataService.commitClientChanges(
          clientName, 
          `Auto-commit before switching to ${targetBranch || 'default'} branch`
        );
        
        if (commitResult.success) {
          console.log(`✅ Changes committed: ${commitResult.message}`);
        }
      }
      
      // Switch to the target branch with progress if specified
      if (targetBranch) {
        this.state.currentProgressParams = { clientName, targetBranch };
        await this.switchBranchWithProgress(clientName, targetBranch);
      }
      
    } catch (error) {
      console.error('Error in commitAndSwitchBranch:', error);
      this.showMessage(`Error switching branch: ${error.message}`, 'error');
    }
  }

  async switchBranchWithProgress(clientName, targetBranch) {
    // Show progress dialog
    this.state.showProgressDialog = true;
    this.state.progressTargetBranch = targetBranch;
    
    // Wait a bit for the component to mount and initialize with a starting step
    await new Promise(resolve => setTimeout(resolve, 100));
    
    if (this.progressDialog) {
      this.progressDialog.updateProgress([{
        step: 1,
        action: "Connecting to server",
        status: "in_progress",
        details: `Establishing connection for branch switch to '${targetBranch}'...`
      }]);
    }
    
    try {
      // Use WebSocket for real-time progress
      const wsUrl = `ws://mcp.localhost/branch-switch/${clientName}`;
      const websocket = new WebSocket(wsUrl);
      
      websocket.onopen = () => {
        console.log('WebSocket connected for branch switch');
        // Send branch switch request
        websocket.send(JSON.stringify({
          branch: targetBranch,
          create: false
        }));
      };
      
      websocket.onmessage = (event) => {
        const message = JSON.parse(event.data);
        console.log('WebSocket message:', message);
        
        switch (message.type) {
          case 'start':
            if (this.progressDialog) {
              this.progressDialog.updateProgress([{
                step: 1,
                action: "Starting branch switch",
                status: "in_progress",
                details: message.message
              }]);
            }
            break;
            
          case 'step':
            if (this.progressDialog) {
              // Update individual step in real-time
              this.progressDialog.updateStep(message.data);
            }
            break;
            
          case 'success':
            console.log(`✅ Switched to branch: ${message.current_branch}`);
            if (this.progressDialog) {
              this.progressDialog.addStep({
                step: 999,
                action: "Branch switch completed",
                status: "completed",
                details: message.message
              });
            }
            
            // Auto-close progress dialog after a short delay if successful
            setTimeout(() => {
              this.closeProgressDialog();
              // Reload the page to reflect the new branch
              window.location.reload();
            }, 2000);
            websocket.close();
            break;
            
          case 'error':
            console.error('❌ Branch switch failed:', message.message);
            if (this.progressDialog) {
              this.progressDialog.addStep({
                step: 999,
                action: "Branch switch failed",
                status: "failed",
                details: message.message
              });
            }
            this.showMessage(`Failed to switch branch: ${message.message}`, 'error');
            websocket.close();
            break;
        }
      };
      
      websocket.onerror = (error) => {
        console.error('❌ WebSocket error:', error);
        if (this.progressDialog) {
          this.progressDialog.addStep({
            step: 999,
            action: "Connection failed",
            status: "failed",
            details: "Failed to connect to server for real-time progress"
          });
        }
        this.showMessage('Failed to connect to server for real-time progress', 'error');
      };
      
      websocket.onclose = () => {
        console.log('WebSocket connection closed');
      };
      
    } catch (error) {
      console.error('❌ Error during branch switch:', error);
      if (this.progressDialog) {
        this.progressDialog.addStep({
          step: 999,
          action: "Branch switch failed",
          status: "failed",
          details: `Network error: ${error.message}`
        });
      }
      this.showMessage(`Error switching branch: ${error.message}`, 'error');
    }
  }

  async commitAndProceed() {
    if (!this.state.pendingBranchSwitch) return;
    
    const { clientName, baseName, branchName } = this.state.pendingBranchSwitch;
    
    // Close the branch switch dialog first
    this.state.showBranchSwitchDialog = false;
    this.state.pendingBranchSwitch = null;
    
    try {
      await this.commitAndSwitchBranch(baseName, branchName);
      this.props.onClientSelect(clientName);
    } catch (error) {
      console.error('Error during commit and proceed:', error);
      this.showMessage(`Error committing changes: ${error.message}`, 'error');
    }
  }

  async discardAndProceed() {
    if (!this.state.pendingBranchSwitch) return;
    
    const { clientName, baseName, branchName } = this.state.pendingBranchSwitch;
    
    // Close the branch switch dialog first
    this.state.showBranchSwitchDialog = false;
    this.state.pendingBranchSwitch = null;
    
    try {
      const { dataService } = await import('../services/dataService.js');
      
      // Reset working directory to discard changes
      await dataService.executeShellCommand(baseName, 'git reset --hard');
      
      // Switch to the target branch with progress if specified
      if (branchName) {
        this.state.currentProgressParams = { clientName: baseName, targetBranch: branchName };
        await this.switchBranchWithProgress(baseName, branchName);
      }
      
      this.props.onClientSelect(clientName);
    } catch (error) {
      console.error('Error during discard and proceed:', error);
      this.showMessage(`Error discarding changes: ${error.message}`, 'error');
    }
  }

  cancelBranchSwitch() {
    this.state.showBranchSwitchDialog = false;
    this.state.pendingBranchSwitch = null;
  }

  filterClients() {
    // Filter is already reactive through t-model
  }

  getClientItemClass(client) {
    // Une branche est active si le nom du client correspond exactement au client sélectionné
    const isActive = this.props.selectedClient === client.name;
    
    if (isActive) {
      return 'bg-gradient-to-r from-blue-50 to-indigo-50 border-blue-200 shadow-sm ring-1 ring-blue-200/50';
    }
    
    return '';
  }

  getStatusClass(status) {
    const statusClasses = {
      'healthy': 'bg-green-500',
      'warning': 'bg-yellow-500',
      'error': 'bg-red-500',
      'critical': 'bg-red-600'
    };
    return statusClasses[status] || 'bg-slate-400';
  }

  // Drag and Drop methods
  handleDragStart(event, client) {
    this.state.draggedClient = client;
    event.dataTransfer.setData('text/plain', '');
    event.dataTransfer.effectAllowed = 'copy';
  }

  handleDragEnd(event) {
    this.state.draggedClient = null;
    this.state.stagingDropZone = false;
    this.state.developmentDropZone = false;
  }

  handleDragOver(event, targetSection) {
    if (!this.state.draggedClient) return;
    
    event.preventDefault();
    event.dataTransfer.dropEffect = 'copy';
    
    // Only allow dropping on staging and development sections
    if (targetSection === 'staging') {
      this.state.stagingDropZone = true;
    } else if (targetSection === 'development') {
      this.state.developmentDropZone = true;
    }
  }

  handleDragLeave(event, targetSection) {
    if (targetSection === 'staging') {
      this.state.stagingDropZone = false;
    } else if (targetSection === 'development') {
      this.state.developmentDropZone = false;
    }
  }

  async handleDrop(event, targetSection) {
    event.preventDefault();
    
    if (!this.state.draggedClient) return;
    
    const sourceClient = this.state.draggedClient;
    this.state.stagingDropZone = false;
    this.state.developmentDropZone = false;
    
    try {
      // Extract the base client name (remove any existing suffixes)
      const baseClientName = sourceClient.name.split('-')[0];
      
      // Generate branch name based on target section
      let branchName;
      if (targetSection === 'staging') {
        const date = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
        branchName = `staging-${date}`;
      } else if (targetSection === 'development') {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
        branchName = `dev-${timestamp}`;
      }
      
      console.log(`Creating ${targetSection} branch ${branchName} from ${sourceClient.branch} for client ${baseClientName}`);
      
      // Call the API to create the branch
      const response = await fetch('http://mcp.localhost/tools/call', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: 'create_client_branch',
          arguments: {
            client: baseClientName,
            branch: branchName,
            source: sourceClient.branch || '18.0'
          }
        })
      });
      
      const result = await response.json();
      
      if (result.success) {
        console.log(`Successfully created branch ${branchName}`);
        
        // Refresh the clients list to show the new branch
        if (this.props.onRefreshClients) {
          await this.props.onRefreshClients();
        }
        
        // Expand the target section to show the new branch
        this.state.expandedSections[targetSection] = true;
        
        // Show success message
        this.showMessage(`Branch ${branchName} created successfully!`, 'success');
      } else {
        console.error('Failed to create branch:', result.error);
        this.showMessage(`Failed to create branch: ${result.error}`, 'error');
      }
    } catch (error) {
      console.error('Error creating branch:', error);
      this.showMessage(`Error creating branch: ${error.message}`, 'error');
    }
    
    this.state.draggedClient = null;
  }

  showMessage(message, type = 'info') {
    // Simple message display - you can enhance this with a proper toast/notification system
    if (type === 'success') {
      console.log(`✅ ${message}`);
    } else if (type === 'error') {
      console.error(`❌ ${message}`);
    } else {
      console.log(`ℹ️ ${message}`);
    }
  }

  closeProgressDialog() {
    this.state.showProgressDialog = false;
    this.state.progressTargetBranch = '';
    this.state.currentProgressParams = null;
  }

  async retryBranchSwitch() {
    if (this.state.currentProgressParams) {
      const { clientName, targetBranch } = this.state.currentProgressParams;
      await this.switchBranchWithProgress(clientName, targetBranch);
    }
  }

  startEditingBranch(client, event) {
    event?.stopPropagation();
    console.log('Starting to edit branch for client:', client);
    
    this.state.editingBranch = client.name;
    this.state.newBranchName = client.branch || client.name.split('-').slice(1).join('-') || '18.0';
    this.state.editingClient = client; // Store the client being edited
  }

  onBranchNameKeydown(event) {
    if (event.key === 'Enter') {
      this.saveBranchName(this.state.editingClient);
    } else if (event.key === 'Escape') {
      this.cancelEditingBranch();
    }
  }

  cancelEditingBranch() {
    this.state.editingBranch = null;
    this.state.newBranchName = '';
    this.state.editingClient = null;
  }

  async saveBranchName(client) {
    if (!this.state.newBranchName.trim()) {
      this.cancelEditingBranch();
      return;
    }

    const oldBranchName = client.branch || client.name.split('-').slice(1).join('-') || '18.0';
    const newBranchName = this.state.newBranchName.trim();

    if (oldBranchName === newBranchName) {
      this.cancelEditingBranch();
      return;
    }

    try {
      const baseClientName = client.name.split('-')[0];

      // Call MCP server to rename the branch
      const response = await fetch('http://mcp.localhost/tools/call', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: 'rename_client_branch',
          arguments: {
            client: baseClientName,
            old_branch: oldBranchName,
            new_branch: newBranchName
          }
        })
      });

      const result = await response.json();
      if (result.success) {
        console.log(`✅ Branch renamed successfully from ${oldBranchName} to ${newBranchName}`);
        this.cancelEditingBranch();
        
        // Refresh the clients list to reflect the change
        if (this.props.onRefreshClients) {
          await this.props.onRefreshClients();
        }
        
        this.showMessage(`Branch renamed to ${newBranchName}`, 'success');
      } else {
        console.error(`❌ Failed to rename branch: ${result.error}`);
        this.showMessage(`Failed to rename branch: ${result.error || 'Unknown error'}`, 'error');
        this.cancelEditingBranch();
      }
    } catch (error) {
      console.error('Error renaming branch:', error);
      this.showMessage(`Error renaming branch: ${error.message}`, 'error');
      this.cancelEditingBranch();
    }
  }

  showMessage(message, type = 'info') {
    // Simple message display - you can enhance this with a proper toast/notification system
    if (type === 'success') {
      console.log(`✅ ${message}`);
    } else if (type === 'error') {
      console.error(`❌ ${message}`);
    } else {
      console.log(`ℹ️ ${message}`);
    }
  }

}