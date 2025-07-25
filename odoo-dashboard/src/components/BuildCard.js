import { Component, xml } from "@odoo/owl";

export class BuildCard extends Component {
  static template = xml`
    <div class="card p-6 hover:shadow-card-hover transition-all duration-200">
      <!-- Header -->
      <div class="flex items-start justify-between mb-4">
        <div>
          <h3 class="font-semibold text-gray-900 mb-1">
            Build #<t t-esc="props.build.id"/>
          </h3>
          <div class="flex items-center space-x-2">
            <span 
              class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
              t-att-class="getBuildTypeClass(props.build.type)"
            >
              <t t-esc="props.build.type"/>
            </span>
            <span t-att-class="getBuildStatusClass(props.build.status)">
              <t t-esc="props.build.status"/>
            </span>
          </div>
        </div>
        
        <div class="flex items-center space-x-1">
          <button 
            class="btn-secondary btn-sm"
            t-on-click="connectToBuild"
          >
            Connect
          </button>
          <button 
            class="btn-secondary btn-sm"
            t-on-click="viewBuildLogs"
          >
            Logs
          </button>
        </div>
      </div>

      <!-- Branch and Commit Info -->
      <div class="mb-4">
        <div class="flex items-center space-x-2 mb-2">
          <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"/>
          </svg>
          <span class="font-mono text-sm text-gray-600" t-esc="props.build.branch"/>
        </div>
        <div class="flex items-center space-x-2">
          <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14"/>
          </svg>
          <span class="font-mono text-xs bg-gray-100 px-2 py-1 rounded" t-esc="props.build.commit"/>
        </div>
      </div>

      <!-- Build Details -->
      <div class="space-y-2 text-sm text-gray-600">
        <div class="flex justify-between">
          <span>Started:</span>
          <span t-esc="formatTimestamp(props.build.startTime)"/>
        </div>
        <div t-if="props.build.endTime" class="flex justify-between">
          <span>Duration:</span>
          <span t-esc="formatDuration(props.build.duration)"/>
        </div>
        <div t-if="props.build.status === 'running'" class="flex justify-between">
          <span>Running for:</span>
          <span t-esc="formatDuration(props.build.runningTime)"/>
        </div>
      </div>

      <!-- Progress Bar for Running Builds -->
      <div t-if="props.build.status === 'running'" class="mt-4">
        <div class="flex justify-between text-xs text-gray-500 mb-1">
          <span t-esc="props.build.currentStep"/>
          <span t-esc="props.build.progress + '%'"/>
        </div>
        <div class="w-full bg-gray-200 rounded-full h-1.5">
          <div 
            class="bg-primary-500 h-1.5 rounded-full transition-all duration-300"
            t-att-style="'width: ' + props.build.progress + '%'"
          />
        </div>
      </div>

      <!-- Error Message for Failed Builds -->
      <div t-if="props.build.status === 'failed' &amp;&amp; props.build.error" class="mt-4 p-3 bg-red-50 border border-red-200 rounded-lg">
        <div class="flex items-start space-x-2">
          <svg class="w-4 h-4 text-red-400 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
          </svg>
          <div>
            <p class="text-sm font-medium text-red-800">Build Failed</p>
            <p class="text-xs text-red-600 mt-1" t-esc="props.build.error"/>
          </div>
        </div>
      </div>
    </div>
  `;

  getBuildStatusClass(status) {
    const statusClasses = {
      'success': 'status-success',
      'running': 'status-info',
      'failed': 'status-error',
      'pending': 'status-warning'
    };
    return statusClasses[status] || 'status-info';
  }

  getBuildTypeClass(type) {
    const typeClasses = {
      'production': 'bg-green-100 text-green-800',
      'staging': 'bg-yellow-100 text-yellow-800',
      'development': 'bg-blue-100 text-blue-800'
    };
    return typeClasses[type] || 'bg-gray-100 text-gray-800';
  }

  formatDuration(seconds) {
    if (seconds < 60) return `${seconds}s`;
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return `${minutes}m ${remainingSeconds}s`;
  }

  formatTimestamp(timestamp) {
    return new Date(timestamp).toLocaleString();
  }

  connectToBuild() {
    this.props.onConnect();
  }

  viewBuildLogs() {
    this.props.onViewLogs();
  }
}