/**
 * Data Service for managing client data and integrating with MCP server
 */
class DataService {
  constructor() {
    this.baseURL = 'http://localhost:3001/api'; // MCP server integration endpoint
    this.mockMode = false; // Utiliser le serveur MCP
    this.mcpServerURL = import.meta.env.VITE_MCP_SERVER_URL || 'http://mcp.localhost'; // MCP server HTTP API
    // Si nous sommes dans le browser, utiliser l'URL publique
    if (typeof window !== 'undefined') {
      this.mcpServerURL = 'http://mcp.localhost';
    }
    console.log('DataService initialized with MCP server at:', this.mcpServerURL);
    this.mcpServerStatus = 'unknown'; // unknown, connected, error
    this.lastError = null;
  }

  /**
   * Get clients overview for the homepage (one card per client - main branch only)
   */
  async getClientsOverview() {
    if (this.mockMode) {
      return this.getMockClients().filter(client => client.environment === 'production');
    }
    
    try {
      // Appeler le serveur MCP pour lister les clients
      const response = await this.callMCPServer('list_clients');
      
      let clientNames = [];
      if (response && response.type === 'text' && response.content) {
        // Parse the text response to extract client names
        const lines = response.content.split('\n').filter(line => line.trim());
        clientNames = lines
          .filter(line => line.includes('  - '))
          .map(line => line.replace('  - ', '').trim())
          .filter(name => name && name.length > 0);
        console.log('Parsed client names from MCP for overview:', clientNames);
      } else if (response && response.clients) {
        // Fallback for JSON response format
        clientNames = response.clients
          .filter(name => name && !name.startsWith('Clients') && !name.includes(':'))
          .filter(name => name.trim().length > 0);
        console.log('Raw clients from MCP for overview:', clientNames);
      }
      
      if (clientNames.length > 0) {
        // Créer une seule entrée par client (branche principale uniquement)
        const clientsOverview = [];
        
        for (const clientName of clientNames) {
          try {
            // Get the current Git branch of the client
            let currentGitBranch = '18.0'; // Default
            let currentBranchName = '18.0';
            
            try {
              const gitStatus = await this.callMCPServer('get_client_git_status', { client: clientName });
              if (gitStatus && gitStatus.type === 'text' && gitStatus.content) {
                const parsed = JSON.parse(gitStatus.content);
                if (parsed.success && parsed.current_branch) {
                  currentGitBranch = parsed.current_branch;
                  currentBranchName = parsed.current_branch;
                }
              }
            } catch (gitError) {
              console.warn(`Could not get Git status for ${clientName}:`, gitError);
            }
            
            // Use the current Git branch as the main branch for this client
            const environment = this.getBranchType(currentBranchName);
            const url = this.generateURL(clientName, currentBranchName, environment);
            
            clientsOverview.push({
              name: clientName,
              displayName: `${clientName} (${currentBranchName})`,
              environment: environment,
              status: 'healthy',
              lastActivity: '1 hour ago',
              url: url,
              version: '18.0',
              branch: currentBranchName,
              currentBranch: currentBranchName,
              odooVersion: '18.0',
              current: true,
              isGitCurrent: true
            });
            
          } catch (error) {
            console.error(`Error getting info for client ${clientName}:`, error);
            
            // Fallback to default production entry
            clientsOverview.push({
              name: clientName,
              displayName: `${clientName} Production`,
              environment: 'production',
              status: 'healthy',
              lastActivity: '2 hours ago',
              url: `http://${clientName}.localhost`,
              version: '18.0',
              branch: '18.0',
              currentBranch: '18.0',
              odooVersion: '18.0',
              current: true
            });
          }
        }
        
        console.log('Clients overview:', clientsOverview);
        return clientsOverview;
      }
      
      console.log('No clients found in MCP response');
      return [];
    } catch (error) {
      console.error('Error loading clients overview from MCP server:', error);
      this.lastError = error.message;
      this.mcpServerStatus = 'error';
      
      // Fallback to mock data in case of error
      console.log('Falling back to mock clients overview');
      return this.getMockClients().filter(client => client.environment === 'production');
    }
  }

