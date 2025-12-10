# Azure File Upload Application v2

Modern file upload application with Fastify API backend and React frontend, deployed to Azure Container Apps and Static Web Apps.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Azure Cloud                          │
│                                                           │
│  ┌──────────────────────┐     ┌────────────────────┐   │
│  │ Azure Static Web App │────▶│ Azure Container App │   │
│  │  (React Frontend)    │     │   (Fastify API)     │   │
│  └──────────────────────┘     └────────────────────┘   │
│                                        │                  │
│                                        ▼                  │
│                              ┌──────────────────┐        │
│                              │ Azure Blob       │        │
│                              │ Storage          │        │
│                              └──────────────────┘        │
│                                                           │
│  🔒 Managed Identity + RBAC (no keys!)                   │
└─────────────────────────────────────────────────────────┘
```

## Features

- ✅ **Keyless Authentication** - Managed identity with RBAC (no storage keys)
- ✅ **User Delegation SAS Tokens** - Microsoft Entra ID-based, not account keys
- ✅ **SAS Expiration Policy** - Compliant with `startsOn` and `expiresOn`
- ✅ **Modern API** - Fastify v5 with TypeScript
- ✅ **Modern Frontend** - React 18 + Vite + Material-UI
- ✅ **Container-Native** - Docker + Docker Compose ready
- ✅ **One-Command Deploy** - Azure Developer CLI (`azd up`)

## 🚀 Quick Start

### Deploy to Azure (Easiest)

```bash
# One command to deploy everything to Azure
azd up

# That's it! The command will:
# ✅ Create all Azure resources
# ✅ Build and deploy API container
# ✅ Build and deploy frontend
# ✅ Configure managed identity and RBAC
# ✅ Create storage container
```

### Deploy to Azure (Manual Steps)

Use Azure CLI for authentication and let Azure Developer CLI know that. 

```bash
az login
azd config set auth.useAzCliAuth true
```

Begin deployment

```bash
azd up
```

### Run Locally (No Azure Credentials Required)

```bash
# Install dependencies
npm install

# Start both API and frontend
npm run dev

# API: http://localhost:3000
# Frontend: http://localhost:5173
```

**Note**: You can develop the frontend and test basic API endpoints **without Azure credentials**. For full file upload testing, run `az login` first.

See **[LOCAL-DEVELOPMENT.md](./azure-upload-file-storage/LOCAL-DEVELOPMENT.md)** for detailed instructions.

### Prerequisites

- **Node.js** 18+ and npm 9+
- **Azure CLI** (for deployment): `az --version`
- **Azure Developer CLI** (for deployment): `azd version`
- **Docker** (optional, for local container testing)

### Local Development

#### Option 1: Run Services Separately

```bash
# Terminal 1 - Start API
npm run dev:api

# Terminal 2 - Start Frontend
npm run dev:app

# API: http://localhost:3000
# Frontend: http://localhost:5173
```

#### Option 2: Run Both Services Concurrently

```bash
# Start both API and frontend together
npm run dev

# API: http://localhost:3000
# Frontend: http://localhost:5173
```

#### Option 3: Docker Compose (Full Environment)

```bash
# Build and start both services
npm run docker:up:build

# Or just start (if already built)
npm run docker:up

# API: http://localhost:3000
# Frontend: http://localhost:8080

# View logs
npm run docker:logs

# Stop services
npm run docker:down
```

### Build for Production

```bash
# Build both API and frontend
npm run build

# Or build individually
npm run build:api
npm run build:app
```

### Deploy to Azure

```bash
# One-command deployment (creates all resources)
npm run deploy

