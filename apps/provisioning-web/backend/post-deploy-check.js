const http = require('http');
const https = require('https');
const { URL } = require('url');

/**
 * Check if a service is accessible at the given URL
 */
async function checkServiceHealth(url, timeout = 5000) {
  return new Promise((resolve) => {
    try {
      const parsedUrl = new URL(url);
      const client = parsedUrl.protocol === 'https:' ? https : http;
      
      const options = {
        hostname: parsedUrl.hostname,
        port: parsedUrl.port,
        path: parsedUrl.pathname,
        method: 'GET',
        timeout: timeout,
        rejectUnauthorized: false // Allow self-signed certificates
      };
      
      const req = client.request(options, (res) => {
        resolve({
          url,
          accessible: true,
          statusCode: res.statusCode,
          statusMessage: res.statusMessage
        });
      });
      
      req.on('error', (error) => {
        resolve({
          url,
          accessible: false,
          error: error.message
        });
      });
      
      req.on('timeout', () => {
        req.destroy();
        resolve({
          url,
          accessible: false,
          error: 'Request timeout'
        });
      });
      
      req.end();
    } catch (error) {
      resolve({
        url,
        accessible: false,
        error: error.message
      });
    }
  });
}

/**
 * Verify all services are accessible after deployment
 */
async function verifyDeployment(config) {
  const results = {
    timestamp: new Date().toISOString(),
    domain: config.domain || 'localhost',
    services: [],
    allHealthy: true,
    summary: ''
  };
  
  const domain = config.domain || 'localhost';
  
  // Define services to check
  const services = [
    {
      name: 'n8n',
      url: `https://${domain}:5678`,
      description: 'Workflow automation platform',
      critical: true
    },
    {
      name: 'Grafana',
      url: `http://${domain}:3000`,
      description: 'Monitoring dashboards',
      critical: true
    },
    {
      name: 'Stack Manager UI',
      url: `http://${domain}:3001`,
      description: 'Stack management interface',
      critical: true
    },
    {
      name: 'Stack Manager API',
      url: `http://${domain}:3002/api/health`,
      description: 'Stack management API',
      critical: true
    },
    {
      name: 'Prometheus',
      url: `http://${domain}:9090`,
      description: 'Metrics collection',
      critical: false
    },
    {
      name: 'GoTrue Auth',
      url: `http://${domain}:9999/health`,
      description: 'Authentication service',
      critical: false
    }
  ];
  
  // Check each service
  for (const service of services) {
    const result = await checkServiceHealth(service.url);
    
    const serviceResult = {
      ...service,
      ...result,
      healthy: result.accessible && result.statusCode < 400
    };
    
    results.services.push(serviceResult);
    
    if (service.critical && !serviceResult.healthy) {
      results.allHealthy = false;
    }
  }
  
  // Generate summary
  const healthyCount = results.services.filter(s => s.healthy).length;
  const totalCount = results.services.length;
  
  if (results.allHealthy) {
    results.summary = `All ${totalCount} services are healthy and accessible.`;
  } else {
    const criticalFailures = results.services.filter(s => s.critical && !s.healthy);
    if (criticalFailures.length > 0) {
      results.summary = `Critical services failed: ${criticalFailures.map(s => s.name).join(', ')}`;
    } else {
      results.summary = `${healthyCount}/${totalCount} services are healthy. Non-critical services may still be starting.`;
    }
  }
  
  return results;
}

/**
 * Wait for services to become healthy with retries
 */
async function waitForServices(config, maxAttempts = 30, delayMs = 10000) {
  console.log('Waiting for services to become healthy...');
  
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    console.log(`Health check attempt ${attempt}/${maxAttempts}`);
    
    const results = await verifyDeployment(config);
    
    if (results.allHealthy) {
      console.log('All services are healthy!');
      return results;
    }
    
    console.log(`Status: ${results.summary}`);
    
    if (attempt < maxAttempts) {
      console.log(`Waiting ${delayMs / 1000} seconds before next check...`);
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }
  
  // Final check
  const finalResults = await verifyDeployment(config);
  console.log('Max attempts reached. Final status:', finalResults.summary);
  return finalResults;
}

module.exports = {
  checkServiceHealth,
  verifyDeployment,
  waitForServices
};