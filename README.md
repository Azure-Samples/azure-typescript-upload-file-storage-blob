# Azure File Upload Application

Modern file upload application with secure, keyless Azure Blob Storage integration.

![Demo](docs/demo.gif)

## 🚀 Get Started in 2 Minutes

### 1. Open in GitHub Codespaces

Click the **Code** button above → **Codespaces** → **Create codespace on main**

### 2. Login to Azure

```bash
az login  
azd config set auth.useAzCliAuth true
```

Set up AZD to use Azure CLI auth. 

### 3. Deploy Everything

```bash
azd up
```

The deployment can take up to 10 minutes.

That's it! The command creates all Azure resources, configures security, and deploys your application to Azure.

**Your app will be live at:** The URL will be displayed after deployment completes.

## What Gets Deployed

```
┌─────────────────────────────────────────────────────────┐
│                     Azure Cloud                          │
│                                                           │
│  ┌──────────────────────┐     ┌────────────────────┐   │
│  │ Container App        │────▶│ Container App       │   │
│  │  (React Frontend)    │     │   (Fastify API)     │   │
│  └──────────────────────┘     └────────────────────┘   │
│                                        │                  │
│                                        ▼                  │
│                              ┌──────────────────┐        │
│                              │ Blob Storage     │        │
│                              └──────────────────┘        │
│                                                           │
│  🔒 Managed Identity + RBAC (no storage keys!)          │
└─────────────────────────────────────────────────────────┘
```

## ✨ Key Features

- ✅ **Keyless Authentication** - Managed identity with RBAC
- ✅ **User Delegation SAS Tokens** - Microsoft Entra ID-based security
- ✅ **One-Command Deploy** - `azd up` handles everything
- ✅ **Modern Stack** - React 18 + Fastify 5 + TypeScript
- ✅ **Container-Native** - Azure Container Apps

## 📚 Documentation

### Getting Started
- **[DEPLOYMENT.md](./DEPLOYMENT.md)** - Complete deployment guide
- **[QUICKSTART.md](./QUICKSTART.md)** - Quick command reference
- **[docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md)** - Local development guide

### Architecture & Design
- **[docs/FUNCTIONAL-SPEC.md](./docs/FUNCTIONAL-SPEC.md)** - Technical specification
- **[docs/SAS-TOKEN-ARCHITECTURE.md](./docs/SAS-TOKEN-ARCHITECTURE.md)** - Security architecture
- **[docs/DIAGRAMS.md](./docs/DIAGRAMS.md)** - Visual architecture diagrams
- **[docs/auth.md](./docs/auth.md)** - Authentication troubleshooting

## 🛠️ Local Development

Want to develop locally? See **[docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md)** for complete instructions.

Quick start:

```bash
# Install dependencies
npm install

# Start both API and frontend
npm run dev

# API: http://localhost:3000
# Frontend: http://localhost:5173
```

## 🏗️ Project Structure

```
├── azure.yaml                 # Azure Developer CLI configuration
├── infra/                     # Bicep infrastructure templates
├── docs/                      # Complete documentation
└── azure-upload-file-storage/
    ├── api/                   # Fastify API backend
    │   ├── src/
    │   │   ├── lib/           # Azure Storage integration
    │   │   └── routes/        # API endpoints
    │   └── tests/             # API tests
    └── app/                   # React frontend
        ├── src/
        │   ├── components/    # React components
        │   └── lib/           # Utilities
        └── public/            # Static assets
```

## 🔒 Security

- **No storage keys** - Uses managed identity + RBAC
- **User delegation SAS** - Microsoft Entra ID-based tokens
- **Expiration policy compliant** - Includes `startsOn` and `expiresOn`
- **CORS configured** - Proper origin validation
- **HTTPS enforced** - In production
- **Non-root containers** - Security best practices

## 🚀 Common Commands

| Command | Description |
|---------|-------------|
| `azd up` | Deploy everything to Azure |
| `npm run dev` | Run locally (API + frontend) |
| `npm run build` | Build both services |
| `npm run docker:up` | Run with Docker Compose |

See **[QUICKSTART.md](./QUICKSTART.md)** for all available commands.

## 📊 Key Technologies

**Backend:** Fastify 5, @azure/identity, @azure/storage-blob, TypeScript  
**Frontend:** React 18, Vite, Material-UI, TypeScript  
**Infrastructure:** Azure Container Apps, Blob Storage, Managed Identity

## 💡 Use Cases

Perfect for applications that need:
- Secure file uploads without managing storage keys
- Direct browser-to-storage uploads (no server proxy)
- Microsoft Entra ID-based security
- Scalable, serverless architecture
- Modern TypeScript development

## 🆘 Troubleshooting

**Deployment fails?**
- Ensure you're logged in: `azd auth login`
- Check Azure subscription: `az account show`

**Can't upload files?**
- Wait 5-10 minutes after first deployment (RBAC propagation)
- See **[docs/auth.md](./docs/auth.md)** for detailed troubleshooting

**Local development issues?**
- See **[docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md)** troubleshooting section

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
## 📝 License

MIT

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make changes
4. Run tests: `npm run check && npm run lint && npm run build`
5. Submit a pull request

---

**Ready to get started?** Open this repo in Codespaces, run `azd auth login`, then `azd up`. You'll have a working file upload app in minutes! 🎉