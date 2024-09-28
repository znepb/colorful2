local function findRecipe(item, recipies)
  for i, v in pairs(recipies) do

    if i == item then
      return v
    elseif item:match(i) then
      local dye = item:match(i)
      local output = {}

      local function format(item)
        if type(item) == "string" then
          return item:format(dye)
        else
          return item
        end
      end

      local function applyDye(t)
        local out = {}
        for i, v in pairs(t) do
          if type(v) == "table" then
            out[format(i)] = applyDye(v)
          else
            out[format(i)] = format(v)
          end
        end

        return out
      end

      return applyDye(v), dye
    end
  end
end

local function hasRecipeFor(item, recipies)
  local recipe = findRecipe(item, recipies)
  return recipe ~= nil
end

local function calculateCountAvailable(item, items, recipies)
  local recipe = findRecipe(item, recipies)
  if recipe.type == "shapeless" then
    local max = math.huge
    for i, v in pairs(recipe.ingredients) do
      local availableByCrafting = 0
      if recipies[i] then
        availableByCrafting = calculateCountAvailable(i, items, recipies)
      end
      max = math.min(max, math.floor((items[i] or 0) / v) + availableByCrafting)
    end
    return max * recipe.result
  elseif recipe.type == "concrete" then
    return calculateCountAvailable(recipe.ingredient, items, recipies)
  end
end

local function calculateCostPer(item, costs, recipies)
  local recipe = findRecipe(item, recipies)
  if recipe.type == "shapeless" then
    local cost = 0
    for i, v in pairs(recipe.ingredients) do
      if recipies[i] then
        cost = cost + calculateCostPer(i, costs, recipies) * v
      else
        cost = cost + (costs[i] * v)
      end
    end
    return cost / recipe.result
  elseif recipe.type == "concrete" then
    return calculateCostPer(recipe.ingredient, costs, recipies)
  end
end

local function calculateCounts(item, recipies)
  local recipe = findRecipe(item, recipies)
  if recipe.type == "shapeless" then
    local items = {}
    for i, v in pairs(recipe.ingredients) do
      if recipies[i] then
        local result = calculateCounts(i, recipies)
        for i, v in pairs(result) do
          items[i] = v
        end
      elseif items[i] then
        items[i] = items[i] + v
      else
        items[i] = v
      end
    end
    return items
  elseif recipe.type == "concrete" then
    return calculateCounts(recipe.ingredient, recipies)
  end
end

return {
  calculateCountAvailable = calculateCountAvailable,
  calculateCostPer = calculateCostPer,
  calculateCounts = calculateCounts,
  hasRecipeFor = hasRecipeFor,
  findRecipe = findRecipe
}