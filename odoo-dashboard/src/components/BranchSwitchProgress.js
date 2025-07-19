import { Component, useState, onMounted, xml } from "@odoo/owl";

export class BranchSwitchProgress extends Component {
  static template = xml`
    <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div class="bg-white rounded-lg p-6 w-[600px] max-w-full mx-4 max-h-[80vh] overflow-y-auto">
        <div class="flex items-center justify-between mb-6">
          <h3 class="text-lg font-semibold text-gray-900">
            Switching to branch: <span class="text-primary-600" t-esc="props.targetBranch"/>
          </h3>
          <div t-if="state.completed" class="text-green-600">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
            </svg>
          </div>
          <div t-elif="state.failed" class="text-red-600">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </div>
          <div t-else="" class="animate-spin text-primary-600">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
            </svg>
          </div>
        </div>

        <!-- Progress Bar -->
        <div class="mb-6">
          <div class="flex justify-between text-sm text-gray-600 mb-2">
            <span>Progress</span>
            <span t-esc="getProgressText()"/>
          </div>
          <div class="w-full bg-gray-200 rounded-full h-2">
            <div 
              class="bg-primary-600 h-2 rounded-full transition-all duration-300"
              t-att-style="'width: ' + getProgressPercentage() + '%'"
            />
          </div>
        </div>

        <!-- Steps List -->
        <div class="space-y-3">
          <div 
            t-foreach="state.steps" 
            t-as="step" 
            t-key="step.step"
            class="flex items-start space-x-3 p-3 rounded-lg"
            t-att-class="getStepClass(step)"
          >
            <!-- Step Icon -->
            <div class="flex-shrink-0 mt-0.5">
              <div t-if="step.status === 'completed'" class="w-5 h-5 text-green-600">
                <svg fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"/>
                </svg>
              </div>
              <div t-elif="step.status === 'failed'" class="w-5 h-5 text-red-600">
                <svg fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"/>
                </svg>
              </div>
              <div t-elif="step.status === 'in_progress'" class="w-5 h-5 text-primary-600 animate-spin">
                <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                </svg>
              </div>
              <div t-elif="step.status === 'completed_with_warnings'" class="w-5 h-5 text-yellow-600">
                <svg fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"/>
                </svg>
              </div>
              <div t-else="" class="w-5 h-5 text-gray-400">
                <svg fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm0-2a6 6 0 100-12 6 6 0 000 12z"/>
                </svg>
              </div>
            </div>

            <!-- Step Content -->
            <div class="flex-1 min-w-0">
              <div class="flex items-center space-x-2">
                <span class="text-sm font-medium text-gray-900" t-esc="'Step ' + step.step"/>
                <span class="text-sm text-gray-600" t-esc="step.action"/>
              </div>
              <div t-if="step.details" class="text-sm text-gray-500 mt-1" t-esc="step.details"/>
            </div>
          </div>
        </div>

        <!-- Action Buttons -->
        <div class="flex justify-end space-x-3 mt-6 pt-4 border-t border-gray-200">
          <button 
            t-if="state.completed || state.failed"
            class="btn-secondary"
            t-on-click="props.onClose"
          >
            Close
          </button>
          <button 
            t-if="state.failed"
            class="btn-primary"
            t-on-click="retry"
          >
            Retry
          </button>
        </div>
      </div>
    </div>
  `;

  setup() {
    this.state = useState({
      steps: [],
      completed: false,
      failed: false
    });

    onMounted(() => {
      if (this.props.onMount) {
        this.props.onMount(this);
      }
      
      // Initialize with a starting step if no steps are provided
      if (this.state.steps.length === 0) {
        this.state.steps = [{
          step: 1,
          action: "Starting branch switch",
          status: "in_progress",
          details: "Initializing..."
        }];
      }
    });
  }

  getProgressPercentage() {
    if (this.state.steps.length === 0) return 0;
    
    const completedSteps = this.state.steps.filter(step => 
      step.status === 'completed' || step.status === 'completed_with_warnings'
    ).length;
    
    return Math.round((completedSteps / this.state.steps.length) * 100);
  }

  getProgressText() {
    const total = this.state.steps.length;
    const completed = this.state.steps.filter(step => 
      step.status === 'completed' || step.status === 'completed_with_warnings'
    ).length;
    
    if (total === 0) return "0/0";
    return `${completed}/${total}`;
  }

  getStepClass(step) {
    const baseClass = "transition-colors duration-200";
    
    switch (step.status) {
      case 'completed':
        return `${baseClass} bg-green-50 border border-green-200`;
      case 'completed_with_warnings':
        return `${baseClass} bg-yellow-50 border border-yellow-200`;
      case 'failed':
        return `${baseClass} bg-red-50 border border-red-200`;
      case 'in_progress':
        return `${baseClass} bg-blue-50 border border-blue-200`;
      default:
        return `${baseClass} bg-gray-50 border border-gray-200`;
    }
  }

  updateProgress(steps) {
    this.state.steps = steps;
    
    // Check if all steps are completed
    const hasInProgress = steps.some(step => step.status === 'in_progress');
    const hasFailed = steps.some(step => step.status === 'failed');
    
    if (!hasInProgress && !hasFailed && steps.length > 0) {
      this.state.completed = true;
      this.state.failed = false;
    } else if (hasFailed) {
      this.state.completed = false;
      this.state.failed = true;
    } else {
      this.state.completed = false;
      this.state.failed = false;
    }
  }

  updateStep(stepData) {
    // Update a specific step by step number
    const existingStepIndex = this.state.steps.findIndex(s => s.step === stepData.step);
    
    if (existingStepIndex !== -1) {
      // Update existing step
      this.state.steps[existingStepIndex] = stepData;
    } else {
      // Add new step
      this.state.steps.push(stepData);
      // Sort steps by step number
      this.state.steps.sort((a, b) => a.step - b.step);
    }
    
    // Update state flags
    this.updateStateFlags();
  }

  addStep(stepData) {
    // Add a new step to the end
    this.state.steps.push(stepData);
    this.updateStateFlags();
  }

  updateStateFlags() {
    // Check if all steps are completed
    const hasInProgress = this.state.steps.some(step => step.status === 'in_progress');
    const hasFailed = this.state.steps.some(step => step.status === 'failed');
    
    if (!hasInProgress && !hasFailed && this.state.steps.length > 0) {
      this.state.completed = true;
      this.state.failed = false;
    } else if (hasFailed) {
      this.state.completed = false;
      this.state.failed = true;
    } else {
      this.state.completed = false;
      this.state.failed = false;
    }
  }

  async retry() {
    this.state.steps = [];
    this.state.completed = false;
    this.state.failed = false;
    
    if (this.props.onRetry) {
      await this.props.onRetry();
    }
  }
}