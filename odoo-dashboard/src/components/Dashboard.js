import { Component, useState, onMounted, onWillUnmount, useEffect, xml } from "@odoo/owl";
import { CommitHistory } from "./CommitHistory.js";
import { BuildCard } from "./BuildCard.js";
import { Terminal } from "./Terminal.js";
import { ClientsOverview } from "./ClientsOverview.js";
import { dataService } from "../services/dataService.js";

export class Dashboard extends Component {
  static template = xml`
    <div class="flex flex-col h-full">
      <!-- Clients Overview (No client selected) -->
      <div t-if="!props.client" class="h-full">
        <ClientsOverview onClientSelect="props.onClientSelect"/>
      </div>

      <!-- Client Dashboard (Client selected) -->
      <div t-if="props.client" class="flex flex-col h-full">
        <!-- Tab Navigation -->
        <div class="border-b border-gray-200 bg-white sticky top-0 z-20">
        <div class="flex items-center justify-between p-4">
          <!-- Tabs -->
          <div class="flex space-x-6">
            <button 
              t-foreach="state.tabs" 
              t-as="tab" 
              t-key="tab.id"
              class="tab-button"
              t-att-class="getTabClass(tab.id)"
              t-on-click="() => this.setActiveTab(tab.id)"
            >
              <t t-esc="tab.label"/>
            </button>
          </div>

          <!-- Action Buttons -->
          <div class="flex items-center space-x-2">
            <button class="btn-secondary" t-on-click="cloneRepository">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
              </svg>
              Clone
            </button>
            <button t-if="state.clientStatus.status !== 'running'" class="btn-success" t-on-click="startClient">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.828 14.828a4 4 0 01-5.656 0M9 10h1m4 0h1m-6 4h8m-9-4h.01M12 5v.01M3 12a9 9 0 0118 0 9 9 0 01-18 0z"/>
              </svg>
              Start
            </button>
            <button t-if="state.clientStatus.status === 'running'" class="btn-warning" t-on-click="stopClient">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 10h6v4H9z"/>
              </svg>
              Stop
            </button>
            <button t-if="state.clientStatus.status === 'running'" class="btn-secondary" t-on-click="restartClient">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
              </svg>
              Restart
            </button>
            <button class="btn-secondary" t-on-click="rebuildClient">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"/>
              </svg>
              Rebuild
            </button>
            <button t-if="state.clientStatus.status === 'running'" class="btn-primary" t-on-click="connectToClient">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/>
              </svg>
              Connect
            </button>
          </div>
        </div>

        <!-- Git Command Display -->
        <div t-if="props.client" class="px-4 pb-4">
          <div class="bg-gray-50 rounded-lg p-3 font-mono text-sm">
            <div class="flex items-center justify-between">
              <span class="text-gray-600">git clone</span>
              <button class="btn-secondary btn-sm" t-on-click="copyGitCommand">
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
                </svg>
              </button>
            </div>
            <div class="text-primary-600 mt-1" t-esc="getGitCloneCommand()"/>
          </div>
        </div>
      </div>

      <!-- Tab Content -->
      <div class="flex-1 overflow-hidden">
        <!-- History Tab -->
        <div t-if="props.currentTab === 'HISTORY'" class="h-full">
          <CommitHistory 
            client="props.client"
            commits="state.commits"
            loading="state.loading"
          />
        </div>

        <!-- Addons Tab -->
        <div t-if="props.currentTab === 'ADDONS'" class="h-full overflow-y-auto p-6">
          <!-- Header with Git status and actions -->
          <div class="mb-6 p-4 bg-gray-50 rounded-lg border">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-lg font-semibold text-gray-900">Module Management</h2>
                <p class="text-sm text-gray-600">Manage linked modules for this client</p>
              </div>
              <div class="flex items-center space-x-3">
                <div t-if="state.gitStatus" class="text-sm">
                  <div class="flex items-center space-x-2">
                    <span class="font-medium">Branch:</span>
                    
                    <!-- Branch name display mode -->
                    <div t-if="!state.editingBranch" class="flex items-center space-x-1">
                      <span class="font-mono text-primary-600" t-esc="state.gitStatus.current_branch"/>
                      <button 
                        class="text-gray-400 hover:text-gray-600 p-1" 
                        t-on-click="startEditingBranch"
                        title="Rename branch">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/>
                        </svg>
                      </button>
                    </div>
                    
                    <!-- Branch name edit mode -->
                    <div t-if="state.editingBranch" class="flex items-center space-x-2">
                      <input 
                        type="text" 
                        class="text-sm border border-gray-300 rounded px-2 py-1 font-mono text-primary-600"
                        t-model="state.newBranchName"
                        t-on-keydown="onBranchNameKeydown"
                        t-ref="branchInput"
                        placeholder="New branch name"/>
                      <button 
                        class="text-green-600 hover:text-green-700 p-1" 
                        t-on-click="saveBranchName"
                        title="Save">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                        </svg>
                      </button>
                      <button 
                        class="text-red-600 hover:text-red-700 p-1" 
                        t-on-click="cancelEditingBranch"
                        title="Cancel">
                        <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                        </svg>
                      </button>
                    </div>
                  </div>
                  
                  <div class="mt-1">
                    <span t-if="state.gitStatus.has_uncommitted_changes" class="text-orange-600">● Uncommitted changes</span>
                    <span t-if="state.gitStatus.sync_status === 'up_to_date'" class="text-green-600">✓ Up to date</span>
                    <span t-if="state.gitStatus.sync_status === 'behind'" class="text-red-600">↓ Behind remote</span>
                    <span t-if="state.gitStatus.sync_status === 'ahead'" class="text-blue-600">↑ Ahead of remote</span>
                  </div>
                </div>
                <button 
                  t-if="state.gitStatus &amp;&amp; state.gitStatus.has_uncommitted_changes"
                  class="btn-primary btn-sm" 
                  t-on-click="showCommitDialog"
                >
                  <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3-3m0 0l-3 3m3-3v12"/>
                  </svg>
                  Commit Changes
                </button>
              </div>
            </div>
          </div>
          
          <div class="space-y-6">
            <div t-foreach="state.addons" t-as="addon" t-key="addon.name" class="card p-6">
              <div class="flex items-center justify-between mb-4">
                <div>
                  <h3 class="text-lg font-semibold text-gray-900" t-esc="addon.name"/>
                  <p class="text-sm text-gray-600">
                    <span class="font-medium">Branch:</span> <span t-esc="addon.branch"/>
                    <span class="ml-4 font-medium">Commit:</span> <span class="font-mono text-xs" t-esc="addon.commit"/>
                  </p>
                </div>
                <div class="flex items-center space-x-2">
                  <span class="badge badge-info" t-esc="addon.url"/>
                </div>
              </div>
              
              <div class="border-t pt-4">
                <h4 class="text-md font-medium text-gray-700 mb-3">Available Modules</h4>
                <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2">
                  <div t-foreach="addon.modules" t-as="module" t-key="module.name" class="flex items-center space-x-2">
                    <input 
                      type="checkbox" 
                      t-att-id="'module-' + addon.name + '-' + module.name"
                      t-att-checked="module.linked"
                      t-on-change="(ev) => this.toggleModule(addon.name, module.name, ev.target.checked)"
                      class="h-4 w-4 text-primary-600 border-gray-300 rounded focus:ring-primary-500"
                    />
                    <label 
                      t-att-for="'module-' + addon.name + '-' + module.name"
                      class="text-sm text-gray-700 cursor-pointer"
                      t-esc="module.name"
                    />
                  </div>
                </div>
              </div>
            </div>
            
            <div t-if="state.addons.length === 0 &amp;&amp; !state.loading" class="text-center py-12">
              <svg class="w-12 h-12 mx-auto text-gray-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 7l-8-4-8 4m16 0l-8 4-8-4m16 0v10l-8 4-8-4V7"/>
              </svg>
              <p class="text-gray-500">No addon repositories found</p>
            </div>
          </div>
        </div>

        <!-- Builds Tab -->
        <div t-if="props.currentTab === 'BUILDS'" class="h-full p-6">
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <BuildCard 
              t-foreach="state.builds" 
              t-as="build" 
              t-key="build.id"
              build="build"
              onConnect="() => this.connectToBuild(build.id)"
              onViewLogs="() => this.viewBuildLogs(build.id)"
            />
          </div>
          
          <div t-if="state.builds.length === 0 &amp;&amp; !state.loading" class="text-center py-12">
            <svg class="w-12 h-12 mx-auto text-gray-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
            </svg>
            <p class="text-gray-500">No builds available</p>
          </div>
        </div>

        <!-- Logs Tab -->
        <div t-if="props.currentTab === 'LOGS'" class="h-full p-6">
          <div class="bg-gray-900 rounded-lg h-full overflow-hidden">
            <div class="bg-gray-800 px-4 py-2 flex items-center justify-between">
              <h3 class="text-white font-medium">Application Logs</h3>
              <div class="flex items-center space-x-2">
                <button class="btn-secondary btn-sm" t-on-click="refreshLogs">
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                  </svg>
                </button>
                <button class="btn-secondary btn-sm" t-on-click="downloadLogs">
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                  </svg>
                </button>
              </div>
            </div>
            <div class="p-4 h-full overflow-y-auto font-mono text-sm text-green-400">
              <div t-foreach="state.logs" t-as="logLine" t-key="logLine_index">
                <span class="text-gray-500" t-esc="logLine.timestamp"/>
                <span t-att-class="getLogLevelClass(logLine.level)" t-esc="logLine.level"/>
                <span class="text-gray-300" t-esc="logLine.message"/>
              </div>
            </div>
          </div>
        </div>

        <!-- Shell Tab -->
        <div t-if="props.currentTab === 'SHELL'" class="h-full p-6">
          <Terminal client="props.client"/>
        </div>
      </div>

      <!-- Loading State -->
      <div t-if="state.loading" class="absolute inset-0 bg-white/80 flex items-center justify-center">
        <div class="text-center">
          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-500 mx-auto mb-2"/>
          <p class="text-gray-600">Loading...</p>
        </div>
      </div>

      <!-- Commit Dialog -->
      <div t-if="state.showCommitDialog" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div class="bg-white rounded-lg p-6 w-96 max-w-full mx-4">
          <h3 class="text-lg font-semibold mb-4">Commit Changes</h3>
          
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Commit Message
            </label>
            <textarea
              class="w-full p-3 border border-gray-300 rounded-lg resize-none focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
              rows="3"
              placeholder="Describe your changes..."
              t-model="state.commitMessage"
            />
          </div>
          
          <div class="flex justify-end space-x-3">
            <button 
              class="btn-secondary"
              t-on-click="cancelCommit"
            >
              Cancel
            </button>
            <button 
              class="btn-primary"
              t-on-click="confirmCommit"
              t-att-disabled="!state.commitMessage.trim()"
            >
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3-3m0 0l-3 3m3-3v12"/>
              </svg>
              Commit
            </button>
          </div>
        </div>
      </div>
      </div>
      
    </div>
  `;
  
