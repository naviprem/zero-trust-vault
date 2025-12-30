const express = require('express');
const morgan = require('morgan');
const helmet = require('helmet');
const jwt = require('jsonwebtoken');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(morgan('combined'));
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  const health = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV || 'production'
  };
  res.json(health);
});

// Helper function to extract user roles from JWT
function getUserRoles(authHeader) {
  try {
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return [];
    }

    const token = authHeader.split(' ')[1];
    // Decode without verification (OPA already validated it)
    const decoded = jwt.decode(token);

    return decoded?.realm_access?.roles || [];
  } catch (error) {
    console.error('Error decoding JWT:', error);
    return [];
  }
}

// API endpoints
app.get('/api/documents', (req, res) => {
  const clientIp = req.headers['x-forwarded-for'] || req.ip;
  console.log(`📄 Document access request from: ${clientIp}`);

  // All documents in the system
  const allDocuments = [
    { id: 1, name: 'Q4 Report.pdf', securityLevel: 'Public' },
    { id: 2, name: 'Employee Handbook.pdf', securityLevel: 'Public' },
    { id: 3, name: 'Salary Data.xlsx', securityLevel: 'Confidential' },
    { id: 4, name: 'Strategic Plan.docx', securityLevel: 'Confidential' }
  ];

  // Extract user roles from JWT token
  const userRoles = getUserRoles(req.headers.authorization);
  console.log(`   User roles: ${userRoles.join(', ')}`);

  // Filter documents based on user's role
  let filteredDocuments = allDocuments;

  if (userRoles.includes('manager')) {
    // Managers can see all documents
    console.log(`   Access level: MANAGER - showing all documents`);
    filteredDocuments = allDocuments;
  } else if (userRoles.includes('employee')) {
    // Employees can only see Public documents
    console.log(`   Access level: EMPLOYEE - filtering to Public documents only`);
    filteredDocuments = allDocuments.filter(doc => doc.securityLevel === 'Public');
  } else {
    // No recognized role - show nothing
    console.log(`   Access level: UNKNOWN - no documents available`);
    filteredDocuments = [];
  }

  res.json({
    documents: filteredDocuments,
    message: 'Document list retrieved successfully',
    documentCount: filteredDocuments.length
  });
});

app.get('/api/admin', (req, res) => {
  console.log(`🔐 Admin access request from: ${req.headers['x-forwarded-for'] || req.ip}`);

  res.json({
    message: 'Admin endpoint accessed successfully',
    timestamp: new Date().toISOString()
  });
});

// SPIFFE ID debug endpoint
app.get('/api/spiffe-debug', (req, res) => {
  // Check if request came through Envoy with mTLS
  const spiffeId = req.headers['x-forwarded-client-cert'];
  const tlsVersion = req.headers['x-forwarded-tls-version'];

  res.json({
    message: 'SPIFFE debug information',
    headers: {
      'x-forwarded-client-cert': spiffeId || 'Not present',
      'x-forwarded-tls-version': tlsVersion || 'Not present'
    },
    note: 'When accessed through Envoy with mTLS, additional headers will be present'
  });
});

// Error handling
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Startup
app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Zero Trust Backend listening on port ${PORT}`);
  console.log(`   Environment: ${process.env.NODE_ENV || 'production'}`);
  console.log(`   Ready to receive requests`);
});
