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
  }

  /**
   * Get all clients from MCP server
   */
  async getClients() {
    if (this.mockMode) {
      return this.getMockClients();
    }
    
    try {
      // Appeler le serveur MCP pour lister les clients
      const response = await this.callMCPServer('list_clients');
      
      if (response && response.clients) {
        // Filtrer et transformer les données pour l'interface
        console.log('Raw clients from MCP:', response.clients);
        const clientNames = response.clients
          .filter(name => name && !name.startsWith('Clients') && !name.includes(':'))
          .filter(name => name.trim().length > 0);
        console.log('Filtered client names:', clientNames);
        
        // Créer des environnements pour chaque client
        const allClients = [];
        
        clientNames.forEach(clientName => {
          // Production (base name)
          allClients.push({
            name: clientName,
            displayName: `${clientName} Production`,
            environment: 'production',
            status: 'healthy',
            lastActivity: '2 hours ago',
            url: `http://${clientName}.localhost`,
            version: '18.0'
          });
          
          // Staging
          allClients.push({
            name: `${clientName}-staging`,
            displayName: `${clientName} Staging`,
            environment: 'staging',
            status: 'healthy',
            lastActivity: '4 hours ago',
            url: `http://staging.${clientName}.localhost`,
            version: '18.0'
          });
          
          // Development
          allClients.push({
            name: `${clientName}-dev`,
            displayName: `${clientName} Development`,
            environment: 'development',
            status: 'healthy',
            lastActivity: '1 hour ago',
            url: `http://dev.${clientName}.localhost`,
            version: '18.0'
          });
        });
        
        console.log('Generated clients for dashboard:', allClients);
        return allClients;
      }
      
      return this.getMockClients();
    } catch (error) {
      console.error('Error fetching clients from MCP server:', error);
      return this.getMockClients();
    }
  }

  /**
   * Call MCP server with a specific command
   */
  async callMCPServer(command, params = {}) {
    try {
      // Use direct endpoints when available
      if (command === 'list_clients') {
        console.log('Calling MCP server at:', `${this.mcpServerURL}/clients`);
        const response = await fetch(`${this.mcpServerURL}/clients`);
        console.log('MCP server response status:', response.status);
        if (!response.ok) {
          throw new Error(`MCP Server error: ${response.status}`);
        }
        const data = await response.json();
        console.log('MCP server response data:', data);
        return data;
      }
      
      // Use generic tool call endpoint
      const response = await fetch(`${this.mcpServerURL}/tools/call`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: command,
          arguments: params
        })
      });

      if (!response.ok) {
        throw new Error(`MCP Server error: ${response.status}`);
      }

      const result = await response.json();
      return result.result || result;
    } catch (error) {
      console.error('MCP Server call failed:', error);
      throw error;
    }
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
   * Get commit history for a client
   */
  async getCommitHistory(clientName) {
    if (this.mockMode) {
      return this.getMockCommitHistory(clientName);
    }
    
    try {
      const response = await this.callMCPServer('get_client_git_log', {
        client: clientName,
        limit: 20,
        format: 'json'
      });
      
      if (response.success && response.commits) {
        return response.commits;
      } else {
        console.warn(`No git history found for client ${clientName}, using mock data`);
        return this.getMockCommitHistory(clientName);
      }
    } catch (error) {
      console.error(`Error fetching commit history for ${clientName}:`, error);
      return this.getMockCommitHistory(clientName);
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
   * Get client status (running/stopped)
   */
  async getClientStatus(clientName) {
    try {
      const response = await this.callMCPServer('get_client_status', { client: clientName });
      return JSON.parse(response.content || '{"status": "unknown"}');
    } catch (error) {
      console.error(`Error fetching client status for ${clientName}:`, error);
      return { status: "unknown" };
    }
  }

  /**
   * Get client logs
   */
  async getClientLogs(clientName, container = 'odoo', lines = 100) {
    try {
      const response = await this.callMCPServer('get_client_logs', { 
        client: clientName, 
        container: container,
        lines: lines 
      });
      return response.content || 'No logs available';
    } catch (error) {
      console.error(`Error fetching logs for ${clientName}:`, error);
      return 'Error fetching logs';
    }
  }

  /**
   * Execute shell command in client container
   */
  async executeShellCommand(clientName, command, container = 'odoo') {
    try {
      const response = await this.callMCPServer('execute_shell_command', { 
        client: clientName, 
        command: command,
        container: container 
      });
      return response.content || '(no output)';
    } catch (error) {
      console.error(`Error executing command for ${clientName}:`, error);
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
        
        if (response && response.clients) {
          // Filtrer et retourner les noms de clients uniques
          return response.clients
            .filter(name => name && !name.startsWith('Clients') && !name.includes(':'))
            .filter(name => name.trim().length > 0);
        }
      }
      
      // Fallback mode mock
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
      return ['bousbotsbar', 'sudokeys', 'testclient'];
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