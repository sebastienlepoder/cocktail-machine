interface SystemStatusProps {
  status: {
    temperature: number
    connected: boolean
    activeOrders: number
    totalBottles: number
  }
}

export function SystemStatus({ status }: SystemStatusProps) {
  return (
    <div className="glass-card p-6">
      <h2 className="text-xl font-bold text-white mb-6">System Status</h2>
      
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <span className="text-gray-300">Connection</span>
          <div className="flex items-center gap-2">
            <span className="text-sm">
              {status.connected ? '🟢' : '🔴'}
            </span>
            <span className={`font-medium ${status.connected ? 'text-green-400' : 'text-red-400'}`}>
              {status.connected ? 'Online' : 'Offline'}
            </span>
          </div>
        </div>
        
        <div className="flex items-center justify-between">
          <span className="text-gray-300">Temperature</span>
          <span className="text-white font-medium">{status.temperature}°C</span>
        </div>
        
        <div className="flex items-center justify-between">
          <span className="text-gray-300">Active Orders</span>
          <span className="text-white font-medium">{status.activeOrders}</span>
        </div>
        
        <div className="flex items-center justify-between">
          <span className="text-gray-300">Total Bottles</span>
          <span className="text-white font-medium">{status.totalBottles}</span>
        </div>
        
        <div className="mt-6 pt-4 border-t border-white/20">
          <button className="w-full bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700 text-white font-medium py-2 px-4 rounded-lg transition-all duration-200">
            System Settings
          </button>
        </div>
      </div>
    </div>
  )
}
