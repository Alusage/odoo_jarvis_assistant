import { Component, useState, onMounted, xml } from "@odoo/owl";
import { dataService } from "../services/dataService.js";

export class Settings extends Component {
  static template = xml`
    <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50" t-if="props.isOpen">
      <div class="bg-white rounded-lg shadow-xl max-w-2xl w-full mx-4 max-h-[90vh] overflow-hidden">
        <!-- Header -->
        <div class="flex items-center justify-between p-6 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-900">Settings</h2>
          <button 
            class="p-2 hover:bg-gray-100 rounded-lg transition-colors"
            t-on-click="props.onClose"
          >
            <svg class="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        </div>

        <!-- Content -->
        <div class="p-6 overflow-y-auto max-h-[calc(90vh-120px)]">
          <!-- GitHub Configuration Section -->
          <div class="mb-8">
            <h3 class="text-lg font-medium text-gray-900 mb-4">GitHub Integration</h3>
            <div class="bg-gray-50 rounded-lg p-4 mb-4">
              <div class="flex items-center space-x-2 mb-2">
                <svg class="w-5 h-5 text-gray-600" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
                </svg>
                <span class="text-sm font-medium text-gray-700">GitHub Configuration</span>
                <span t-if="state.github.isConfigured" class="px-2 py-1 text-xs bg-green-100 text-green-800 rounded-full">Configured</span>
                <span t-else="" class="px-2 py-1 text-xs bg-yellow-100 text-yellow-800 rounded-full">Not Configured</span>
              </div>
              <p class="text-sm text-gray-600">Configure GitHub integration to automatically create repositories for new clients.</p>
            </div>

            <form t-on-submit.prevent="saveGitHubConfig" class="space-y-4">
              <!-- GitHub Token -->
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  GitHub Personal Access Token
                </label>
                <div class="relative">
                  <input 
                    type="password" 
                    class="input w-full pr-10"
                    placeholder="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
                    t-model="state.github.token"
                    required=""
                  />
                  <button 
                    type="button"
                    class="absolute inset-y-0 right-0 pr-3 flex items-center"
                    t-on-click="toggleTokenVisibility"
                  >
                    <svg t-if="!state.showToken" class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/>
                    </svg>
                    <svg t-else="" class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.878 9.878L3 3m6.878 6.878L12 12m0 0l3.122 3.122M12 12l6.878-6.878"/>
                    </svg>
                  </button>
                </div>
                <p class="text-xs text-gray-500 mt-1">
                  Create a token at <a href="https://github.com/settings/tokens/new" target="_blank" class="text-blue-500 hover:text-blue-700">GitHub Settings</a>
                  with 'repo' and 'admin:org' permissions.
                </p>
              </div>

              <!-- GitHub Organization -->
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">
                  GitHub Organization
                </label>
                <input 
                  type="text" 
                  class="input w-full"
                  placeholder="Alusage"
                  t-model="state.github.organization"
                  required=""
                />
                <p class="text-xs text-gray-500 mt-1">
                  The GitHub organization where client repositories will be created.
                </p>
              </div>

              <!-- Git User Configuration -->
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Git User Name
                  </label>
                  <input 
                    type="text" 
                    class="input w-full"
                    placeholder="Your Name"
                    t-model="state.github.gitUserName"
                    required=""
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Git User Email
                  </label>
                  <input 
                    type="email" 
                    class="input w-full"
                    placeholder="your.email@example.com"
                    t-model="state.github.gitUserEmail"
                    required=""
                  />
                </div>
              </div>

              <!-- Test Connection Button -->
              <div class="flex items-center space-x-3">
                <button 
                  type="button"
                  class="btn-secondary"
                  t-on-click="testGitHubConnection"
                  t-att-disabled="state.testing || !state.github.token"
                >
                  <svg t-if="state.testing" class="w-4 h-4 mr-2 animate-spin" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
                    <path class="opacity-75" fill="currentColor" d="m4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"/>
                  </svg>
                  <span t-if="state.testing">Testing...</span>
                  <span t-else="">Test Connection</span>
                </button>
                
                <div t-if="state.testResult" class="flex items-center space-x-2">
                  <svg t-if="state.testResult.success" class="w-4 h-4 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"/>
                  </svg>
                  <svg t-else="" class="w-4 h-4 text-red-500" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"/>
                  </svg>
                  <span t-att-class="state.testResult.success ? 'text-green-700' : 'text-red-700'" class="text-sm">
                    <t t-esc="state.testResult.message"/>
                  </span>
                </div>
              </div>

              <!-- Save Button -->
              <div class="flex items-center space-x-3 pt-4">
                <button 
                  type="submit"
                  class="btn-primary"
                  t-att-disabled="state.saving"
                >
                  <svg t-if="state.saving" class="w-4 h-4 mr-2 animate-spin" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
                    <path class="opacity-75" fill="currentColor" d="m4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"/>
                  </svg>
                  <span t-if="state.saving">Saving...</span>
                  <span t-else="">Save GitHub Configuration</span>
                </button>
                
                <div t-if="state.saveResult" class="flex items-center space-x-2">
                  <svg t-if="state.saveResult.success" class="w-4 h-4 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"/>
                  </svg>
                  <svg t-else="" class="w-4 h-4 text-red-500" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"/>
                  </svg>
                  <span t-att-class="state.saveResult.success ? 'text-green-700' : 'text-red-700'" class="text-sm">
                    <t t-esc="state.saveResult.message"/>
                  </span>
                </div>
              </div>
            </form>
          </div>

          <!-- Other Settings Sections -->
          <div class="border-t border-gray-200 pt-6">
            <h3 class="text-lg font-medium text-gray-900 mb-4">General Settings</h3>
            <div class="space-y-4">
              <div class="flex items-center justify-between">
                <div>
                  <label class="text-sm font-medium text-gray-700">Auto-refresh Dashboard</label>
                  <p class="text-xs text-gray-500">Automatically refresh client data every 30 seconds</p>
                </div>
                <label class="toggle">
                  <input type="checkbox" t-model="state.general.autoRefresh"/>
                  <span class="slider"></span>
                </label>
              </div>
              
              <div class="flex items-center justify-between">
                <div>
                  <label class="text-sm font-medium text-gray-700">Show Detailed Logs</label>
                  <p class="text-xs text-gray-500">Display detailed logs in terminal and build outputs</p>
                </div>
                <label class="toggle">
                  <input type="checkbox" t-model="state.general.detailedLogs"/>
                  <span class="slider"></span>
                </label>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  `;

