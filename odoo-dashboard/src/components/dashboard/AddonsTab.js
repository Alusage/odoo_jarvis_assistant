import { Component, xml } from "@odoo/owl";

export class AddonsTab extends Component {
  static template = xml`
    <div class="h-full overflow-y-auto p-6">
      <!-- Header with Git status and actions -->
      <div class="mb-6 p-4 bg-gray-50 rounded-lg border">
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-lg font-semibold text-gray-900">Module Management</h2>
            <p class="text-sm text-gray-600">Manage linked modules for this client</p>
          </div>
          <div class="flex items-center space-x-3">
            <div t-if="props.gitStatus" class="text-sm">
              <div class="flex items-center space-x-2">
                <span class="font-medium">Branch:</span>
                
                <!-- Branch name display mode -->
                <div t-if="!props.editingBranch" class="flex items-center space-x-1">
                  <span class="font-mono text-primary-600" t-esc="props.gitStatus.current_branch"/>
                  <button 
                    class="text-gray-400 hover:text-gray-600 p-1" 
                    t-on-click="props.onStartEditingBranch"
                    title="Rename branch">
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/>
                    </svg>
                  </button>
                </div>
                
                <!-- Branch name edit mode -->
                <div t-if="props.editingBranch" class="flex items-center space-x-2">
                  <input 
                    type="text" 
                    class="text-sm border border-gray-300 rounded px-2 py-1 font-mono text-primary-600"
                    t-model="props.newBranchName"
                    t-on-keydown="props.onBranchNameKeydown"
                    t-ref="branchInput"
                    placeholder="New branch name"/>
                  <button 
                    class="text-green-600 hover:text-green-700 p-1" 
                    t-on-click="props.onSaveBranchName"
                    title="Save">
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                    </svg>
                  </button>
                  <button 
                    class="text-red-600 hover:text-red-700 p-1" 
                    t-on-click="props.onCancelEditingBranch"
                    title="Cancel">
                    <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                    </svg>
                  </button>
                </div>
              </div>
              
              <div class="mt-1">
                <span t-if="props.gitStatus.has_uncommitted_changes" class="text-orange-600">● Uncommitted changes</span>
                <span t-if="props.gitStatus.sync_status === 'up_to_date'" class="text-green-600">✓ Up to date</span>
                <span t-if="props.gitStatus.sync_status === 'behind'" class="text-red-600">↓ Behind remote</span>
                <span t-if="props.gitStatus.sync_status === 'ahead'" class="text-blue-600">↑ Ahead of remote</span>
              </div>
            </div>
            <div t-if="props.gitStatus and props.gitStatus.has_uncommitted_changes" class="flex gap-2">
              <button 
                class="btn-secondary btn-sm" 
                t-on-click="props.onShowDiffDialog"
              >
                <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                </svg>
                Voir le diff
              </button>
              <button 
                class="btn-primary btn-sm" 
                t-on-click="props.onShowCommitDialog"
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
            t-on-click="props.onSyncSubmodules"
            t-att-disabled="props.updatingSubmodules"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
            </svg>
            <span t-if="!props.updatingSubmodules">Sync Submodules</span>
            <span t-if="props.updatingSubmodules">Syncing...</span>
          </button>
          <button 
            class="btn-primary flex items-center space-x-2"
            t-on-click="props.onUpdateAllSubmodules"
            t-att-disabled="props.updatingSubmodules || props.getOutdatedSubmodulesCount() === 0"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16l-4-4m0 0l4-4m-4 4h18"/>
            </svg>
            <span t-esc="'Update All (' + props.getOutdatedSubmodulesCount() + ')'"/>
          </button>
          <button 
            class="btn-success flex items-center space-x-2"
            t-on-click="props.onOpenAddRepoDialog"
            t-att-disabled="props.updatingSubmodules"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
            </svg>
            <span>Add Repository</span>
          </button>
        </div>
      </div>

      <div class="space-y-6">
        <div t-foreach="props.addons" t-as="addon" t-key="addon.name" class="card p-6">
          <div class="flex items-center justify-between mb-4">
            <div>
              <h3 class="text-lg font-semibold text-gray-900" t-esc="addon.name"/>
              <p class="text-sm text-gray-600">
                <span class="font-medium">Branch:</span> <span t-esc="addon.branch"/>
                <span class="ml-4 font-medium">Commit:</span> <span class="font-mono text-xs" t-esc="addon.commit"/>
              </p>
              
              <!-- Submodule update status -->
              <div t-if="props.getSubmoduleStatus(addon.name)" class="mt-2">
                <div t-if="props.getSubmoduleStatus(addon.name).needs_update" class="flex items-center space-x-2">
                  <span class="badge badge-warning">Update Available</span>
                  <span class="text-xs text-gray-500">Latest: <span class="font-mono" t-esc="props.getSubmoduleStatus(addon.name).latest_commit.slice(0,8)"/></span>
                </div>
                <div t-if="!props.getSubmoduleStatus(addon.name).needs_update" class="flex items-center space-x-2">
                  <span class="badge badge-success">Up to Date</span>
                </div>
              </div>
              
              <!-- Dev Mode status -->
              <div class="mt-2">
                <div t-if="props.isDevModeActive(addon.name)" class="flex items-center space-x-2">
                  <span class="badge bg-orange-100 text-orange-800 border-orange-200">🛠️ Dev Mode</span>
                </div>
                <div t-if="!props.isDevModeActive(addon.name)" class="flex items-center space-x-2">
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
                  t-if="props.getSubmoduleStatus(addon.name) and props.getSubmoduleStatus(addon.name).needs_update"
                  class="btn-sm btn-primary flex items-center space-x-1"
                  t-on-click="() => props.onUpdateSubmodule(addon.name)"
                  t-att-disabled="props.updatingSubmodules"
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
                  t-on-click="() => props.onOpenChangeBranchDialog(addon.name, addon.branch)"
                  t-att-disabled="props.updatingSubmodules"
                  title="Change branch"
                >
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"/>
                  </svg>
                  <span>Branch</span>
                </button>
                
                <!-- Dev Mode Toggle button -->
                <button 
                  t-att-class="props.isDevModeActive(addon.name) ? 'btn-sm btn-warning flex items-center space-x-1' : 'btn-sm btn-outline flex items-center space-x-1'"
                  t-on-click="() => props.onToggleDevMode(addon.name)"
                  t-att-disabled="props.togglingDevMode[addon.name] || props.updatingSubmodules"
                  t-att-title="props.isDevModeActive(addon.name) ? 'Switch to Production Mode' : 'Switch to Dev Mode'"
                >
                  <div t-if="props.togglingDevMode[addon.name]" class="animate-spin rounded-full h-3 w-3 border-b-2 border-current"/>
                  <svg t-else="" class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path t-if="props.isDevModeActive(addon.name)" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"/>
                    <path t-else="" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3"/>
                  </svg>
                  <span t-if="props.isDevModeActive(addon.name)">Dev</span>
                  <span t-else="">Dev</span>
                </button>
                
                <!-- Rename dev branch button (only for dev mode) -->
                <button 
                  t-if="props.isDevModeActive(addon.name)"
                  class="btn-sm btn-outline flex items-center space-x-1"
                  t-on-click="() => props.onRenameDevBranch(addon.name)"
                  t-att-disabled="props.updatingSubmodules"
                  title="Rename development branch"
                >
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/>
                  </svg>
                  <span>Rename</span>
                </button>
                
                <!-- Remove repository button -->
                <button 
                  class="btn-sm btn-danger flex items-center space-x-1"
                  t-on-click="() => props.onRemoveRepository(addon.name)"
                  t-att-disabled="props.updatingSubmodules"
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
                  t-on-change="(ev) => props.onToggleModule(addon.name, module.name, ev.target.checked)"
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
      </div>
    </div>
  `;

  static props = {
    gitStatus: { type: Object, optional: true },
    editingBranch: { type: Boolean },
    newBranchName: { type: String },
    updatingSubmodules: { type: Boolean },
    addons: { type: Array },
    togglingDevMode: { type: Object },
    onStartEditingBranch: { type: Function },
    onBranchNameKeydown: { type: Function },
    onSaveBranchName: { type: Function },
    onCancelEditingBranch: { type: Function },
    onShowDiffDialog: { type: Function },
    onShowCommitDialog: { type: Function },
    onSyncSubmodules: { type: Function },
    onUpdateAllSubmodules: { type: Function },
    onOpenAddRepoDialog: { type: Function },
    getOutdatedSubmodulesCount: { type: Function },
    getSubmoduleStatus: { type: Function },
    isDevModeActive: { type: Function },
    getDevModeInfo: { type: Function },
    onUpdateSubmodule: { type: Function },
    onOpenChangeBranchDialog: { type: Function },
    onToggleDevMode: { type: Function },
    onRenameDevBranch: { type: Function },
    onRemoveRepository: { type: Function },
    onToggleModule: { type: Function }
  };
}