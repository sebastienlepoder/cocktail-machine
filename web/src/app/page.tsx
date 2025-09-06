'use client'

import { useState, useEffect } from 'react'
import { BottleStatus } from '@/components/BottleStatus'
import { CocktailMenu } from '@/components/CocktailMenu'
import { SystemStatus } from '@/components/SystemStatus'

export default function Dashboard() {
  const [bottles, setBottles] = useState([
    { id: 'vodka', name: 'Vodka', level: 75, status: 'online' },
    { id: 'rum', name: 'White Rum', level: 60, status: 'online' },
    { id: 'gin', name: 'Gin', level: 40, status: 'online' },
    { id: 'tequila', name: 'Tequila', level: 85, status: 'offline' },
    { id: 'whiskey', name: 'Whiskey', level: 20, status: 'online' },
    { id: 'triple-sec', name: 'Triple Sec', level: 90, status: 'online' },
  ])

  const [systemStatus, setSystemStatus] = useState({
    temperature: 22,
    connected: true,
    activeOrders: 2,
    totalBottles: bottles.length
  })

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="text-center mb-8">
        <h1 className="text-4xl font-bold text-white mb-2">
          🍹 Cocktail Machine Dashboard
        </h1>
        <p className="text-blue-200">
          Professional automated cocktail dispensing system
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* System Status */}
        <div className="lg:col-span-1">
          <SystemStatus status={systemStatus} />
        </div>

        {/* Bottle Grid */}
        <div className="lg:col-span-2">
          <h2 className="text-2xl font-bold text-white mb-4">Bottle Status</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {bottles.map((bottle) => (
              <BottleStatus key={bottle.id} bottle={bottle} />
            ))}
          </div>
        </div>

        {/* Cocktail Menu */}
        <div className="lg:col-span-3 mt-8">
          <CocktailMenu bottles={bottles} />
        </div>
      </div>
    </div>
  )
}
