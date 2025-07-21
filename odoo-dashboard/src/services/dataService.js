/**
 * Data Service for managing client data and integrating with MCP server
 */
class DataService {
  constructor() {
    this.baseURL = 'http://localhost:3001/api'; // MCP server integration endpoint
    this.mockMode = false; // Utiliser le serveur MCP
    this.mcpServerURL = null; // Will be set dynamically
    this.traefikDomain = this.getTraefikDomainFromBrowser(); // Get from current URL
    this.mcpServerStatus = 'unknown'; // unknown, connected, error
    this.lastError = null;
    console.log('🚀 DataService constructor - traefikDomain:', this.traefikDomain);
    // Initialize MCP URL with current domain configuration
    this.initializeMcpUrl();
  }

  /**
   * Get Traefik domain from current browser URL
   */
  getTraefikDomainFromBrowser() {
    if (typeof window !== 'undefined' && window.location) {
      const hostname = window.location.hostname;
      console.log('🌐 Browser hostname:', hostname);
      
      // Extract domain from dashboard.local -> local
      if (hostname.includes('.')) {
        const domain = hostname.split('.').slice(-1)[0]; // Get last part (local, localhost, dev, etc.)
        console.log('🌐 Extracted domain:', domain);
        return domain;
      }
      console.log('🌐 Using hostname directly:', hostname);
      return hostname;
    }
    console.log('🌐 Using fallback domain: localhost');
    return 'localhost'; // Fallback for SSR or when window is not available
  }

  /**
   * Initialize MCP server URL based on current domain configuration
   */
  async initializeMcpUrl() {
    // Force rebuild URL with current domain from browser
    const browserDomain = this.getTraefikDomainFromBrowser();
    this.traefikDomain = browserDomain; // Override with browser detection
    this.mcpServerURL = `http://mcp.${this.traefikDomain}`;
    console.log('🚀 DataService force-set MCP server URL to:', this.mcpServerURL, 'using domain:', this.traefikDomain);
    
    // Test connectivity immediately with correct domain
    if (typeof window !== 'undefined') {
      setTimeout(async () => {
        await this.testMCPConnectivity();
      }, 1000); // Wait 1 second for services to be ready
    }
  }

  /**
   * Update Traefik domain from configuration
   */
  async updateTraefikDomain() {
    try {
      // Try to get config from a simple endpoint first
      const response = await fetch('/api/traefik-domain');
      if (response.ok) {
        const data = await response.json();
        this.traefikDomain = data.domain || 'localhost';
        return;
      }
    } catch (error) {
      // If that fails, try via MCP (using fallback URL)
      try {
        const config = await this.getTraefikConfig();
        this.traefikDomain = config.domain || 'localhost';
        this.mcpServerURL = `http://mcp.${this.traefikDomain}`;
      } catch (mcpError) {
        console.warn('Could not get Traefik domain, using localhost:', mcpError);
      }
    }
  }

  /**
   * Get current MCP server URL (dynamically updated based on Traefik config)
   */
  getMcpServerUrl() {
    // Si on est côté serveur (pendant le build), utiliser l'URL interne
    if (typeof window === 'undefined') {
      return 'http://mcp-server:8000';
    }
    // Côté client (navigateur), utiliser l'URL Traefik
    const url = this.mcpServerURL || `http://mcp.${this.traefikDomain}`;
    console.log('🔗 getMcpServerUrl returning:', url, 'from domain:', this.traefikDomain);
    return url;
  }

  /**
   * Get current Traefik domain
   */
  getTraefikDomain() {
    return this.traefikDomain;
  }

  /**
   * Get WebSocket URL for terminal connections
   */
  getWsUrl(baseName, branchName = null) {
    const mcpUrl = this.getMcpServerUrl().replace('http://', 'ws://').replace('https://', 'wss://');
    if (branchName) {
      return `${mcpUrl}/terminal/${baseName}/${branchName}`;
    }
    return `${mcpUrl}/terminal/${baseName}`;
  }

