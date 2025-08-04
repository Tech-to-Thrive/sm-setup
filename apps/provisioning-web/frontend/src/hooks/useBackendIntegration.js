// Hook to integrate with existing backend APIs
import { useState, useEffect } from 'react'

export function useBackendIntegration() {
  const [validating, setValidating] = useState(false)
  const [csrfToken, setCsrfToken] = useState('')
  const [authToken, setAuthToken] = useState('')
  
  // Initialize security tokens
  useEffect(() => {
    // Get auth token from URL
    const urlParams = new URLSearchParams(window.location.search)
    const token = urlParams.get('token')
    if (token) {
      setAuthToken(token)
      sessionStorage.setItem('provisioningToken', token)
    } else {
      // Try to get from session storage
      const stored = sessionStorage.getItem('provisioningToken')
      if (stored) setAuthToken(stored)
    }

    // Fetch CSRF token
    fetch('/api/csrf-token', {
      credentials: 'include',
      headers: authToken ? { 'X-Setup-Token': authToken } : {}
    })
      .then(res => res.json())
      .then(data => setCsrfToken(data.token))
      .catch(err => console.error('Failed to get CSRF token:', err))
  }, [authToken])
  
  // Helper to get security headers
  const getSecureHeaders = () => ({
    'Content-Type': 'application/json',
    'X-CSRF-Token': csrfToken,
    'X-Setup-Token': authToken
  })
  
  // Real-time domain validation
  const validateDomain = async (domain) => {
    if (!domain) return { valid: false, message: '' }
    
    setValidating(true)
    try {
      const response = await fetch('/api/validate/domain', {
        method: 'POST',
        headers: getSecureHeaders(),
        credentials: 'include',
        body: JSON.stringify({ domain })
      })
      const result = await response.json()
      return result
    } catch (error) {
      return { valid: false, message: 'Validation failed' }
    } finally {
      setValidating(false)
    }
  }
  
  // Real-time URL validation with edition and SSL provider support
  const validateServiceUrl = async (url, service, edition, sslProvider) => {
    if (!url) return { valid: false, message: '' }
    
    try {
      const response = await fetch('/api/validate/service-url', {
        method: 'POST',
        headers: getSecureHeaders(),
        credentials: 'include',
        body: JSON.stringify({ url, service, edition, sslProvider })
      })
      const result = await response.json()
      return result
    } catch (error) {
      return { valid: false, message: 'Validation failed' }
    }
  }
  
  // Cloudflare validation
  const validateCloudflare = async (apiToken, zoneId, accountId = null) => {
    try {
      const response = await fetch('/api/validate/cloudflare', {
        method: 'POST',
        headers: getSecureHeaders(),
        credentials: 'include',
        body: JSON.stringify({ apiToken, zoneId, accountId })
      })
      const result = await response.json()
      return result
    } catch (error) {
      return { valid: false, message: 'Cloudflare validation failed' }
    }
  }
  
  // DNS propagation check
  const checkDnsPropagation = async (domains) => {
    try {
      const response = await fetch('/api/dns/check', {
        method: 'POST',
        headers: getSecureHeaders(),
        credentials: 'include',
        body: JSON.stringify({ domains })
      })
      const result = await response.json()
      return result
    } catch (error) {
      return { propagated: false, domains: {} }
    }
  }
  
  // Export configuration
  const exportConfiguration = async (config, format = 'json') => {
    try {
      const response = await fetch('/api/export/config', {
        method: 'POST',
        headers: getSecureHeaders(),
        credentials: 'include',
        body: JSON.stringify({ config, format })
      })
      
      if (format === 'json' || format === 'text') {
        const blob = await response.blob()
        const url = window.URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        a.download = `ai-stack-config-${new Date().toISOString().split('T')[0]}.${format}`
        document.body.appendChild(a)
        a.click()
        document.body.removeChild(a)
        window.URL.revokeObjectURL(url)
      } else if (format === 'print') {
        const text = await response.text()
        const printWindow = window.open('', '_blank')
        printWindow.document.write(`<pre>${text}</pre>`)
        printWindow.document.close()
        printWindow.print()
      }
    } catch (error) {
      console.error('Export failed:', error)
    }
  }
  
  return {
    validateDomain,
    validateServiceUrl,
    validateCloudflare,
    checkDnsPropagation,
    exportConfiguration,
    validating
  }
}