// Backend API integration for React UI
// Connects to existing working backend endpoints

const API_BASE = window.location.origin;

// Helper to get CSRF token
async function getCsrfToken() {
  const response = await fetch('/api/csrf-token', {
    credentials: 'include'
  });
  const data = await response.json();
  return data.token;
}

// Snapshot API
export const snapshotAPI = {
  async list(deploymentId) {
    const response = await fetch(`/api/deployments/${deploymentId}/snapshots`, {
      credentials: 'include'
    });
    if (!response.ok) {
      throw new Error('Failed to list snapshots');
    }
    return response.json();
  },

  async rollback(deploymentId, snapshotId) {
    const response = await fetch(`/api/deployments/${deploymentId}/rollback`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': await getCsrfToken()
      },
      credentials: 'include',
      body: JSON.stringify({ snapshotId })
    });
    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.message || 'Rollback failed');
    }
    return response.json();
  }
};

// Deployment APIs
export const deploymentAPI = {
  // Start deployment using existing backend
  async start(config) {
    const response = await fetch(`${API_BASE}/api/deploy/start`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(config)
    });
    return response.json();
  },

  // Get deployment status
  async getStatus(deploymentId) {
    const response = await fetch(`${API_BASE}/api/deploy/status/${deploymentId}`);
    return response.json();
  },

  // Retry failed step
  async retryStep(deploymentId, stepId) {
    const response = await fetch(`${API_BASE}/api/deploy/${deploymentId}/retry/${stepId}`, {
      method: 'POST'
    });
    return response.json();
  },

  // Connect WebSocket for real-time updates
  connectWebSocket() {
    const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return new WebSocket(`${wsProtocol}//${window.location.host}/ws/deploy`);
  }
};

// Validation APIs
export const validationAPI = {
  // Validate domain
  async validateDomain(domain) {
    const response = await fetch(`${API_BASE}/api/validate/domain`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ domain })
    });
    return response.json();
  },

  // Validate Cloudflare credentials
  async validateCloudflare(credentials) {
    const response = await fetch(`${API_BASE}/api/validate/cloudflare`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(credentials)
    });
    return response.json();
  },

  // Check URL availability
  async checkUrl(url, edition) {
    const response = await fetch(`${API_BASE}/api/validate/url`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url, edition })
    });
    return response.json();
  }
};

// Export/Download APIs
export const exportAPI = {
  // Download deployment logs
  async downloadLogs(deploymentId, type = 'full') {
    const response = await fetch(`${API_BASE}/api/deployments/${deploymentId}/logs/download?type=${type}`, {
      credentials: 'include'
    });
    
    if (!response.ok) {
      throw new Error('Failed to download logs');
    }

    const contentDisposition = response.headers.get('content-disposition');
    const filenameMatch = contentDisposition?.match(/filename="(.+)"/);
    const filename = filenameMatch ? filenameMatch[1] : `deployment-logs-${deploymentId}.txt`;

    const blob = await response.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);
  },

  // Export configuration
  async exportConfig(config) {
    const blob = new Blob([JSON.stringify(config, null, 2)], { type: 'application/json' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `ai-stack-config-${new Date().toISOString().split('T')[0]}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);
  }
};

// DNS Check API
export const dnsAPI = {
  // Check DNS propagation
  async checkPropagation(domain) {
    const response = await fetch(`${API_BASE}/api/dns/check`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ domain })
    });
    return response.json();
  }
};

// Telemetry API
export const telemetryAPI = {
  // Get telemetry status
  async getStatus(deploymentId) {
    const response = await fetch(`${API_BASE}/api/deployments/${deploymentId}/telemetry`, {
      credentials: 'include'
    });
    if (!response.ok) {
      throw new Error('Failed to get telemetry status');
    }
    return response.json();
  }
};