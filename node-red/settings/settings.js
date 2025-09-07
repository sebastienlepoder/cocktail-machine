/**
 * Cocktail Machine - Node-RED Configuration
 * Production settings for Raspberry Pi deployment
 */

module.exports = {
    // Server settings
    uiPort: process.env.PORT || 1880,
    uiHost: '0.0.0.0',
    
    // Security
    httpAdminRoot: '/admin',
    httpNodeRoot: '/api',
    userDir: '/data',
    
    // Flow settings
    flowFile: 'flows.json',
    flowFilePretty: true,
    
    // Logging
    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        },
        file: {
            level: "info",
            filename: "/data/nodered.log",
            maxFiles: 5,
            maxSize: "10M"
        }
    },
    
    // Editor settings
    editorTheme: {
        projects: {
            enabled: false
        },
        page: {
            title: "Cocktail Machine - Node-RED",
            favicon: "🍹"
        },
        header: {
            title: "🍹 Cocktail Machine Control",
            url: "http://localhost"
        }
    },
    
    // Runtime settings
    runtimeState: {
        enabled: true,
        ui: true
    },
    
    // Function global context
    functionGlobalContext: {
        os: require('os'),
        fs: require('fs'),
        path: require('path'),
        mqtt: require('mqtt'),
        // Cocktail machine specific
        bottleStates: {},
        recipeQueue: [],
        systemStatus: {
            version: '1.0.0',
            uptime: new Date(),
            last_update_check: null
        }
    },
    
    // Export global context to HTTP endpoints
    exportGlobalContextKeys: false,
    
    // Context storage
    contextStorage: {
        default: "memoryOnly",
        memory: { module: 'memory' },
        file: { module: 'localfilesystem' }
    }
};