  static components = { CommitHistory, BuildCard, Terminal, ClientsOverview };

  setup() {
    this.state = useState({
      tabs: [
        { id: 'HISTORY', label: 'HISTORY' },
        { id: 'ADDONS', label: 'ADDONS' },
        { id: 'BUILDS', label: 'BUILDS' },
        { id: 'LOGS', label: 'LOGS' },
        { id: 'SHELL', label: 'SHELL' }
      ],
      commits: [],
      addons: [],
      builds: [],
      logs: [],
      loading: false,
      clientStatus: { status: 'unknown' },
      gitStatus: null,
      editingBranch: false,
      newBranchName: '',
      commitMessage: 'Update module configuration',
      showCommitDialog: false
    });

    onMounted(() => {
      this.loadTabData();
      this.loadClientStatus();
      
      // Auto-refresh client status every 5 seconds
      this.statusInterval = setInterval(() => {
        this.loadClientStatus();
      }, 5000);
    });

    // Watch for client prop changes to reload data when switching branches
    useEffect(
      () => {
        console.log('Client prop changed, reloading data...');
        this.loadTabData();
        this.loadClientStatus();
      },
      () => [this.props.client ? `${this.props.client.name}-${this.props.client.branch || ''}` : null]
    );
    
    onWillUnmount(() => {
      if (this.statusInterval) {
        clearInterval(this.statusInterval);
      }
    });
  }

