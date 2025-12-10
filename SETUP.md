# Landing Zone IAM System - Setup Guide

This guide will help you set up the complete end-to-end workflow for the Landing Zone IAM system with a local backend server.

## Features

- **User Request Portal**: Users can submit access requests through a web form
- **Admin Console**: Admins can approve/deny requests and provision access
- **Automatic User Management**: Users.yml is automatically updated when access is provisioned
- **Audit Logging**: All actions are logged in audit-log.json
- **Pending Requests**: Requests are stored and displayed in admin console
- **Dropdown Selection**: Admin can select users from pending requests or enter manually

## Prerequisites

- Node.js (v14 or higher)
- npm

## Installation

1. **Install Dependencies**

```bash
cd /home/saithivyah/Hackathon/landing-zone
npm install
```

2. **Start the Server**

```bash
npm start
```

The server will start on `http://localhost:3000`

## File Structure

```
landing-zone/
├── server.js                 # Backend API server
├── index-new.html           # User access request portal
├── admin-new.html           # Admin console
├── users.yml                # User directory (auto-updated)
├── roles.yml                # Role definitions
├── audit-log.json           # Audit trail (auto-created)
├── package.json             # Node.js dependencies
└── SETUP.md                 # This file
```

## Usage

### For Users Requesting Access

1. Open `http://localhost:3000/index-new.html` in your browser
2. Fill in the form:
   - **Username**: Your username
   - **Email**: Your email address
   - **Role**: Select from available roles
   - **Justification**: Explain why you need access
3. Click "Submit Request"
4. Your request will be sent to the admin console

### For Admins

1. Open `http://localhost:3000/admin-new.html` in your browser
2. The admin console has 4 tabs:

   **📨 Pending Requests Tab**
   - View all pending access requests
   - Click "Approve" to provision access
   - Click "Deny" to reject the request
   - Approved requests are automatically:
     - Added to users.yml
     - Removed from pending list
     - Logged in audit-log.json

   **⚙️ Provision Access Tab**
   - Select user from pending requests dropdown (auto-fills role and username)
   - OR enter username manually
   - Select role
   - Enter email (optional)
   - Click "Provision Now" to grant access

   **👥 User Directory Tab**
   - View all users from users.yml
   - See their current roles, status, and expiration dates

   **📋 Audit Log Tab**
   - View complete audit trail
   - Track all provisioning and request events

## How It Works

### 1. User Submits Request

```
User fills form → POST /api/request-access → Request stored in memory
                                            → Added to audit log
```

### 2. Admin Reviews Request

```
Admin opens console → GET /api/pending-requests → Displays all pending requests
```

### 3. Admin Approves Request

```
Admin clicks Approve → POST /api/provision-access → Updates users.yml
                                                   → Removes from pending
                                                   → Adds to audit log
                                                   → Returns expiration date
```

### 4. Admin Can Also Manually Provision

```
Admin selects/enters user → Selects role → POST /api/provision-access
                                         → Same flow as above
```

## API Endpoints

- `GET /api/roles` - Get all available roles
- `GET /api/users` - Get all users from users.yml
- `GET /api/pending-requests` - Get pending access requests
- `POST /api/request-access` - Submit new access request
- `POST /api/provision-access` - Approve and provision access
- `POST /api/deny-request` - Deny an access request
- `GET /api/audit-log` - Get complete audit trail

## Users.yml Structure

When access is provisioned, the user entry in users.yml is created or updated:

```yaml
users:
  - username: "john-doe"
    name: "john-doe"
    email: "john@company.com"
    teams: []
    current_roles:
      - "devops-full"
    status: "active"
    mfa_enabled: false
    last_provisioned: "2025-12-10T12:00:00.000Z"
    expiration_date: "2026-03-10T12:00:00.000Z"
```

## Audit Log Structure

All events are logged in `audit-log.json`:

```json
[
  {
    "timestamp": "2025-12-10T12:00:00.000Z",
    "event": "access_request_submitted",
    "username": "john-doe",
    "role": "devops-full",
    "details": {
      "justification": "Need to deploy new feature"
    }
  },
  {
    "timestamp": "2025-12-10T12:05:00.000Z",
    "event": "access_provisioned",
    "username": "john-doe",
    "role": "devops-full",
    "provisionedBy": "admin",
    "expiresAt": "2026-03-10T12:00:00.000Z",
    "details": {
      "ttlDays": 90,
      "requestId": "1234567890"
    }
  }
]
```

## Important Notes

1. **In-Memory Storage**: Pending requests are stored in memory. They will be lost if the server restarts. For production, use a database.

2. **Users.yml Updates**: The system directly updates users.yml when provisioning access. Make sure you have write permissions.

3. **No Authentication**: This demo doesn't include authentication. In production, add proper authentication for both portals.

4. **Port Configuration**: The server runs on port 3000 by default. Change `PORT` in server.js if needed.

5. **CORS**: CORS is enabled for local development. Configure appropriately for production.

## Troubleshooting

### Server won't start
- Make sure port 3000 is not in use
- Check that all dependencies are installed: `npm install`

### Dropdowns are empty
- Make sure `roles.yml` and `users.yml` exist in the same directory
- Check server console for errors

### Users.yml not updating
- Check file permissions
- Ensure the server has write access to the directory

### Pending requests disappear
- Pending requests are stored in memory
- They will be lost if you restart the server
- For persistence, implement database storage

## Production Deployment

For production use, consider:

1. **Database**: Replace in-memory storage with a database (PostgreSQL, MongoDB, etc.)
2. **Authentication**: Add OAuth/SAML for both portals
3. **Authorization**: Implement role-based access control
4. **HTTPS**: Use SSL/TLS certificates
5. **Environment Variables**: Use .env for configuration
6. **Logging**: Implement proper logging (Winston, Pino, etc.)
7. **Error Handling**: Add comprehensive error handling
8. **Rate Limiting**: Prevent abuse with rate limiting
9. **Backup**: Regular backups of users.yml and audit logs

## Next Steps

1. Start the server: `npm start`
2. Open user portal: `http://localhost:3000/index-new.html`
3. Submit a test request
4. Open admin console: `http://localhost:3000/admin-new.html`
5. Approve the request
6. Check `users.yml` and `audit-log.json` for updates

## Support

For issues or questions, refer to the main repository documentation.
