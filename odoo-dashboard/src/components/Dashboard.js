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
            <!-- Status info -->
            <span t-if="state.clientStatus.status === 'missing'" class="text-xs bg-orange-100 text-orange-800 px-2 py-1 rounded">
              ⚠️ Docker image missing - Build first
            </span>
            <span t-elif="state.clientStatus.status === 'stopped'" class="text-xs bg-yellow-100 text-yellow-800 px-2 py-1 rounded">
              ⏸️ Ready to start
            </span>
            <span t-elif="state.clientStatus.status === 'running'" class="text-xs bg-green-100 text-green-800 px-2 py-1 rounded">
              ✅ Running
            </span>
            <span t-elif="state.clientStatus.status === 'partial'" class="text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded">
              🔄 Partially running
            </span>
            <span t-else="" class="text-xs bg-gray-100 px-2 py-1 rounded" t-esc="'Status: ' + state.clientStatus.status"></span>
            <button class="btn-secondary" t-on-click="cloneRepository">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
              </svg>
              Clone
            </button>
            <button t-if="state.clientStatus.status !== 'running' and state.clientStatus.status !== 'missing'" class="btn-success" t-on-click="startClient">
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
            <button class="btn-secondary" t-on-click="rebuildClient" 
                    t-att-class="state.clientStatus.status === 'missing' ? 'btn-primary' : 'btn-secondary'"
                    t-att-title="state.clientStatus.status === 'missing' ? 'Build Docker image first' : 'Rebuild Docker image'">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"/>
              </svg>
              Rebuild
            </button>
            <button t-if="state.clientStatus.status === 'running' || state.clientStatus.status === 'partial'" class="btn-primary" t-on-click="connectToClient">
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
                <div t-if="state.gitStatus and state.gitStatus.has_uncommitted_changes" class="flex gap-2">
                  <button 
                    class="btn-secondary btn-sm" 
                    t-on-click="showDiffDialog"
                  >
                    <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                    </svg>
                    Voir le diff
                  </button>
                  <button 
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
          </div>
          
          <!-- Submodules management buttons -->
          <div class="flex justify-between items-center mb-6">
            <h3 class="text-lg font-semibold text-gray-900">Addon Repositories</h3>
            <div class="flex space-x-3">
              <button 
                class="btn-secondary flex items-center space-x-2"
                t-on-click="syncSubmodules"
                t-att-disabled="state.updatingSubmodules"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                </svg>
                <span t-if="!state.updatingSubmodules">Sync Submodules</span>
                <span t-if="state.updatingSubmodules">Syncing...</span>
              </button>
              <button 
                class="btn-primary flex items-center space-x-2"
                t-on-click="updateAllSubmodules"
                t-att-disabled="state.updatingSubmodules || getOutdatedSubmodulesCount() === 0"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16l-4-4m0 0l4-4m-4 4h18"/>
                </svg>
                <span t-esc="'Update All (' + getOutdatedSubmodulesCount() + ')'"/>
              </button>
              <button 
                class="btn-success flex items-center space-x-2"
                t-on-click="openAddRepoDialog"
                t-att-disabled="state.updatingSubmodules"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
                </svg>
                <span>Add Repository</span>
              </button>
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
                  <!-- Submodule update status -->
                  <div t-if="getSubmoduleStatus(addon.name)" class="mt-2">
                    <div t-if="getSubmoduleStatus(addon.name).needs_update" class="flex items-center space-x-2">
                      <span class="badge badge-warning">Update Available</span>
                      <span class="text-xs text-gray-500">Latest: <span class="font-mono" t-esc="getSubmoduleStatus(addon.name).latest_commit.slice(0,8)"/></span>
                    </div>
                    <div t-if="!getSubmoduleStatus(addon.name).needs_update" class="flex items-center space-x-2">
                      <span class="badge badge-success">Up to Date</span>
                    </div>
                  </div>
                  <!-- Dev Mode status -->
                  <div class="mt-2">
                    <div t-if="isDevModeActive(addon.name)" class="flex items-center space-x-2">
                      <span class="badge bg-orange-100 text-orange-800 border-orange-200">🛠️ Dev Mode</span>
                      <span t-if="getDevModeInfo(addon.name).dev_branch" class="text-xs text-gray-500">
                        Branch: <span class="font-mono" t-esc="getDevModeInfo(addon.name).dev_branch"/>
                      </span>
                    </div>
                    <div t-if="!isDevModeActive(addon.name)" class="flex items-center space-x-2">
                      <span class="badge bg-blue-100 text-blue-800 border-blue-200">🏭 Production Mode</span>
                    </div>
                  </div>
                </div>
                <div class="flex items-center space-x-2">
                  <span class="badge badge-info" t-esc="addon.url"/>
                  
                  <!-- Repository management buttons -->
                  <div class="flex items-center space-x-1">
                    <!-- Individual pull button for outdated submodules -->
                    <button 
                      t-if="getSubmoduleStatus(addon.name) and getSubmoduleStatus(addon.name).needs_update"
                      class="btn-sm btn-primary flex items-center space-x-1"
                      t-on-click="() => this.updateSubmodule(addon.name)"
                      t-att-disabled="state.updatingSubmodules"
                      title="Pull latest changes"
                    >
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16l-4-4m0 0l4-4m-4 4h18"/>
                      </svg>
                      <span>Pull</span>
                    </button>
                    
                    <!-- Change branch button -->
                    <button 
                      class="btn-sm btn-secondary flex items-center space-x-1"
                      t-on-click="() => this.openChangeBranchDialog(addon.name, addon.branch)"
                      t-att-disabled="state.updatingSubmodules"
                      title="Change branch"
                    >
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"/>
                      </svg>
                      <span>Branch</span>
                    </button>
                    
                    <!-- Dev Mode Toggle button -->
                    <button 
                      t-att-class="isDevModeActive(addon.name) ? 'btn-sm btn-warning flex items-center space-x-1' : 'btn-sm btn-outline flex items-center space-x-1'"
                      t-on-click="() => this.toggleDevMode(addon.name)"
                      t-att-disabled="state.togglingDevMode[addon.name] || state.updatingSubmodules"
                      t-att-title="isDevModeActive(addon.name) ? 'Switch to Production Mode' : 'Switch to Dev Mode'"
                    >
                      <div t-if="state.togglingDevMode[addon.name]" class="animate-spin rounded-full h-3 w-3 border-b-2 border-current"/>
                      <svg t-else="" class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path t-if="isDevModeActive(addon.name)" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"/>
                        <path t-else="" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3"/>
                      </svg>
                      <span t-if="isDevModeActive(addon.name)">Dev Mode</span>
                      <span t-else="">Dev Mode</span>
                    </button>
                    
                    <!-- Rename dev branch button (only for dev mode) -->
                    <button 
                      t-if="isDevModeActive(addon.name)"
                      class="btn-sm btn-secondary flex items-center space-x-1"
                      t-on-click="() => this.promptRenameDevBranch(addon.name)"
                      t-att-disabled="state.togglingDevMode[addon.name] || state.updatingSubmodules"
                      title="Rename development branch"
                    >
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/>
                      </svg>
                      <span>Rename</span>
                    </button>

                    <!-- Remove repository button -->
                    <button 
                      class="btn-sm btn-danger flex items-center space-x-1"
                      t-on-click="() => this.confirmRemoveSubmodule(addon.name)"
                      t-att-disabled="state.updatingSubmodules"
                      title="Remove repository"
                    >
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                      </svg>
                      <span>Remove</span>
                    </button>
                  </div>
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
            
            <div t-if="state.addons.length === 0 and !state.loading" class="text-center py-12">
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
          
          <div t-if="state.builds.length === 0 and !state.loading" class="text-center py-12">
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

        <!-- Cloudron Tab -->
        <div t-if="props.currentTab === 'CLOUDRON'" class="h-full overflow-y-auto p-6">
          <div class="max-w-4xl mx-auto space-y-8">
            <!-- Cloudron Status Section -->
            <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
              <div class="p-6 border-b border-gray-200">
                <h3 class="text-lg font-semibold text-gray-900 flex items-center">
                  <svg class="w-5 h-5 mr-2 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M9 19l3 3m0 0l3-3m-3 3V10"/>
                  </svg>
                  Cloudron Publication
                </h3>
                <p class="text-sm text-gray-600 mt-1">
                  Deploy your Odoo instance to Cloudron.io platform
                </p>
              </div>
              
              <div class="p-6">
                <div t-if="!state.cloudronStatus.cloudron_enabled" class="text-center py-8">
                  <div class="text-gray-400 mb-4">
                    <svg class="w-12 h-12 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M9 19l3 3m0 0l3-3m-3 3V10"/>
                    </svg>
                  </div>
                  <h4 class="text-lg font-medium text-gray-900 mb-2">Cloudron Not Enabled</h4>
                  <p class="text-gray-600 mb-4">Enable Cloudron to deploy this client online</p>
                  <button class="btn-primary" t-on-click="enableCloudron">
                    <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
                    </svg>
                    Enable Cloudron
                  </button>
                </div>
                
                <div t-if="state.cloudronStatus.cloudron_enabled" class="space-y-6">
                  <!-- Status Display -->
                  <div class="bg-gray-50 rounded-lg p-4">
                    <div class="flex items-center justify-between mb-2">
                      <span class="text-sm font-medium text-gray-700">Status</span>
                      <span t-if="state.cloudronStatus.is_production_branch" class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                        ✓ Production Branch
                      </span>
                      <span t-else="" class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
                        ⚠️ Non-production Branch
                      </span>
                    </div>
                    <div class="text-sm text-gray-600">
                      <div>Current Branch: <span class="font-mono font-medium" t-esc="state.cloudronStatus.current_branch"/></div>
                      <div t-if="state.cloudronStatus.cloudron_server">Server: <span class="font-mono text-xs" t-esc="state.cloudronStatus.cloudron_server"/></div>
                      <div t-if="state.cloudronStatus.app_id">App ID: <span class="font-mono text-xs" t-esc="state.cloudronStatus.app_id"/></div>
                    </div>
                  </div>
                  
                  <!-- Configuration Form -->
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Cloudron Server
                      </label>
                      <input 
                        type="text" 
                        class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        t-model="state.cloudronConfig.server"
                        placeholder="https://my.cloudron.me"/>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        App ID
                      </label>
                      <input 
                        type="text" 
                        class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        t-model="state.cloudronConfig.app_id"
                        t-att-placeholder="props.client.name + '.odoo.localhost'"/>
                      <p class="text-xs text-gray-500 mt-1">Full app identifier (e.g., myapp.odoo.localhost or myapp.odoo.mydomain.com)</p>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Docker Registry
                      </label>
                      <input 
                        type="text" 
                        class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        t-model="state.cloudronConfig.docker_registry"
                        placeholder="docker.io/username"/>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Docker Username
                      </label>
                      <input 
                        type="text" 
                        class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        t-model="state.cloudronConfig.docker_username"
                        placeholder="Docker registry username"/>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Docker Password
                      </label>
                      <input 
                        type="password" 
                        class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        t-model="state.cloudronConfig.docker_password"
                        placeholder="Docker registry password"/>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Cloudron Username
                      </label>
                      <input 
                        type="text" 
                        class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        t-model="state.cloudronConfig.cloudron_username"
                        placeholder="Cloudron account username"/>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Cloudron Password
                      </label>
                      <input 
                        type="password" 
                        class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        t-model="state.cloudronConfig.cloudron_password"
                        placeholder="Cloudron account password"/>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Contact Email
                      </label>
                      <input 
                        type="email" 
                        class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        t-model="state.cloudronConfig.contact_email"
                        placeholder="admin@example.com"/>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        Author Name
                      </label>
                      <input 
                        type="text" 
                        class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        t-model="state.cloudronConfig.author_name"
                        placeholder="Admin"/>
                    </div>
                  </div>
                  
                  <div class="flex justify-between">
                    <button class="btn-secondary" t-on-click="updateCloudronConfig">
                      <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3-3m0 0l-3 3m3-3v12"/>
                      </svg>
                      Update Configuration
                    </button>
                    <div class="space-x-3">
                      <button 
                        class="btn-secondary"
                        t-on-click="buildCloudronApp"
                        t-att-disabled="!state.cloudronStatus.is_production_branch"
                      >
                        <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"/>
                        </svg>
                        Build App
                      </button>
                      <button 
                        class="btn-success"
                        t-on-click="deployCloudronApp"
                        t-att-disabled="!state.cloudronStatus.is_production_branch"
                      >
                        <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M9 19l3 3m0 0l3-3m-3 3V10"/>
                        </svg>
                        Deploy
                      </button>
                    </div>
                  </div>
                  
                  <div t-if="!state.cloudronStatus.is_production_branch" class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
                    <div class="flex items-start">
                      <svg class="w-5 h-5 text-yellow-400 mt-0.5 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 15.5c-.77.833.192 2.5 1.732 2.5z"/>
                      </svg>
                      <div>
                        <h4 class="text-sm font-medium text-yellow-800">Production Branch Required</h4>
                        <p class="text-sm text-yellow-700 mt-1">
                          Cloudron deployment is only available on production branches (18.0, master, main). 
                          Switch to a production branch to enable build and deployment.
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Shell Tab -->
        <div t-if="props.currentTab === 'SHELL'" class="h-full p-6">
          <Terminal client="props.client"/>
        </div>

        <!-- Settings Tab -->
        <div t-if="props.currentTab === 'SETTINGS'" class="h-full overflow-y-auto p-6">
          <div class="max-w-4xl mx-auto space-y-8">
            <!-- Traefik Configuration Section -->
            <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
              <div class="p-6 border-b border-gray-200">
                <h3 class="text-lg font-semibold text-gray-900 flex items-center">
                  <svg class="w-5 h-5 mr-2 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/>
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
                  </svg>
                  Traefik Configuration
                </h3>
                <p class="mt-1 text-sm text-gray-500">Configure domain and protocol for branch deployments</p>
              </div>
              
              <div class="p-6">
                <div t-if="!state.editingTraefikConfig" class="space-y-4">
                  <!-- Display current configuration -->
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Domain</label>
                      <div class="text-sm text-gray-900 font-mono bg-gray-50 px-3 py-2 rounded border">
                        <t t-esc="state.traefikConfig.domain"/>
                      </div>
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Protocol</label>
                      <div class="text-sm text-gray-900 font-mono bg-gray-50 px-3 py-2 rounded border">
                        <t t-esc="state.traefikConfig.protocol"/>
                      </div>
                    </div>
                  </div>
                  
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Example Branch URL</label>
                    <div class="text-sm text-blue-600 font-mono bg-blue-50 px-3 py-2 rounded border">
                      <t t-esc="state.traefikConfig.protocol"/>://{branch}.{client}.<t t-esc="state.traefikConfig.domain"/>
                    </div>
                  </div>
                  
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Current MCP Server URL</label>
                    <div class="text-sm text-green-600 font-mono bg-green-50 px-3 py-2 rounded border">
                      <t t-esc="state.traefikConfig.protocol"/>://mcp.<t t-esc="state.traefikConfig.domain"/>
                    </div>
                  </div>
                  
                  <div class="flex justify-between items-center pt-4">
                    <div class="text-xs text-gray-500">
                      <strong>Note:</strong> Add <code class="bg-gray-100 px-1 rounded">127.0.0.1 *.{domain}</code> to your /etc/hosts file
                    </div>
                    <button 
                      class="btn-primary" 
                      t-on-click="startEditingTraefikConfig"
                      t-att-disabled="state.traefikConfigLoading">
                      Edit Configuration
                    </button>
                  </div>
                </div>

                <div t-if="state.editingTraefikConfig" class="space-y-4">
                  <!-- Edit configuration form -->
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Domain</label>
                      <input 
                        type="text" 
                        class="form-input w-full"
                        t-model="state.traefikConfig.domain"
                        placeholder="local, localhost, dev..."
                      />
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Protocol</label>
                      <select class="form-input w-full" t-model="state.traefikConfig.protocol">
                        <option value="http">HTTP</option>
                        <option value="https">HTTPS</option>
                      </select>
                    </div>
                  </div>
                  
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Preview URL</label>
                    <div class="text-sm text-blue-600 font-mono bg-blue-50 px-3 py-2 rounded border">
                      <t t-esc="state.traefikConfig.protocol"/>://{branch}.{client}.<t t-esc="state.traefikConfig.domain"/>
                    </div>
                  </div>
                  
                  <div class="flex justify-end space-x-3 pt-4">
                    <button 
                      class="btn-secondary" 
                      t-on-click="cancelTraefikConfigEdit"
                      t-att-disabled="state.traefikConfigLoading">
                      Cancel
                    </button>
                    <button 
                      class="btn-success" 
                      t-on-click="saveTraefikConfig"
                      t-att-disabled="state.traefikConfigLoading">
                      <span t-if="state.traefikConfigLoading" class="mr-2">
                        <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-white inline-block"/>
                      </span>
                      Save &amp; Restart Services
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <!-- GitHub Integration Section (existing) -->
            <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
              <div class="p-6 border-b border-gray-200">
                <h3 class="text-lg font-semibold text-gray-900 flex items-center">
                  <svg class="w-5 h-5 mr-2 text-gray-700" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 0C4.477 0 0 4.484 0 10.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0110 4.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.203 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.942.359.31.678.921.678 1.856 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0020 10.017C20 4.484 15.522 0 10 0z" clip-rule="evenodd"/>
                  </svg>
                  GitHub Integration
                </h3>
                <p class="mt-1 text-sm text-gray-500">Configure GitHub repository settings</p>
              </div>
              
              <div class="p-6">
                <div class="text-sm text-gray-600">
                  GitHub integration settings will be available in a future update.
                </div>
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
            <label class="block text-sm font-medium text-gray-700 mb-2">New Branch</label>
            <input 
              type="text" 
              class="input w-full"
              placeholder="Enter new branch name"
              t-model="state.changeBranchNewBranch"
            />
          </div>
          
          <div class="flex justify-end space-x-3">
            <button class="btn-secondary" t-on-click="closeChangeBranchDialog">Cancel</button>
            <button 
              class="btn-primary" 
              t-on-click="confirmChangeBranch"
              t-att-disabled="!state.changeBranchNewBranch || state.changeBranchNewBranch === state.changeBranchCurrentBranch"
            >
              Change Branch
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
        author_name: 'Admin'
      },
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

  // ===========================
  // Submodules Management
  // ===========================

  async loadSubmodulesStatus() {
    try {
      const { baseName } = this.parseClientInfo();
      if (!baseName) return;

      const result = await dataService.checkSubmodulesStatus(baseName);
      if (result.success) {
        this.state.submodulesStatus = result.submodules || [];
      } else {
        console.error('Error loading submodules status:', result.error);
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

  openChangeBranchDialog(addonName, currentBranch) {
    this.state.showChangeBranchDialog = true;
    this.state.changeBranchRepoName = addonName;
    this.state.changeBranchCurrentBranch = currentBranch;
    this.state.changeBranchNewBranch = '';
  }

  closeChangeBranchDialog() {
    this.state.showChangeBranchDialog = false;
    this.state.changeBranchRepoName = '';
    this.state.changeBranchCurrentBranch = '';
    this.state.changeBranchNewBranch = '';
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

}