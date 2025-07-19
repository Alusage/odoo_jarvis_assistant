import { Component, useState, onMounted, onWillUnmount, xml } from "@odoo/owl";

export class Terminal extends Component {
  static template = xml`
    <div class="h-full bg-gray-900 rounded-lg overflow-hidden">
      <div class="bg-gray-800 px-4 py-2 flex items-center justify-between">
        <h3 class="text-white font-medium">Interactive Terminal</h3>
        <div class="flex items-center space-x-2">
          <span t-if="state.connected" class="text-green-400 text-sm">● Connected</span>
          <span t-elif="state.connecting" class="text-yellow-400 text-sm">● Connecting...</span>
          <span t-else="" class="text-red-400 text-sm">● Disconnected</span>
          <button class="btn-secondary btn-sm" t-on-click="reconnect">
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
            </svg>
          </button>
        </div>
      </div>
      <div 
        id="terminal-container" 
        class="h-full"
        style="padding: 0; margin: 0;"
      ></div>
    </div>
  `;

  setup() {
    this.state = useState({
      connected: false,
      connecting: false,
      terminalReady: false
    });

    this.terminal = null;
    this.websocket = null;
    this.reconnectTimer = null;
    this.manualDisconnect = false;

    onMounted(async () => {
      console.log("Terminal mounted");
      await this.initializeTerminal();
      this.connectWebSocket();
    });

    onWillUnmount(() => {
      console.log("Terminal unmounted");
      this.cleanup();
    });
  }

  async initializeTerminal() {
    try {
      console.log("Loading xterm.js and addons...");
      
      // Load xterm and fit addon
      const xtermModule = await import("@xterm/xterm");
      const fitModule = await import("@xterm/addon-fit");
      
      const Terminal = xtermModule.Terminal;
      const FitAddon = fitModule.FitAddon;
      
      console.log("✅ xterm.js loaded successfully");

      // Create terminal instance
      this.terminal = new Terminal({
        cursorBlink: true,
        fontSize: 14,
        fontFamily: 'JetBrains Mono, Monaco, Consolas, "Liberation Mono", "Courier New", monospace',
        theme: {
          background: '#1f2937', // gray-800
          foreground: '#f3f4f6', // gray-100
          cursor: '#10b981', // green-500
          selection: '#374151', // gray-700
          black: '#000000',
          red: '#ef4444',
          green: '#10b981',
          yellow: '#f59e0b',
          blue: '#3b82f6',
          magenta: '#8b5cf6',
          cyan: '#06b6d4',
          white: '#f3f4f6',
          brightBlack: '#6b7280',
          brightRed: '#f87171',
          brightGreen: '#34d399',
          brightYellow: '#fbbf24',
          brightBlue: '#60a5fa',
          brightMagenta: '#a78bfa',
          brightCyan: '#22d3ee',
          brightWhite: '#ffffff'
        },
        allowTransparency: false,
        scrollback: 1000
      });

      // Add fit addon
      this.fitAddon = new FitAddon();
      this.terminal.loadAddon(this.fitAddon);

      // Get container and attach
      const container = document.getElementById('terminal-container');
      if (container) {
        this.terminal.open(container);
        this.fitAddon.fit();
        
        // Initial welcome message
        this.terminal.writeln('\\x1b[1;32m┌─ Odoo Interactive Terminal ─────────────────────────────────────┐\\x1b[0m');
        this.terminal.writeln('\\x1b[1;32m│\\x1b[0m \\x1b[33mConnecting to container...\\x1b[0m                               \\x1b[1;32m│\\x1b[0m');
        this.terminal.writeln('\\x1b[1;32m└─────────────────────────────────────────────────────────────────┘\\x1b[0m');
        this.terminal.writeln('');
        
        this.state.terminalReady = true;
        console.log("✅ Terminal attached to DOM");
      } else {
        console.error("❌ Terminal container not found");
        return;
      }

      // Handle terminal input
      this.terminal.onData((data) => {
        if (this.websocket && this.websocket.readyState === WebSocket.OPEN) {
          this.websocket.send(data);
        }
      });

      // Handle resize
      this.resizeHandler = () => {
        if (this.fitAddon) {
          this.fitAddon.fit();
        }
      };
      window.addEventListener('resize', this.resizeHandler);

    } catch (error) {
      console.error("❌ Failed to initialize terminal:", error);
    }
  }

  connectWebSocket() {
    if (!this.props.client || !this.state.terminalReady) {
      console.log("❌ Cannot connect: no client or terminal not ready");
      return;
    }

    const { baseName, branchName } = this.parseClientInfo();

    this.state.connecting = true;
    this.state.connected = false;

    // Create WebSocket connection - use branch-specific endpoint if available
    let wsUrl;
    if (branchName && branchName !== '18.0') {
      wsUrl = `ws://mcp.localhost/terminal/${baseName}/${branchName}`;
    } else {
      wsUrl = `ws://mcp.localhost/terminal/${baseName}`;
    }
    
    console.log(`🔌 Connecting to WebSocket: ${wsUrl}`);
    
    this.websocket = new WebSocket(wsUrl);

    this.websocket.onopen = () => {
      this.state.connecting = false;
      this.state.connected = true;
      this.terminal.write('\\x1b[2K\\r'); // Clear current line
      this.terminal.writeln('\\x1b[32m✅ Connected to container terminal\\x1b[0m');
      this.terminal.writeln('');
      console.log("✅ WebSocket connected");
    };

    this.websocket.onmessage = (event) => {
      this.terminal.write(event.data);
    };

    this.websocket.onclose = () => {
      this.state.connecting = false;
      this.state.connected = false;
      this.terminal.writeln('\\r\\n\\x1b[33m⚠️  Connection closed\\x1b[0m');
      console.log("⚠️ WebSocket closed");
      
      // Auto-reconnect after 3 seconds if not manually disconnected
      if (!this.manualDisconnect) {
        this.reconnectTimer = setTimeout(() => {
          this.terminal.writeln('\\x1b[36m🔄 Attempting to reconnect...\\x1b[0m');
          this.connectWebSocket();
        }, 3000);
      }
    };

    this.websocket.onerror = (error) => {
      this.state.connecting = false;
      this.state.connected = false;
      this.terminal.writeln('\\x1b[31m❌ Connection error\\x1b[0m');
      console.error('❌ WebSocket error:', error);
    };
  }

  reconnect() {
    console.log("🔄 Manual reconnect");
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    
    if (this.websocket) {
      this.manualDisconnect = true;
      this.websocket.close();
    }
    
    setTimeout(() => {
      this.manualDisconnect = false;
      this.terminal.writeln('\\x1b[36m🔄 Reconnecting...\\x1b[0m');
      this.connectWebSocket();
    }, 500);
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
    
    // Use actual branch name from client data if available
    if (this.props.client.branch && this.props.client.branch !== '18.0') {
      branchName = this.props.client.branch;
    }
    
    return { baseName, branchName };
  }

  cleanup() {
    console.log("🧹 Cleaning up terminal");
    
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.websocket) {
      this.manualDisconnect = true;
      this.websocket.close();
      this.websocket = null;
    }

    if (this.terminal) {
      this.terminal.dispose();
      this.terminal = null;
    }

    if (this.resizeHandler) {
      window.removeEventListener('resize', this.resizeHandler);
    }
  }
}