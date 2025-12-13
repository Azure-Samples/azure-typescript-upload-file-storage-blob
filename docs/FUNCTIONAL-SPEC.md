# Functional Specification: Azure File Upload Application

## Overview

**Application Type**: Full-stack web application with RESTful API and Single Page Application (SPA) frontend

**Domain**: Secure cloud file upload and storage management

**Technology Stack**:
- **Backend**: Fastify v5, TypeScript, Node.js 22+
- **Frontend**: React 18, Vite, Material-UI v5
- **Cloud Platform**: Azure Container Apps, Azure Blob Storage
- **Authentication**: Microsoft Entra ID (formerly Azure AD) with Managed Identity
- **Infrastructure**: Azure Bicep with Azure Verified Modules (AVM)

**Core Capability**: Secure file upload to Azure Blob Storage using keyless authentication (Managed Identity) and User Delegation SAS tokens

## System Architecture

### High-Level Flow

```
User → Frontend (React) → API (Fastify) → Azure Blob Storage
                              ↓
                        Managed Identity
                              ↓
                    Microsoft Entra ID (RBAC)
```

### Component Breakdown

#### 1. Frontend (React SPA)
**Inputs**:
- User file selection via HTML file input
- Upload button click events
- List files request

**Outputs**:
- File upload UI with status messages
- List of uploaded files with image previews
- Error messages for failed operations

**Responsibilities**:
- Render file upload interface
- Request SAS token from API
- Upload file directly to Azure Blob Storage using SAS token
- Display uploaded files and error states

#### 2. Backend API (Fastify)
**Inputs**:
- HTTP GET `/api/sas?file={filename}&container={container}&permission={permissions}&timerange={minutes}`
- HTTP GET `/api/list?container={container}`
- HTTP GET `/api/status`
- HTTP GET `/health`

**Outputs**:
- JSON response with SAS token URL
- JSON response with list of blob names
- JSON response with storage account status
- Health check response

**Responsibilities**:
- Generate User Delegation SAS tokens using Managed Identity
- List blobs in specified container
- Verify storage account connectivity
- Enforce CORS policies
- Handle authentication with Azure Blob Storage

#### 3. Azure Blob Storage
**Inputs**:
- File upload requests with SAS tokens
- List blob requests from API
- User Delegation Key requests

**Outputs**:
- Stored blob data
- Blob metadata and lists
- User Delegation Keys for SAS token generation

**Responsibilities**:
- Store uploaded files
- Enforce RBAC permissions
- Validate SAS tokens
- Serve CORS preflight responses

## Data Model

### Blob Metadata Schema

| Field | Type | Description | Indexed | Required |
|-------|------|-------------|---------|----------|
| `name` | string | Blob file name (e.g., "photo.jpg") | Yes | Yes |
| `url` | string | Full URL to blob | No | Yes |
| `contentType` | string | MIME type (e.g., "image/jpeg") | No | No |
| `contentLength` | number | File size in bytes | No | No |
| `lastModified` | DateTime | Upload/modification timestamp | Yes | Yes |
| `etag` | string | Entity tag for concurrency control | No | Yes |

### SAS Token Schema

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `url` | string | Complete blob URL with SAS query parameters | Yes |

**SAS Query Parameters** (embedded in URL):
- `sv` - Storage service version (e.g., "2025-11-05")
- `st` - Start time (ISO 8601)
- `se` - Expiry time (ISO 8601)
- `skoid` - Signing key object ID
- `sktid` - Signing key tenant ID
- `skt` - Key start time
- `ske` - Key expiry time
- `sks` - Key service
- `skv` - Key version
- `sr` - Signed resource (b=blob)
- `sp` - Signed permissions (w=write, r=read)
- `sig` - Signature (base64-encoded HMAC-SHA256)

### File Upload Request Schema

```typescript
interface FileUploadRequest {
  file: File;              // Browser File object
  container: string;       // Target container name (default: "upload")
  permission: string;      // SAS permissions (default: "w")
  timerange: number;       // SAS validity in minutes (default: 10)
}
```

### Data Validation Requirements

- **File size**: Maximum 256KB enforced in frontend
- **Container name**: Lowercase alphanumeric with hyphens, 3-63 characters
- **File name**: Must be URL-safe (will be encoded)
- **SAS timerange**: 1-60 minutes (recommended: 10 minutes)
- **Permissions**: Valid values: r (read), w (write), d (delete), c (create)

