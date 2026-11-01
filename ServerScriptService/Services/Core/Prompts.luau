--!strict
-- Every ProximityPrompt in the game is created here, and only this module turns
-- prompts on or off. Each prompt has a rule; a refresh loop applies them:
--   * the item must be visible (attribute Visible ~= false)
--   * a Broken item shows ONLY its Repair prompt (Spec.Repair); a working item
--     never shows a Repair prompt
--   * Spec.Show() (optional) must return true, e.g. "hopper not full"
-- Prompts on the same part share one anchor attachment and the visible ones are
-- stacked with UIOffset in Spec.Order (lowest at the bottom), so they never draw
-- on top of each other. Keys within one machine must be distinct:
--   E main action · F hold-to-fill · R recipe · T on/off · G unload · Q repair
-- (Config.Prompts holds the keys, hold times and spacing.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Prompts = {}

export type Spec = {
	Name: string,
	Action: string,
	Object: string?,
	Key: Enum.KeyCode?,
	Hold: number?,
	Order: number?, -- stacking order (1 = bottom)
	Distance: number?,
	Repair: boolean?, -- only shown while the item is Broken
	Show: (() -> boolean)?,
	Trigger: (player: Player) -> (),
}

type Entry = { prompt: ProximityPrompt, spec: Spec, anchor: Attachment }

local registry: { [Model]: { Entry } } = {}

local function anchorFor(part: BasePart): Attachment
	local anchor = part:FindFirstChild("PromptAnchor") :: Attachment?
	if not anchor then
		local created = Instance.new("Attachment")
		created.Name = "PromptAnchor"
		created.Position = Vector3.new(0, part.Size.Y / 2 + Config.Prompts.AnchorLift, 0)
		created.Parent = part
		anchor = created
	end
	return anchor :: Attachment
end

-- Creates a prompt on `part` (inside `model`) and registers its rule.
function Prompts.Add(model: Model, part: BasePart, spec: Spec): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = spec.Name
	prompt.ActionText = spec.Action
	prompt.ObjectText = spec.Object or ""
	prompt.KeyboardKeyCode = spec.Key or Enum.KeyCode.E
	prompt.HoldDuration = spec.Hold or Config.Prompts.DefaultHold
	prompt.MaxActivationDistance = spec.Distance or Config.Prompts.Distance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	local anchor = anchorFor(part)
	prompt.Parent = anchor
	prompt.Triggered:Connect(spec.Trigger)
	registry[model] = registry[model] or {}
	table.insert(registry[model], { prompt = prompt, spec = spec, anchor = anchor })
	table.sort(registry[model], function(a, b)
		return (a.spec.Order or 1) < (b.spec.Order or 1)
	end)
	model.Destroying:Connect(function()
		registry[model] = nil
	end)
	return prompt
end

-- A registered prompt by name (for changing its text).
function Prompts.Get(model: Model, name: string): ProximityPrompt?
	for _, entry in registry[model] or {} do
		if entry.spec.Name == name then
			return entry.prompt
		end
	end
	return nil
end

local function shouldShow(model: Model, entry: Entry): boolean
	if model:GetAttribute("Visible") == false then
		return false
	end
	local broken = model:GetAttribute("Broken") == true
	if broken ~= (entry.spec.Repair == true) then
		return false
	end
	if entry.spec.Show then
		local ok, result = pcall(entry.spec.Show)
		return ok and result == true
	end
	return true
end

-- Applies every rule of one model (or all models) right now.
function Prompts.Refresh(model: Model?)
	local models = if model then { [model] = registry[model] } else registry
	for m, entries in models do
		local stackIndex: { [Attachment]: number } = {}
		for _, entry in entries :: { Entry } do
			local show = shouldShow(m, entry)
			if show then
				local i = (stackIndex[entry.anchor] or 0) + 1
				stackIndex[entry.anchor] = i
				entry.prompt.UIOffset = Vector2.new(0, -(i - 1) * Config.Prompts.StackSpacing)
			end
			if entry.prompt.Enabled ~= show then
				entry.prompt.Enabled = show
			end
		end
	end
end

-- Test helper: names of the prompts currently shown on a model, bottom first.
function Prompts.Visible(model: Model): { string }
	local names = {}
	for _, entry in registry[model] or {} do
		if entry.prompt.Enabled then
			table.insert(names, `{entry.spec.Name}[{entry.prompt.KeyboardKeyCode.Name}]`)
		end
	end
	return names
end

function Prompts.Init()
	task.spawn(function()
		while true do
			task.wait(Config.Prompts.RefreshInterval)
			local ok, err = pcall(Prompts.Refresh, nil)
			if not ok then
				warn(`[Prompts] {err}`)
			end
		end
	end)
end

return Prompts
