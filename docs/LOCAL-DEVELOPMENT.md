# Local Development Guide - Running Without Azure Keys

This guide shows how to run the application locally for development, including running without Azure credentials for frontend-only testing.

## Quick Start (No Azure Required for Frontend)

### Option 1: Frontend Only (No Azure Needed)

Test the frontend UI without connecting to Azure:

```bash
# Terminal 1 - Start API in demo mode (no Azure)
cd packages/api
npm run dev

# Terminal 2 - Start Frontend
cd packages/app
npm run dev

# Open: http://localhost:5173
```

The API will start without Azure credentials. SAS token generation will fail gracefully, but you can test the UI.

### Option 2: Full Stack with Azure (Requires Azure CLI)

Test the complete upload flow:

```bash
# 1. Authenticate with Azure
az login

# 2. Terminal 1 - Start API
cd packages/api
npm run dev

# 3. Terminal 2 - Start Frontend  
cd packages/app
npm run dev

# Open: http://localhost:5173
```

### Option 3: Using Workspace Commands (Recommended)

Run both services from the root:

```bash
# From packages/ directory

# Install dependencies
npm install

# Start both services concurrently
npm run dev

# API: http://localhost:3000
# Frontend: http://localhost:5173
```

### Option 4: Using Docker Compose

Run the full stack in containers:

```bash
# Set storage account (optional, can run without)
export AZURE_STORAGE_ACCOUNT_NAME=your-storage-account

# Start services
npm run docker:up:build

# API: http://localhost:3000
# Frontend: http://localhost:8080

# View logs
npm run docker:logs

# Stop
npm run docker:down
```

## Environment Setup

### API Environment (api/.env)

```env
NODE_ENV=development
PORT=3000
# AZURE_STORAGE_ACCOUNT_NAME=your-storage-account  # Optional for dev
FRONTEND_URL=http://localhost:5173
```

### Frontend Environment (app/.env)

```env
VITE_API_URL=http://localhost:3000
```

## Running Without Azure Credentials

You can develop and test the frontend **without** Azure credentials:

### What Works Without Azure:
- ✅ Frontend UI loads
- ✅ File selection
- ✅ UI components and styling
- ✅ CORS configuration
- ✅ API health endpoint
- ✅ API status endpoint

### What Requires Azure:
- ❌ SAS token generation (requires `az login`)
- ❌ File upload to storage
- ❌ Listing uploaded files

### Development Workflow:

1. **Frontend Development** - No Azure needed:
   ```bash
   cd app
   npm run dev
   ```

2. **API Development** - No Azure needed for basic endpoints:
   ```bash
   cd api
   npm run dev
   
   # Test endpoints that don't require Azure:
   curl http://localhost:3000/health        # ✅ Works
   curl http://localhost:3000/api/status    # ✅ Works
   ```

3. **Full Integration Testing** - Requires Azure:
   ```bash
   # Authenticate
   az login
   
   # Start both services
   cd packages
   npm run dev
   ```

## Testing Locally

### 1. Test API Health (No Azure Required)

```bash
curl http://localhost:3000/health
# Expected: {"status":"healthy","timestamp":"..."}

curl http://localhost:3000/api/status
# Expected: JSON with configuration info
```

### 2. Test SAS Token Generation (Requires Azure)

```bash
# Must be authenticated: az login

curl "http://localhost:3000/api/sas?container=upload&file=test.txt"
# Expected: {"url":"https://...blob.core.windows.net/...?sig=..."}
```

### 3. Test Frontend

1. Open http://localhost:5173
2. Click "Select File"
3. Choose a file
4. Click "Get SAS Token" (requires Azure)
5. Click "Upload" (requires Azure)

## Troubleshooting

### API Won't Start

**Check logs**:
```bash
# If using npm run dev
ps aux | grep tsx

# Check if port is in use
lsof -i :3000
```

**Solution**:
```bash
# Kill existing process
pkill -f "tsx watch server.ts"

# Restart
cd api
npm run dev
```

### "DefaultAzureCredential authentication failed"

This is **normal** if you haven't authenticated with Azure. The API will still start.

**For Frontend-Only Development**: Ignore this error.

**For Full Testing**: 
```bash
az login
az account show
```

### Frontend Can't Connect to API

**Check CORS**:
```bash
cat api/.env | grep FRONTEND_URL
# Should be: FRONTEND_URL=http://localhost:5173
```

**Check API is running**:
```bash
curl http://localhost:3000/health
```

### Port Already in Use

```bash
# Find and kill process
lsof -i :3000
kill <PID>

# Or kill all node processes
pkill -f node
```

## Development Tips

### 1. Use Workspace Commands

From the root directory:

```bash
# Start both services
npm run dev

# Build both
npm run build

# Type-check both
npm run check

# Lint both
npm run lint
```

### 2. Watch Mode

Both API and frontend support hot reload:

```bash
# API - Auto-restarts on file changes
cd api
npm run dev

# Frontend - Auto-refreshes on file changes
cd app
npm run dev
```

### 3. Test Without Storage Account

You can test most functionality without a real storage account:

```bash
# API will start, endpoints will work
# SAS generation will fail with helpful error messages
npm run dev:api

# Frontend will load, UI works
# Upload will fail gracefully
npm run dev:app
```

### 4. Use Docker for Isolated Testing

```bash
# Complete environment in containers
npm run docker:up:build

# No port conflicts
# Isolated from local Node processes
```

## Next Steps

### After Local Development

1. **Deploy to Azure**:
   ```bash
   npm run deploy
   ```

2. **View Production Logs**:
   ```bash
   npm run logs
   ```

3. **Test Production**:
   - Frontend will be at: `https://your-app.azurestaticapps.net`
   - API will be at: `https://your-api.azurecontainerapps.io`

## Common Development Scenarios

### Scenario 1: UI/UX Work

```bash
cd app
npm run dev
# Edit src/App.tsx, see changes instantly
# No Azure needed
```

### Scenario 2: API Logic (No Storage)

```bash
cd api
npm run dev
# Edit routes, test with curl
# No Azure needed for basic endpoints
```

### Scenario 3: Full Integration Test

```bash
az login
npm run dev
# Test complete upload flow
# File gets uploaded to Azure Storage
```

### Scenario 4: Docker Testing

```bash
npm run docker:up:build
# Test in production-like environment
# Both services isolated
```

## Environment Variables Reference

### API

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NODE_ENV` | No | `development` | Environment mode |
| `PORT` | No | `3000` | Server port |
| `AZURE_STORAGE_ACCOUNT_NAME` | For upload | - | Storage account name |
| `FRONTEND_URL` | No | `*` | CORS allowed origin |

### Frontend

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `VITE_API_URL` | Yes | `http://localhost:3000` | API endpoint URL |

## Summary

✅ **Can run without Azure** for frontend/UI development  
✅ **Can run without Azure** for API basic endpoints  
❌ **Need Azure** for SAS tokens and file upload  

**Recommended workflow**:
1. Develop frontend/UI → No Azure needed
2. Develop API logic → No Azure needed
3. Integration testing → Use `az login`
4. Deploy → Use `azd up`