## Azure Resources Required

### 1. Resource Group
**Purpose**: Logical container for all resources

**Configuration**:
- Naming: `rg-{environmentName}`
- Location: User-specified (e.g., `eastus2`)
- Tags: `azd-env-name: {environmentName}`

### 2. User-Assigned Managed Identity
**Purpose**: Keyless authentication for Container Apps

**Configuration**:
- Naming: `{prefix}-identity`
- RBAC Roles Assigned:
  - **Storage Blob Data Contributor** (`ba92f5b4-2d11-453d-a403-e96b0029c9fe`)
  - **Storage Blob Delegator** (`db58b8e5-c6ad-4a2a-8342-4190687cbf4a`)
  - **AcrPull** (`7f951dda-4ed3-4680-a7ca-43fe172d538d`)

**Required Outputs**:
- `principalId` - For role assignments
- `clientId` - For application configuration
- `resourceId` - For Container App assignment

### 3. Storage Account
**Purpose**: Blob storage for uploaded files

**Configuration**:
- SKU: `Standard_LRS`
- Kind: `StorageV2`
- Allow Blob Public Access: `true`
- Network ACLs: `defaultAction: Allow`, `bypass: AzureServices`
- Container: `upload` with `publicAccess: Blob`
- CORS Rules:
  - Allowed Origins: `*`
  - Allowed Methods: `GET, POST, PUT, DELETE, HEAD, OPTIONS`
  - Allowed Headers: `*`
  - Exposed Headers: `*`
  - Max Age: `86400` seconds (24 hours)

**Required Outputs**:
- `name` - Storage account name (for AZURE_STORAGE_ACCOUNT_NAME env var)
- `primaryEndpoints.blob` - Blob service endpoint

### 4. Container Registry (ACR)
**Purpose**: Store and serve container images

**Configuration**:
- SKU: `Basic`
- Admin User Enabled: `true`
- RBAC: Managed Identity has `AcrPull` role

**Required Outputs**:
- `loginServer` - For Docker push/pull operations
- `name` - Registry name

### 5. Log Analytics Workspace
**Purpose**: Centralized logging and monitoring

**Configuration**:
- Retention: Default (30 days)
- Used by Container Apps Environment

**Required Outputs**:
- `resourceId` - For Container Apps Environment configuration

### 6. Container Apps Environment
**Purpose**: Hosting platform for containers

**Configuration**:
- Zone Redundant: `false` (single availability zone)
- Connected to Log Analytics Workspace

**Required Outputs**:
- `resourceId` - For Container App deployment

### 7. API Container App
**Purpose**: Host Fastify API backend

**Configuration**:
- Replicas: Min 0, Max 1 (scale to zero enabled)
- Resources: 0.5 CPU, 1Gi memory
- Ingress: External, port 3000, HTTP/2
- Environment Variables:
  - `NODE_ENV=production`
  - `AZURE_STORAGE_ACCOUNT_NAME={storage.name}`
  - `AZURE_CLIENT_ID={managedIdentity.clientId}`
- Health Checks:
  - Liveness: `/health` every 30s
  - Readiness: `/health` every 10s

**Required Outputs**:
- `fqdn` - Fully qualified domain name
- `name` - Container app name

### 8. Web Container App
**Purpose**: Host React frontend

**Configuration**:
- Replicas: Min 1, Max 3 (always-on)
- Resources: 0.5 CPU, 1Gi memory
- Ingress: External, port 8080, HTTP/2
- Environment Variables:
  - `API_URL={apiApp.fqdn}`

**Required Outputs**:
- `fqdn` - Public URL for application
- `name` - Container app name

## Authentication

### Passwordless (Microsoft Entra ID) Implementation

#### Architecture
```
Container App → Managed Identity → Azure RBAC → Storage Account
```

#### Flow
1. Container App starts with User-Assigned Managed Identity configured
2. Application code uses `DefaultAzureCredential` from `@azure/identity`
3. Credential automatically discovers Managed Identity context
4. BlobServiceClient uses credential to authenticate
5. Azure validates identity has required RBAC roles
6. Application receives User Delegation Key
7. Application generates SAS token signed with User Delegation Key

