interface Bottle {
  id: string
  name: string
  level: number
  status: 'online' | 'offline'
}

interface CocktailMenuProps {
  bottles: Bottle[]
}

interface Recipe {
  id: string
  name: string
  description: string
  ingredients: { bottleId: string; amount: number; name: string }[]
  emoji: string
}

const SAMPLE_RECIPES: Recipe[] = [
  {
    id: 'cosmopolitan',
    name: 'Cosmopolitan',
    description: 'Classic pink cocktail with cranberry and lime',
    emoji: '🍸',
    ingredients: [
      { bottleId: 'vodka', amount: 45, name: 'Vodka' },
      { bottleId: 'triple-sec', amount: 15, name: 'Triple Sec' },
    ]
  },
  {
    id: 'mojito',
    name: 'Virgin Mojito',
    description: 'Refreshing mint and lime mocktail',
    emoji: '🌿',
    ingredients: [
      { bottleId: 'rum', amount: 50, name: 'White Rum' },
    ]
  },
  {
    id: 'gin-tonic',
    name: 'Gin & Tonic',
    description: 'Classic British cocktail',
    emoji: '🍋',
    ingredients: [
      { bottleId: 'gin', amount: 50, name: 'Gin' },
    ]
  }
]

export function CocktailMenu({ bottles }: CocktailMenuProps) {
  const canMakeRecipe = (recipe: Recipe) => {
    return recipe.ingredients.every(ingredient => {
      const bottle = bottles.find(b => b.id === ingredient.bottleId)
      return bottle && bottle.status === 'online' && bottle.level > 10
    })
  }

  const handleOrderCocktail = (recipe: Recipe) => {
    // TODO: Implement MQTT message to start cocktail preparation
    console.log('Ordering:', recipe.name)
    alert(`Preparing ${recipe.name}... 🍹`)
  }

  return (
    <div className="glass-card p-6">
      <h2 className="text-2xl font-bold text-white mb-6">Cocktail Menu</h2>
      
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {SAMPLE_RECIPES.map((recipe) => {
          const available = canMakeRecipe(recipe)
          
          return (
            <div 
              key={recipe.id} 
              className={`p-4 rounded-lg border transition-all duration-200 ${
                available 
                  ? 'bg-white/10 border-white/30 hover:bg-white/20 cursor-pointer' 
                  : 'bg-gray-900/50 border-gray-600/50 opacity-60'
              }`}
              onClick={available ? () => handleOrderCocktail(recipe) : undefined}
            >
              <div className="flex items-center gap-3 mb-3">
                <span className="text-2xl">{recipe.emoji}</span>
                <div>
                  <h3 className="font-bold text-white">{recipe.name}</h3>
                  <p className="text-xs text-gray-300">{recipe.description}</p>
                </div>
              </div>
              
              <div className="space-y-1 mb-3">
                {recipe.ingredients.map((ingredient, idx) => (
                  <div key={idx} className="text-xs text-gray-400 flex justify-between">
                    <span>{ingredient.name}</span>
                    <span>{ingredient.amount}ml</span>
                  </div>
                ))}
              </div>
              
              {available ? (
                <div className="text-xs text-green-400 font-medium">
                  ✅ Available
                </div>
              ) : (
                <div className="text-xs text-red-400">
                  ❌ Ingredients unavailable
                </div>
              )}
            </div>
          )
        })}
      </div>
      
      <div className="mt-6 p-4 bg-blue-900/30 border border-blue-500/30 rounded-lg">
        <p className="text-sm text-blue-200">
          💡 <strong>Tip:</strong> Click on available cocktails to start preparation. 
          Make sure all ingredient bottles are online and have sufficient liquid levels.
        </p>
      </div>
    </div>
  )
}
