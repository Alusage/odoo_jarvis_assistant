import { Component, xml } from "@odoo/owl";

export class CommitDialog extends Component {
  static template = xml`
    <div t-if="props.show" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div class="bg-white rounded-lg p-6 w-96 max-w-full mx-4">
        <h3 class="text-lg font-semibold mb-4">Commit Changes</h3>
        
        <div class="mb-4">
          <label class="block text-sm font-medium text-gray-700 mb-2">
            Commit Message
          </label>
          <textarea
            class="w-full p-3 border border-gray-300 rounded-lg resize-none focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
            rows="3"
            placeholder="Describe your changes..."
            t-model="props.commitMessage"
          />
        </div>
        
        <div class="flex justify-end space-x-3">
          <button 
            class="btn-secondary"
            t-on-click="props.onCancel"
          >
            Cancel
          </button>
          <button 
            class="btn-primary"
            t-on-click="props.onConfirm"
            t-att-disabled="!props.commitMessage.trim()"
          >
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3-3m0 0l-3 3m3-3v12"/>
            </svg>
            Commit
          </button>
        </div>
      </div>
    </div>
  `;

  static props = {
    show: { type: Boolean },
    commitMessage: { type: String },
    onCancel: { type: Function },
    onConfirm: { type: Function }
  };
}