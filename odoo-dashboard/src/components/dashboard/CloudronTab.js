import { Component, xml } from "@odoo/owl";

export class CloudronTab extends Component {
  static template = xml`
    <div class="h-full overflow-y-auto p-6">
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
            <div t-if="!props.cloudronStatus.cloudron_enabled" class="text-center py-8">
              <div class="text-gray-400 mb-4">
                <svg class="w-12 h-12 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M9 19l3 3m0 0l3-3m-3 3V10"/>
                </svg>
              </div>
              <h4 class="text-lg font-medium text-gray-900 mb-2">Cloudron Not Enabled</h4>
              <p class="text-gray-600 mb-4">Enable Cloudron to deploy this client online</p>
              <button class="btn-primary" t-on-click="props.onEnableCloudron">
                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
                </svg>
                Enable Cloudron
              </button>
            </div>
            
            <div t-if="props.cloudronStatus.cloudron_enabled" class="space-y-6">
              <!-- Status Display -->
              <div class="bg-gray-50 rounded-lg p-4">
                <div class="flex items-center justify-between mb-2">
                  <span class="text-sm font-medium text-gray-700">Status</span>
                  <span t-if="props.cloudronStatus.is_production_branch" class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                    ✓ Production Branch
                  </span>
                  <span t-else="" class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
                    ⚠️ Non-production Branch
                  </span>
                </div>
                <div class="text-sm text-gray-600">
                  <div>Current Branch: <span class="font-mono font-medium" t-esc="props.cloudronStatus.current_branch"/></div>
                  <div t-if="props.cloudronStatus.cloudron_server">Server: <span class="font-mono text-xs" t-esc="props.cloudronStatus.cloudron_server"/></div>
                  <div t-if="props.cloudronStatus.app_id">App ID: <span class="font-mono text-xs" t-esc="props.cloudronStatus.app_id"/></div>
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
                    t-model="props.cloudronConfig.server"
                    placeholder="https://my.cloudron.me"/>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    App ID
                  </label>
                  <input 
                    type="text" 
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    t-model="props.cloudronConfig.app_id"
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
                    t-model="props.cloudronConfig.docker_registry"
                    placeholder="docker.io/username"/>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    Docker Username
                  </label>
                  <input 
                    type="text" 
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    t-model="props.cloudronConfig.docker_username"
                    placeholder="Docker registry username"/>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    Docker Password
                  </label>
                  <input 
                    type="password" 
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    t-model="props.cloudronConfig.docker_password"
                    placeholder="••••••••"/>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    Cloudron CLI Token
                  </label>
                  <input 
                    type="password" 
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    t-model="props.cloudronConfig.cloudron_token"
                    placeholder="••••••••"/>
                </div>
              </div>
              
              <!-- Configuration Actions -->
              <div class="flex justify-end space-x-3">
                <button 
                  class="btn-secondary"
                  t-on-click="props.onSaveCloudronConfig"
                  t-att-disabled="props.savingConfig"
                >
                  <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3-3m0 0l-3 3m3-3v12"/>
                  </svg>
                  <span t-if="!props.savingConfig">Save Configuration</span>
                  <span t-if="props.savingConfig">Saving...</span>
                </button>
              </div>
              
              <!-- Deployment Actions -->
              <div t-if="props.cloudronStatus.is_production_branch" class="mt-8 p-6 bg-blue-50 rounded-lg border border-blue-200">
                <h4 class="text-lg font-semibold text-blue-900 mb-3">Deployment Actions</h4>
                <p class="text-sm text-blue-700 mb-4">
                  You are on the production branch. You can build and deploy to Cloudron.
                </p>
                <div class="flex flex-col sm:flex-row space-y-3 sm:space-y-0 sm:space-x-3">
                  <button 
                    class="btn-primary flex items-center justify-center"
                    t-on-click="props.onBuildCloudron"
                    t-att-disabled="props.building"
                  >
                    <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"/>
                    </svg>
                    <span t-if="!props.building">Build Docker Image</span>
                    <span t-if="props.building">Building...</span>
                  </button>
                  <button 
                    class="btn-success flex items-center justify-center"
                    t-on-click="props.onDeployCloudron"
                    t-att-disabled="props.deploying"
                  >
                    <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"/>
                    </svg>
                    <span t-if="!props.deploying">Deploy to Cloudron</span>
                    <span t-if="props.deploying">Deploying...</span>
                  </button>
                  <button 
                    class="btn-primary flex items-center justify-center"
                    t-on-click="props.onBuildAndDeployCloudron"
                    t-att-disabled="props.building || props.deploying"
                  >
                    <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"/>
                    </svg>
                    <span t-if="!props.building and !props.deploying">Build &amp; Deploy</span>
                    <span t-if="props.building or props.deploying">Processing...</span>
                  </button>
                </div>
              </div>
              
              <div t-else="" class="mt-8 p-6 bg-yellow-50 rounded-lg border border-yellow-200">
                <h4 class="text-lg font-semibold text-yellow-900 mb-3">Non-Production Branch</h4>
                <p class="text-sm text-yellow-700">
                  You are not on the production branch. Cloudron deployment is only available from the production branch.
                  Please switch to the production branch to deploy.
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  `;

  static props = {
    client: { type: Object },
    cloudronStatus: { type: Object },
    cloudronConfig: { type: Object },
    savingConfig: { type: Boolean },
    building: { type: Boolean },
    deploying: { type: Boolean },
    onEnableCloudron: { type: Function },
    onSaveCloudronConfig: { type: Function },
    onBuildCloudron: { type: Function },
    onDeployCloudron: { type: Function },
    onBuildAndDeployCloudron: { type: Function }
  };
}