  /**
   * Get all clients from MCP server (all branches)
   */
  async getClients() {
    if (this.mockMode) {
      return this.getMockClients();
    }
    
    try {
      // Appeler le serveur MCP pour lister les clients
      const response = await this.callMCPServer('list_clients');
      
      let clientNames = [];
      if (response && response.type === 'text' && response.content) {
        // Parse the text response to extract client names
        const lines = response.content.split('\n').filter(line => line.trim());
        clientNames = lines
          .filter(line => line.includes('  - '))
          .map(line => line.replace('  - ', '').trim())
          .filter(name => name && name.length > 0);
        console.log('Parsed client names from MCP:', clientNames);
      } else if (response && response.clients) {
        // Fallback for JSON response format
        clientNames = response.clients
          .filter(name => name && !name.startsWith('Clients') && !name.includes(':'))
          .filter(name => name.trim().length > 0);
        console.log('Raw clients from MCP:', clientNames);
      }
      
      if (clientNames.length > 0) {
        // Créer des environnements pour chaque client
        const allClients = [];
        
        // Get real branches for each client
        for (const clientName of clientNames) {
          try {
            // First get the current Git branch of the client
            let currentGitBranch = null;
            try {
              const gitStatus = await this.callMCPServer('get_client_git_status', { client: clientName });
              if (gitStatus && gitStatus.type === 'text' && gitStatus.content) {
                const parsed = JSON.parse(gitStatus.content);
                if (parsed.success && parsed.current_branch) {
                  currentGitBranch = parsed.current_branch;
                }
              }
            } catch (gitError) {
              console.warn(`Could not get Git status for ${clientName}:`, gitError);
            }
            
            const branchesData = await this.callMCPServer('get_client_branches', { client: clientName });
            
            let branches = [];
            if (branchesData && branchesData.type === 'text' && branchesData.content) {
              try {
                const parsed = JSON.parse(branchesData.content);
                if (parsed.success && parsed.branches) {
                  branches = parsed.branches;
                }
              } catch (parseError) {
                console.error(`Error parsing branches for ${clientName}:`, parseError);
                console.error('Raw content:', branchesData.content);
              }
            }
            
            // If no branches found, create default production entry with Git current branch
            if (branches.length === 0) {
              const defaultBranch = currentGitBranch || '18.0';
              branches = [{
                name: defaultBranch,
                type: 'production',
                current: true,
                upstream: null
              }];
            }
            
            // Mark the current Git branch as active
            if (currentGitBranch) {
              branches.forEach(branch => {
                branch.current = (branch.name === currentGitBranch);
              });
              
              // If current Git branch is not in the list, add it
              const branchExists = branches.some(b => b.name === currentGitBranch);
              if (!branchExists) {
                branches.push({
                  name: currentGitBranch,
                  type: this.getBranchType(currentGitBranch),
                  current: true,
                  upstream: null
                });
              }
            }
            
            // Create client entries for each branch
            branches.forEach(branch => {
              const environment = branch.type;
              const displayName = this.generateDisplayName(clientName, branch.name, environment);
              const url = this.generateURL(clientName, branch.name, environment);
              
              allClients.push({
                name: branch.name === '18.0' ? clientName : `${clientName}-${branch.name}`,
                displayName: displayName,
                environment: environment,
                status: 'healthy',
                lastActivity: branch.current ? '1 hour ago' : '2 hours ago',
                url: url,
                version: '18.0',
                branch: branch.name,
                current: branch.current,
                isGitCurrent: branch.current  // Mark which branch is actually checked out in Git
              });
            });
            
          } catch (error) {
            console.error(`Error getting branches for ${clientName}:`, error);
            
            // Fallback to default production entry
            allClients.push({
              name: clientName,
              displayName: `${clientName} Production`,
              environment: 'production',
              status: 'healthy',
              lastActivity: '2 hours ago',
              url: `http://${clientName}.localhost`,
              version: '18.0',
              branch: '18.0',
              current: true
            });
          }
        }
        
        console.log('Generated clients for dashboard:', allClients);
        return allClients;
      }
      
      // Si pas de clients trouvés via MCP et pas en mode mock, retourner tableau vide
      if (!this.mockMode) {
        console.log('No clients found from MCP server, returning empty array');
        return [];
      }
      
      return this.getMockClients();
    } catch (error) {
      console.error('Error fetching clients from MCP server:', error);
      
      // En cas d'erreur, retourner mock uniquement si mockMode est activé
      if (this.mockMode) {
        return this.getMockClients();
      }
      
      return [];
    }
  }

