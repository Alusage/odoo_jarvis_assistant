import { Component, useState, onMounted, onWillUnmount, useEffect, xml } from "@odoo/owl";
import { CommitHistory } from "./CommitHistory.js";
import { BuildCard } from "./BuildCard.js";
import { Terminal } from "./Terminal.js";
import { ClientsOverview } from "./ClientsOverview.js";
import { 
  DashboardHeader,
  AddonsTab,
  LogsTab,
  CloudronTab,
  SettingsTab,
  CommitDialog
} from "./dashboard/index.js";
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
        <!-- Dashboard Header -->
        <DashboardHeader 
          client="props.client"
          tabs="state.tabs"
          clientStatus="state.clientStatus"
          gitCommand="getGitCloneCommand()"
          getTabClass="getTabClass.bind(this)"
          onTabChange="setActiveTab.bind(this)"
          onClone="cloneRepository.bind(this)"
          onStart="startClient.bind(this)"
          onStop="stopClient.bind(this)"
          onRestart="restartClient.bind(this)"
          onRebuild="rebuildClient.bind(this)"
          onConnect="connectToClient.bind(this)"
          onCopyGitCommand="copyGitCommand.bind(this)"
        />

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
        <div t-if="props.currentTab === 'ADDONS'" class="h-full">
          <AddonsTab
            gitStatus="state.gitStatus"
            editingBranch="state.editingBranch"
            newBranchName="state.newBranchName"
            updatingSubmodules="state.updatingSubmodules"
            addons="state.addons"
            togglingDevMode="state.togglingDevMode"
            onStartEditingBranch="startEditingBranch.bind(this)"
            onBranchNameKeydown="onBranchNameKeydown.bind(this)"
            onSaveBranchName="saveBranchName.bind(this)"
            onCancelEditingBranch="cancelEditingBranch.bind(this)"
            onShowDiffDialog="showDiffDialog.bind(this)"
            onShowCommitDialog="showCommitDialog.bind(this)"
            onSyncSubmodules="syncSubmodules.bind(this)"
            onUpdateAllSubmodules="updateAllSubmodules.bind(this)"
            onOpenAddRepoDialog="openAddRepoDialog.bind(this)"
            getOutdatedSubmodulesCount="getOutdatedSubmodulesCount.bind(this)"
            getSubmoduleStatus="getSubmoduleStatus.bind(this)"
            isDevModeActive="isDevModeActive.bind(this)"
            getDevModeInfo="getDevModeInfo.bind(this)"
            onUpdateSubmodule="updateSubmodule.bind(this)"
            onOpenChangeBranchDialog="openChangeBranchDialog.bind(this)"
            onToggleDevMode="toggleDevMode.bind(this)"
            onRenameDevBranch="promptRenameDevBranch.bind(this)"
            onRemoveRepository="confirmRemoveSubmodule.bind(this)"
            onToggleModule="toggleModule.bind(this)"
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
          
          <div t-if="state.builds.length === 0 and !state.loading" class="text-center py-12">
            <svg class="w-12 h-12 mx-auto text-gray-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
            </svg>
            <p class="text-gray-500">No builds available</p>
          </div>
        </div>

        <!-- Logs Tab -->
        <div t-if="props.currentTab === 'LOGS'" class="h-full">
          <LogsTab
            logs="state.logs"
            onRefreshLogs="refreshLogs.bind(this)"
            onDownloadLogs="downloadLogs.bind(this)"
            getLogLevelClass="getLogLevelClass.bind(this)"
          />
        </div>

        <!-- Cloudron Tab -->
        <div t-if="props.currentTab === 'CLOUDRON'" class="h-full">
          <CloudronTab
            client="props.client"
            cloudronStatus="state.cloudronStatus"
            cloudronConfig="state.cloudronConfig"
            savingConfig="state.savingConfig"
            building="state.building"
            deploying="state.deploying"
            onEnableCloudron="enableCloudron.bind(this)"
            onSaveCloudronConfig="updateCloudronConfig.bind(this)"
            onBuildCloudron="buildCloudronApp.bind(this)"
            onDeployCloudron="deployCloudronApp.bind(this)"
            onBuildAndDeployCloudron="buildAndDeployCloudron.bind(this)"
          />
        </div>

        <!-- Shell Tab -->
        <div t-if="props.currentTab === 'SHELL'" class="h-full p-6">
          <Terminal client="props.client"/>
        </div>

        <!-- Settings Tab -->
        <div t-if="props.currentTab === 'SETTINGS'" class="h-full">
          <SettingsTab
            traefikConfig="state.traefikConfig"
            editingTraefikConfig="state.editingTraefikConfig"
            traefikConfigLoading="state.traefikConfigLoading"
            gitRemoteUrl="state.gitRemoteUrl"
            onStartEditingTraefikConfig="startEditingTraefikConfig.bind(this)"
            onCancelTraefikConfigEdit="cancelTraefikConfigEdit.bind(this)"
            onSaveTraefikConfig="saveTraefikConfig.bind(this)"
            onOpenGitHub="openGitHub.bind(this)"
          />
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
      <CommitDialog
        show="state.showCommitDialog"
        commitMessage="state.commitMessage"
        onCancel="cancelCommit.bind(this)"
        onConfirm="confirmCommit.bind(this)"
      />

      <!-- Diff Dialog -->
      <div t-if="state.showDiffDialog" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div class="bg-white rounded-lg p-6 w-full max-w-4xl h-3/4 mx-4 flex flex-col">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold">Git Diff - Uncommitted Changes</h3>
            <button 
              class="text-gray-400 hover:text-gray-600"
              t-on-click="closeDiffDialog"
            >
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>
          </div>
          
          <div class="flex-1 overflow-y-auto">
            <!-- Loading State -->
            <div t-if="state.diffLoading" class="flex items-center justify-center h-full">
              <div class="text-center">
                <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-500 mx-auto mb-2"/>
                <p class="text-gray-600">Loading diff...</p>
              </div>
            </div>
            
            <!-- Diff Stats -->
            <div t-if="!state.diffLoading and state.diffContent and state.diffContent.stats" class="px-6 py-4 border-b border-gray-200">
              <div class="flex items-center space-x-6">
                <div class="text-sm">
                  <span class="text-gray-500">Files changed:</span>
                  <span class="ml-2 font-medium" t-esc="state.diffContent.stats.files"/>
                </div>
                <div class="text-sm">
                  <span class="text-green-600">+<t t-esc="state.diffContent.stats.insertions"/></span>
                  <span class="ml-2 text-red-600">-<t t-esc="state.diffContent.stats.deletions"/></span>
                </div>
              </div>
            </div>
            
            <!-- Diff Content -->
            <div t-if="!state.diffLoading and state.diffContent and state.diffContent.files and state.diffContent.files.length > 0" class="px-6 py-4">
              <h3 class="text-lg font-medium text-gray-900 mb-4">Changes</h3>
              
              <!-- File Changes -->
              <div class="space-y-4">
                <div t-foreach="state.diffContent.files" t-as="file" t-key="file.filename" class="border border-gray-200 rounded-lg overflow-hidden">
                  <!-- File Header -->
                  <div class="bg-gray-50 px-4 py-3 border-b border-gray-200 cursor-pointer hover:bg-gray-100 transition-colors" 
                       t-on-click="() => this.toggleFileCollapse(file.filename)">
                    <div class="flex items-center justify-between">
                      <div class="flex items-center space-x-3">
                        <svg t-if="!isFileCollapsed(file.filename)" class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
                        </svg>
                        <svg t-if="isFileCollapsed(file.filename)" class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
                        </svg>
                        <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                        </svg>
                        <span class="font-mono text-sm font-medium" t-esc="file.filename"/>
                      </div>
                      <div class="flex items-center space-x-2 text-sm">
                        <span class="text-green-600">+<t t-esc="file.additions"/></span>
                        <span class="text-red-600">-<t t-esc="file.deletions"/></span>
                      </div>
                    </div>
                  </div>

                  <!-- File Diff -->
                  <div t-if="!isFileCollapsed(file.filename)" class="font-mono text-sm">
                    <div t-foreach="file.hunks" t-as="hunk" t-key="hunk_index" class="border-b border-gray-100 last:border-b-0">
                      <!-- Hunk Header -->
                      <div class="bg-blue-50 px-4 py-2 text-blue-800 border-b border-blue-100">
                        <t t-esc="hunk.header"/>
                      </div>
                      
                      <!-- Hunk Lines -->
                      <div class="divide-y divide-gray-100">
                        <div t-foreach="hunk.lines" t-as="line" t-key="line_index" 
                             t-att-class="getDiffLineClass(line.type)"
                             class="px-4 py-1 hover:bg-gray-50">
                          <div class="flex">
                            <span class="w-16 text-gray-400 text-right mr-4 select-none" t-esc="line.lineNumber"/>
                            <span class="flex-1" t-esc="line.content"/>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            
            <!-- No Changes -->
            <div t-if="!state.diffLoading and state.diffContent and (!state.diffContent.files || state.diffContent.files.length === 0)" class="flex items-center justify-center h-full">
              <div class="text-center">
                <svg class="w-12 h-12 mx-auto text-gray-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                </svg>
                <p class="text-gray-500">No changes to display</p>
              </div>
            </div>
          </div>
          
          <div class="flex justify-between items-center mt-4 pt-4 border-t">
            <button 
              class="btn-secondary"
              t-on-click="closeDiffDialog"
            >
              Close
            </button>
            <button 
              class="btn-primary"
              t-on-click="showCommitFromDiff"
            >
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3-3m0 0l-3 3m3-3v12"/>
              </svg>
              Commit These Changes
            </button>
          </div>
        </div>
      </div>
      
      <!-- Add Repository Dialog -->
      <div t-if="state.showAddRepoDialog" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div class="bg-white rounded-lg p-6 w-[600px] max-w-full mx-4">
          <h3 class="text-lg font-semibold mb-4">Add Repository</h3>
          
          <!-- Repository Type Selection -->
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">Repository Type</label>
            <div class="flex space-x-4">
              <label class="flex items-center">
                <input 
                  type="radio" 
                  name="repoType" 
                  value="oca" 
                  t-model="state.addRepoType"
                  class="mr-2"
                />
                <span>OCA Module</span>
              </label>
              <label class="flex items-center">
                <input 
                  type="radio" 
                  name="repoType" 
                  value="external" 
                  t-model="state.addRepoType"
                  class="mr-2"
                />
                <span>External Repository</span>
              </label>
            </div>
          </div>

          <!-- OCA Module Selection -->
          <div t-if="state.addRepoType === 'oca'" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Search OCA Modules
                <span t-if="state.selectedOcaModules.length > 0" class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-primary-100 text-primary-800">
                  <span t-esc="state.selectedOcaModules.length"/> selected
                </span>
              </label>
              <input 
                type="text" 
                class="input w-full"
                placeholder="Search modules..."
                t-model="state.ocaModulesSearch"
                t-on-input="searchOcaModules"
              />
            </div>
            
            <div class="max-h-60 overflow-y-auto border rounded-lg">
              <div t-if="state.loadingOcaModules" class="p-4 text-center">
                <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-primary-500 mx-auto mb-2"/>
                <p class="text-gray-600">Loading modules...</p>
              </div>
              
              <div t-if="!state.loadingOcaModules" class="space-y-1">
                <div 
                  t-foreach="state.availableOcaModules" 
                  t-as="module" 
                  t-key="module.key"
                  t-attf-class="p-3 hover:bg-gray-50 cursor-pointer border-b border-gray-100 select-none {{ state.selectedOcaModules.includes(module.key) ? 'bg-primary-50 border-primary-200' : '' }}"
                  style="user-select: none; pointer-events: auto;"
                  t-on-click="_toggleOcaModule"
                  t-att-data-module="module.key"
                >
                  <div class="flex items-start space-x-3">
                    <input 
                      type="checkbox" 
                      t-att-checked="state.selectedOcaModules.includes(module.key)"
                      class="mt-1 h-4 w-4 text-primary-600 focus:ring-primary-500 border-gray-300 rounded"
                      readonly="true"
                    />
                    <div class="flex-1">
                      <div class="font-medium text-gray-900" t-esc="module.key"/>
                      <div class="text-sm text-gray-600" t-esc="module.description"/>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- External Repository Form -->
          <div t-if="state.addRepoType === 'external'" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Repository URL</label>
              <input 
                type="url" 
                class="input w-full"
                placeholder="https://github.com/user/repository.git"
                t-model="state.externalRepoUrl"
              />
            </div>
            
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Repository Name</label>
              <input 
                type="text" 
                class="input w-full"
                placeholder="repository-name"
                t-model="state.externalRepoName"
              />
            </div>
          </div>

          <!-- Branch Selection (Common) -->
          <div class="mt-4">
            <label class="block text-sm font-medium text-gray-700 mb-2">Branch (Optional)</label>
            <input 
              type="text" 
              class="input w-full"
              placeholder="Leave empty to use default branch"
              t-model="state.selectedRepoBranch"
            />
          </div>
          
          <div class="flex justify-end space-x-3 mt-6">
            <button class="btn-secondary" t-on-click="closeAddRepoDialog">Cancel</button>
            <button 
              class="btn-primary" 
              t-on-click="confirmAddRepository"
              t-att-disabled="!canAddRepository() or state.addingRepository"
            >
              <div t-if="state.addingRepository" class="flex items-center space-x-2">
                <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-white"/>
                <span>Adding...</span>
              </div>
              <div t-else="" class="flex items-center">
                <span t-if="state.addRepoType === 'oca' and state.selectedOcaModules.length > 1">
                  Add <span t-esc="state.selectedOcaModules.length"/> Repositories
                </span>
                <span t-else="">Add Repository</span>
              </div>
            </button>
          </div>
        </div>
      </div>

      <!-- Change Branch Dialog -->
      <div t-if="state.showChangeBranchDialog" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div class="bg-white rounded-lg p-6 w-96 max-w-full mx-4">
          <h3 class="text-lg font-semibold mb-4">Change Repository Branch</h3>
          
          <div class="mb-4">
            <p class="text-sm text-gray-600 mb-3">
              Repository: <span class="font-medium" t-esc="state.changeBranchRepoName"/>
            </p>
            <p class="text-sm text-gray-600 mb-3">
              Current branch: <span class="font-medium" t-esc="state.changeBranchCurrentBranch"/>
            </p>
          </div>
          
          <div class="mb-4">
            <div class="flex items-center justify-between mb-2">
              <label class="block text-sm font-medium text-gray-700">New Branch</label>
              <button 
                type="button"
                class="text-sm text-primary-600 hover:text-primary-700 flex items-center gap-1"
                t-on-click="refreshBranchList"
                t-att-disabled="state.changeBranchLoading"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                </svg>
                <span>Refresh</span>
              </button>
            </div>
            <div t-if="state.changeBranchLoading" class="flex items-center justify-center py-4">
              <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-primary-500"></div>
              <span class="ml-2 text-gray-600">Loading branches...</span>
            </div>
            <select 
              t-if="!state.changeBranchLoading"
              class="input w-full"
              t-model="state.changeBranchNewBranch"
              t-att-disabled="state.changeBranchAvailableBranches.length === 0"
            >
              <option value="" disabled="">Select a branch</option>
              <option 
                t-foreach="state.changeBranchAvailableBranches" 
                t-as="branch" 
                t-key="branch"
                t-att-value="branch"
                t-att-selected="branch === state.changeBranchNewBranch"
                t-esc="branch"
              />
            </select>
            <p t-if="!state.changeBranchLoading and state.changeBranchAvailableBranches.length === 0" class="text-sm text-red-600 mt-1">
              No branches found
            </p>
          </div>
          
          <div class="flex justify-end space-x-3">
            <button class="btn-secondary" t-on-click="closeChangeBranchDialog">Cancel</button>
            <button 
              class="btn-primary" 
              t-on-click="confirmChangeBranch"
              t-att-disabled="state.changeBranchLoading || !state.changeBranchNewBranch || state.changeBranchNewBranch === state.changeBranchCurrentBranch"
            >
              Change Branch
            </button>
          </div>
        </div>
      </div>
      </div>
      
    </div>
  `;
  
  static components = { 
    CommitHistory, 
    BuildCard, 
    Terminal, 
    ClientsOverview,
    DashboardHeader,
    AddonsTab,
    LogsTab,
    CloudronTab,
    SettingsTab,
    CommitDialog
  };

  setup() {
    this.state = useState({
      tabs: [
        { id: 'HISTORY', label: 'HISTORY' },
        { id: 'ADDONS', label: 'ADDONS' },
        { id: 'BUILDS', label: 'BUILDS' },
        { id: 'LOGS', label: 'LOGS' },
        { id: 'SHELL', label: 'SHELL' },
        { id: 'CLOUDRON', label: 'CLOUDRON' },
        { id: 'SETTINGS', label: 'SETTINGS' }
      ],
      commits: [],
      addons: [],
      submodulesStatus: [],
      updatingSubmodules: false,
      addingRepository: false,
      showAddRepoDialog: false,
      addRepoType: 'oca', // 'oca' or 'external'
      availableOcaModules: [],
      loadingOcaModules: false,
      ocaModulesSearch: '',
      selectedOcaModules: [], // Array for multiple selection
      externalRepoUrl: '',
      externalRepoName: '',
      selectedRepoBranch: '',
      showChangeBranchDialog: false,
      changeBranchRepoName: '',
      changeBranchCurrentBranch: '',
      changeBranchNewBranch: '',
      changeBranchAvailableBranches: [],
      changeBranchLoading: false,
      builds: [],
      logs: [],
      loading: false,
      clientStatus: { status: 'unknown' },
      gitStatus: null,
      editingBranch: false,
      newBranchName: '',
      commitMessage: 'Update module configuration',
      showCommitDialog: false,
      showDiffDialog: false,
      diffContent: null,
      diffLoading: false,
      collapsedFiles: new Set(),
      // Traefik configuration
      traefikConfig: { domain: 'local', protocol: 'http' },
      editingTraefikConfig: false,
      traefikConfigLoading: false,
      // Dev mode management
      devModeStatus: {}, // repo_name -> { mode: 'dev'|'production', dev_branch?: string, created_at?: string }
      togglingDevMode: {}, // repo_name -> boolean
      // Cloudron publication
      cloudronStatus: { cloudron_enabled: false, current_branch: '', is_production_branch: false },
      cloudronConfig: {
        server: 'https://my.cloudron.me',
        domain: 'localhost',
        subdomain: '',
        docker_registry: 'docker.io/username',
        contact_email: 'admin@example.com',
        author_name: 'Admin',
        app_id: '',
        docker_username: '',
        docker_password: '',
        cloudron_token: ''
      },
      savingConfig: false,
      building: false,
      deploying: false,
      gitRemoteUrl: ''
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
      // First load Git status to get current branch
      const baseName = this.props.client.name.split('-')[0]; // Get base name before parsing
      
      try {
        const previousGitStatus = this.state.gitStatus;
        this.state.gitStatus = await dataService.getClientGitStatus(baseName);
        
        // Check if branch has changed since last load
        if (previousGitStatus && this.state.gitStatus && 
            previousGitStatus.current_branch !== this.state.gitStatus.current_branch) {
          console.log(`Branch changed from ${previousGitStatus.current_branch} to ${this.state.gitStatus.current_branch}`);
          // Auto-update submodules when branch changes
          this.updateSubmodulesAfterBranchChange(baseName);
        }
      } catch (error) {
        console.error('Error loading Git status:', error);
        this.state.gitStatus = null;
      }
      
      // Now extract base client name and current branch (using Git status)
      const { baseName: finalBaseName, branchName } = this.parseClientInfo();
      
      console.log(`Loading status for client: ${finalBaseName}, branch: ${branchName}`);
      this.state.clientStatus = await dataService.getClientStatus(finalBaseName, branchName);
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
    
    // Use actual Git branch name if available (this is the real current branch)
    if (this.state.gitStatus && this.state.gitStatus.current_branch) {
      branchName = this.state.gitStatus.current_branch;
    }
    // Otherwise use branch name from client data if available
    else if (this.props.client.branch && this.props.client.branch !== '18.0') {
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
          // Load submodules status
          await this.loadSubmodulesStatus();
          // Load dev mode status
          await this.loadDevModeStatus();
          break;
        case 'BUILDS':
          this.state.builds = await dataService.getBuildHistory(baseName, branchName);
          break;
        case 'LOGS':
          await this.loadLogs();
          break;
        case 'SHELL':
          // Terminal component handles its own initialization
          break;
        case 'CLOUDRON':
          await this.loadCloudronData();
          break;
        case 'SETTINGS':
          await this.loadTraefikConfig();
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
      console.log('Loading logs for:', baseName, branchName);
      
      const rawLogs = await dataService.getClientLogs(baseName, branchName, 'odoo', 50);
      console.log('Raw logs received:', rawLogs);
      
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
        const mcpResult = await dataService.callMCPServer('start_client', {
          client: baseName
        });
        result = { success: true, result: mcpResult };
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
        const mcpResult = await dataService.callMCPServer('stop_client', {
          client: baseName
        });
        result = { success: true, result: mcpResult };
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
        const mcpResult = await dataService.callMCPServer('restart_client', {
          client: baseName
        });
        result = { success: true, result: mcpResult };
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
      
      console.log(`Rebuilding Docker image for client ${baseName}, branch ${branchName}...`);
      
      // Use the new branch-specific Docker build system
      const result = await dataService.callMCPServer('build_client_branch_docker', {
        client: baseName,
        branch: branchName || 'main',
        force: true,  // Force rebuild
        no_cache: false
      });
      
      // Check if the MCP call was successful
      if (result && result.success !== false) {
        console.log(`✅ Docker image rebuilt successfully for ${baseName}:${branchName || 'main'}`);
        
        // Show success message - check for success indicators in the response
        const responseText = result.content || result.text || JSON.stringify(result);
        if (responseText.includes('✅') || responseText.includes('succès') || responseText.includes('success')) {
          console.log(`✅ Docker image rebuilt: odoo-alusage-${baseName}:${branchName || 'main'}`);
          
          // Reload client status and data
          await this.loadClientStatus();
          await this.loadTabData();
          
          // Notify parent to refresh Docker statuses in sidebar
          if (this.props.onDockerStatusChange) {
            await this.props.onDockerStatusChange();
          }
        } else {
          console.warn('Build completed but success not confirmed:', responseText);
        }
      } else {
        const errorMsg = result?.error || result?.message || 'Unknown error occurred';
        console.error('Failed to rebuild Docker image:', errorMsg);
        console.error(`❌ Failed to rebuild Docker image: ${errorMsg}`);
      }
    } catch (error) {
      console.error('Error rebuilding Docker image:', error);
      console.error(`❌ Error rebuilding Docker image: ${error.message}`);
    } finally {
      this.state.loading = false;
    }
  }

  connectToClient() {
    if (!this.props.client) return;
    
    const { baseName, branchName } = this.parseClientInfo();
    
    let url;
    if (branchName && branchName !== '18.0') {
      // Clean branch name (replace non-alphanumeric with dashes, like in deploy script)
      const cleanBranch = branchName.replace(/[^a-zA-Z0-9]/g, '-');
      // For branch deployments, construct URL from Traefik pattern
      url = `http://${cleanBranch}.${baseName}.local`;
    } else {
      // For default/production deployments, use client URL or fallback
      url = this.props.client.url || `http://${baseName}.localhost`;
    }
    
    console.log(`Opening client URL: ${url}`);
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
      const result = await dataService.callMCPServer('rename_client_branch', {
        client: baseName,
        old_branch: oldBranchName,
        new_branch: newBranchName
      });
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

  async showDiffDialog() {
    this.state.showDiffDialog = true;
    this.state.diffLoading = true;
    this.state.diffContent = null;
    this.state.collapsedFiles = new Set();
    
    await this.loadDiff();
  }

  closeDiffDialog() {
    this.state.showDiffDialog = false;
    this.state.diffContent = null;
    this.state.collapsedFiles = new Set();
  }

  showCommitFromDiff() {
    this.closeDiffDialog();
    this.showCommitDialog();
  }

  async loadDiff() {
    if (!this.props.client) return;
    
    const { baseName, branchName } = this.parseClientInfo();
    
    try {
      const diffResult = await dataService.getClientDiff(baseName, branchName);
      this.state.diffContent = diffResult;
    } catch (error) {
      console.error('Error loading diff:', error);
      this.state.diffContent = {
        files: [],
        stats: { files: 0, insertions: 0, deletions: 0 },
        raw: `Error loading diff: ${error.message}`
      };
    } finally {
      this.state.diffLoading = false;
    }
  }

  toggleFileCollapse(filename) {
    if (this.state.collapsedFiles.has(filename)) {
      this.state.collapsedFiles.delete(filename);
    } else {
      this.state.collapsedFiles.add(filename);
    }
    // Force re-render
    this.state.collapsedFiles = new Set(this.state.collapsedFiles);
  }

  isFileCollapsed(filename) {
    return this.state.collapsedFiles.has(filename);
  }

  getDiffLineClass(lineType) {
    switch (lineType) {
      case 'added':
        return 'bg-green-50 border-l-4 border-green-400';
      case 'removed':
        return 'bg-red-50 border-l-4 border-red-400';
      case 'context':
        return 'bg-white';
      default:
        return 'bg-gray-50';
    }
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

  // Traefik Configuration Methods
  async loadTraefikConfig() {
    try {
      const config = await dataService.getTraefikConfig();
      if (config && config.content) {
        const parsed = JSON.parse(config.content);
        this.state.traefikConfig = {
          domain: parsed.domain || 'local',
          protocol: parsed.protocol || 'http'
        };
      } else {
        this.state.traefikConfig = config || { domain: 'local', protocol: 'http' };
      }
      
      // Update dataService with current config
      dataService.traefikDomain = this.state.traefikConfig.domain;
      dataService.mcpServerURL = `http://mcp.${this.state.traefikConfig.domain}`;
      
    } catch (error) {
      console.error('Error loading Traefik config:', error);
      // Keep default values if loading fails
    }
  }

  startEditingTraefikConfig() {
    this.state.editingTraefikConfig = true;
  }

  cancelTraefikConfigEdit() {
    this.state.editingTraefikConfig = false;
    // Reload original config
    this.loadTraefikConfig();
  }

  async saveTraefikConfig() {
    this.state.traefikConfigLoading = true;
    
    try {
      // Save the configuration
      const result = await dataService.setTraefikConfig(
        this.state.traefikConfig.domain,
        this.state.traefikConfig.protocol
      );
      
      if (result.success) {
        this.state.editingTraefikConfig = false;
        this.showCommitMessage('Traefik configuration updated successfully', 'success');
        
        // Restart active branch services
        await this.restartActiveBranchServices();
      } else {
        this.showCommitMessage(`Failed to update configuration: ${result.error}`, 'error');
      }
    } catch (error) {
      console.error('Error saving Traefik config:', error);
      this.showCommitMessage(`Error saving configuration: ${error.message}`, 'error');
    } finally {
      this.state.traefikConfigLoading = false;
    }
  }

  async restartActiveBranchServices() {
    try {
      const { baseName, branchName } = this.parseClientInfo();
      
      if (branchName) {
        this.showCommitMessage('Restarting branch services with new configuration...', 'info');
        
        // Stop current branch service
        await dataService.stopClientBranch(baseName, branchName);
        
        // Wait a moment
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        // Start with new configuration
        await dataService.startClientBranch(baseName, branchName, false);
        
        this.showCommitMessage('Branch services restarted successfully', 'success');
      }
    } catch (error) {
      console.error('Error restarting services:', error);
      this.showCommitMessage(`Error restarting services: ${error.message}`, 'error');
    }
  }

  openGitHub() {
    if (this.state.gitRemoteUrl) {
      // Convert git URL to GitHub URL
      let githubUrl = this.state.gitRemoteUrl;
      
      // Handle SSH URLs
      if (githubUrl.startsWith('git@github.com:')) {
        githubUrl = githubUrl.replace('git@github.com:', 'https://github.com/');
      }
      
      // Remove .git extension
      githubUrl = githubUrl.replace(/\.git$/, '');
      
      // Open in new tab
      window.open(githubUrl, '_blank');
    }
  }

  // ===========================
  // Submodules Management
  // ===========================

  async loadSubmodulesStatus() {
    try {
      const { baseName } = this.parseClientInfo();
      if (!baseName) return;

      const result = await dataService.checkSubmodulesStatus(baseName);
      if (result && result.success) {
        this.state.submodulesStatus = result.submodules || [];
      } else {
        // Log the error only if it exists and is meaningful
        if (result && result.error && result.error !== 'undefined') {
          console.error('Error loading submodules status:', result.error);
        }
        this.state.submodulesStatus = [];
      }
    } catch (error) {
      console.error('Error loading submodules status:', error);
      this.state.submodulesStatus = [];
    }
  }

  getSubmoduleStatus(addonName) {
    // Find submodule status by matching addon name with submodule path
    return this.state.submodulesStatus.find(sub => 
      sub.path === `addons/${addonName}` || sub.path.endsWith(`/${addonName}`)
    );
  }

  getOutdatedSubmodulesCount() {
    return this.state.submodulesStatus.filter(sub => sub.needs_update).length;
  }

  async syncSubmodules() {
    try {
      this.state.updatingSubmodules = true;
      const { baseName } = this.parseClientInfo();
      
      const result = await dataService.updateClientSubmodules(baseName);
      
      if (result.success) {
        this.showCommitMessage('Submodules synchronized successfully', 'success');
        // Reload addons and submodules status
        await this.loadAddons();
        await this.loadSubmodulesStatus();
      } else {
        this.showCommitMessage(`Failed to sync submodules: ${result.error}`, 'error');
      }
    } catch (error) {
      console.error('Error syncing submodules:', error);
      this.showCommitMessage(`Error syncing submodules: ${error.message}`, 'error');
    } finally {
      this.state.updatingSubmodules = false;
    }
  }

  async updateSubmodule(addonName) {
    try {
      this.state.updatingSubmodules = true;
      const { baseName } = this.parseClientInfo();
      const submodulePath = `addons/${addonName}`;
      
      const result = await dataService.updateSubmodule(baseName, submodulePath);
      
      if (result.success) {
        this.showCommitMessage(`Submodule '${addonName}' updated successfully`, 'success');
        // Reload addons and submodules status
        await this.loadAddons();
        await this.loadSubmodulesStatus();
      } else {
        this.showCommitMessage(`Failed to update submodule '${addonName}': ${result.error}`, 'error');
      }
    } catch (error) {
      console.error('Error updating submodule:', error);
      this.showCommitMessage(`Error updating submodule '${addonName}': ${error.message}`, 'error');
    } finally {
      this.state.updatingSubmodules = false;
    }
  }

  async updateAllSubmodules() {
    try {
      this.state.updatingSubmodules = true;
      const { baseName } = this.parseClientInfo();
      
      const result = await dataService.updateAllSubmodules(baseName);
      
      if (result.success) {
        this.showCommitMessage(result.message || 'All submodules updated successfully', 'success');
        // Reload addons and submodules status
        await this.loadAddons();
        await this.loadSubmodulesStatus();
      } else {
        this.showCommitMessage(`Failed to update submodules: ${result.error}`, 'error');
      }
    } catch (error) {
      console.error('Error updating all submodules:', error);
      this.showCommitMessage(`Error updating all submodules: ${error.message}`, 'error');
    } finally {
      this.state.updatingSubmodules = false;
    }
  }

  async loadAddons() {
    try {
      const { baseName } = this.parseClientInfo();
      if (baseName) {
        this.state.addons = await dataService.getClientAddons(baseName);
      }
    } catch (error) {
      console.error('Error loading addons:', error);
      this.state.addons = [];
    }
  }

  // ===========================
  // Dev Mode Management
  // ===========================
  async loadDevModeStatus() {
    try {
      const { baseName } = this.parseClientInfo();
      if (!baseName) return;
      
      const result = await dataService.getDevStatus(baseName);
      if (result.success) {
        this.state.devModeStatus = result.repositories || {};
      } else {
        console.error('Error loading dev mode status:', result.error);
        this.state.devModeStatus = {};
      }
    } catch (error) {
      console.error('Error loading dev mode status:', error);
      this.state.devModeStatus = {};
    }
  }

  async toggleDevMode(repoName) {
    if (this.state.togglingDevMode[repoName]) return;
    
    try {
      this.state.togglingDevMode[repoName] = true;
      const { baseName } = this.parseClientInfo();
      if (!baseName) return;
      
      const result = await dataService.toggleDevMode(baseName, repoName);
      if (result.success) {
        this.showCommitMessage(result.message || 'Dev mode toggled successfully', 'success');
        // Reload dev mode status and addons
        await Promise.all([
          this.loadDevModeStatus(),
          this.loadAddons()
        ]);
      } else {
        this.showCommitMessage(`Failed to toggle dev mode: ${result.error}`, 'error');
      }
    } catch (error) {
      console.error('Error toggling dev mode:', error);
      this.showCommitMessage(`Error toggling dev mode: ${error.message}`, 'error');
    } finally {
      this.state.togglingDevMode[repoName] = false;
    }
  }

  getDevModeInfo(repoName) {
    return this.state.devModeStatus[repoName] || { mode: 'production' };
  }

  isDevModeActive(repoName) {
    const info = this.getDevModeInfo(repoName);
    return info.mode === 'dev';
  }

  // ===========================
  // Repository Management
  // ===========================

  async openAddRepoDialog() {
    this.state.showAddRepoDialog = true;
    this.resetAddRepoForm();
    // Load OCA modules if needed
    if (this.state.addRepoType === 'oca') {
      await this.loadOcaModules();
    }
  }

  closeAddRepoDialog() {
    this.state.showAddRepoDialog = false;
    this.resetAddRepoForm();
  }

  resetAddRepoForm() {
    this.state.addRepoType = 'oca';
    this.state.ocaModulesSearch = '';
    this.state.selectedOcaModules = [];
    this.state.externalRepoUrl = '';
    this.state.externalRepoName = '';
    this.state.selectedRepoBranch = '';
    this.state.availableOcaModules = [];
    this.state.addingRepository = false;
  }

  async loadOcaModules() {
    try {
      this.state.loadingOcaModules = true;
      const { baseName } = this.parseClientInfo();
      const result = await dataService.listAvailableOcaModules(null, baseName);
      if (result.success) {
        this.state.availableOcaModules = result.modules || [];
      } else {
        console.error('Error loading OCA modules:', result.error);
        this.state.availableOcaModules = [];
      }
    } catch (error) {
      console.error('Error loading OCA modules:', error);
      this.state.availableOcaModules = [];
    } finally {
      this.state.loadingOcaModules = false;
    }
  }

  async searchOcaModules() {
    try {
      this.state.loadingOcaModules = true;
      const { baseName } = this.parseClientInfo();
      const result = await dataService.listAvailableOcaModules(this.state.ocaModulesSearch, baseName);
      if (result.success) {
        this.state.availableOcaModules = result.modules || [];
      } else {
        console.error('Error searching OCA modules:', result.error);
      }
    } catch (error) {
      console.error('Error searching OCA modules:', error);
    } finally {
      this.state.loadingOcaModules = false;
    }
  }

  _toggleOcaModule(event) {
    const moduleKey = event.currentTarget.getAttribute('data-module');
    console.log('OCA toggle event triggered, moduleKey:', moduleKey);
    
    if (moduleKey) {
      const currentIndex = this.state.selectedOcaModules.indexOf(moduleKey);
      if (currentIndex === -1) {
        // Add to selection
        this.state.selectedOcaModules.push(moduleKey);
      } else {
        // Remove from selection
        this.state.selectedOcaModules.splice(currentIndex, 1);
      }
      console.log('Selected OCA modules:', this.state.selectedOcaModules);
    } else {
      console.error('No moduleKey found in event target');
    }
  }

  selectOcaModule(moduleKey) {
    this.state.selectedOcaModule = moduleKey;
    console.log('Selected OCA module:', moduleKey);
  }

  canAddRepository() {
    if (this.state.addRepoType === 'oca') {
      return this.state.selectedOcaModules.length > 0;
    } else {
      return this.state.externalRepoUrl && this.state.externalRepoName;
    }
  }

  async confirmAddRepository() {
    console.log('🚀 confirmAddRepository called');
    try {
      this.state.updatingSubmodules = true;
      this.state.addingRepository = true; // New loading state
      const { baseName } = this.parseClientInfo();
      console.log('🚀 Client name:', baseName);
      let result;

      if (this.state.addRepoType === 'oca') {
        console.log('🚀 Adding OCA modules:', this.state.selectedOcaModules);
        // Add multiple OCA modules
        const results = [];
        for (const moduleKey of this.state.selectedOcaModules) {
          console.log('🚀 Adding module:', moduleKey);
          const moduleResult = await dataService.addOcaModuleToClient(
            baseName,
            moduleKey,
            this.state.selectedRepoBranch || null
          );
          console.log('🚀 Module result:', moduleKey, moduleResult);
          results.push({ module: moduleKey, result: moduleResult });
        }
        console.log('🚀 All modules processed, results:', results);
        
        // Combine results
        const successCount = results.filter(r => r.result.success).length;
        const totalCount = results.length;
        
        if (successCount === totalCount) {
          result = {
            success: true,
            message: `Successfully added ${successCount} OCA module(s)`
          };
        } else if (successCount > 0) {
          result = {
            success: true,
            message: `Added ${successCount}/${totalCount} OCA modules (some failed)`
          };
        } else {
          const firstError = results[0]?.result?.error || 'Unknown error';
          result = {
            success: false,
            error: firstError
          };
        }
      } else {
        result = await dataService.addExternalRepoToClient(
          baseName,
          this.state.externalRepoUrl,
          this.state.externalRepoName,
          this.state.selectedRepoBranch || null
        );
      }

      console.log('Add repository result:', result);
      
      if (result && result.success) {
        this.showCommitMessage(result.message || 'Repository added successfully', 'success');
        this.closeAddRepoDialog();
        // Reload addons and submodules status
        await this.loadAddons();
        await this.loadSubmodulesStatus();
      } else {
        const errorMsg = result ? (result.error || result.message || 'Unknown error') : 'No response received';
        this.showCommitMessage(`Failed to add repository: ${errorMsg}`, 'error');
        console.error('Add repository failed:', result);
      }
    } catch (error) {
      console.error('Error adding repository:', error);
      this.showCommitMessage(`Error adding repository: ${error.message}`, 'error');
    } finally {
      this.state.updatingSubmodules = false;
      this.state.addingRepository = false;
    }
  }

  async openChangeBranchDialog(addonName, currentBranch) {
    this.state.showChangeBranchDialog = true;
    this.state.changeBranchRepoName = addonName;
    this.state.changeBranchCurrentBranch = currentBranch;
    this.state.changeBranchNewBranch = currentBranch;
    this.state.changeBranchAvailableBranches = [];
    this.state.changeBranchLoading = true;
    
    // Load available branches
    try {
      const { baseName } = this.parseClientInfo();
      const submodulePath = `addons/${addonName}`;
      const result = await dataService.getSubmoduleBranches(baseName, submodulePath);
      
      if (result.success) {
        this.state.changeBranchAvailableBranches = result.branches;
        // If current branch is not in the list, select the first available branch
        if (!result.branches.includes(currentBranch) && result.branches.length > 0) {
          this.state.changeBranchNewBranch = result.branches[0];
        }
      } else {
        console.error('Failed to load branches:', result.error);
        // Fallback to common branches
        this.state.changeBranchAvailableBranches = ['18.0', '17.0', '16.0', 'master'];
      }
    } catch (error) {
      console.error('Error loading branches:', error);
      // Fallback to common branches
      this.state.changeBranchAvailableBranches = ['18.0', '17.0', '16.0', 'master'];
    } finally {
      this.state.changeBranchLoading = false;
    }
  }

  closeChangeBranchDialog() {
    this.state.showChangeBranchDialog = false;
    this.state.changeBranchRepoName = '';
    this.state.changeBranchCurrentBranch = '';
    this.state.changeBranchNewBranch = '';
    this.state.changeBranchAvailableBranches = [];
    this.state.changeBranchLoading = false;
  }
  
  async refreshBranchList() {
    if (!this.state.changeBranchRepoName || this.state.changeBranchLoading) {
      return;
    }
    
    this.state.changeBranchLoading = true;
    this.state.changeBranchAvailableBranches = [];
    
    try {
      const { baseName } = this.parseClientInfo();
      const submodulePath = `addons/${this.state.changeBranchRepoName}`;
      const result = await dataService.getSubmoduleBranches(baseName, submodulePath);
      
      if (result.success) {
        this.state.changeBranchAvailableBranches = result.branches;
        // Keep current selection if it's still valid
        if (!result.branches.includes(this.state.changeBranchNewBranch)) {
          this.state.changeBranchNewBranch = this.state.changeBranchCurrentBranch;
        }
        this.showCommitMessage('Branch list refreshed successfully', 'success');
      } else {
        console.error('Failed to refresh branches:', result.error);
        this.showCommitMessage('Failed to refresh branch list', 'error');
      }
    } catch (error) {
      console.error('Error refreshing branches:', error);
      this.showCommitMessage('Error refreshing branch list', 'error');
    } finally {
      this.state.changeBranchLoading = false;
    }
  }

  async confirmChangeBranch() {
    try {
      this.state.updatingSubmodules = true;
      const { baseName } = this.parseClientInfo();
      const submodulePath = `addons/${this.state.changeBranchRepoName}`;

      const result = await dataService.changeSubmoduleBranch(
        baseName,
        submodulePath,
        this.state.changeBranchNewBranch
      );

      if (result.success) {
        this.showCommitMessage(result.message || 'Branch changed successfully', 'success');
        this.closeChangeBranchDialog();
        // Reload addons and submodules status
        await this.loadAddons();
        await this.loadSubmodulesStatus();
        // Also reload dev mode status to ensure branch display is updated
        await this.loadDevModeStatus();
        // Force a re-render of the addons tab
        if (this.state.activeTab === 'ADDONS') {
          this.state.activeTab = '';
          await this.nextTick();
          this.state.activeTab = 'ADDONS';
        }
      } else {
        this.showCommitMessage(`Failed to change branch: ${result.error}`, 'error');
      }
    } catch (error) {
      console.error('Error changing branch:', error);
      this.showCommitMessage(`Error changing branch: ${error.message}`, 'error');
    } finally {
      this.state.updatingSubmodules = false;
    }
  }

  async confirmRemoveSubmodule(addonName) {
    if (!confirm(`Are you sure you want to remove the repository "${addonName}"? This action cannot be undone.`)) {
      return;
    }

    try {
      this.state.updatingSubmodules = true;
      const { baseName } = this.parseClientInfo();
      const submodulePath = `addons/${addonName}`;

      const result = await dataService.removeSubmodule(baseName, submodulePath);

      if (result.success) {
        this.showCommitMessage(result.message || 'Repository removed successfully', 'success');
        // Reload addons and submodules status
        await this.loadAddons();
        await this.loadSubmodulesStatus();
      } else {
        this.showCommitMessage(`Failed to remove repository: ${result.error}`, 'error');
      }
    } catch (error) {
      console.error('Error removing repository:', error);
      this.showCommitMessage(`Error removing repository: ${error.message}`, 'error');
    } finally {
      this.state.updatingSubmodules = false;
    }
  }

  /**
   * Prompt user to rename a development branch
   */
  async promptRenameDevBranch(repositoryName) {
    const devInfo = this.getDevModeInfo(repositoryName);
    const currentBranch = devInfo.dev_branch || 'unknown';
    
    const newBranchName = prompt(
      `Rename development branch for repository "${repositoryName}"\n\nCurrent branch: ${currentBranch}\n\nEnter new branch name:`,
      currentBranch.replace(/^dev-\d+\.\d+-\d{8}-\d{6}$/, '')
    );
    
    if (!newBranchName || newBranchName.trim() === '') {
      return;
    }
    
    if (newBranchName === currentBranch) {
      this.showCommitMessage('New branch name must be different from current name', 'warning');
      return;
    }
    
    try {
      this.state.togglingDevMode[repositoryName] = true;
      const { baseName } = this.parseClientInfo();
      
      const result = await dataService.renameDevBranch(baseName, repositoryName, newBranchName);
      
      if (result.success) {
        this.showCommitMessage(result.message || `Development branch renamed to ${newBranchName}`, 'success');
        // Reload dev mode status to reflect the new branch name
        await this.loadDevModeStatus();
      } else {
        this.showCommitMessage(`Failed to rename dev branch: ${result.error}`, 'error');
      }
    } catch (error) {
      console.error('Error renaming dev branch:', error);
      this.showCommitMessage(`Error renaming dev branch: ${error.message}`, 'error');
    } finally {
      this.state.togglingDevMode[repositoryName] = false;
    }
  }

  // Cloudron methods
  async loadCloudronData() {
    if (!this.props.client) return;
    
    try {
      const { baseName } = this.parseClientInfo();
      
      // Load Cloudron status
      const statusResponse = await dataService.getCloudronStatus(baseName);
      if (statusResponse && statusResponse.success && statusResponse.status) {
        this.state.cloudronStatus = statusResponse.status;
      } else if (statusResponse && statusResponse.status) {
        // Direct status without success wrapper
        this.state.cloudronStatus = statusResponse;
      }
      
      // Load Cloudron config if enabled
      if (this.state.cloudronStatus.cloudron_enabled) {
        const configResponse = await dataService.getCloudronConfig(baseName);
        if (configResponse && configResponse.config && configResponse.config.cloudron) {
          this.state.cloudronConfig = { ...this.state.cloudronConfig, ...configResponse.config.cloudron };
        }
      }
    } catch (error) {
      console.error('Error loading Cloudron data:', error);
    }
  }

  async enableCloudron() {
    if (!this.props.client) return;
    
    try {
      const { baseName } = this.parseClientInfo();
      
      // Call the dataService enableCloudron method
      const response = await dataService.enableCloudron(baseName);
      
      if (response && response.success) {
        this.showCommitMessage('Cloudron enabled successfully!', 'success');
        // Reload Cloudron data
        await this.loadCloudronData();
      } else {
        this.showCommitMessage(`Failed to enable Cloudron: ${response.error}`, 'error');
      }
    } catch (error) {
      console.error('Error enabling Cloudron:', error);
      this.showCommitMessage(`Error enabling Cloudron: ${error.message}`, 'error');
    }
  }

  async updateCloudronConfig() {
    if (!this.props.client) return;
    
    try {
      const { baseName } = this.parseClientInfo();
      
      const response = await dataService.updateCloudronConfig(baseName, this.state.cloudronConfig);
      
      if (response && response.success) {
        this.showCommitMessage('Cloudron configuration updated successfully!', 'success');
      } else {
        this.showCommitMessage(`Failed to update Cloudron config: ${response.error}`, 'error');
      }
    } catch (error) {
      console.error('Error updating Cloudron config:', error);
      this.showCommitMessage(`Error updating Cloudron config: ${error.message}`, 'error');
    }
  }

  async buildCloudronApp() {
    if (!this.props.client) return;
    
    try {
      const { baseName } = this.parseClientInfo();
      
      this.showCommitMessage('Building Cloudron application...', 'info');
      
      const response = await dataService.buildCloudronApp(baseName, false);
      
      if (response && response.success) {
        this.showCommitMessage('Cloudron application built successfully!', 'success');
      } else {
        this.showCommitMessage(`Failed to build Cloudron app: ${response.error}`, 'error');
      }
    } catch (error) {
      console.error('Error building Cloudron app:', error);
      this.showCommitMessage(`Error building Cloudron app: ${error.message}`, 'error');
    }
  }

  async deployCloudronApp() {
    if (!this.props.client) return;
    
    try {
      const { baseName } = this.parseClientInfo();
      
      this.showCommitMessage('Deploying Cloudron application...', 'info');
      
      const response = await dataService.deployCloudronApp(baseName, 'install');
      
      if (response && response.success) {
        this.showCommitMessage('Cloudron application deployed successfully!', 'success');
      } else if (response && response.error && response.solution) {
        // Handle interactive terminal requirement
        this.showCommitMessage(`${response.error}\n\nSolution:\n${response.solution}`, 'error');
        
        // Show instructions in a popup or dedicated area
        if (typeof window !== 'undefined' && window.alert) {
          window.alert(`Cloudron Deployment Instructions:\n\n${response.solution}`);
        }
      } else {
        this.showCommitMessage(`Failed to deploy Cloudron app: ${response.error || 'Unknown error'}`, 'error');
      }
    } catch (error) {
      console.error('Error deploying Cloudron app:', error);
      this.showCommitMessage(`Error deploying Cloudron app: ${error.message}`, 'error');
    }
  }

  async buildAndDeployCloudron() {
    if (!this.props.client) return;
    
    try {
      const { baseName } = this.parseClientInfo();
      
      // First build
      this.state.building = true;
      this.showCommitMessage('Building Cloudron application...', 'info');
      
      const buildResponse = await dataService.buildCloudronApp(baseName, false);
      
      if (buildResponse && buildResponse.success) {
        this.showCommitMessage('Build successful! Now deploying...', 'success');
        
        // Then deploy
        this.state.building = false;
        this.state.deploying = true;
        
        const deployResponse = await dataService.deployCloudronApp(baseName, 'install');
        
        if (deployResponse && deployResponse.success) {
          this.showCommitMessage('Cloudron application built and deployed successfully!', 'success');
        } else if (deployResponse && deployResponse.error && deployResponse.solution) {
          this.showCommitMessage(`${deployResponse.error}\n\nSolution:\n${deployResponse.solution}`, 'error');
          if (typeof window !== 'undefined' && window.alert) {
            window.alert(`Cloudron Deployment Instructions:\n\n${deployResponse.solution}`);
          }
        } else {
          this.showCommitMessage(`Failed to deploy: ${deployResponse.error || 'Unknown error'}`, 'error');
        }
      } else {
        this.showCommitMessage(`Failed to build: ${buildResponse.error || 'Unknown error'}`, 'error');
      }
    } catch (error) {
      console.error('Error in build and deploy:', error);
      this.showCommitMessage(`Error: ${error.message}`, 'error');
    } finally {
      this.state.building = false;
      this.state.deploying = false;
    }
  }

}