  async loadClientStatus() {
    if (!this.props.client) return;
    
    try {
      // Extract base client name and branch
      const { baseName, branchName } = this.parseClientInfo();
      
      this.state.clientStatus = await dataService.getClientStatus(baseName, branchName);
    } catch (error) {
      console.error('Error loading client status:', error);
      this.state.clientStatus = { status: 'unknown' };
    }
  }

  parseClientInfo() {
    if (!this.props.client) return { baseName: '', branchName: null };
    
    let baseName = this.props.client.name;
    let branchName = this.props.client.branch;
    
    // If client name contains branch info, extract base name
    if (baseName.includes('-') && !branchName) {
      const parts = baseName.split('-');
      baseName = parts[0];
      branchName = parts.slice(1).join('-');
    }
    
    // Use actual branch name from client data if available
    if (this.props.client.branch && this.props.client.branch !== '18.0') {
      branchName = this.props.client.branch;
    }
    
    return { baseName, branchName };
  }

  async loadTabData() {
    if (!this.props.client) return;

    this.state.loading = true;
    
    try {
      const { baseName, branchName } = this.parseClientInfo();
      
      // Load data based on current tab
      switch (this.props.currentTab) {
        case 'HISTORY':
          this.state.commits = await dataService.getCommitHistory(baseName, branchName);
          break;
        case 'ADDONS':
          this.state.addons = await dataService.getClientAddons(baseName);
          // Also load Git status for ADDONS tab
          try {
            this.state.gitStatus = await dataService.getClientGitStatus(baseName);
          } catch (error) {
            console.error('Error loading Git status:', error);
            this.state.gitStatus = null;
          }
          break;
        case 'BUILDS':
          this.state.builds = await dataService.getBuildHistory(baseName);
          break;
        case 'LOGS':
          await this.loadLogs();
          break;
        case 'SHELL':
          // Terminal component handles its own initialization
          break;
      }
    } catch (error) {
      console.error('Error loading tab data:', error);
    } finally {
      this.state.loading = false;
    }
  }