  /**
   * Get WebSocket URL for branch switching
   */
  getBranchSwitchWsUrl(clientName) {
    const mcpUrl = this.getMcpServerUrl().replace('http://', 'ws://').replace('https://', 'wss://');
    return `${mcpUrl}/branch-switch/${clientName}`;
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
                isGitCurrent: branch.current,  // Mark which branch is actually checked out in Git
                baseClientName: clientName  // Store the base client name
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
   * Test basic connectivity to MCP server
   */
  async testMCPConnectivity() {
    try {
      const mcpUrl = this.getMcpServerUrl();
      console.log(`🔍 Testing MCP server connectivity at: ${mcpUrl}`);
      
      const response = await fetch(`${mcpUrl}/`, {
        method: 'GET',
        mode: 'cors',
        headers: {
          'Accept': 'application/json',
        }
      });
      
      if (response.ok) {
        const data = await response.json();
        console.log('✅ MCP server is reachable:', data);
        this.mcpServerStatus = 'connected';
        return true;
      } else {
        console.error('❌ MCP server returned error:', response.status, response.statusText);
        this.mcpServerStatus = 'error';
        this.lastError = `HTTP ${response.status}: ${response.statusText}`;
        return false;
      }
    } catch (error) {
      console.error('❌ MCP server connectivity test failed:', error);
      this.mcpServerStatus = 'error';
      this.lastError = error.message;
      return false;
    }
  }

  /**
   * Call MCP server with a specific command
   */
  async callMCPServer(command, params = {}) {
    try {
      // Use current MCP server URL (dynamically updated)
      const mcpUrl = this.getMcpServerUrl();
      console.log(`🔗 Calling MCP server tool: ${command} with params:`, params, 'at', mcpUrl);
      
      const response = await fetch(`${mcpUrl}/tools/call`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        mode: 'cors', // Explicitly enable CORS
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
  async getBuildHistory(clientName, branchName = null) {
    if (this.mockMode) {
      return this.getMockBuildHistory(clientName);
    }
    
    try {
      const params = {
        client: clientName,
        limit: 20
      };
      
      // Add branch filter if specified
      if (branchName && branchName !== '18.0') {
        params.branch = branchName;
      }
      
      const response = await this.callMCPServer('get_build_history', params);
      
      if (response.success !== false) {
        const data = JSON.parse(response.content || response.text || '{}');
        if (data.success && data.builds) {
          // Transform the data to match the expected format
          const transformedBuilds = data.builds.map((build, index) => ({
            id: `${build.id || 'build'}_${build.image_tag || index}_${build.created_at || Date.now()}`,
            title: build.git_message || `Build ${build.image_tag}`,
            author: build.author || 'Unknown',
            timestamp: this.formatTimestamp(build.created_at),
            duration: build.duration || 'Unknown',
            status: build.status || 'success',
            branch: build.branch,
            image_tag: build.image_tag,
            size: build.size,
            git_hash: build.git_hash,
            image_id: build.image_id,
            type: build.type || 'docker'
          }));
          
          // Ensure unique IDs by adding index if duplicates exist
          const seenIds = new Set();
          const uniqueBuilds = transformedBuilds.map((build, index) => {
            let uniqueId = build.id;
            let counter = 0;
            while (seenIds.has(uniqueId)) {
              counter++;
              uniqueId = `${build.id}_${counter}`;
            }
            seenIds.add(uniqueId);
            return { ...build, id: uniqueId };
          });
          
          return uniqueBuilds;
        }
      }
      
      // Fallback to mock data if API fails
      console.warn('Build history API returned no data, using mock data');
      return this.getMockBuildHistory(clientName);
    } catch (error) {
      console.error(`Error fetching build history for ${clientName}:`, error);
      return this.getMockBuildHistory(clientName);
    }
  }

  formatTimestamp(dockerTimestamp) {
    try {
      // Docker timestamp format: "2025-07-20 14:41:53 +0200 CEST"
      const date = new Date(dockerTimestamp);
      return date.toLocaleString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      });
    } catch (error) {
      return dockerTimestamp || 'Unknown';
    }
  }

  /**
   * Get client status (running/stopped) for a specific branch
   */
  async getClientStatus(clientName, branchName = null) {
    try {
      // For production branch (18.0), use normal client status, not branch status
      const isProductionBranch = branchName === '18.0';
      const toolName = (branchName && !isProductionBranch) ? 'get_branch_status' : 'get_client_status';
      const params = (branchName && !isProductionBranch) ? 
        { client: clientName, branch: branchName } : 
        { client: clientName };
      
      const response = await this.callMCPServer(toolName, params);
      console.log(`getClientStatus(${clientName}, ${branchName}):`, response);
      
      if (branchName && !isProductionBranch) {
        // For branch status, parse the nested JSON response
        try {
          const content = response.content || '{}';
          const nestedData = JSON.parse(content);
          const statusText = nestedData.status || '';
          
          let status = 'unknown';
          
          // Look for actual status indicators in the text
          if (statusText.includes('✓ Container running:') && statusText.includes('✓ PostgreSQL running:')) {
            status = 'running';
          } else if (statusText.includes('✓ Container running:') || statusText.includes('✓ PostgreSQL running:')) {
            status = 'partial';
          } else if (statusText.includes('✓ Image found:') || statusText.includes('✓ Image exists:')) {
            // Image exists but containers not running
            status = 'stopped';
          } else if (statusText.includes('✗ Image not found:')) {
            // No image available  
            status = 'missing';
          } else {
            // Check for other success indicators
            if (statusText.includes('✓') && !statusText.includes('✗')) {
              status = 'stopped'; // Has some success indicators
            } else if (statusText.includes('✗') && !statusText.includes('✓')) {
              status = 'missing'; // Only error indicators
            }
          }
          
          console.log(`Parsed branch status: ${status} from:`, statusText);
          return { 
            status: status,
            details: statusText
          };
        } catch (e) {
          console.error('Failed to parse nested JSON for branch status:', e, response);
          return { status: 'unknown', details: response.content };
        }
      } else {
        // For regular client status, try to parse as JSON
        try {
          const parsed = JSON.parse(response.content || '{"status": "unknown"}');
          console.log(`Parsed status:`, parsed);
          return parsed;
        } catch (e) {
          console.log(`Failed to parse JSON, treating as text:`, response.content);
          return { status: 'unknown', details: response.content };
        }
      }
    } catch (error) {
      console.error(`Error fetching client status for ${clientName}${branchName ? ' branch ' + branchName : ''}:`, error);
      return { status: "unknown" };
    }
  }

  /**
   * Start client branch deployment
   */
  async startClientBranch(clientName, branchName, build = false) {
    try {
      // For production branch (18.0), use normal client start
      const isProductionBranch = branchName === '18.0';
      const toolName = isProductionBranch ? 'start_client' : 'start_client_branch';
      const params = isProductionBranch ? 
        { client: clientName } : 
        { client: clientName, branch: branchName, build: build };
      
      const response = await this.callMCPServer(toolName, params);
      
      if (response && response.success !== false) {
        return { 
          success: true, 
          message: response.content || response.text || 'Client started successfully'
        };
      } else {
        return { 
          success: false, 
          error: response?.error || 'Failed to start client'
        };
      }
    } catch (error) {
      console.error(`Error starting client ${clientName}:${branchName}:`, error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Stop client branch deployment
   */
  async stopClientBranch(clientName, branchName, cleanVolumes = false, stopPostgres = false) {
    try {
      // For production branch (18.0), use normal client stop
      const isProductionBranch = branchName === '18.0';
      const toolName = isProductionBranch ? 'stop_client' : 'stop_client_branch';
      const params = isProductionBranch ? 
        { client: clientName } : 
        { client: clientName, branch: branchName, clean_volumes: cleanVolumes, stop_postgres: stopPostgres };
      
      const response = await this.callMCPServer(toolName, params);
      
      if (response && response.success !== false) {
        return { 
          success: true, 
          message: response.content || response.text || 'Client stopped successfully'
        };
      } else {
        return { 
          success: false, 
          error: response?.error || 'Failed to stop client'
        };
      }
    } catch (error) {
      console.error(`Error stopping client ${clientName}:${branchName}:`, error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Restart client branch deployment
   */
  async restartClientBranch(clientName, branchName) {
    try {
      // For production branch (18.0), use normal client restart
      const isProductionBranch = branchName === '18.0';
      const toolName = isProductionBranch ? 'restart_client' : 'restart_client_branch';
      const params = isProductionBranch ? 
        { client: clientName } : 
        { client: clientName, branch: branchName };
      
      const response = await this.callMCPServer(toolName, params);
      
      if (response && response.success !== false) {
        return { 
          success: true, 
          message: response.content || response.text || 'Client restarted successfully'
        };
      } else {
        return { 
          success: false, 
          error: response?.error || 'Failed to restart client'
        };
      }
    } catch (error) {
      console.error(`Error restarting client ${clientName}:${branchName}:`, error);
      return { success: false, error: error.message };
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
   * Delete a client and all its data
   */
  async deleteClient(clientName) {
    if (this.mockMode) {
      return { success: true, message: 'Client deleted (mock mode)' };
    }

    try {
      const response = await this.callMCPServer('delete_client', {
        client: clientName,
        confirmed: true
      });
      
      // Parse the JSON content from MCP response if needed
      if (response && response.content) {
        try {
          const parsed = JSON.parse(response.content);
          return parsed;
        } catch (parseError) {
          // If parsing fails, assume it's a simple success response
          return {
            success: true,
            message: response.content || 'Client deleted successfully'
          };
        }
      }
      
      return {
        success: true,
        message: 'Client deleted successfully'
      };
    } catch (error) {
      console.error('Error deleting client:', error);
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

  /**
   * Update Git submodules for a client repository
   */
  async updateClientSubmodules(clientName) {
    try {
      const response = await this.callMCPServer('update_client_submodules', {
        client: clientName
      });
      
      if (response && response.content) {
        const parsed = JSON.parse(response.content);
        return parsed;
      }
      return response;
    } catch (error) {
      console.error(`Error updating submodules for ${clientName}:`, error);
      throw error;
    }
  }

  /**
   * Get diff of uncommitted changes in client repository
   */
  async getClientDiff(clientName, branchName = null) {
    try {
      const response = await this.callMCPServer('get_client_diff', {
        client: clientName,
        branch: branchName
      });
      
      if (response && response.type === 'text' && response.content) {
        try {
          const parsed = JSON.parse(response.content);
          if (parsed.success && parsed.diff) {
            return this.parseDiff(parsed.diff);
          }
        } catch (parseError) {
          // If parsing fails, assume the content is the diff itself
          return this.parseDiff(response.content);
        }
      }
      
      const rawDiff = response.content || 'No changes found';
      return this.parseDiff(rawDiff);
    } catch (error) {
      console.error(`Error getting diff for ${clientName}${branchName ? ' branch ' + branchName : ''}:`, error);
      throw error;
    }
  }

  /**
   * Parse raw git diff into structured format
   */
  parseDiff(rawDiff) {
    if (!rawDiff || rawDiff === 'No changes found' || rawDiff.trim() === '') {
      return {
        files: [],
        stats: { files: 0, insertions: 0, deletions: 0 },
        raw: rawDiff
      };
    }

    const files = [];
    const lines = rawDiff.split('\n');
    let currentFile = null;
    let currentHunk = null;
    let totalInsertions = 0;
    let totalDeletions = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      // File header: diff --git a/file b/file
      if (line.startsWith('diff --git')) {
        if (currentFile) {
          files.push(currentFile);
        }
        
        // Extract filename
        const match = line.match(/diff --git a\/(.+?) b\/(.+)/);
        const filename = match ? match[2] : 'unknown';
        
        currentFile = {
          filename: filename,
          additions: 0,
          deletions: 0,
          hunks: []
        };
        currentHunk = null;
      }
      // Hunk header: @@ -1,4 +1,6 @@
      else if (line.startsWith('@@')) {
        if (currentFile) {
          if (currentHunk) {
            currentFile.hunks.push(currentHunk);
          }
          
          currentHunk = {
            header: line,
            lines: []
          };
        }
      }
      // Added line
      else if (line.startsWith('+') && !line.startsWith('+++')) {
        if (currentHunk) {
          currentHunk.lines.push({
            type: 'added',
            content: line.substring(1),
            lineNumber: ''
          });
          if (currentFile) {
            currentFile.additions++;
            totalInsertions++;
          }
        }
      }
      // Removed line
      else if (line.startsWith('-') && !line.startsWith('---')) {
        if (currentHunk) {
          currentHunk.lines.push({
            type: 'removed',
            content: line.substring(1),
            lineNumber: ''
          });
          if (currentFile) {
            currentFile.deletions++;
            totalDeletions++;
          }
        }
      }
      // Context line
      else if (line.startsWith(' ') && currentHunk) {
        currentHunk.lines.push({
          type: 'context',
          content: line.substring(1),
          lineNumber: ''
        });
      }
    }

    // Add last file and hunk
    if (currentHunk && currentFile) {
      currentFile.hunks.push(currentHunk);
    }
    if (currentFile) {
      files.push(currentFile);
    }

    return {
      files: files,
      stats: {
        files: files.length,
        insertions: totalInsertions,
        deletions: totalDeletions
      },
      raw: rawDiff
    };
  }

  /**
   * Check Docker image status for a client branch
   */
  async checkBranchDockerStatus(clientName, branchName = null) {
    try {
      const response = await this.callMCPServer('check_branch_docker_status', {
        client: clientName,
        branch: branchName
      });
      
      if (response && response.type === 'text' && response.content) {
        try {
          const parsed = JSON.parse(response.content);
          if (parsed.success) {
            return parsed;
          }
        } catch (parseError) {
          console.error('Error parsing Docker status response:', parseError);
        }
      }
      
      return {
        success: false,
        status: 'unknown',
        message: 'Could not check Docker status'
      };
    } catch (error) {
      console.error(`Error checking Docker status for ${clientName}${branchName ? ' branch ' + branchName : ''}:`, error);
      return {
        success: false,
        status: 'error',
        message: error.message
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
    
    // Extract base client name if it's a branch name (e.g., "njtest-staging-2025-07-20" -> "njtest")
    const baseClientName = clientName.includes('-') ? clientName.split('-')[0] : clientName;
    
    // First try to find exact match, then try base name
    let client = clients.find(c => c.name === clientName);
    if (!client) {
      client = clients.find(c => c.name === baseClientName || c.baseClientName === baseClientName);
    }
    
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

  /**
   * Get Traefik configuration
   */
  async getTraefikConfig() {
    if (this.mockMode) {
      return { domain: 'local', protocol: 'http' };
    }

    try {
      const response = await this.callMCPServer('get_traefik_config');
      return response;
    } catch (error) {
      console.error('Error getting Traefik config:', error);
      // Return default values on error
      return { domain: 'local', protocol: 'http' };
    }
  }

  /**
   * Get Git configuration
   */
  async getGitConfig() {
    if (this.mockMode) {
      return {
        userName: 'Mock User',
        userEmail: 'mock@example.com'
      };
    }

    try {
      const response = await this.callMCPServer('get_git_config');
      
      // Parse the JSON content from MCP response
      if (response && response.content) {
        try {
          const parsed = JSON.parse(response.content);
          return parsed;
        } catch (parseError) {
          console.error('Error parsing Git config response:', parseError);
          return null;
        }
      }
      
      return response;
    } catch (error) {
      console.error('Error getting Git config:', error);
      return null;
    }
  }

  /**
   * Save Git configuration
   */
  async saveGitConfig(config) {
    if (this.mockMode) {
      return { success: true };
    }

    try {
      const response = await this.callMCPServer('save_git_config', {
        user_name: config.userName,
        user_email: config.userEmail
      });
      
      console.log('Raw MCP response for save_git_config:', response);
      
      // Parse the JSON content from MCP response
      if (response && response.content) {
        try {
          const parsed = JSON.parse(response.content);
          console.log('Parsed Git config response:', parsed);
          return parsed;
        } catch (parseError) {
          console.error('Error parsing Git config response:', parseError);
          console.log('Raw content was:', response.content);
          return { success: false, error: 'Failed to parse server response' };
        }
      }
      
      console.log('No content to parse, returning raw response:', response);
      return response;
    } catch (error) {
      console.error('Error saving Git config:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Set Traefik configuration and update MCP URL
   */
  async setTraefikConfig(domain, protocol) {
    if (this.mockMode) {
      return { success: true };
    }

    try {
      const response = await this.callMCPServer('set_traefik_config', {
        domain: domain,
        protocol: protocol
      });
      
      // Update our local domain and MCP URL
      if (response && response.success !== false) {
        this.traefikDomain = domain;
        this.mcpServerURL = `http://mcp.${domain}`;
        console.log('Updated MCP server URL to:', this.mcpServerURL);
      }
      
      return response;
    } catch (error) {
      console.error('Error setting Traefik config:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Sync submodules for a client (force sync)
   */
  async updateClientSubmodules(clientName) {
    if (this.mockMode) {
      return { success: true, message: 'Submodules synchronized successfully' };
    }

    try {
      const response = await this.callMCPServer('update_client_submodules', {
        client: clientName
      });
      
      return response;
    } catch (error) {
      console.error('Error syncing submodules:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Check status of submodules and detect outdated ones
   */
  async checkSubmodulesStatus(clientName) {
    if (this.mockMode) {
      return {
        success: true,
        submodules: [
          {
            path: 'addons/partner-contact',
            current_commit: 'abc123',
            current_message: 'Current version',
            latest_commit: 'def456',
            latest_message: 'Latest version with improvements',
            needs_update: true,
            branch: '18.0'
          },
          {
            path: 'addons/account-analytic',
            current_commit: 'ghi789',
            current_message: 'Up to date version',
            latest_commit: 'ghi789',
            latest_message: 'Up to date version',
            needs_update: false,
            branch: '18.0'
          }
        ]
      };
    }

    try {
      const response = await this.callMCPServer('check_submodules_status', {
        client: clientName
      });
      
      return response;
    } catch (error) {
      console.error('Error checking submodules status:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Update a specific submodule to latest version
   */
  async updateSubmodule(clientName, submodulePath) {
    if (this.mockMode) {
      return { 
        success: true, 
        message: `Submodule '${submodulePath}' updated successfully`,
        new_commit: 'xyz999',
        commit_message: 'Latest improvements'
      };
    }

    try {
      const response = await this.callMCPServer('update_submodule', {
        client: clientName,
        submodule_path: submodulePath
      });
      
      return response;
    } catch (error) {
      console.error('Error updating submodule:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Update all outdated submodules to their latest versions
   */
  async updateAllSubmodules(clientName) {
    if (this.mockMode) {
      return { 
        success: true, 
        message: 'Updated 2 submodules',
        updated_count: 2,
        failed_count: 0,
        updated_submodules: [
          { path: 'addons/partner-contact', old_commit: 'abc123', new_commit: 'def456' },
          { path: 'addons/server-ux', old_commit: 'ghi789', new_commit: 'jkl012' }
        ],
        failed_submodules: []
      };
    }

    try {
      const response = await this.callMCPServer('update_all_submodules', {
        client: clientName
      });
      
      return response;
    } catch (error) {
      console.error('Error updating all submodules:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Add an OCA module to a client
   */
  async addOcaModuleToClient(clientName, moduleKey, branch = null) {
    if (this.mockMode) {
      return { 
        success: true, 
        message: `OCA module '${moduleKey}' added successfully to client '${clientName}'`
      };
    }

    try {
      const params = { client: clientName, module_key: moduleKey };
      if (branch) {
        params.branch = branch;
      }

      console.log(`🔧 Adding OCA module: ${moduleKey} to client: ${clientName}`, params);
      
      const response = await this.callMCPServer('add_oca_module_to_client', params);
      
      console.log('🔧 Raw MCP response for addOcaModuleToClient:', response);
      console.log('🔧 Response type:', typeof response);
      console.log('🔧 Response keys:', response ? Object.keys(response) : 'N/A');
      
      // Handle different response formats like in listAvailableOcaModules
      if (response) {
        // Case 1: Response has text content that needs parsing
        if (response.type === 'text' && response.content) {
          console.log('🔧 Response has text content, attempting to parse...');
          try {
            const parsed = JSON.parse(response.content);
            console.log('🔧 Parsed JSON from text content:', parsed);
            return parsed;
          } catch (parseError) {
            console.error('🔧 JSON parse error:', parseError);
            console.error('🔧 Content was:', response.content);
            return { success: false, error: 'Failed to parse text content' };
          }
        }
        
        // Case 2: Response is already a parsed object
        if (response.success !== undefined || response.error !== undefined) {
          console.log('🔧 Response is already parsed object:', response);
          return response;
        }
        
        // Case 3: Response is a string that needs parsing  
        if (typeof response === 'string') {
          console.log('🔧 Response is string, attempting to parse...');
          try {
            const parsed = JSON.parse(response);
            console.log('🔧 Parsed JSON from string:', parsed);
            return parsed;
          } catch (parseError) {
            console.error('🔧 String parse error:', parseError);
            return { success: false, error: 'Failed to parse string response' };
          }
        }
      }

      console.log('🔧 Response format not recognized, returning error');
      return { success: false, error: 'Unknown response format' };
    } catch (error) {
      console.error('🔧 Error adding OCA module:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Add an external repository to a client
   */
  async addExternalRepoToClient(clientName, repoUrl, repoName, branch = null) {
    if (this.mockMode) {
      return { 
        success: true, 
        message: `External repository '${repoName}' added successfully to client '${clientName}'`
      };
    }

    try {
      const params = { 
        client: clientName, 
        repo_url: repoUrl, 
        repo_name: repoName 
      };
      if (branch) {
        params.branch = branch;
      }

      const response = await this.callMCPServer('add_external_repo_to_client', params);
      return response;
    } catch (error) {
      console.error('Error adding external repository:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Change the branch of a submodule
   */
  async changeSubmoduleBranch(clientName, submodulePath, newBranch) {
    if (this.mockMode) {
      return { 
        success: true, 
        message: `Submodule '${submodulePath}' branch changed to '${newBranch}' successfully`
      };
    }

    try {
      const response = await this.callMCPServer('change_submodule_branch', {
        client: clientName,
        submodule_path: submodulePath,
        new_branch: newBranch
      });
      
      return response;
    } catch (error) {
      console.error('Error changing submodule branch:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Remove a submodule from a client
   */
  async removeSubmodule(clientName, submodulePath) {
    if (this.mockMode) {
      return { 
        success: true, 
        message: `Submodule '${submodulePath}' removed successfully from client '${clientName}'`
      };
    }

    try {
      const response = await this.callMCPServer('remove_submodule', {
        client: clientName,
        submodule_path: submodulePath
      });
      
      return response;
    } catch (error) {
      console.error('Error removing submodule:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Get existing submodule names for a client
   */
  async getExistingSubmodules(clientName) {
    if (this.mockMode) {
      return {
        success: true,
        submodules: ['account-analytic', 'partner-contact']
      };
    }

    try {
      const response = await this.callMCPServer('list_submodules', {
        client: clientName
      });
      
      let submoduleNames = [];
      if (response && response.type === 'text' && response.content) {
        try {
          const parsed = JSON.parse(response.content);
          if (parsed.success && parsed.submodules) {
            // Extract just the names from the submodules
            submoduleNames = parsed.submodules.map(sub => sub.name);
          }
        } catch (parseError) {
          console.error('Error parsing submodules response:', parseError);
        }
      }
      
      return {
        success: true,
        submodules: submoduleNames
      };
    } catch (error) {
      console.error('Error getting existing submodules:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * List available OCA modules
   */
  async listAvailableOcaModules(search = null, clientName = null) {
    if (this.mockMode) {
      return {
        success: true,
        modules: [
          { key: 'account-analytic', description: 'Account analytic tools and utilities' },
          { key: 'partner-contact', description: 'Partner and contact management extensions' },
          { key: 'server-ux', description: 'Server user experience improvements' },
          { key: 'stock-logistics-workflow', description: 'Stock and logistics workflow management' },
          { key: 'project', description: 'Project management tools' }
        ].filter(m => !search || m.key.includes(search) || m.description.toLowerCase().includes(search.toLowerCase())),
        total: 5
      };
    }

    try {
      const params = {};
      if (search) {
        params.search = search;
      }

      console.log(`📋 listAvailableOcaModules called with search: "${search}"`);
      console.log('📋 MCP parameters:', params);

      const response = await this.callMCPServer('list_available_oca_modules', params);
      
      console.log('📋 Raw MCP response for listAvailableOcaModules:', response);
      console.log('📋 Response type:', typeof response);
      console.log('📋 Response keys:', response ? Object.keys(response) : 'N/A');

      // Handle different response formats
      if (response) {
        // Case 1: Response has text content that needs parsing
        if (response.type === 'text' && response.content) {
          console.log('📋 Response has text content, attempting to parse...');
          try {
            const parsed = JSON.parse(response.content);
            console.log('📋 Parsed JSON from text content:', parsed);
            
            // Filter out existing submodules if clientName is provided
            if (clientName && parsed.success && parsed.modules) {
              try {
                const existingSubmodules = await this.getExistingSubmodules(clientName);
                if (existingSubmodules.success && existingSubmodules.submodules) {
                  const filteredModules = parsed.modules.filter(module => 
                    !existingSubmodules.submodules.includes(module.key)
                  );
                  console.log(`📋 Filtered ${parsed.modules.length - filteredModules.length} existing modules from text content`);
                  return {
                    ...parsed,
                    modules: filteredModules,
                    total: filteredModules.length
                  };
                }
              } catch (filterError) {
                console.error('📋 Error filtering existing modules from text content:', filterError);
                // If filtering fails, return original response
              }
            }
            
            return parsed;
          } catch (parseError) {
            console.error('📋 JSON parse error:', parseError);
            console.error('📋 Content was:', response.content);
            return { success: false, error: 'Failed to parse text content' };
          }
        }
        
        // Case 2: Response is already a parsed object
        if (response.success !== undefined || response.modules !== undefined) {
          console.log('📋 Response is already parsed object:', response);
          
          // Filter out existing submodules if clientName is provided
          if (clientName && response.success && response.modules) {
            try {
              const existingSubmodules = await this.getExistingSubmodules(clientName);
              if (existingSubmodules.success && existingSubmodules.submodules) {
                const filteredModules = response.modules.filter(module => 
                  !existingSubmodules.submodules.includes(module.key)
                );
                console.log(`📋 Filtered ${response.modules.length - filteredModules.length} existing modules`);
                return {
                  ...response,
                  modules: filteredModules,
                  total: filteredModules.length
                };
              }
            } catch (filterError) {
              console.error('📋 Error filtering existing modules:', filterError);
              // If filtering fails, return original response
            }
          }
          
          return response;
        }
        
        // Case 3: Response is a string that needs parsing  
        if (typeof response === 'string') {
          console.log('📋 Response is string, attempting to parse...');
          try {
            const parsed = JSON.parse(response);
            console.log('📋 Parsed JSON from string:', parsed);
            
            // Filter out existing submodules if clientName is provided
            if (clientName && parsed.success && parsed.modules) {
              try {
                const existingSubmodules = await this.getExistingSubmodules(clientName);
                if (existingSubmodules.success && existingSubmodules.submodules) {
                  const filteredModules = parsed.modules.filter(module => 
                    !existingSubmodules.submodules.includes(module.key)
                  );
                  console.log(`📋 Filtered ${parsed.modules.length - filteredModules.length} existing modules from string`);
                  return {
                    ...parsed,
                    modules: filteredModules,
                    total: filteredModules.length
                  };
                }
              } catch (filterError) {
                console.error('📋 Error filtering existing modules from string:', filterError);
                // If filtering fails, return original response
              }
            }
            
            return parsed;
          } catch (parseError) {
            console.error('📋 String parse error:', parseError);
            return { success: false, error: 'Failed to parse string response' };
          }
        }
      }

      console.log('📋 Response format not recognized, returning error');
      return { success: false, error: 'Unknown response format' };
    } catch (error) {
      console.error('📋 Error listing available OCA modules:', error);
      return { success: false, error: error.message };
    }
  }
}

export const dataService = new DataService();