  /**
   * Determine branch type based on branch name
   */
  getBranchType(branchName) {
    if (branchName === 'master' || branchName === 'main' || branchName === '18.0') {
      return 'production';
    } else if (branchName.startsWith('staging') || branchName.includes('staging')) {
      return 'staging';
    } else if (branchName.startsWith('dev') || branchName.startsWith('feature') || branchName.startsWith('develop')) {
      return 'development';
    } else {
      return 'development'; // Default for unknown branch patterns
    }
  }

  /**
   * Generate display name for a client branch
   */
  generateDisplayName(clientName, branchName, environment) {
    const environmentNames = {
      'production': 'Production',
      'staging': 'Staging', 
      'development': 'Development'
    };
    
    const envName = environmentNames[environment] || 'Production';
    
    if (branchName === '18.0' || branchName === 'master' || branchName === 'main') {
      return `${clientName} ${envName}`;
    }
    
    return `${clientName} ${envName} (${branchName})`;
  }

  /**
   * Generate URL for a client branch
   */
  generateURL(clientName, branchName, environment) {
    const subdomain = {
      'production': '',
      'staging': 'staging.',
      'development': 'dev.'
    };
    
    const prefix = subdomain[environment] || '';
    
    if (branchName === '18.0' || branchName === 'master' || branchName === 'main') {
      return `http://${prefix}${clientName}.localhost`;
    }
    
    return `http://${prefix}${clientName}-${branchName}.localhost`;
  }

