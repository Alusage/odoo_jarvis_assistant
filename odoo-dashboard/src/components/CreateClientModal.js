import { Component, useState, onMounted, xml } from "@odoo/owl";
import { dataService } from "../services/dataService.js";

export class CreateClientModal extends Component {
  static template = xml`
    <!-- Create Client Modal -->
    <div t-if="props.isOpen" class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div class="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
        <!-- Header -->
        <div class="flex items-center justify-between p-6 border-b border-gray-200">
          <h2 class="text-xl font-semibold text-gray-900">Create New Client</h2>
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
        <form t-on-submit.prevent="createClient" class="p-6 space-y-4">
          <!-- Client Name -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Client Name
            </label>
            <input 
              type="text" 
              class="input w-full"
              placeholder="my-client-name"
              t-model="state.newClient.name"
              required=""
              pattern="[a-zA-Z0-9_\-]*"
              title="Only letters, numbers, underscore and hyphen allowed"
            />
            <p class="text-xs text-gray-500 mt-1">
              Only letters, numbers, underscore and hyphen allowed
            </p>
          </div>

          <!-- Odoo Version -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Odoo Version
            </label>
            <select class="input w-full" t-model="state.newClient.version">
              <option value="18.0">18.0 (Latest)</option>
              <option value="17.0">17.0</option>
              <option value="16.0">16.0</option>
            </select>
          </div>

          <!-- Template -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Template
            </label>
            <select class="input w-full" t-model="state.newClient.template">
              <option value="basic">Basic - Essential modules</option>
              <option value="ecommerce">E-commerce - Online store ready</option>
              <option value="manufacturing">Manufacturing - Production ready</option>
              <option value="services">Services - Service company ready</option>
              <option value="custom">Custom - Choose your modules</option>
            </select>
          </div>

          <!-- Enterprise -->
          <div class="flex items-center">
            <input 
              type="checkbox" 
              id="enterprise"
              class="h-4 w-4 text-primary-600 border-gray-300 rounded focus:ring-primary-500"
              t-model="state.newClient.hasEnterprise"
            />
            <label for="enterprise" class="ml-2 text-sm text-gray-700">
              Include Odoo Enterprise modules
            </label>
          </div>

          <!-- GitHub Integration Status -->
          <div t-if="state.githubConfigured" class="bg-green-50 border border-green-200 rounded-lg p-3">
            <div class="flex items-center space-x-2">
              <svg class="w-4 h-4 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"/>
              </svg>
              <span class="text-sm text-green-700">GitHub integration enabled - Repository will be created automatically</span>
            </div>
          </div>

          <div t-else="" class="bg-yellow-50 border border-yellow-200 rounded-lg p-3">
            <div class="flex items-center space-x-2">
              <svg class="w-4 h-4 text-yellow-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"/>
              </svg>
              <span class="text-sm text-yellow-700">GitHub not configured - Client will be created locally only</span>
            </div>
          </div>

          <!-- Buttons -->
          <div class="flex items-center space-x-3 pt-4">
            <button 
              type="submit"
              class="btn-primary flex-1"
              t-att-disabled="state.creating"
            >
              <svg t-if="state.creating" class="w-4 h-4 mr-2 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
                <path class="opacity-75" fill="currentColor" d="m4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"/>
              </svg>
              <span t-if="state.creating">Creating...</span>
              <span t-else="">Create Client</span>
            </button>
            
            <button 
              type="button"
              class="btn-secondary"
              t-on-click="props.onClose"
              t-att-disabled="state.creating"
            >
              Cancel
            </button>
          </div>

          <!-- Result Messages -->
          <div t-if="state.createResult" class="mt-4">
            <div t-if="state.createResult.success" class="bg-green-50 border border-green-200 rounded-lg p-3">
              <div class="flex items-start space-x-2">
                <svg class="w-5 h-5 text-green-500 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"/>
                </svg>
                <div>
                  <p class="text-sm font-medium text-green-700">Client created successfully!</p>
                  <p class="text-sm text-green-600 mt-1" t-esc="state.createResult.message"/>
                </div>
              </div>
            </div>
            
            <div t-else="" class="bg-red-50 border border-red-200 rounded-lg p-3">
              <div class="flex items-start space-x-2">
                <svg class="w-5 h-5 text-red-500 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"/>
                </svg>
                <div>
                  <p class="text-sm font-medium text-red-700">Error creating client</p>
                  <p class="text-sm text-red-600 mt-1" t-esc="state.createResult.error"/>
                </div>
              </div>
            </div>
          </div>
        </form>
      </div>
    </div>
  `;

  setup() {
    this.state = useState({
      githubConfigured: false,
      creating: false,
      createResult: null,
      newClient: {
        name: '',
        version: '18.0',
        template: 'basic',
        hasEnterprise: false
      }
    });

    onMounted(async () => {
      await this.checkGitHubConfig();
    });
  }

  async checkGitHubConfig() {
    try {
      const config = await dataService.getGitHubConfig();
      this.state.githubConfigured = !!(config && config.github_token && config.github_organization);
    } catch (error) {
      console.error('Error checking GitHub config:', error);
      this.state.githubConfigured = false;
    }
  }

  async createClient() {
    if (!this.state.newClient.name.trim()) {
      return;
    }

    this.state.creating = true;
    this.state.createResult = null;

    try {
      // Always use create_client_github - it will automatically fall back to normal creation if GitHub is not configured
      console.log('Creating client via MCP server...');
      const mcpResult = await dataService.callMCPServer('create_client_github', {
        name: this.state.newClient.name,
        template: this.state.newClient.template,
        version: this.state.newClient.version,
        has_enterprise: this.state.newClient.hasEnterprise
      });
      console.log('MCP Result:', mcpResult);
      
      // Parse MCP server response - mcpResult has structure: {success, result: {type, content}, error}
      let result;
      if (mcpResult.success && mcpResult.result && mcpResult.result.content) {
        // Successful MCP response
        const responseText = mcpResult.result.content;
        result = {
          success: true,
          message: responseText
        };
      } else if (mcpResult.error) {
        // Error response
        result = {
          success: false,
          error: mcpResult.error
        };
      } else {
        // Fallback - check if there's any content in result
        const responseText = mcpResult.result?.content || mcpResult.result?.text || JSON.stringify(mcpResult);
        const isSuccess = responseText.includes('✅') || responseText.includes('created successfully');
        result = {
          success: isSuccess,
          message: isSuccess ? responseText : undefined,
          error: isSuccess ? undefined : responseText
        };
      }

      if (result.success) {
        this.state.createResult = {
          success: true,
          message: result.message || `Client '${this.state.newClient.name}' created successfully!`
        };
        
        // Notify parent component after a delay
        setTimeout(() => {
          if (this.props.onClientCreated) {
            this.props.onClientCreated();
          }
        }, 2000);
        
        // Close modal after showing success for 3 seconds
        setTimeout(() => {
          this.props.onClose();
          this.resetForm();
        }, 3000);
      } else {
        this.state.createResult = {
          success: false,
          error: result.error || result.message || 'Unknown error occurred'
        };
      }
    } catch (error) {
      console.error('Error creating client:', error);
      this.state.createResult = {
        success: false,
        error: error.message || 'Network error occurred'
      };
    } finally {
      this.state.creating = false;
    }
  }

  resetForm() {
    this.state.createResult = null;
    this.state.newClient = {
      name: '',
      version: '18.0',
      template: 'basic',
      hasEnterprise: false
    };
  }
}