  setup() {
    this.state = useState({
      github: {
        token: '',
        organization: 'Alusage',
        gitUserName: '',
        gitUserEmail: '',
        isConfigured: false
      },
      general: {
        autoRefresh: true,
        detailedLogs: false
      },
      showToken: false,
      testing: false,
      testResult: null,
      saving: false,
      saveResult: null
    });

    onMounted(async () => {
      await this.loadSettings();
    });
  }

  async loadSettings() {
    try {
      // Charger la configuration GitHub existante
      const githubConfig = await dataService.getGitHubConfig();
      if (githubConfig) {
        this.state.github = {
          ...this.state.github,
          ...githubConfig,
          isConfigured: !!(githubConfig.token && githubConfig.organization)
        };
      }
    } catch (error) {
      console.error('Error loading GitHub config:', error);
    }
  }

  toggleTokenVisibility() {
    this.state.showToken = !this.state.showToken;
    const input = document.querySelector('input[type="password"], input[type="text"]');
    if (input) {
      input.type = this.state.showToken ? 'text' : 'password';
    }
  }

  async testGitHubConnection() {
    this.state.testing = true;
    this.state.testResult = null;

    try {
      const result = await dataService.testGitHubConnection({
        token: this.state.github.token,
        organization: this.state.github.organization
      });

      this.state.testResult = {
        success: result.success,
        message: result.success ? 
          `✅ Connected as ${result.username}` : 
          `❌ ${result.error || 'Connection failed'}`
      };
    } catch (error) {
      this.state.testResult = {
        success: false,
        message: `❌ Error: ${error.message}`
      };
    } finally {
      this.state.testing = false;
      
      // Clear test result after 5 seconds
      setTimeout(() => {
        this.state.testResult = null;
      }, 5000);
    }
  }

  async saveGitHubConfig() {
    this.state.saving = true;
    this.state.saveResult = null;

    try {
      const config = {
        token: this.state.github.token,
        organization: this.state.github.organization,
        gitUserName: this.state.github.gitUserName,
        gitUserEmail: this.state.github.gitUserEmail
      };

      const result = await dataService.saveGitHubConfig(config);
      
      if (result.success) {
        this.state.github.isConfigured = true;
        this.state.saveResult = {
          success: true,
          message: '✅ GitHub configuration saved successfully'
        };
      } else {
        throw new Error(result.error || 'Failed to save configuration');
      }
    } catch (error) {
      this.state.saveResult = {
        success: false,
        message: `❌ Error: ${error.message}`
      };
    } finally {
      this.state.saving = false;
      
      // Clear save result after 5 seconds
      setTimeout(() => {
        this.state.saveResult = null;
      }, 5000);
    }
  }
}