  /**
   * Call MCP server with a specific command
   */
  async callMCPServer(command, params = {}) {
    try {
      // All calls use the generic tool call endpoint
      console.log(`Calling MCP server tool: ${command} with params:`, params);
      const response = await fetch(`${this.mcpServerURL}/tools/call`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: JSON.stringify({
          name: command,
          arguments: params
        })
      });

      console.log('MCP server response status:', response.status);
      if (!response.ok) {
        this.mcpServerStatus = 'error';
        this.lastError = `HTTP ${response.status}: ${response.statusText}`;
        throw new Error(`MCP Server error: ${response.status} ${response.statusText}`);
      }

      const result = await response.json();
      console.log('MCP server response data:', result);
      
      this.mcpServerStatus = 'connected';
      this.lastError = null;
      
      // Return the result content directly
      return result.result || result;
    } catch (error) {
      this.mcpServerStatus = 'error';
      if (error.name === 'TypeError' && error.message.includes('fetch')) {
        this.lastError = 'Cannot connect to MCP server - is it running?';
      } else {
        this.lastError = error.message;
      }
      console.error('MCP Server call failed:', error);
      throw error;
    }
  }

  /**
   * Get MCP server status and last error
   */
  getMCPStatus() {
    return {
      status: this.mcpServerStatus,
      error: this.lastError,
      url: this.mcpServerURL
    };
  }

  /**
   * Get client details by name
   */
  async getClient(clientName) {
    if (this.mockMode) {
      return this.getMockClient(clientName);
    }
    
    try {
      // Utiliser le serveur MCP pour diagnostiquer le client
      const response = await this.callMCPServer('check_client', { client: clientName });
      return this.getMockClient(clientName); // Pour l'instant, retourner mock data enrichie
    } catch (error) {
      console.error(`Error fetching client ${clientName}:`, error);
      return this.getMockClient(clientName);
    }
  }

  /**
   * Diagnose client health
   */
  async diagnoseClient(clientName) {
    if (this.mockMode) {
      return this.getMockDiagnosis(clientName);
    }
    
    try {
      const response = await fetch(`${this.baseURL}/clients/${clientName}/diagnose`);
      return await response.json();
    } catch (error) {
      console.error(`Error diagnosing client ${clientName}:`, error);
      return this.getMockDiagnosis(clientName);
    }
  }

  /**
   * Get commit history for a client branch
   */
  async getCommitHistory(clientName, branchName = null) {
    if (this.mockMode) {
      return this.getMockCommitHistory(clientName);
    }
    
    try {
      const params = {
        client: clientName,
        limit: 20,
        format: 'json'
      };
      
      // If we have branch info, use it for git log
      if (branchName && branchName !== '18.0') {
        params.branch = branchName;
      }
      
      const response = await this.callMCPServer('get_client_git_log', params);
      
      console.log('Raw MCP response for git log:', response);
      
      // Parse JSON content if it's returned as text
      let parsedResponse = response;
      if (response.type === 'text' && response.content) {
        try {
          parsedResponse = JSON.parse(response.content);
          console.log('Parsed git log response:', parsedResponse);
        } catch (parseError) {
          console.error('Error parsing JSON content:', parseError);
        }
      }
      
      if (parsedResponse.success && parsedResponse.commits) {
        console.log('Returning real commits:', parsedResponse.commits);
        return parsedResponse.commits;
      } else {
        console.warn(`No git history found for client ${clientName}${branchName ? ' branch ' + branchName : ''}, using mock data`);
        return this.getMockCommitHistory(clientName);
      }
    } catch (error) {
      console.error(`Error fetching commit history for ${clientName}${branchName ? ' branch ' + branchName : ''}:`, error);
      return this.getMockCommitHistory(clientName);
    }
  }

  /**
   * Get commit details including diff
   */
  async getCommitDetails(clientName, commitHash) {
    if (this.mockMode) {
      return this.getMockCommitDetails(clientName, commitHash);
    }
    
    try {
      const response = await this.callMCPServer('get_commit_details', {
        client: clientName,
        commit: commitHash
      });
      
      console.log('Raw MCP response for commit details:', response);
      
      // Parse JSON content if it's returned as text
      let parsedResponse = response;
      if (response.type === 'text' && response.content) {
        try {
          parsedResponse = JSON.parse(response.content);
          console.log('Parsed commit details response:', parsedResponse);
        } catch (parseError) {
          console.error('Error parsing JSON content:', parseError);
        }
      }
      
      if (parsedResponse.success) {
        return parsedResponse.details;
      } else {
        console.warn(`No commit details found for ${commitHash}, using mock data`);
        return this.getMockCommitDetails(clientName, commitHash);
      }
    } catch (error) {
      console.error(`Error fetching commit details for ${commitHash}:`, error);
      return this.getMockCommitDetails(clientName, commitHash);
    }
  }

  /**
   * Get build history for a client
   */
  async getBuildHistory(clientName) {
    if (this.mockMode) {
      return this.getMockBuildHistory(clientName);
    }
    
    try {
      // Pour l'instant, utiliser les données mock car pas d'API MCP pour l'historique des builds
      return this.getMockBuildHistory(clientName);
    } catch (error) {
      console.error(`Error fetching build history for ${clientName}:`, error);
      return this.getMockBuildHistory(clientName);
    }
  }

  /**
   * Get client status (running/stopped) for a specific branch
   */
  async getClientStatus(clientName, branchName = null) {
    try {
      const toolName = branchName ? 'get_branch_status' : 'get_client_status';
      const params = branchName ? 
        { client: clientName, branch: branchName } : 
        { client: clientName };
      
      const response = await this.callMCPServer(toolName, params);
      return JSON.parse(response.content || '{"status": "unknown"}');
    } catch (error) {
      console.error(`Error fetching client status for ${clientName}${branchName ? ' branch ' + branchName : ''}:`, error);
      return { status: "unknown" };
    }
  }

  /**
   * Get client logs for a specific branch
   */
  async getClientLogs(clientName, branchName = null, container = 'odoo', lines = 100) {
    try {
      const toolName = branchName ? 'get_branch_logs' : 'get_client_logs';
      const params = branchName ? 
        { client: clientName, branch: branchName, container: container, lines: lines } :
        { client: clientName, container: container, lines: lines };
        
      const response = await this.callMCPServer(toolName, params);
      return response.content || 'No logs available';
    } catch (error) {
      console.error(`Error fetching logs for ${clientName}${branchName ? ' branch ' + branchName : ''}:`, error);
      return 'Error fetching logs';
    }
  }

  /**
   * Execute shell command in client container for a specific branch
   */
  async executeShellCommand(clientName, command, branchName = null, container = 'odoo') {
    try {
      const toolName = branchName ? 'open_branch_shell' : 'execute_shell_command';
      const params = branchName ? 
        { client: clientName, branch: branchName, command: command, container: container } :
        { client: clientName, command: command, container: container };
        
      const response = await this.callMCPServer(toolName, params);
      return response.content || '(no output)';
    } catch (error) {
      console.error(`Error executing command for ${clientName}${branchName ? ' branch ' + branchName : ''}:`, error);
      return `Error: ${error.message}`;
    }
  }

  /**
   * Get GitHub configuration
   */
  async getGitHubConfig() {
    try {
      // For now, return default config since the GitHub tools are not stable yet
      return {
        github_token: "",
        github_organization: "Alusage",
        git_user_name: "",
        git_user_email: ""
      };
    } catch (error) {
      console.error('Error fetching GitHub config:', error);
      return null;
    }
  }

  /**
   * Save GitHub configuration
   */
  async saveGitHubConfig(config) {
    try {
      // For now, simulate success since the GitHub tools are not stable yet
      console.log('Simulating GitHub config save:', config);
      return {
        success: true,
        message: 'Configuration saved successfully (simulated)'
      };
    } catch (error) {
      console.error('Error saving GitHub config:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Test GitHub connection
   */
  async testGitHubConnection(config) {
    try {
      // For now, simulate connection test since the GitHub tools are not stable yet
      console.log('Simulating GitHub connection test:', config);
      return {
        success: true,
        username: 'test-user',
        error: ''
      };
    } catch (error) {
      console.error('Error testing GitHub connection:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Create client with GitHub integration
   */
  async createClientWithGitHub(clientConfig) {
    try {
      const response = await this.callMCPServer('create_client_github', clientConfig);
      return {
        success: true,
        message: response.content || 'Client created with GitHub integration'
      };
    } catch (error) {
      console.error('Error creating client with GitHub:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Start a specific client branch
   */
  async startClientBranch(clientName, branchName) {
    try {
      const response = await this.callMCPServer('start_client_branch', {
        client: clientName,
        branch: branchName
      });
      return {
        success: true,
        message: response.content || 'Branch started successfully'
      };
    } catch (error) {
      console.error(`Error starting branch ${branchName} for client ${clientName}:`, error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Stop a specific client branch
   */
  async stopClientBranch(clientName, branchName) {
    try {
      const response = await this.callMCPServer('stop_client_branch', {
        client: clientName,
        branch: branchName
      });
      return {
        success: true,
        message: response.content || 'Branch stopped successfully'
      };
    } catch (error) {
      console.error(`Error stopping branch ${branchName} for client ${clientName}:`, error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Restart a specific client branch
   */
  async restartClientBranch(clientName, branchName) {
    try {
      const response = await this.callMCPServer('restart_client_branch', {
        client: clientName,
        branch: branchName
      });
      return {
        success: true,
        message: response.content || 'Branch restarted successfully'
      };
    } catch (error) {
      console.error(`Error restarting branch ${branchName} for client ${clientName}:`, error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  /**
   * Get client addons (submodules) with their modules and link status
   */
  async getClientAddons(clientName) {
    try {
      // Get submodules using the new MCP tool
      const submodulesResponse = await this.callMCPServer('list_submodules', {
        client: clientName
      });
      
      // Parse the response
      let submodules = [];
      if (submodulesResponse && submodulesResponse.type === 'text' && submodulesResponse.content) {
        try {
          const parsed = JSON.parse(submodulesResponse.content);
          if (parsed.success && parsed.submodules) {
            submodules = parsed.submodules;
          }
        } catch (parseError) {
          console.error('Error parsing submodules response:', parseError);
        }
      }
      
      // Get linked modules using the new MCP tool
      const linkedResponse = await this.callMCPServer('list_linked_modules', {
        client: clientName
      });
      
      let linkedModules = [];
      if (linkedResponse && linkedResponse.type === 'text' && linkedResponse.content) {
        try {
          const parsed = JSON.parse(linkedResponse.content);
          if (parsed.success && parsed.modules) {
            linkedModules = parsed.modules;
          }
        } catch (parseError) {
          console.error('Error parsing linked modules response:', parseError);
        }
      }
      
      // Combine the data
      const addons = submodules.map(submodule => {
        const modules = submodule.modules.map(module => ({
          name: module,
          linked: linkedModules.includes(module)
        }));
        
        return {
          name: submodule.name,
          url: submodule.url,
          branch: submodule.branch,
          commit: submodule.commit,
          modules: modules
        };
      });
      
      return addons;
      
    } catch (error) {
      console.error(`Error fetching addons for ${clientName}:`, error);
      return [];
    }
  }

  /**
   * Link a module from an addon repository
   */
  async linkModule(clientName, addonName, moduleName) {
    try {
      const response = await this.callMCPServer('link_module_with_config', {
        client: clientName,
        repository: addonName,
        module: moduleName
      });
      
      return response;
    } catch (error) {
      console.error(`Error linking module ${moduleName}:`, error);
      throw error;
    }
  }

  /**
   * Unlink a module by removing the symbolic link
   */
  async unlinkModule(clientName, addonName, moduleName) {
    try {
      const response = await this.callMCPServer('unlink_module_with_config', {
        client: clientName,
        repository: addonName,
        module: moduleName
      });
      
      console.log(`Unlinked module ${moduleName}:`, response);
      return response;
    } catch (error) {
      console.error(`Error unlinking module ${moduleName}:`, error);
      throw error;
    }
  }

  /**
   * Commit current changes in client repository
   */
  async commitClientChanges(clientName, message = "Update module links") {
    try {
      const response = await this.callMCPServer('commit_client_changes', {
        client: clientName,
        message: message
      });
      
      if (response && response.type === 'text' && response.content) {
        const parsed = JSON.parse(response.content);
        return parsed;
      }
      return response;
    } catch (error) {
      console.error(`Error committing changes for ${clientName}:`, error);
      throw error;
    }
  }

  /**
   * Switch client repository to a specific Git branch
   */
  async switchClientBranch(clientName, branch, create = false) {
    try {
      const response = await this.callMCPServer('switch_client_branch', {
        client: clientName,
        branch: branch,
        create: create
      });
      
      if (response && response.type === 'text' && response.content) {
        const parsed = JSON.parse(response.content);
        return parsed;
      }
      return response;
    } catch (error) {
      console.error(`Error switching branch for ${clientName}:`, error);
      throw error;
    }
  }

  /**
   * Get Git status of client repository including sync status with remote
   */
  async getClientGitStatus(clientName) {
    try {
      const response = await this.callMCPServer('get_client_git_status', {
        client: clientName
      });
      
      if (response && response.type === 'text' && response.content) {
        const parsed = JSON.parse(response.content);
        return parsed;
      }
      return response;
    } catch (error) {
      console.error(`Error getting Git status for ${clientName}:`, error);
      throw error;
    }
  }

  // Mock data methods
  getMockClients() {
    return [
      // BousBotsBar - Production
      {
        name: 'bousbotsbar',
        displayName: 'BousBotsBar Production',
        status: 'healthy',
        environment: 'production',
        version: '18.0',
        lastActivity: '2 hours ago',
        url: 'http://bousbotsbar.com'
      },
      // BousBotsBar - Staging
      {
        name: 'bousbotsbar-staging',
        displayName: 'BousBotsBar Staging',
        status: 'healthy',
        environment: 'staging',
        version: '18.0',
        lastActivity: '4 hours ago',
        url: 'http://staging.bousbotsbar.com'
      },
      // BousBotsBar - Development
      {
        name: 'bousbotsbar-dev',
        displayName: 'BousBotsBar Development',
        status: 'healthy',
        environment: 'development',
        version: '18.0',
        lastActivity: '1 hour ago',
        url: 'http://dev.bousbotsbar.localhost'
      },
      
      // SudoKeys - Production
      {
        name: 'sudokeys',
        displayName: 'SudoKeys Production',
        status: 'healthy',
        environment: 'production',
        version: '18.0',
        lastActivity: '1 day ago',
        url: 'http://sudokeys.com'
      },
      // SudoKeys - Staging
      {
        name: 'sudokeys-staging',
        displayName: 'SudoKeys Staging',
        status: 'warning',
        environment: 'staging',
        version: '18.0',
        lastActivity: '2 days ago',
        url: 'http://staging.sudokeys.com'
      },
      // SudoKeys - Development
      {
        name: 'sudokeys-dev',
        displayName: 'SudoKeys Development',
        status: 'healthy',
        environment: 'development',
        version: '18.0',
        lastActivity: '3 hours ago',
        url: 'http://dev.sudokeys.localhost'
      },

      // TestClient - Production
      {
        name: 'testclient',
        displayName: 'TestClient Production',
        status: 'healthy',
        environment: 'production',
        version: '18.0',
        lastActivity: '5 minutes ago',
        url: 'http://testclient.com'
      },
      // TestClient - Development
      {
        name: 'testclient-dev',
        displayName: 'TestClient Development',
        status: 'error',
        environment: 'development',
        version: '18.0',
        lastActivity: '10 minutes ago',
        url: 'http://dev.testclient.localhost'
      }
    ];
  }

  /**
   * Get unique client names for dropdown (without environments)
   */
  async getUniqueClientNames() {
    try {
      if (!this.mockMode) {
        // Utiliser le serveur MCP
        const response = await this.callMCPServer('list_clients');
        
        let clientNames = [];
        if (response && response.type === 'text' && response.content) {
          // Parse the text response to extract client names
          const lines = response.content.split('\n').filter(line => line.trim());
          clientNames = lines
            .filter(line => line.includes('  - '))
            .map(line => line.replace('  - ', '').trim())
            .filter(name => name && name.length > 0);
        } else if (response && response.clients) {
          // Fallback for JSON response format
          clientNames = response.clients
            .filter(name => name && !name.startsWith('Clients') && !name.includes(':'))
            .filter(name => name.trim().length > 0);
        }
        
        console.log('Unique client names from MCP:', clientNames);
        return clientNames;
      }
      
      // Si pas en mode mock et pas de réponse du serveur MCP, retourner un tableau vide
      if (!this.mockMode) {
        console.log('No clients found from MCP server');
        return [];
      }
      
      // Fallback mode mock uniquement si mockMode est activé
      const clients = this.getMockClients();
      const uniqueNames = new Set();
      
      clients.forEach(client => {
        // Extraire le nom de base du client (sans -staging, -dev, etc.)
        let baseName = client.name;
        if (baseName.includes('-staging')) {
          baseName = baseName.replace('-staging', '');
        } else if (baseName.includes('-dev')) {
          baseName = baseName.replace('-dev', '');
        }
        uniqueNames.add(baseName);
      });
      
      return Array.from(uniqueNames);
    } catch (error) {
      console.error('Error getting unique client names:', error);
      // En cas d'erreur, retourner un tableau vide plutôt que des données hardcodées
      return [];
    }
  }

  getMockClient(clientName) {
    const clients = this.getMockClients();
    const client = clients.find(c => c.name === clientName);
    
    if (!client) {
      throw new Error(`Client ${clientName} not found`);
    }

    return {
      ...client,
      containers: [
        {
          name: `odoo-${clientName}`,
          status: 'running',
          health: 'healthy',
          uptime: '2h 15m'
        },
        {
          name: `postgresql-${clientName}`,
          status: 'running',
          health: 'healthy',
          uptime: '2h 15m'
        }
      ],
      modules: [
        'base',
        'web',
        'sale',
        'purchase',
        'account',
        'stock'
      ],
      lastBackup: '2024-07-14 02:00:00',
      diskUsage: '15%',
      memoryUsage: '45%',
      cpuUsage: '12%'
    };
  }

  getMockDiagnosis(clientName) {
    const statuses = ['success', 'warning', 'error'];
    const randomStatus = statuses[Math.floor(Math.random() * statuses.length)];
    
    return {
      overall: randomStatus,
      timestamp: new Date().toISOString(),
      components: {
        docker: { status: 'success', message: 'All containers running' },
        postgresql: { status: 'success', message: 'Database accessible' },
        odoo: { status: randomStatus, message: 'Application responsive' },
        traefik: { status: 'success', message: 'Routing configured' },
        disk: { status: 'success', message: 'Sufficient space available' }
      }
    };
  }

  getMockCommitHistory(clientName) {
    return [
      {
        id: 'a1b2c3d',
        author: {
          name: 'John Developer',
          avatar: 'https://api.dicebear.com/7.x/avataaars/svg?seed=John'
        },
        timestamp: '2 hours ago',
        message: 'feat: add new client management features',
        branch: {
          from: 'DEVELOPMENT',
          to: 'STAGING'
        },
        status: {
          testing: 'running',
          build: 'success'
        }
      },
      {
        id: 'e4f5g6h',
        author: {
          name: 'Jane Smith',
          avatar: 'https://api.dicebear.com/7.x/avataaars/svg?seed=Jane'
        },
        timestamp: '1 day ago',
        message: 'fix: resolve PostgreSQL connection issues',
        branch: {
          from: 'STAGING',
          to: 'PRODUCTION'
        },
        status: {
          testing: 'passed',
          build: 'success'
        }
      },
      {
        id: 'i7j8k9l',
        author: {
          name: 'Bob Wilson',
          avatar: 'https://api.dicebear.com/7.x/avataaars/svg?seed=Bob'
        },
        timestamp: '3 days ago',
        message: 'chore: update dependencies and security patches',
        branch: {
          from: 'DEVELOPMENT',
          to: 'STAGING'
        },
        status: {
          testing: 'failed',
          build: 'error'
        }
      }
    ];
  }

  getMockCommitDetails(clientName, commitHash) {
    return {
      diff: true,
      stats: {
        files: 5,
        insertions: 245,
        deletions: 78
      },
      files: [
        {
          filename: 'clients/testclient/config/odoo.conf',
          additions: 12,
          deletions: 3,
          hunks: [
            {
              header: '@@ -1,10 +1,15 @@',
              lines: [
                { lineNumber: 1, type: 'context', content: '[options]' },
                { lineNumber: 2, type: 'context', content: 'admin_passwd = admin' },
                { lineNumber: 3, type: 'added', content: 'db_name = testclient' },
                { lineNumber: 4, type: 'added', content: 'db_user = odoo' },
                { lineNumber: 5, type: 'context', content: 'addons_path = /mnt/extra-addons' },
                { lineNumber: 6, type: 'removed', content: 'log_level = info' },
                { lineNumber: 7, type: 'added', content: 'log_level = debug' },
                { lineNumber: 8, type: 'context', content: 'xmlrpc_port = 8069' }
              ]
            }
          ]
        },
        {
          filename: 'clients/testclient/requirements.txt',
          additions: 8,
          deletions: 2,
          hunks: [
            {
              header: '@@ -1,5 +1,10 @@',
              lines: [
                { lineNumber: 1, type: 'added', content: '# OCA Dependencies' },
                { lineNumber: 2, type: 'context', content: 'requests>=2.25.1' },
                { lineNumber: 3, type: 'added', content: 'python-dateutil>=2.8.2' },
                { lineNumber: 4, type: 'added', content: 'lxml>=4.6.3' },
                { lineNumber: 5, type: 'context', content: 'psycopg2-binary>=2.8.6' },
                { lineNumber: 6, type: 'removed', content: 'pillow==8.2.0' },
                { lineNumber: 7, type: 'added', content: 'pillow>=8.3.0' }
              ]
            }
          ]
        }
      ]
    };
  }

  getMockBuildHistory(clientName) {
    return [
      {
        id: 'build_001',
        title: '[FEAT] Enhanced client dashboard with real-time updates',
        author: 'Alice Johnson',
        timestamp: 'July 14, 2024 - 08:30',
        duration: '0:03:45',
        status: 'success',
        branch: 'master-dashboard-enhancement'
      },
      {
        id: 'build_002',
        title: '[FIX] Resolve Docker container health check issues',
        author: 'Mike Rodriguez',
        timestamp: 'July 13, 2024 - 15:22',
        duration: '0:02:15',
        status: 'success',
        branch: 'hotfix-docker-health'
      },
      {
        id: 'build_003',
        title: '[UPDATE] Upgrade to Odoo 18.0 with module compatibility',
        author: 'Sarah Chen',
        timestamp: 'July 12, 2024 - 11:45',
        duration: '0:07:30',
        status: 'failed',
        branch: 'upgrade-odoo-18'
      }
    ];
  }
}

export const dataService = new DataService();