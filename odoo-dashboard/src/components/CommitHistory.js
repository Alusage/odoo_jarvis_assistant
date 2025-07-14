import { Component, xml } from "@odoo/owl";

export class CommitHistory extends Component {
  static template = xml`
    <div class="h-full overflow-y-auto">
      <div class="p-6 space-y-6">
        <!-- Commit Cards -->
        <div t-foreach="props.commits" t-as="commit" t-key="commit.id" class="commit-card">
          <div class="card p-6">
            <!-- Header -->
            <div class="flex items-start justify-between mb-4">
              <div class="flex items-center space-x-3">
                <img 
                  class="w-10 h-10 rounded-full border-2 border-gray-200"
                  t-att-src="commit.author.avatar"
                  t-att-alt="commit.author.name"
                />
                <div>
                  <div class="font-medium text-gray-900" t-esc="commit.author.name"/>
                  <div class="text-sm text-gray-500" t-esc="commit.timestamp"/>
                </div>
              </div>
              
              <div class="flex items-center space-x-2">
                <span class="font-mono text-sm bg-gray-100 px-2 py-1 rounded" t-esc="commit.id"/>
                <div t-att-class="getCommitStatusClass(commit.status.build)">
                  <t t-esc="commit.status.build"/>
                </div>
              </div>
            </div>

            <!-- Branch Flow -->
            <div class="flex items-center space-x-4 mb-4">
              <div class="flex items-center space-x-2">
                <div t-att-class="getBranchClass(commit.branch.from)">
                  <t t-esc="commit.branch.from"/>
                </div>
                <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 8l4 4m0 0l-4 4m4-4H3"/>
                </svg>
                <div t-att-class="getBranchClass(commit.branch.to)">
                  <t t-esc="commit.branch.to"/>
                </div>
              </div>
            </div>

            <!-- Commit Message -->
            <div class="mb-4">
              <p class="text-gray-700 leading-relaxed" t-esc="commit.message"/>
            </div>

            <!-- Status and Testing -->
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-4">
                <div class="flex items-center space-x-2">
                  <span class="text-sm text-gray-500">Testing:</span>
                  <div t-att-class="getTestingStatusClass(commit.status.testing)">
                    <t t-esc="commit.status.testing"/>
                  </div>
                </div>
              </div>

              <div class="flex items-center space-x-2">
                <button class="btn-secondary btn-sm" t-on-click="() => this.connectToCommit(commit.id)">
                  Connect
                </button>
                <button class="btn-secondary btn-sm" t-on-click="() => this.rebuildCommit(commit.id)">
                  Rebuild
                </button>
                <button class="btn-secondary btn-sm" t-on-click="() => this.viewCommitLogs(commit.id)">
                  Logs
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Empty State -->
        <div t-if="props.commits.length === 0 &amp;&amp; !props.loading" class="text-center py-12">
          <svg class="w-12 h-12 mx-auto text-gray-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
          </svg>
          <p class="text-gray-500">No commit history available</p>
        </div>

        <!-- Loading State -->
        <div t-if="props.loading" class="text-center py-12">
          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-500 mx-auto mb-2"/>
          <p class="text-gray-600">Loading commit history...</p>
        </div>
      </div>
    </div>
  `;

  getCommitStatusClass(status) {
    const statusClasses = {
      'success': 'status-success',
      'running': 'status-info',
      'failed': 'status-error',
      'pending': 'status-warning'
    };
    return statusClasses[status] || 'status-info';
  }

  getTestingStatusClass(status) {
    const statusClasses = {
      'passed': 'status-success',
      'running': 'status-info',
      'failed': 'status-error',
      'pending': 'status-warning'
    };
    return statusClasses[status] || 'status-info';
  }

  getBranchClass(branch) {
    const branchClasses = {
      'master': 'bg-green-100 text-green-800',
      'main': 'bg-green-100 text-green-800',
      'staging': 'bg-yellow-100 text-yellow-800',
      'development': 'bg-blue-100 text-blue-800'
    };
    return branchClasses[branch] || 'bg-gray-100 text-gray-800';
  }

  connectToCommit(commitId) {
    console.log(`Connecting to commit ${commitId}...`);
  }

  rebuildCommit(commitId) {
    console.log(`Rebuilding commit ${commitId}...`);
  }

  viewCommitLogs(commitId) {
    console.log(`Viewing logs for commit ${commitId}...`);
  }
}