# Or use Azure Developer CLI directly
azd up
```

## Workspace Scripts

All commands can be run from the root directory:

### Installation & Setup

| Command | Description |
|---------|-------------|
| `npm install` | Install root dependencies |
| `npm run install:all` | Install all workspace dependencies |
| `npm run setup` | Run automated local dev setup |

### Development

| Command | Description |
|---------|-------------|
| `npm run dev` | Start both API and frontend in dev mode |
| `npm run dev:api` | Start API dev server only |
| `npm run dev:app` | Start frontend dev server only |

### Build

| Command | Description |
|---------|-------------|
| `npm run build` | Build both API and frontend |
| `npm run build:api` | Build API only |
| `npm run build:app` | Build frontend only |
| `npm run clean` | Clean all build artifacts |

### Start (Production Mode)

| Command | Description |
|---------|-------------|
| `npm run start` | Start both services in production mode |
| `npm run start:api` | Start API production server |
| `npm run start:app` | Start frontend production server |

### Testing

| Command | Description |
|---------|-------------|
| `npm run test:api` | Run API tests |
| `npm run test:app` | Run frontend tests |
| `npm run test:sas` | Test SAS token generation |
| `npm run check` | Type-check both workspaces |
| `npm run check:api` | Type-check API |
| `npm run check:app` | Type-check frontend |

### Code Quality

| Command | Description |
|---------|-------------|
| `npm run lint` | Lint both workspaces |
| `npm run lint:api` | Lint API code |
| `npm run lint:app` | Lint frontend code |
| `npm run format` | Format code with Prettier |
| `npm run format:api` | Format API code |
| `npm run format:app` | Format frontend code |

### Docker

| Command | Description |
|---------|-------------|
| `npm run docker:build` | Build Docker images |
| `npm run docker:up` | Start services with docker-compose |
| `npm run docker:up:build` | Build and start services |
| `npm run docker:down` | Stop services |
| `npm run docker:logs` | View all logs |
| `npm run docker:logs:api` | View API logs only |
| `npm run docker:logs:app` | View frontend logs only |
| `npm run docker:clean` | Remove containers, volumes, and images |

### Deployment

| Command | Description |
|---------|-------------|
| `npm run deploy` | Deploy all services to Azure |
| `npm run deploy:api` | Deploy API only |
| `npm run deploy:app` | Deploy frontend only |
| `npm run logs` | View Azure logs |
| `npm run logs:api` | View API logs from Azure |
| `npm run logs:app` | View frontend logs from Azure |

## Project Structure

```
azure-upload-file-storage/
├── package.json              # Root workspace configuration (this file)
├── docker-compose.yml        # Local development orchestration
├── DEPLOYMENT.md             # Azure deployment guide
├── README.md                 # This file
│
├── api/                      # Fastify API backend
│   ├── package.json          # API dependencies
│   ├── server.ts             # API entry point
│   ├── Dockerfile            # API container image
│   ├── src/
│   │   ├── lib/
│   │   │   └── azure-storage.ts
│   │   └── routes/
│   │       ├── sas.ts        # SAS token generation
│   │       ├── list.ts       # Blob listing
│   │       └── status.ts     # Status endpoint
│   ├── tests/
│   │   └── test-sas-generation.sh
│   ├── README.md             # API documentation
│   ├── CONFIGURATION.md      # Setup guide
│   ├── MIGRATION.md          # v1→v2 migration
│   ├── SAS-TOKENS.md         # User delegation guide
│   ├── QUICKSTART.md         # Quick reference
│   └── setup-local-dev.sh    # Automated setup
│
└── app/                      # React frontend
    ├── package.json          # Frontend dependencies
    ├── index.html            # HTML entry point
    ├── Dockerfile            # Frontend container image
    ├── nginx.conf            # nginx configuration
    ├── src/
    │   ├── App.tsx           # Main component
    │   ├── components/
    │   └── lib/
    ├── public/
    └── README.md             # Frontend documentation
```

## Environment Configuration

### API Configuration

Create `api/.env`:

```env
NODE_ENV=development
PORT=3000
AZURE_STORAGE_ACCOUNT_NAME=your-storage-account
FRONTEND_URL=http://localhost:5173
```

### Frontend Configuration

Create `app/.env`:

```env
VITE_API_URL=http://localhost:3000
```

## Common Workflows

### First-Time Setup

```bash
# 1. Install dependencies
npm install

# 2. Set up API environment
npm run setup

# 3. Start development
npm run dev
```

### Daily Development

```bash
# Start both services
npm run dev

# In another terminal, test SAS tokens
npm run test:sas
```

### Before Committing

```bash
# Type-check
npm run check

# Lint
npm run lint

# Format
npm run format

# Build
npm run build
```

### Deploy to Azure

```bash
# First time (creates all resources)
npm run deploy

# Subsequent deployments
npm run deploy

