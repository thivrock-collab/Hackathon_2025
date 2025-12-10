const express = require('express');
const cors = require('cors');
const fs = require('fs').promises;
const yaml = require('js-yaml');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('.'));

// In-memory storage for pending requests (replace with DB in production)
let pendingRequests = [];
let auditLog = [];

// Load audit log from file
async function loadAuditLog() {
  try {
    const auditPath = path.join(__dirname, 'audit-log.json');
    const data = await fs.readFile(auditPath, 'utf8');
    auditLog = JSON.parse(data);
  } catch (error) {
    if (error.code !== 'ENOENT') {
      console.error('Error loading audit log:', error);
    }
    auditLog = [];
  }
}

// Save audit log to file
async function saveAuditLog() {
  try {
    const auditPath = path.join(__dirname, 'audit-log.json');
    await fs.writeFile(auditPath, JSON.stringify(auditLog, null, 2));
  } catch (error) {
    console.error('Error saving audit log:', error);
  }
}

// Load users.yml
async function loadUsers() {
  try {
    const usersPath = path.join(__dirname, 'users.yml');
    const fileContents = await fs.readFile(usersPath, 'utf8');
    return yaml.load(fileContents);
  } catch (error) {
    console.error('Error loading users.yml:', error);
    throw error;
  }
}

// Save users.yml
async function saveUsers(usersData) {
  try {
    const usersPath = path.join(__dirname, 'users.yml');
    const yamlStr = yaml.dump(usersData);
    await fs.writeFile(usersPath, yamlStr);
  } catch (error) {
    console.error('Error saving users.yml:', error);
    throw error;
  }
}

// Load roles.yml
async function loadRoles() {
  try {
    const rolesPath = path.join(__dirname, 'roles.yml');
    const fileContents = await fs.readFile(rolesPath, 'utf8');
    return yaml.load(fileContents);
  } catch (error) {
    console.error('Error loading roles.yml:', error);
    throw error;
  }
}

// API Routes

// Get pending requests
app.get('/api/pending-requests', async (req, res) => {
  try {
    res.json(pendingRequests);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch pending requests' });
  }
});

// Submit new access request
app.post('/api/request-access', async (req, res) => {
  try {
    const { username, role, justification, email } = req.body;

    if (!username || !role || !justification) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Validate role exists
    const roles = await loadRoles();
    if (!roles.roles || !roles.roles[role]) {
      return res.status(400).json({ error: 'Invalid role' });
    }

    // Create request
    const request = {
      id: Date.now().toString(),
      username,
      role,
      justification,
      email: email || '',
      status: 'pending',
      submittedAt: new Date().toISOString(),
      submittedBy: username
    };

    pendingRequests.push(request);

    // Add to audit log
    auditLog.push({
      timestamp: new Date().toISOString(),
      event: 'access_request_submitted',
      username,
      role,
      details: { justification }
    });
    await saveAuditLog();

    res.json({ success: true, requestId: request.id });
  } catch (error) {
    console.error('Error submitting request:', error);
    res.status(500).json({ error: 'Failed to submit request' });
  }
});

// Approve and provision access
app.post('/api/provision-access', async (req, res) => {
  try {
    const { requestId, username, role, adminUser } = req.body;

    if (!username || !role || !adminUser) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Load current users
    const usersData = await loadUsers();
    const roles = await loadRoles();

    // Validate role
    if (!roles.roles || !roles.roles[role]) {
      return res.status(400).json({ error: 'Invalid role' });
    }

    const roleConfig = roles.roles[role];
    const ttlDays = roleConfig.ttl_days || 90;

    // Calculate expiration
    const now = new Date();
    const expirationDate = new Date(now);
    expirationDate.setDate(expirationDate.getDate() + ttlDays);

    // Find or create user in users.yml
    if (!usersData.users) {
      usersData.users = [];
    }

    let userIndex = usersData.users.findIndex(u => u.username === username);

    if (userIndex === -1) {
      // Create new user
      usersData.users.push({
        username: username,
        name: username, // You might want to get this from request
        email: req.body.email || `${username}@company.com`,
        teams: [],
        current_roles: [role],
        status: 'active',
        mfa_enabled: false,
        last_provisioned: now.toISOString(),
        expiration_date: expirationDate.toISOString()
      });
    } else {
      // Update existing user
      usersData.users[userIndex].current_roles = [role];
      usersData.users[userIndex].status = 'active';
      usersData.users[userIndex].last_provisioned = now.toISOString();
      usersData.users[userIndex].expiration_date = expirationDate.toISOString();
    }

    // Save users.yml
    await saveUsers(usersData);

    // Remove from pending requests
    if (requestId) {
      pendingRequests = pendingRequests.filter(r => r.id !== requestId);
    }

    // Add to audit log
    auditLog.push({
      timestamp: now.toISOString(),
      event: 'access_provisioned',
      username,
      role,
      provisionedBy: adminUser,
      expiresAt: expirationDate.toISOString(),
      details: {
        ttlDays,
        requestId
      }
    });
    await saveAuditLog();

    res.json({
      success: true,
      message: 'Access provisioned successfully',
      expirationDate: expirationDate.toISOString()
    });
  } catch (error) {
    console.error('Error provisioning access:', error);
    res.status(500).json({ error: 'Failed to provision access', details: error.message });
  }
});

// Get audit log
app.get('/api/audit-log', async (req, res) => {
  try {
    res.json(auditLog);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch audit log' });
  }
});

// Get users
app.get('/api/users', async (req, res) => {
  try {
    const usersData = await loadUsers();
    res.json(usersData.users || []);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

// Get roles
app.get('/api/roles', async (req, res) => {
  try {
    const rolesData = await loadRoles();
    res.json(rolesData.roles || {});
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch roles' });
  }
});

// Deny request
app.post('/api/deny-request', async (req, res) => {
  try {
    const { requestId, adminUser, reason } = req.body;

    const request = pendingRequests.find(r => r.id === requestId);
    if (!request) {
      return res.status(404).json({ error: 'Request not found' });
    }

    // Add to audit log
    auditLog.push({
      timestamp: new Date().toISOString(),
      event: 'access_request_denied',
      username: request.username,
      role: request.role,
      deniedBy: adminUser,
      details: { reason }
    });
    await saveAuditLog();

    // Remove from pending
    pendingRequests = pendingRequests.filter(r => r.id !== requestId);

    res.json({ success: true, message: 'Request denied' });
  } catch (error) {
    console.error('Error denying request:', error);
    res.status(500).json({ error: 'Failed to deny request' });
  }
});

// Initialize server
async function startServer() {
  await loadAuditLog();

  app.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
    console.log(`API endpoints:`);
    console.log(`  GET  /api/pending-requests`);
    console.log(`  POST /api/request-access`);
    console.log(`  POST /api/provision-access`);
    console.log(`  POST /api/deny-request`);
    console.log(`  GET  /api/audit-log`);
    console.log(`  GET  /api/users`);
    console.log(`  GET  /api/roles`);
  });
}

startServer();