#### Code Implementation (TypeScript)

```typescript
import { DefaultAzureCredential } from '@azure/identity';
import { BlobServiceClient } from '@azure/storage-blob';

const accountName = process.env.AZURE_STORAGE_ACCOUNT_NAME;
const credential = new DefaultAzureCredential({
  managedIdentityClientId: process.env.AZURE_CLIENT_ID
});

const blobServiceClient = new BlobServiceClient(
  `https://${accountName}.blob.core.windows.net`,
  credential
);
```

#### Required RBAC Roles

| Role | Purpose | Required For |
|------|---------|--------------|
| **Storage Blob Data Contributor** | Read, write, delete blobs | Listing blobs, verifying storage access |
| **Storage Blob Delegator** | Obtain user delegation keys | Generating SAS tokens |

#### Token Scopes
- Managed Identity uses system-assigned Azure scopes
- No explicit token refresh needed (SDK handles automatically)
- Tokens valid for duration of container session

### API Key Fallback (Not Used in This Implementation)

This application uses **passwordless-only** authentication. No connection strings or account keys are used.

## Core Workflows

### Workflow 1: File Upload

**User Story**: As a user, I want to upload a file to Azure Blob Storage securely.

**Step-by-Step Flow**:

1. **User selects file** (Frontend)
   - User clicks file input and selects local file
   - Frontend validates file size (max 256KB)
   - Frontend stores `File` object in state

2. **Request SAS token** (Frontend → API)
   - Frontend sends GET request: `/api/sas?file={filename}&container=upload&permission=w&timerange=10`
   - CORS preflight (OPTIONS) request sent first
   - API validates CORS origin against allowed list

3. **Generate SAS token** (API → Azure)
   - API extracts query parameters
   - API validates required parameters present
   - API creates `BlobServiceClient` with `DefaultAzureCredential`
   - API requests User Delegation Key from Azure (valid for 10 minutes)
   - Azure validates Managed Identity has `Storage Blob Delegator` role
   - API generates SAS token with `generateBlobSASQueryParameters`
   - API constructs full blob URL with SAS query string

4. **Return SAS URL** (API → Frontend)
   - API returns JSON: `{ url: "https://{account}.blob.core.windows.net/upload/{file}?{sas-params}" }`
   - Frontend stores SAS URL in state

5. **Upload file** (Frontend → Azure Storage)
   - Frontend converts `File` to `ArrayBuffer`
   - Frontend creates `BlockBlobClient` with SAS URL
   - Frontend calls `uploadData(arrayBuffer)`
   - Azure validates SAS token signature and expiration
   - Azure checks Managed Identity permissions
   - Blob is written to storage

6. **Confirm upload** (Frontend)
   - Frontend displays success message
   - Frontend triggers file list refresh

**Error Handling**:
- **File too large**: Frontend shows error, prevents upload
- **SAS generation fails**: API returns 500 with error details
- **Upload fails**: Frontend catches exception, displays error message
- **SAS expired**: Azure returns 403, frontend must request new token

### Workflow 2: List Files

**User Story**: As a user, I want to see all files I've uploaded.

**Step-by-Step Flow**:

1. **Request file list** (Frontend → API)
   - Frontend sends GET request: `/api/list?container=upload`

2. **List blobs** (API → Azure)
   - API creates `ContainerClient` with `DefaultAzureCredential`
   - API calls `listBlobsFlat()` iterator
   - Azure validates Managed Identity has `Storage Blob Data Contributor` role
   - Azure returns blob metadata (name, size, lastModified)

3. **Return file list** (API → Frontend)
   - API constructs array of blob URLs
   - API returns JSON: `{ list: ["https://...blob1", "https://...blob2"] }`

4. **Display files** (Frontend)
   - Frontend renders grid of images (for image files)
   - Frontend shows file names as fallback

**Error Handling**:
- **Container not found**: API returns empty list
- **Permission denied**: API returns 500 with RBAC error

### Workflow 3: Authentication Flow (Startup)

**User Story**: As a system, I need to verify I have correct permissions before accepting requests.

**Step-by-Step Flow**:

1. **Container App starts** (Azure)
   - Azure injects Managed Identity environment variables
   - Container runs `node dist/server.js`

2. **Verify permissions** (API startup)
   - API reads `AZURE_STORAGE_ACCOUNT_NAME` and `AZURE_CLIENT_ID` env vars
   - API calls `verifyStoragePermissions()` function
   - Test 1: Check storage account existence
   - Test 2: Request user delegation key (validates `Storage Blob Delegator` role)
   - Test 3: List blobs in container (validates `Storage Blob Data Contributor` role)

3. **Log results** (API)
   - Success: Log "✅ All storage permissions verified"
   - Failure: Log specific failing test with detailed error
   - Failure: Log Azure CLI commands to debug RBAC

4. **Start server** (API)
   - Register routes and CORS middleware
   - Listen on port 3000
   - Log startup message with environment info

**Error Handling**:
- **Missing env vars**: Log error, exit process
- **Permission verification fails**: Log warning, continue startup (allows debugging)
- **Port already in use**: Log error, exit process

## Application Entry Points

### API Server (`src/server.ts`)

**Purpose**: Start Fastify API server with routes and middleware

**Command**: `npm run dev` (development) or `npm start` (production)

**Required Environment Variables**:
- `AZURE_STORAGE_ACCOUNT_NAME` - Storage account name (e.g., "stv2daytfgtvjwm")
- `AZURE_CLIENT_ID` - Managed Identity client ID (optional, for explicit assignment)
- `WEB_URL` - Frontend URL for CORS (e.g., "https://app-xyz.azurecontainerapps.io")
- `PORT` - Server port (default: 3000)
- `NODE_ENV` - Environment mode (development/production)

**Routes Registered**:
- `GET /api/sas` - Generate SAS token
- `GET /api/list` - List files in container
- `GET /api/status` - Check storage account status
- `GET /health` - Health check endpoint

**Startup Sequence**:
1. Load environment variables
2. Create Fastify instance with logger
3. Register CORS middleware
4. Register routes
5. Verify storage permissions
6. Start listening on port 3000

### Frontend App (`src/App.tsx`)

**Purpose**: Render file upload UI and handle user interactions

**Command**: `npm run dev` (development) or `npm start` (production)

**Required Environment Variables**:
- `VITE_API_URL` - API base URL (e.g., "https://api-xyz.azurecontainerapps.io")

**User Interface Components**:
- File input selector
- "Get SAS Token" button
- "Upload File" button
- Upload status message display
- Uploaded files grid with image previews

**State Management**:
- `selectedFile` - Currently selected file
- `sasTokenUrl` - Generated SAS URL
- `uploadStatus` - Current upload status message
- `list` - Array of uploaded file URLs

## API Specifications

### Endpoint: `GET /api/sas`

**Purpose**: Generate User Delegation SAS token for blob upload

**Query Parameters**:
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `file` | string | Yes | - | Blob file name |
| `container` | string | No | `upload` | Target container name |
| `permission` | string | No | `w` | SAS permissions (r/w/d/c) |
| `timerange` | number | No | `10` | SAS validity in minutes |

**Success Response** (200):
```json
{
  "url": "https://{account}.blob.core.windows.net/{container}/{file}?sv=2025-11-05&st=2025-12-13T18%3A30%3A03Z&se=2025-12-13T18%3A40%3A03Z&..."
}
```

**Error Responses**:
- **400 Bad Request**: Missing required `file` parameter
  ```json
  { "error": "Missing required parameter: file" }
  ```
- **500 Internal Server Error**: Storage configuration missing or SAS generation failed
  ```json
  {
    "error": "Failed to generate SAS token",
    "details": "Error message from Azure SDK"
  }
  ```

**CORS Headers**:
- `Access-Control-Allow-Origin`: Configured origins or `*`
- `Access-Control-Allow-Methods`: `GET, POST, OPTIONS`
- `Access-Control-Allow-Credentials`: `true`

### Endpoint: `GET /api/list`

**Purpose**: List all blobs in specified container

**Query Parameters**:
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `container` | string | No | `upload` | Container to list |

**Success Response** (200):
```json
{
  "list": [
    "https://{account}.blob.core.windows.net/upload/photo1.jpg",
    "https://{account}.blob.core.windows.net/upload/document.pdf"
  ]
}
```

**Error Responses**:
- **500 Internal Server Error**: Storage configuration missing or list operation failed
  ```json
  {
    "error": "Failed to list files",
    "details": "Error message from Azure SDK"
  }
  ```

### Endpoint: `GET /api/status`

**Purpose**: Check storage account connectivity and configuration

**Success Response** (200):
```json
{
  "status": "ok",
  "accountName": "stv2daytfgtvjwm",
  "containerClient": "Available",
  "message": "Successfully connected to Azure Blob Storage"
}
```

**Error Response** (500):
```json
{
  "status": "error",
  "accountName": "stv2daytfgtvjwm",
  "message": "Error message from connection attempt"
}
```

### Endpoint: `GET /health`

**Purpose**: Health check for load balancers and monitoring

**Success Response** (200):
```json
{
  "status": "healthy",
  "timestamp": "2025-12-13T18:45:00.000Z"
}
```

## Environment Configuration

### Complete .env Template

```bash
# Azure Storage Configuration (REQUIRED)
AZURE_STORAGE_ACCOUNT_NAME=your-storage-account-name