# View logs
npm run logs
```

## Testing End-to-End

### Local Testing

1. **Start services**:
   ```bash
   npm run dev
   ```

2. **Open frontend**: http://localhost:5173

3. **Test upload flow**:
   - Click "Select File"
   - Choose a file
   - Click "Get SAS Token"
   - Click "Upload"
   - File appears in grid

### Docker Testing

1. **Start with Docker Compose**:
   ```bash
   npm run docker:up:build
   ```

2. **Open frontend**: http://localhost:8080

3. **Test upload flow** (same as above)

4. **View logs**:
   ```bash
   npm run docker:logs
   ```

## 📚 Documentation

- **[QUICKSTART.md](./QUICKSTART.md)** - Quick reference for all commands ⭐
- **[LOCAL-DEVELOPMENT.md](./azure-upload-file-storage/LOCAL-DEVELOPMENT.md)** - Run locally without Azure ⭐
- **[DEPLOYMENT.md](./azure-upload-file-storage/DEPLOYMENT.md)** - Complete Azure deployment guide
- **[API README](./azure-upload-file-storage/api/README.md)** - API documentation
- **[API Configuration](./azure-upload-file-storage/api/CONFIGURATION.md)** - Setup guide
- **[API Migration](./azure-upload-file-storage/api/MIGRATION.md)** - v1→v2 migration
- **[SAS Tokens Guide](./azure-upload-file-storage/api/SAS-TOKENS.md)** - User delegation SAS
- **[Frontend README](./azure-upload-file-storage/app/README.md)** - Frontend documentation

## Troubleshooting

### "Cannot find module" errors

```bash
# Reinstall dependencies
npm run clean
npm run install:all
```

### API won't start

```bash
# Check Azure CLI authentication
az login
az account show

# Verify environment variables
cat api/.env
```

### Frontend can't connect to API

```bash
# Verify API is running
curl http://localhost:3000/health

# Check CORS configuration
cat api/.env | grep FRONTEND_URL
```

### Docker issues

```bash
# Clean everything
npm run docker:clean

# Rebuild
npm run docker:up:build
```

## Requirements

- **Node.js**: ≥18.0.0
- **npm**: ≥9.0.0
- **Azure CLI**: Latest version
- **Docker**: Latest version (for Docker workflows)
- **Azure Developer CLI**: Latest version (for deployment)

## Key Technologies

### Backend
- **Fastify** v5 - Fast Node.js web framework
- **@azure/identity** - Managed identity authentication
- **@azure/storage-blob** - Azure Blob Storage SDK
- **TypeScript** - Type safety

### Frontend
- **React** 18 - UI library
- **Vite** - Build tool and dev server
- **Material-UI** - Component library
- **TypeScript** - Type safety

### Infrastructure
- **Azure Container Apps** - API hosting
- **Azure Static Web Apps** - Frontend hosting
- **Azure Blob Storage** - File storage
- **Managed Identity** - Keyless authentication

## Security

- ✅ **No storage keys** - Uses managed identity + RBAC
- ✅ **User delegation SAS** - Microsoft Entra ID-based tokens
- ✅ **Expiration policy compliant** - Includes `startsOn` and `expiresOn`
- ✅ **CORS configured** - Not wildcard (`*`)
- ✅ **HTTPS enforced** - In production
- ✅ **Security headers** - nginx configuration
- ✅ **Non-root containers** - Both API and frontend

## Performance

- ⚡ **Fast builds** - Vite for frontend, TypeScript for API
- ⚡ **Code splitting** - Optimized bundles
- ⚡ **Caching** - Static assets cached for 1 year
- ⚡ **Compression** - gzip enabled in nginx
- ⚡ **Autoscaling** - Container Apps scale based on load

## License

MIT

## Support

For issues:
1. Check documentation in relevant README files
2. Review troubleshooting sections
3. Check Azure CLI authentication: `az account show`
4. Verify environment variables in `.env` files
5. Check logs: `npm run docker:logs` or `npm run logs`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes
4. Run `npm run check && npm run lint && npm run build`
5. Submit a pull request

## Version History

- **v2.0.0** - Fastify API + managed identity + user delegation SAS
- **v1.0.0** - Azure Functions + storage keys (deprecated)
