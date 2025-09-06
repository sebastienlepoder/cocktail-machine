interface Bottle {
  id: string
  name: string
  level: number
  status: 'online' | 'offline'
}

interface BottleStatusProps {
  bottle: Bottle
}

export function BottleStatus({ bottle }: BottleStatusProps) {
  const getLevelColor = (level: number) => {
    if (level >= 60) return 'level-high'
    if (level >= 30) return 'level-medium'
    return 'level-low'
  }

  const getStatusIcon = (status: string) => {
    return status === 'online' ? '🟢' : '🔴'
  }

  return (
    <div className="bottle-card">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-white">{bottle.name}</h3>
        <div className="flex items-center gap-2">
          <span className="text-sm">{getStatusIcon(bottle.status)}</span>
          <span className={`text-sm font-medium status-${bottle.status}`}>
            {bottle.status}
          </span>
        </div>
      </div>
      
      <div className="space-y-2">
        <div className="flex justify-between text-sm text-gray-300">
          <span>Level</span>
          <span>{bottle.level}%</span>
        </div>
        
        <div className="level-indicator">
          <div 
            className={`level-fill ${getLevelColor(bottle.level)}`}
            style={{ width: `${bottle.level}%` }}
          />
        </div>
        
        {bottle.level < 20 && (
          <div className="mt-2 p-2 bg-red-900/50 border border-red-500/50 rounded-lg">
            <p className="text-xs text-red-200">⚠️ Low level - refill needed</p>
          </div>
        )}
      </div>
    </div>
  )
}