# Azure Managed Identity (OPTIONAL - auto-detected in Azure)
AZURE_CLIENT_ID=your-managed-identity-client-id

# Frontend URL for CORS (REQUIRED for production)
WEB_URL=https://your-frontend-url.azurecontainerapps.io

# Server Configuration (OPTIONAL)
PORT=3000
NODE_ENV=development

# Frontend API URL (OPTIONAL - defaults to localhost:3000)
VITE_API_URL=http://localhost:3000
```

### Environment Variable Descriptions

| Variable | Required | Default | Description | Example |
|----------|----------|---------|-------------|---------|
| `AZURE_STORAGE_ACCOUNT_NAME` | **Yes** | - | Name of Azure Storage account | `stv2daytfgtvjwm` |
| `AZURE_CLIENT_ID` | No | Auto-detected | Managed Identity client ID | `419095a2-f637-4729-925a-460252bafc17` |
| `WEB_URL` | Production only | - | Frontend URL for CORS | `https://app-v2daytfgtvjwm.ashysky-63a05288.eastus2.azurecontainerapps.io` |
| `PORT` | No | `3000` | API server port | `3000` |
| `NODE_ENV` | No | `development` | Environment mode | `production` |
| `VITE_API_URL` | No | `http://localhost:3000` | API base URL for frontend | `https://api-v2daytfgtvjwm.ashysky-63a05288.eastus2.azurecontainerapps.io` |

