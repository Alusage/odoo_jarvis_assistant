/**
 * Data Service for managing client data and integrating with MCP server
 */
class DataService {
  constructor() {
    this.baseURL = 'http://localhost:3001/api'; // MCP server integration endpoint
    this.mockMode = true; // Temporairement en mode mock pour tester
    this.mcpServerURL = 'http://localhost:3001'; // MCP server endpoint
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
        // Transformer les données pour l'interface
        return response.clients.map(clientName => ({
          name: clientName,
          displayName: clientName,
          environment: 'production', // Par défaut, à adapter selon vos besoins
          status: 'healthy',
          lastActivity: '2 hours ago',
          url: `http://localhost:8069`, // URL par défaut
          version: '18.0'
        }));
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
      const mcpCommand = {
        method: 'tools/call',
        params: {
          name: command,
          arguments: params
        }
      };

      const response = await fetch(`${this.mcpServerURL}/mcp`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(mcpCommand)
      });

      if (!response.ok) {
        throw new Error(`MCP Server error: ${response.status}`);
      }

      const result = await response.json();
      return result.content || result;
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
      const response = await fetch(`${this.baseURL}/clients/${clientName}`);
      return await response.json();
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
      const response = await fetch(`${this.baseURL}/clients/${clientName}/commits`);
      return await response.json();
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
      const response = await fetch(`${this.baseURL}/clients/${clientName}/builds`);
      return await response.json();
    } catch (error) {
      console.error(`Error fetching build history for ${clientName}:`, error);
      return this.getMockBuildHistory(clientName);
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
  getUniqueClientNames() {
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