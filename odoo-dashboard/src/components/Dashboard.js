import { Component, useState, onMounted, xml } from "@odoo/owl";
import { CommitHistory } from "./CommitHistory.js";
import { BuildCard } from "./BuildCard.js";
import { dataService } from "../services/dataService.js";

export class Dashboard extends Component {
  static template = xml`
    <div class="flex flex-col h-full">
      <!-- Tab Navigation -->
      <div class="border-b border-gray-200 bg-white">
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
            <button class="btn-secondary" t-on-click="rebuildClient">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
              </svg>
              Rebuild
            </button>
            <button class="btn-primary" t-on-click="connectToClient">
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
          <div class="bg-gray-900 rounded-lg h-full overflow-hidden">
            <div class="bg-gray-800 px-4 py-2">
              <h3 class="text-white font-medium">Interactive Shell</h3>
            </div>
            <div class="p-4 h-full overflow-y-auto font-mono text-sm">
              <div t-foreach="state.shellHistory" t-as="entry" t-key="entry_index">
                <div class="text-green-400">
                  <span class="text-gray-500">$</span>
                  <span t-esc="entry.command"/>
                </div>
                <div class="text-gray-300 mb-2" t-esc="entry.output"/>
              </div>
              
              <!-- Command Input -->
              <div class="flex items-center">
                <span class="text-green-400 mr-2">$</span>
                <input 
                  type="text" 
                  class="flex-1 bg-transparent text-green-400 outline-none"
                  placeholder="Enter command..."
                  t-model="state.currentCommand"
                  t-on-keydown="handleShellInput"
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Loading State -->
      <div t-if="state.loading" class="absolute inset-0 bg-white/80 flex items-center justify-center">
        <div class="text-center">
          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-500 mx-auto mb-2"/>
          <p class="text-gray-600">Loading...</p>
        </div>
      </div>
    </div>
  `;
  
  static components = { CommitHistory, BuildCard };

  setup() {
    this.state = useState({
      tabs: [
        { id: 'HISTORY', label: 'HISTORY' },
        { id: 'BUILDS', label: 'BUILDS' },
        { id: 'LOGS', label: 'LOGS' },
        { id: 'SHELL', label: 'SHELL' }
      ],
      commits: [],
      builds: [],
      logs: [],
      shellHistory: [],
      currentCommand: '',
      loading: false
    });

    onMounted(() => {
      this.loadTabData();
    });
  }

  async loadTabData() {
    if (!this.props.client) return;

    this.state.loading = true;
    
    try {
      // Load data based on current tab
      switch (this.props.currentTab) {
        case 'HISTORY':
          this.state.commits = await dataService.getCommitHistory(this.props.client.name);
          break;
        case 'BUILDS':
          this.state.builds = await dataService.getBuildHistory(this.props.client.name);
          break;
        case 'LOGS':
          await this.loadLogs();
          break;
        case 'SHELL':
          this.initializeShell();
          break;
      }
    } catch (error) {
      console.error('Error loading tab data:', error);
    } finally {
      this.state.loading = false;
    }
  }

  async loadLogs() {
    // Simulate log loading
    this.state.logs = [
      {
        timestamp: new Date().toISOString(),
        level: 'INFO',
        message: `Starting Odoo for client ${this.props.client?.name}`
      },
      {
        timestamp: new Date().toISOString(),
        level: 'INFO', 
        message: 'Database connection established'
      },
      {
        timestamp: new Date().toISOString(),
        level: 'INFO',
        message: 'All modules loaded successfully'
      },
      {
        timestamp: new Date().toISOString(),
        level: 'INFO',
        message: 'HTTP server listening on port 8069'
      }
    ];
  }

  initializeShell() {
    this.state.shellHistory = [
      {
        command: 'docker compose ps',
        output: 'NAME                     IMAGE                           COMMAND                  SERVICE                  CREATED        STATUS\nodoo-' + this.props.client?.name + '         odoo:18.0                   "/entrypoint.sh odoo"    odoo                     2 hours ago    Up 2 hours\npostgresql-' + this.props.client?.name + '   postgres:15                 "docker-entrypoint.s…"   postgresql               2 hours ago    Up 2 hours'
      }
    ];
  }

  setActiveTab(tabId) {
    this.props.onTabChange(tabId);
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

  async rebuildClient() {
    if (!this.props.client) return;
    
    this.state.loading = true;
    try {
      // Simulate rebuild process
      console.log(`Rebuilding client ${this.props.client.name}...`);
      await new Promise(resolve => setTimeout(resolve, 2000));
      await this.loadTabData();
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

  handleShellInput(event) {
    if (event.key === 'Enter' && this.state.currentCommand.trim()) {
      const command = this.state.currentCommand.trim();
      
      // Simulate command execution
      this.state.shellHistory.push({
        command: command,
        output: this.executeShellCommand(command)
      });
      
      this.state.currentCommand = '';
    }
  }

  executeShellCommand(command) {
    // Simulate basic shell commands
    const commands = {
      'ls': 'addons  config  data  docker-compose.yml  extra-addons  logs  requirements.txt  scripts',
      'pwd': `/clients/${this.props.client?.name || 'unknown'}`,
      'docker ps': 'CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS   PORTS   NAMES',
      'docker compose ps': this.getDockerComposeStatus(),
      'git status': 'On branch master\nnothing to commit, working tree clean',
      'help': 'Available commands: ls, pwd, docker ps, docker compose ps, git status, help'
    };
    
    return commands[command] || `bash: ${command}: command not found`;
  }

  getDockerComposeStatus() {
    if (!this.props.client) return 'No client selected';
    
    return `NAME                     IMAGE                           STATUS
odoo-${this.props.client.name}         odoo:18.0                   Up 2 hours (healthy)
postgresql-${this.props.client.name}   postgres:15                 Up 2 hours (healthy)`;
  }
}