### Validation Requirements

**Startup Validation**:
- `AZURE_STORAGE_ACCOUNT_NAME` must be set (process exits if missing)
- Storage account must be accessible (warning logged if not)
- Managed Identity must have required RBAC roles (warning logged if not)

**Runtime Validation**:
- File names must be URL-safe (encoded before use)
- Container names validated against Azure naming rules
- SAS timerange clamped to 1-60 minutes

### Local Development Configuration

For local development without Azure credentials:
```bash
# Minimal config for local development (API will start but uploads will fail)
AZURE_STORAGE_ACCOUNT_NAME=dummy-for-local-dev
WEB_URL=http://localhost:5173
```

For local development **with** Azure credentials:
```bash
# Run 'az login' first
AZURE_STORAGE_ACCOUNT_NAME=your-dev-storage-account
WEB_URL=http://localhost:5173
```

### Production Configuration

Managed via Azure Container Apps environment variables (set by Bicep):
```bicep
env: [
  { name: 'NODE_ENV', value: 'production' }
  { name: 'AZURE_STORAGE_ACCOUNT_NAME', value: storage.outputs.name }
  { name: 'AZURE_CLIENT_ID', value: managedIdentity.outputs.clientId }
]
```

Frontend URL passed from API Container App FQDN to Web Container App.

---

## Summary

This specification provides a **language-agnostic** blueprint for implementing a secure file upload system using Azure Blob Storage with keyless authentication. The design emphasizes:

1. **Security**: No storage keys, only Managed Identity and RBAC
2. **Scalability**: Container Apps with auto-scaling
3. **Developer Experience**: One-command deployment with `azd up`
4. **Observability**: Comprehensive logging and health checks
5. **Portability**: Can be implemented in any language supporting Azure SDKs

Developers can use this specification to recreate the solution in Python, C#, Java, or any other language by following the workflows and API contracts defined here.