  async loadLogs() {
    if (!this.props.client) return;
    
    try {
      const { baseName, branchName } = this.parseClientInfo();
      
      const rawLogs = await dataService.getClientLogs(baseName, branchName, 'odoo', 50);
      
      // Parse logs into structured format
      this.state.logs = [];
      const logLines = rawLogs.split('\n').filter(line => line.trim());
      
      logLines.forEach((line, index) => {
        // Extract timestamp, level and message from Odoo logs
        const timestamp = new Date().toISOString(); // Fallback timestamp
        let level = 'INFO';
        let message = line;
        
        // Try to parse log level from line
        if (line.includes('ERROR')) {
          level = 'ERROR';
        } else if (line.includes('WARNING')) {
          level = 'WARN';
        } else if (line.includes('DEBUG')) {
          level = 'DEBUG';
        }
        
        this.state.logs.push({
          timestamp: timestamp,
          level: level,
          message: message
        });
      });
      
      // If no logs, show default message
      if (this.state.logs.length === 0) {
        this.state.logs = [{
          timestamp: new Date().toISOString(),
          level: 'INFO',
          message: 'No logs available or container not running'
        }];
      }
    } catch (error) {
      console.error('Error loading logs:', error);
      this.state.logs = [{
        timestamp: new Date().toISOString(),
        level: 'ERROR',
        message: `Error loading logs: ${error.message}`
      }];
    }
  }


  async setActiveTab(tabId) {
    this.props.onTabChange(tabId);
    // Wait for the next tick to ensure the UI has updated
    await new Promise(resolve => setTimeout(resolve, 0));
    this.loadTabData();
  }

  getTabClass(tabId) {
    return this.props.currentTab === tabId ? 'tab-button active' : 'tab-button';
  }

  getGitCloneCommand() {
    if (!this.props.client) return '';
    return `git clone http://localhost/git/${this.props.client.name}.git`;
  }

  getLogLevelClass(level) {
    const classes = {
      'ERROR': 'text-red-400',
      'WARN': 'text-yellow-400',
      'INFO': 'text-blue-400',
      'DEBUG': 'text-gray-400'
    };
    return classes[level] || 'text-gray-300';
  }

  // Action handlers
  async cloneRepository() {
    if (!this.props.client) return;
    
    const command = this.getGitCloneCommand();
    await navigator.clipboard.writeText(command);
    
    // Show success notification
    console.log('Git clone command copied to clipboard');
  }

