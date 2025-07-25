import { Component, xml } from "@odoo/owl";

export class LogsTab extends Component {
  static template = xml`
    <div class="h-full p-6">
      <div class="bg-gray-900 rounded-lg h-full overflow-hidden">
        <div class="bg-gray-800 px-4 py-2 flex items-center justify-between">
          <h3 class="text-white font-medium">Application Logs</h3>
          <div class="flex items-center space-x-2">
            <button class="btn-secondary btn-sm" t-on-click="props.onRefreshLogs">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
              </svg>
            </button>
            <button class="btn-secondary btn-sm" t-on-click="props.onDownloadLogs">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
              </svg>
            </button>
          </div>
        </div>
        <div class="p-4 h-full overflow-y-auto font-mono text-sm text-green-400">
          <div t-foreach="props.logs" t-as="logLine" t-key="logLine_index">
            <span class="text-gray-500" t-esc="logLine.timestamp"/>
            <span t-att-class="props.getLogLevelClass(logLine.level)" t-esc="logLine.level"/>
            <span class="text-gray-300" t-esc="logLine.message"/>
          </div>
        </div>
      </div>
    </div>
  `;

  static props = {
    logs: { type: Array },
    onRefreshLogs: { type: Function },
    onDownloadLogs: { type: Function },
    getLogLevelClass: { type: Function }
  };
}