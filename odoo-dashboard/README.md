# Odoo Client Dashboard

A professional web dashboard application built with Owl.js and Tailwind CSS that replicates the Odoo.sh platform experience for managing Odoo client repositories.

## 🚀 Features

- **Real-time Client Monitoring**: Monitor all your Odoo clients in one dashboard
- **Health Diagnostics**: Comprehensive health checks for Docker, PostgreSQL, Odoo, and Traefik
- **Build Pipeline Management**: Track deployments and build history
- **Responsive Design**: Mobile-first design with desktop optimization
- **Modern UI**: Clean, professional interface matching Odoo.sh aesthetics

## 🛠️ Technology Stack

- **Frontend Framework**: [Owl.js](https://github.com/odoo/owl) (Odoo Web Library)
- **Styling**: [Tailwind CSS](https://tailwindcss.com)
- **Build Tool**: [Vite](https://vitejs.dev)
- **Package Manager**: npm

## 📋 Prerequisites

- Node.js 18+ 
- npm or yarn
- Access to the Odoo Alusage MCP server

## 🚀 Quick Start

1. **Install dependencies**:
   ```bash
   cd odoo-dashboard
   npm install
   ```

2. **Start development server**:
   ```bash
   npm run dev
   ```

3. **Open in browser**:
   Navigate to `http://localhost:3000`

## 📁 Project Structure

```
odoo-dashboard/
├── src/
│   ├── components/          # Owl.js components
│   │   ├── App.js          # Main application component
│   │   ├── Navbar.js       # Top navigation bar
│   │   ├── Sidebar.js      # Client navigation sidebar
│   │   ├── Dashboard.js    # Main dashboard view
│   │   ├── BuildCard.js    # Build status cards
│   │   └── ...
│   ├── templates/          # Owl.js XML templates
│   │   ├── app.xml
│   │   ├── navbar.xml
│   │   └── ...
│   ├── services/           # Data services
│   │   └── dataService.js  # API integration & mock data
│   ├── styles/             # CSS styles
│   │   └── main.css        # Tailwind CSS + custom styles
│   └── main.js             # Application entry point
├── public/                 # Static assets
├── package.json            # Dependencies and scripts
├── tailwind.config.js      # Tailwind configuration
├── vite.config.js          # Vite configuration
└── README.md
```

## 🎨 Design System

### Color Palette
- **Primary**: Purple gradient (#7D6CA8 to darker)
- **Success**: Green (#4CAF50)
- **Error**: Red (#F44336)
- **Warning**: Orange (#FF9800)
- **Info**: Blue (#2196F3)

### Typography
- **Font Family**: Inter (sans-serif), JetBrains Mono (monospace)
- **Headings**: font-semibold
- **Body**: font-normal

### Components
- **Cards**: Rounded with subtle shadows and hover effects
- **Buttons**: Multiple variants with transitions
- **Badges**: Status indicators with color coding
- **Forms**: Clean inputs with focus states

## 🔧 Available Scripts

- `npm run dev` - Start development server with hot reload
- `npm run build` - Build for production
- `npm run preview` - Preview production build
- `npm run lint` - Run ESLint
- `npm run lint:fix` - Fix ESLint issues automatically
- `npm run format` - Format code with Prettier

## 🔌 MCP Server Integration

The dashboard integrates with the existing MCP server for real client data:

### Endpoints Used:
- `GET /api/clients` - List all clients
- `GET /api/clients/:name` - Get client details
- `POST /api/clients/:name/diagnose` - Run health diagnostics
- `GET /api/clients/:name/commits` - Get commit history
- `GET /api/clients/:name/builds` - Get build history

### Mock Mode
By default, the dashboard runs in mock mode with sample data. To enable real MCP integration:

1. Ensure your MCP server is running
2. Update `dataService.js`:
   ```javascript
   this.mockMode = false; // Enable real API calls
   this.baseURL = 'http://your-mcp-server:port/api';
   ```

## 📱 Responsive Design

The dashboard is optimized for all screen sizes:

- **Mobile (< 768px)**: Single column, collapsed sidebar
- **Tablet (768px - 1024px)**: Two column grid, overlay sidebar
- **Desktop (> 1024px)**: Full layout with expanded sidebar

## 🎯 Key Components

### Navbar
- Project selector dropdown
- User menu with avatar
- Navigation tabs (Branches, Builds, Settings)

### Sidebar
- Client list with status indicators
- Environment grouping (Production, Staging, Development)
- Search/filter functionality
- Collapsible design

### Dashboard
- Tab navigation (History, Builds, Logs, Shell)
- Build pipeline visualization
- Commit history with status tracking
- Real-time health monitoring

### Build Cards
- Build status and duration
- Author information and timestamps
- Action buttons (Connect, View Logs)
- Progress indicators

## 🚀 Deployment

1. **Build for production**:
   ```bash
   npm run build
   ```

2. **Deploy static files**:
   The `dist/` folder contains all files needed for deployment to any static hosting service.

3. **Environment variables** (optional):
   ```bash
   # .env.production
   VITE_API_BASE_URL=https://your-mcp-server.com/api
   VITE_APP_TITLE=Odoo Client Dashboard
   ```

## 🧪 Development Tips

### Adding New Components
1. Create component file in `src/components/`
2. Create corresponding template in `src/templates/`
3. Import and register in parent component
4. Follow existing naming conventions

### Styling Guidelines
- Use Tailwind utility classes primarily
- Create component classes in `main.css` for reusable patterns
- Follow the established color palette
- Maintain consistent spacing (4px grid)

### Data Integration
- All API calls go through `dataService.js`
- Mock data is provided for development
- Error handling is built into all service methods

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is part of the Odoo Alusage client management system.

## 🆘 Support

For issues and questions:
1. Check the MCP server logs
2. Verify client container status
3. Review browser console for errors
4. Check network connectivity to MCP server

---

Built with ❤️ using Owl.js and Tailwind CSS