  async startClient() {
    if (!this.props.client) return;
    
    this.state.loading = true;
    try {
      const { baseName, branchName } = this.parseClientInfo();
      
      console.log(`Starting client ${baseName}${branchName ? ' branch ' + branchName : ''}...`);
      
      let result;
      if (branchName && branchName !== '18.0') {
        // Use branch-specific start for non-default branches
        result = await dataService.startClientBranch(baseName, branchName);
      } else {
        // Use regular start for default/production branches
        const response = await fetch('http://mcp.localhost/tools/call', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            name: 'start_client',
            arguments: {
              client: baseName
            }
          })
        });
        result = await response.json();
      }

      if (result.success) {
        console.log('Client started successfully');
        await this.loadClientStatus();
        await this.loadTabData();
      } else {
        console.error('Failed to start client:', result.error);
      }
    } catch (error) {
      console.error('Error starting client:', error);
    } finally {
      this.state.loading = false;
    }
  }

  async stopClient() {
    if (!this.props.client) return;
    
    this.state.loading = true;
    try {
      const { baseName, branchName } = this.parseClientInfo();
      
      console.log(`Stopping client ${baseName}${branchName ? ' branch ' + branchName : ''}...`);
      
      let result;
      if (branchName && branchName !== '18.0') {
        // Use branch-specific stop for non-default branches
        result = await dataService.stopClientBranch(baseName, branchName);
      } else {
        // Use regular stop for default/production branches
        const response = await fetch('http://mcp.localhost/tools/call', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            name: 'stop_client',
            arguments: {
              client: baseName
            }
          })
        });
        result = await response.json();
      }

      if (result.success) {
        console.log('Client stopped successfully');
        await this.loadClientStatus();
        await this.loadTabData();
      } else {
        console.error('Failed to stop client:', result.error);
      }
    } catch (error) {
      console.error('Error stopping client:', error);
    } finally {
      this.state.loading = false;
    }
  }

  async restartClient() {
    if (!this.props.client) return;
    
    this.state.loading = true;
    try {
      const { baseName, branchName } = this.parseClientInfo();
      
      console.log(`Restarting client ${baseName}${branchName ? ' branch ' + branchName : ''}...`);
      
      let result;
      if (branchName && branchName !== '18.0') {
        // Use branch-specific restart for non-default branches
        result = await dataService.restartClientBranch(baseName, branchName);
      } else {
        // Use regular restart for default/production branches
        const response = await fetch('http://mcp.localhost/tools/call', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            name: 'restart_client',
            arguments: {
              client: baseName
            }
          })
        });
        result = await response.json();
      }

      if (result.success) {
        console.log('Client restarted successfully');
        await this.loadClientStatus();
        await this.loadTabData();
      } else {
        console.error('Failed to restart client:', result.error);
      }
    } catch (error) {
      console.error('Error restarting client:', error);
    } finally {
      this.state.loading = false;
    }
  }

  async rebuildClient() {
    if (!this.props.client) return;
    
    this.state.loading = true;
    try {
      const { baseName, branchName } = this.parseClientInfo();
      
      console.log(`Rebuilding client ${baseName}${branchName ? ' branch ' + branchName : ''}...`);
      
      // For rebuilds, we might want to rebuild the branch-specific image if it's not default
      const response = await fetch('http://mcp.localhost/tools/call', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: 'rebuild_client',
          arguments: {
            client: baseName,
            no_cache: false
          }
        })
      });

      const result = await response.json();
      if (result.success) {
        console.log('Client rebuilt successfully');
        await this.loadClientStatus();
        await this.loadTabData();
      } else {
        console.error('Failed to rebuild client:', result.error);
      }
    } catch (error) {
      console.error('Error rebuilding client:', error);
    } finally {
      this.state.loading = false;
    }
  }

  connectToClient() {
    if (!this.props.client) return;
    
    const url = this.props.client.url;
    window.open(url, '_blank');
  }

  copyGitCommand() {
    const command = this.getGitCloneCommand();
    navigator.clipboard.writeText(command);
  }

  startEditingBranch() {
    this.state.editingBranch = true;
    this.state.newBranchName = this.state.gitStatus.current_branch;
    
    // Focus the input after the next render
    setTimeout(() => {
      const input = this.refs.branchInput;
      if (input) {
        input.focus();
        input.select();
      }
    }, 0);
  }

  cancelEditingBranch() {
    this.state.editingBranch = false;
    this.state.newBranchName = '';
  }

  onBranchNameKeydown(event) {
    if (event.key === 'Enter') {
      this.saveBranchName();
    } else if (event.key === 'Escape') {
      this.cancelEditingBranch();
    }
  }

  async saveBranchName() {
    if (!this.state.newBranchName.trim()) {
      this.cancelEditingBranch();
      return;
    }

    const oldBranchName = this.state.gitStatus.current_branch;
    const newBranchName = this.state.newBranchName.trim();

    if (oldBranchName === newBranchName) {
      this.cancelEditingBranch();
      return;
    }

    try {
      const { baseName } = this.parseClientInfo();

      // Call MCP server to rename the branch
      const response = await fetch('http://mcp.localhost/tools/call', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: 'rename_client_branch',
          arguments: {
            client: baseName,
            old_branch: oldBranchName,
            new_branch: newBranchName
          }
        })
      });

      const result = await response.json();
      if (result.success) {
        console.log(`✅ Branch renamed successfully from ${oldBranchName} to ${newBranchName}`);
        
        // Update the git status to reflect the new branch name
        this.state.gitStatus.current_branch = newBranchName;
        this.cancelEditingBranch();
        
        // Refresh the git status to ensure consistency
        await this.loadClientStatus();
      } else {
        console.error(`❌ Failed to rename branch: ${result.error}`);
        alert(`Failed to rename branch: ${result.error || 'Unknown error'}`);
        this.cancelEditingBranch();
      }
    } catch (error) {
      console.error('Error renaming branch:', error);
      alert(`Error renaming branch: ${error.message}`);
      this.cancelEditingBranch();
    }
  }

  refreshLogs() {
    this.loadLogs();
  }

  downloadLogs() {
    const logsText = this.state.logs
      .map(log => `${log.timestamp} ${log.level} ${log.message}`)
      .join('\n');
    
    const blob = new Blob([logsText], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${this.props.client?.name || 'client'}-logs.txt`;
    a.click();
    URL.revokeObjectURL(url);
  }

  connectToBuild(buildId) {
    console.log(`Connecting to build ${buildId}...`);
  }

  viewBuildLogs(buildId) {
    console.log(`Viewing logs for build ${buildId}...`);
  }


  async toggleModule(addonName, moduleName, shouldLink) {
    if (!this.props.client) return;
    
    const { baseName } = this.parseClientInfo();
    
    try {
      if (shouldLink) {
        // Link the module
        await dataService.linkModule(baseName, addonName, moduleName);
        console.log(`Linked module ${moduleName} from ${addonName}`);
      } else {
        // Unlink the module
        await dataService.unlinkModule(baseName, addonName, moduleName);
        console.log(`Unlinked module ${moduleName} from ${addonName}`);
      }
      
      // Reload addons data to reflect changes
      this.state.addons = await dataService.getClientAddons(baseName);
      
      // Update Git status to show commit button if there are changes
      try {
        this.state.gitStatus = await dataService.getClientGitStatus(baseName);
      } catch (error) {
        console.error('Error loading Git status:', error);
      }
    } catch (error) {
      console.error(`Error toggling module ${moduleName}:`, error);
      // Revert checkbox state on error
      await this.loadTabData();
    }
  }

  getDockerComposeStatus() {
    if (!this.props.client) return 'No client selected';
    
    return `NAME                     IMAGE                           STATUS
odoo-${this.props.client.name}         odoo:18.0                   Up 2 hours (healthy)
postgresql-${this.props.client.name}   postgres:15                 Up 2 hours (healthy)`;
  }

  showCommitDialog() {
    this.state.showCommitDialog = true;
  }

  cancelCommit() {
    this.state.showCommitDialog = false;
    this.state.commitMessage = 'Update module configuration'; // Reset to default
  }

  async confirmCommit() {
    if (!this.props.client || !this.state.commitMessage.trim()) return;
    
    const { baseName } = this.parseClientInfo();
    
    try {
      this.state.loading = true;
      this.state.showCommitDialog = false;
      
      const commitResult = await dataService.commitClientChanges(
        baseName, 
        this.state.commitMessage.trim()
      );
      
      if (commitResult.success) {
        console.log(`✅ Changes committed: ${commitResult.message}`);
        
        // Reload Git status
        this.state.gitStatus = await dataService.getClientGitStatus(baseName);
        
        // Show success message
        this.showCommitMessage('Changes committed successfully!', 'success');
        
        // Reset commit message for next time
        this.state.commitMessage = 'Update module configuration';
      } else {
        console.error('Failed to commit:', commitResult.error);
        this.showCommitMessage(`Failed to commit: ${commitResult.error}`, 'error');
      }
    } catch (error) {
      console.error('Error committing changes:', error);
      this.showCommitMessage(`Error: ${error.message}`, 'error');
    } finally {
      this.state.loading = false;
    }
  }

  async commitChanges() {
    // Keep the old method for backward compatibility, but redirect to dialog
    this.showCommitDialog();
  }

  showCommitMessage(message, type = 'info') {
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