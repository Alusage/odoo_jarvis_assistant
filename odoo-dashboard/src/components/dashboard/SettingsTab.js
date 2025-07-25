import { Component, xml } from "@odoo/owl";

export class SettingsTab extends Component {
  static template = xml`
    <div class="h-full overflow-y-auto p-6">
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
            <div t-if="!props.editingTraefikConfig" class="space-y-4">
              <!-- Display current configuration -->
              <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Domain</label>
                  <div class="text-sm text-gray-900 font-mono bg-gray-50 px-3 py-2 rounded border">
                    <t t-esc="props.traefikConfig.domain"/>
                  </div>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Protocol</label>
                  <div class="text-sm text-gray-900 font-mono bg-gray-50 px-3 py-2 rounded border">
                    <t t-esc="props.traefikConfig.protocol"/>
                  </div>
                </div>
              </div>
              
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Example Branch URL</label>
                <div class="text-sm text-blue-600 font-mono bg-blue-50 px-3 py-2 rounded border">
                  <t t-esc="props.traefikConfig.protocol"/>://{branch}.{client}.<t t-esc="props.traefikConfig.domain"/>
                </div>
              </div>
              
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Current MCP Server URL</label>
                <div class="text-sm text-green-600 font-mono bg-green-50 px-3 py-2 rounded border">
                  <t t-esc="props.traefikConfig.protocol"/>://mcp.<t t-esc="props.traefikConfig.domain"/>
                </div>
              </div>
              
              <div class="flex justify-between items-center pt-4">
                <div class="text-xs text-gray-500">
                  <strong>Note:</strong> Add <code class="bg-gray-100 px-1 rounded">127.0.0.1 *.{domain}</code> to your /etc/hosts file
                </div>
                <button 
                  class="btn-primary" 
                  t-on-click="props.onStartEditingTraefikConfig"
                  t-att-disabled="props.traefikConfigLoading">
                  Edit Configuration
                </button>
              </div>
            </div>

            <div t-if="props.editingTraefikConfig" class="space-y-4">
              <!-- Edit configuration form -->
              <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Domain</label>
                  <input 
                    type="text" 
                    class="form-input w-full"
                    t-model="props.traefikConfig.domain"
                    placeholder="local, localhost, dev..."
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Protocol</label>
                  <select class="form-input w-full" t-model="props.traefikConfig.protocol">
                    <option value="http">HTTP</option>
                    <option value="https">HTTPS</option>
                  </select>
                </div>
              </div>
              
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Preview URL</label>
                <div class="text-sm text-blue-600 font-mono bg-blue-50 px-3 py-2 rounded border">
                  <t t-esc="props.traefikConfig.protocol"/>://{branch}.{client}.<t t-esc="props.traefikConfig.domain"/>
                </div>
              </div>
              
              <div class="flex justify-end space-x-3 pt-4">
                <button 
                  class="btn-secondary" 
                  t-on-click="props.onCancelTraefikConfigEdit"
                  t-att-disabled="props.traefikConfigLoading">
                  Cancel
                </button>
                <button 
                  class="btn-success" 
                  t-on-click="props.onSaveTraefikConfig"
                  t-att-disabled="props.traefikConfigLoading">
                  <span t-if="props.traefikConfigLoading" class="mr-2">
                    <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
                  </span>
                  Save Configuration
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- GitHub Integration Section -->
        <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
          <div class="p-6 border-b border-gray-200">
            <h3 class="text-lg font-semibold text-gray-900 flex items-center">
              <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
              </svg>
              GitHub Integration
            </h3>
            <p class="mt-1 text-sm text-gray-500">Configure GitHub repository settings</p>
          </div>
          
          <div class="p-6">
            <div class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Remote URL</label>
                <div class="text-sm text-gray-900 font-mono bg-gray-50 px-3 py-2 rounded border">
                  <t t-if="props.gitRemoteUrl" t-esc="props.gitRemoteUrl"/>
                  <span t-else="" class="text-gray-500">No remote configured</span>
                </div>
              </div>
              
              <div t-if="props.gitRemoteUrl" class="flex space-x-3">
                <button class="btn-secondary" t-on-click="props.onOpenGitHub">
                  <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/>
                  </svg>
                  Open on GitHub
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  `;

  static props = {
    traefikConfig: { type: Object },
    editingTraefikConfig: { type: Boolean },
    traefikConfigLoading: { type: Boolean },
    gitRemoteUrl: { type: String, optional: true },
    onStartEditingTraefikConfig: { type: Function },
    onCancelTraefikConfigEdit: { type: Function },
    onSaveTraefikConfig: { type: Function },
    onOpenGitHub: { type: Function }
  };
}