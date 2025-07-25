import { Component, xml } from "@odoo/owl";

export class DashboardHeader extends Component {
  static template = xml`
    <div class="border-b border-gray-200 bg-white sticky top-0 z-20">
      <div class="flex items-center justify-between p-4">
        <!-- Tabs -->
        <div class="flex space-x-6">
          <button 
            t-foreach="props.tabs" 
            t-as="tab" 
            t-key="tab.id"
            class="tab-button"
            t-att-class="props.getTabClass(tab.id)"
            t-on-click="() => props.onTabChange(tab.id)"
          >
            <t t-esc="tab.label"/>
          </button>
        </div>

        <!-- Action Buttons -->
        <div class="flex items-center space-x-2">
          <!-- Status info -->
          <span t-if="props.clientStatus.status === 'missing'" class="text-xs bg-orange-100 text-orange-800 px-2 py-1 rounded">
            ⚠️ Docker image missing - Build first
          </span>
          <span t-elif="props.clientStatus.status === 'stopped'" class="text-xs bg-yellow-100 text-yellow-800 px-2 py-1 rounded">
            ⏸️ Ready to start
          </span>
          <span t-elif="props.clientStatus.status === 'running'" class="text-xs bg-green-100 text-green-800 px-2 py-1 rounded">
            ✅ Running
          </span>
          <span t-elif="props.clientStatus.status === 'partial'" class="text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded">
            🔄 Partially running
          </span>
          <span t-else="" class="text-xs bg-gray-100 px-2 py-1 rounded" t-esc="'Status: ' + props.clientStatus.status"></span>
          
          <button class="btn-secondary" t-on-click="props.onClone">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
            </svg>
            Clone
          </button>
          
          <button t-if="props.clientStatus.status !== 'running' and props.clientStatus.status !== 'missing'" class="btn-success" t-on-click="props.onStart">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.828 14.828a4 4 0 01-5.656 0M9 10h1m4 0h1m-6 4h8m-9-4h.01M12 5v.01M3 12a9 9 0 0118 0 9 9 0 01-18 0z"/>
            </svg>
            Start
          </button>
          
          <button t-if="props.clientStatus.status === 'running'" class="btn-warning" t-on-click="props.onStop">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 10h6v4H9z"/>
            </svg>
            Stop
          </button>
          
          <button t-if="props.clientStatus.status === 'running'" class="btn-secondary" t-on-click="props.onRestart">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
            </svg>
            Restart
          </button>
          
          <button class="btn-secondary" t-on-click="props.onRebuild" 
                  t-att-class="props.clientStatus.status === 'missing' ? 'btn-primary' : 'btn-secondary'"
                  t-att-title="props.clientStatus.status === 'missing' ? 'Build Docker image first' : 'Rebuild Docker image'">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"/>
            </svg>
            Rebuild
          </button>
          
          <button t-if="props.clientStatus.status === 'running' || props.clientStatus.status === 'partial'" class="btn-primary" t-on-click="props.onConnect">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/>
            </svg>
            Connect
          </button>
        </div>
      </div>

      <!-- Git Command Display -->
      <div t-if="props.client" class="px-4 pb-4">
        <div class="bg-gray-50 rounded-lg p-3 font-mono text-sm">
          <div class="flex items-center justify-between">
            <span class="text-gray-600">git clone</span>
            <button class="btn-secondary btn-sm" t-on-click="props.onCopyGitCommand">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
              </svg>
              Copy
            </button>
          </div>
          <div class="mt-1 text-gray-800">
            <t t-esc="props.gitCommand"/>
          </div>
        </div>
      </div>
    </div>
  `;

  static props = {
    client: { type: Object, optional: true },
    tabs: { type: Array },
    clientStatus: { type: Object },
    gitCommand: { type: String },
    getTabClass: { type: Function },
    onTabChange: { type: Function },
    onClone: { type: Function },
    onStart: { type: Function },
    onStop: { type: Function },
    onRestart: { type: Function },
    onRebuild: { type: Function },
    onConnect: { type: Function },
    onCopyGitCommand: { type: Function }
  };
}