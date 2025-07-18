import { Component, useState, onMounted, xml } from "@odoo/owl";
import { dataService } from "../services/dataService.js";

export class CommitDetailsModal extends Component {
  static template = xml`
    <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50" t-on-click="closeModal">
      <div class="bg-white rounded-lg shadow-xl max-w-6xl w-full max-h-[90vh] overflow-hidden" t-on-click.stop="">
        <!-- Header -->
        <div class="bg-gray-50 border-b border-gray-200 px-6 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-4">
              <img 
                class="w-12 h-12 rounded-full border-2 border-gray-200"
                t-att-src="props.commit.author.avatar"
                t-att-alt="props.commit.author.name"
              />
              <div>
                <h2 class="text-xl font-semibold text-gray-900" t-esc="props.commit.message"/>
                <div class="flex items-center space-x-4 mt-1">
                  <span class="text-sm text-gray-600" t-esc="props.commit.author.name"/>
                  <span class="text-sm text-gray-500" t-esc="props.commit.timestamp"/>
                  <span class="font-mono text-sm bg-gray-100 px-2 py-1 rounded" t-esc="props.commit.hash"/>
                </div>
              </div>
            </div>
            <button 
              class="text-gray-400 hover:text-gray-600 focus:outline-none focus:text-gray-600"
              t-on-click="closeModal"
            >
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
              </svg>
            </button>
          </div>
        </div>

        <!-- Content -->
        <div class="overflow-y-auto" style="max-height: calc(90vh - 80px);">
          <!-- Commit Stats -->
          <div class="px-6 py-4 border-b border-gray-200">
            <div class="flex items-center space-x-6">
              <div class="text-sm">
                <span class="text-gray-500">Branch:</span>
                <span class="ml-2 font-medium" t-esc="props.commit.branch"/>
              </div>
              <div class="text-sm" t-if="state.commitDetails.stats">
                <span class="text-gray-500">Files changed:</span>
                <span class="ml-2 font-medium" t-esc="state.commitDetails.stats.files"/>
              </div>
              <div class="text-sm" t-if="state.commitDetails.stats">
                <span class="text-green-600">+<t t-esc="state.commitDetails.stats.insertions"/></span>
                <span class="text-red-600 ml-2">-<t t-esc="state.commitDetails.stats.deletions"/></span>
              </div>
            </div>
          </div>

          <!-- Loading State -->
          <div t-if="state.loading" class="px-6 py-12 text-center">
            <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-500 mx-auto mb-4"/>
            <p class="text-gray-600">Loading commit details...</p>
          </div>

          <!-- Error State -->
          <div t-if="state.error" class="px-6 py-12 text-center">
            <svg class="w-12 h-12 mx-auto text-red-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.99-.833-2.76 0L3.054 16.5c-.77.833.192 2.5 1.732 2.5z"/>
            </svg>
            <p class="text-red-600 mb-2">Error loading commit details</p>
            <p class="text-gray-500 text-sm" t-esc="state.error"/>
          </div>

          <!-- Diff Content -->
          <div t-if="!state.loading &amp;&amp; !state.error &amp;&amp; state.commitDetails.diff" class="px-6 py-4">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Changes</h3>
            
            <!-- File Changes -->
            <div class="space-y-4">
              <div t-foreach="state.commitDetails.files" t-as="file" t-key="file.filename" class="border border-gray-200 rounded-lg overflow-hidden">
                <!-- File Header -->
                <div class="bg-gray-50 px-4 py-3 border-b border-gray-200 cursor-pointer hover:bg-gray-100 transition-colors" 
                     t-on-click="() => this.toggleFileCollapse(file.filename)">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center space-x-3">
                      <svg t-if="!isFileCollapsed(file.filename)" class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
                      </svg>
                      <svg t-if="isFileCollapsed(file.filename)" class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
                      </svg>
                      <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                      </svg>
                      <span class="font-mono text-sm font-medium" t-esc="file.filename"/>
                    </div>
                    <div class="flex items-center space-x-2 text-sm">
                      <span class="text-green-600">+<t t-esc="file.additions"/></span>
                      <span class="text-red-600">-<t t-esc="file.deletions"/></span>
                    </div>
                  </div>
                </div>

                <!-- File Diff -->
                <div t-if="!isFileCollapsed(file.filename)" class="font-mono text-sm">
                  <div t-foreach="file.hunks" t-as="hunk" t-key="hunk_index" class="border-b border-gray-100 last:border-b-0">
                    <!-- Hunk Header -->
                    <div class="bg-blue-50 px-4 py-2 text-blue-800 border-b border-blue-100">
                      <t t-esc="hunk.header"/>
                    </div>
                    
                    <!-- Hunk Lines -->
                    <div class="divide-y divide-gray-100">
                      <div t-foreach="hunk.lines" t-as="line" t-key="line_index" 
                           t-att-class="getDiffLineClass(line.type)"
                           class="px-4 py-1 hover:bg-gray-50">
                        <div class="flex">
                          <span class="w-16 text-gray-400 text-right mr-4 select-none" t-esc="line.lineNumber"/>
                          <span class="flex-1" t-esc="line.content"/>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- No Changes -->
          <div t-if="!state.loading &amp;&amp; !state.error &amp;&amp; !state.commitDetails.diff" class="px-6 py-12 text-center">
            <svg class="w-12 h-12 mx-auto text-gray-400 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
            </svg>
            <p class="text-gray-500">No changes to display</p>
          </div>
        </div>

        <!-- Footer -->
        <div class="bg-gray-50 border-t border-gray-200 px-6 py-4">
          <div class="flex justify-end space-x-3">
            <button class="btn-secondary" t-on-click="closeModal">
              Close
            </button>
            <button class="btn-primary" t-on-click="copyCommitHash">
              <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
              </svg>
              Copy Hash
            </button>
          </div>
        </div>
      </div>
    </div>
  `;

  setup() {
    this.state = useState({
      loading: true,
      error: null,
      commitDetails: {
        diff: null,
        stats: null,
        files: []
      },
      collapsedFiles: new Set() // Track which files are collapsed
    });

    onMounted(() => {
      this.loadCommitDetails();
    });
  }

  async loadCommitDetails() {
    try {
      this.state.loading = true;
      this.state.error = null;

      const details = await dataService.getCommitDetails(
        this.props.client.name,
        this.props.commit.hash
      );

      this.state.commitDetails = details;
    } catch (error) {
      console.error('Error loading commit details:', error);
      this.state.error = error.message;
    } finally {
      this.state.loading = false;
    }
  }

  getDiffLineClass(lineType) {
    switch (lineType) {
      case 'added':
        return 'bg-green-50 border-l-4 border-green-400';
      case 'removed':
        return 'bg-red-50 border-l-4 border-red-400';
      case 'context':
        return 'bg-white';
      default:
        return 'bg-gray-50';
    }
  }

  closeModal() {
    this.props.onClose();
  }

  async copyCommitHash() {
    try {
      await navigator.clipboard.writeText(this.props.commit.hash);
      // TODO: Show success toast
      console.log('Commit hash copied to clipboard');
    } catch (error) {
      console.error('Error copying to clipboard:', error);
    }
  }

  toggleFileCollapse(filename) {
    if (this.state.collapsedFiles.has(filename)) {
      this.state.collapsedFiles.delete(filename);
    } else {
      this.state.collapsedFiles.add(filename);
    }
    // Force re-render by creating a new Set
    this.state.collapsedFiles = new Set(this.state.collapsedFiles);
  }

  isFileCollapsed(filename) {
    return this.state.collapsedFiles.has(filename);
  }
}