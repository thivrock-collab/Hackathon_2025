# Quick Start Guide

## Start the Server

```bash
npm start
```

## Access the Portals

1. **User Request Portal**: http://localhost:3000/index-new.html
2. **Admin Console**: http://localhost:3000/admin-new.html

## Test the Complete Flow

### Step 1: Submit a Request (User Portal)

1. Open http://localhost:3000/index-new.html
2. Fill in:
   - Username: `test-user`
   - Email: `test@company.com`
   - Role: Select `devops-full` or any role from dropdown
   - Justification: `Testing the system`
3. Click "Submit Request"
4. You should see: "✅ Request submitted successfully!"

### Step 2: Approve Request (Admin Console)

1. Open http://localhost:3000/admin-new.html
2. Go to "📨 Pending Requests" tab (should be default)
3. You should see the request from `test-user`
4. Click "Approve" button
5. Confirm the prompt
6. You should see: "✅ Access provisioned for test-user!"

### Step 3: Verify Changes

1. **Check users.yml**:
   ```bash
   cat users.yml | grep test-user -A 10
   ```
   You should see the new user entry with:
   - Status: active
   - Current role
   - Expiration date

2. **Check audit log**:
   ```bash
   cat audit-log.json
   ```
   You should see two events:
   - `access_request_submitted`
   - `access_provisioned`

3. **Check User Directory Tab**:
   - Go to "👥 User Directory" tab in admin console
   - You should see `test-user` in the table

4. **Check Audit Log Tab**:
   - Go to "📋 Audit Log" tab
   - You should see all events

## Alternative Flow: Manual Provisioning

1. Open http://localhost:3000/admin-new.html
2. Go to "⚙️ Provision Access" tab
3. Enter:
   - Username: `manual-user`
   - Email: `manual@company.com`
   - Role: Select any role
4. Click "Provision Now"
5. Check users.yml - user should be added

## Troubleshooting

### Server not starting?
```bash
# Check if port 3000 is in use
lsof -i :3000

# If in use, kill the process or change port in server.js
```

### Dropdowns empty?
```bash
# Make sure these files exist:
ls -la roles.yml users.yml

# Check server logs for errors
```

### users.yml not updating?
```bash
# Check permissions
ls -la users.yml

# Make sure file is writable
chmod 644 users.yml
```

## Files Created/Modified

- `audit-log.json` - Created automatically on first request
- `users.yml` - Modified when access is provisioned
- Server console - Shows all API requests

## Stop the Server

Press `Ctrl+C` in the terminal where the server is running
