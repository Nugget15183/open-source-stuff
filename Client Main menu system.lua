--this is a client localscript that loads and manages a main menu, data is retrieved from the server.

script.Parent:WaitForChild("loading").Visible = true

local stats = script.Parent:WaitForChild("main"):WaitForChild("stats")
local main = script.Parent.main:WaitForChild("main")

--DROPDOWN
local Dropdown = require(script:WaitForChild("GuiLib"):WaitForChild("Classes"):WaitForChild("Dropdown"))

local gamemodes = {
	"Extraction",
	"Test Area",
}

local gamemodeDropdown = Dropdown.Create(gamemodes, #gamemodes)

gamemodeDropdown.Button.AnchorPoint = Vector2.new(0.5,0.5)
gamemodeDropdown.Button.Position = UDim2.new(0.133, 0,0.769, 0)
gamemodeDropdown.Button.Size = UDim2.new(0, 200, 0, 50)
gamemodeDropdown.Button.Parent = main
--END DROPDOWN

local rep = game:GetService("ReplicatedStorage")

local remotesF = rep:WaitForChild("Remotes")

local joinRem = remotesF:WaitForChild("MatchmakingJoin")
local queueRem = remotesF:WaitForChild("MatchmakingQueue")

local plr = game.Players.LocalPlayer

local pf = main:WaitForChild("pf")
local mainstats = script.Parent.main:WaitForChild("stats")

local performance = mainstats:WaitForChild("performance")
local combatstats = mainstats:WaitForChild("combatRecord").container

local data = remotesF:WaitForChild("getprof"):InvokeServer()

script.Parent.loading.Visible = false

local s,e = false, nil
local sgui = game:GetService("StarterGui")
local content, isReady = game.Players:GetUserThumbnailAsync(plr.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
local toptab = script.Parent:WaitForChild("toptab")

local accuracy = (data.ShotsHit / data.ShotsTotal) * 100

local hours = math.floor(data.Playtime / 3600)
local minutes = math.floor((data.Playtime % 3600) / 60)

local winrate = (data.Extractions / data.TotalMatchesJoined) * 100

pf.user.Text = plr.Name
pf.pfp.Image = content
pf.level.Text = "Level "..data.Level

performance.Kills.TextLabel.Text = data.Kills
performance.Deaths.TextLabel.Text = data.Deaths
performance.KD.TextLabel.Text = string.format("%0.2f", data.Kills / data.Deaths)

if accuracy ~= accuracy then
	accuracy = "100"
end

performance.Accuracy.TextLabel.Text = string.format("%0.2f", accuracy).."%"

combatstats.Wins.val.Text = data.Extractions
combatstats.Matches.val.Text = data.TotalMatchesJoined
combatstats.Headshots.val.Text = data.Headshots

combatstats.Playtime.val.Text = string.format("%02dh:%02dm", hours, minutes)

if winrate ~= winrate then
	winrate = "100%"
end

combatstats.WinRate.val.Text = winrate

local selectedGamemode = "Extraction"
gamemodeDropdown.Changed:Connect(function(selectedOption)
	local gamemodeName = selectedOption.Label.Text
	selectedGamemode = gamemodeName
end)

main:WaitForChild("Matchmake").MouseButton1Click:Connect(function()
	joinRem:FireServer(selectedGamemode)
end)

queueRem.OnClientEvent:Connect(function(txt)--for callbacks
	main.Matchmake.status.Visible = true
	main.Matchmake.status.Text = txt
end)

repeat
	s,e = pcall(function()
		sgui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
	task.wait()
until s

remotesF:WaitForChild("getchar").OnClientInvoke = function()
	local finished = false

	local selected = {}
	local indices = {}

	local accessories = game.ReplicatedStorage:WaitForChild("accessories")
	local viewport = script.Parent.charcustomizer.ViewportFrame
	local rig = viewport.WorldModel:FindFirstChild("Rig")
	local humanoid = rig:FindFirstChildOfClass("Humanoid")

	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = rig
	end

	local function aSelect(folderName, index)
		local folder = accessories:FindFirstChild(folderName)
		if not folder then print("no folder") return end

		local list = folder:GetChildren()
		if #list == 0 then print("empty folder "..folderName) return end

		index = ((index - 1) % #list) + 1
		local inst = list[index]
		if not inst:IsA("Accessory") then print("handle not accessory") return end

		
		selected[folderName] = inst.Name
		indices[folderName] = index
		remotesF.weld:FireServer(folderName,inst.Name)
	end

	for _, folder in accessories:GetChildren() do
		if #folder:GetChildren() > 0 then
			local randomIndex = math.random(1, #folder:GetChildren())
			print("rand equipping",folder:GetChildren()[randomIndex]," on pos",folder.Name)
			aSelect(folder.Name, randomIndex)
		end
	end

	local charcustomizer = script.Parent.charcustomizer
	for _, folderUI in {charcustomizer.Legs, charcustomizer.Head, charcustomizer.Torso, charcustomizer.Arms} do
		local name = folderUI.Name
		local nextButton = folderUI.next
		local backButton = folderUI.back

		nextButton.MouseButton1Click:Connect(function()
			local current = indices[name] or 1
			aSelect(name, current + 1)
		end)

		backButton.MouseButton1Click:Connect(function()
			local current = indices[name] or 1
			aSelect(name, current - 1)
		end)
	end

	charcustomizer.finish.MouseButton1Click:Connect(function()
		finished = true
	end)

	charcustomizer.Visible = true

	repeat task.wait() until finished

	charcustomizer.Visible = false
	return selected
end

toptab:WaitForChild("Locker").MouseButton1Click:Connect(function()
	script.Parent.main.Visible = false
	script.Parent.locker.Visible = true
	script.Parent.options.Visible = false
end)

toptab:WaitForChild("Options").MouseButton1Click:Connect(function()
	script.Parent.options.Visible = true
	script.Parent.main.Visible = false
	script.Parent.locker.Visible = false
end)

toptab:WaitForChild("Main").MouseButton1Click:Connect(function()
	script.Parent.main.Visible = true
	script.Parent.locker.Visible = false
	script.Parent.options.Visible = false
end)

local bgColors = {
		Common = Color3.fromRGB(48, 48, 48),
		Uncommon = Color3.fromRGB(9, 181, 0),
		Rare = Color3.fromRGB(0, 120, 180),
		Epic = Color3.fromRGB(78, 0, 167),
		Legendary = Color3.fromRGB(155, 190, 0),
		Mythic = Color3.fromRGB()
}

local o = 19
local selected = nil
local selectedInst = nil

local function getBorderColor(col:Color3)
	return Color3.fromRGB(col.R + o, col.G + o, col.B + o)
end

function additemtoinv(itemdata)
	local uiItem = script.InventoryItem:Clone()

	local ishovering = false
	local rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" = itemdata.rarity or "Common"
	local itemname = itemdata.name
	local weight = itemdata.weight or 0
	local itemid = string.lower(itemdata.id)
	local count = itemdata.count or 1

	uiItem.Name = itemid
	uiItem.rarity.Text = rarity
	uiItem.itemname.Text = itemname
	uiItem.count.Text = count

	uiItem.BackgroundColor3 = bgColors[rarity]
	uiItem.UIStroke.Color = getBorderColor(bgColors[rarity])

	uiItem.Parent = script.Parent.locker.curinv

	uiItem.MouseButton1Click:Connect(function()
		selected = itemdata
		selectedInst = uiItem
	end)
end

for _,itemdata in data.Inventory do
	additemtoinv(itemdata)
end

for _, p in script.Parent.locker.stored:GetChildren() do
	if not p:IsA("TextButton") then continue end

	local slotIndex = tonumber(p.Name:match("%d+"))
	local slotData = data.stored[slotIndex]

	local function clearSlot()
		p.BackgroundColor3 = Color3.fromRGB(48, 48, 48)
		p.UIStroke.Color = Color3.fromRGB(67, 67, 67)
		p.additemlabel.Visible = true
		p.itemname.Visible = false
		p.rarity.Visible = false
		p.weight.Visible = false
	end

	p.MouseButton1Click:Connect(function()
		if not selected then 
			-- remove existing item from slot if clicked empty-handed
			if slotData then
				additemtoinv(slotData)
				remotesF.removeitem:FireServer(slotIndex)
				slotData = nil
				clearSlot()
			end
			return 
		end

		-- place selected item into slot
		slotData = selected
		remotesF.storeitem:FireServer(selected, slotIndex)

		p.BackgroundColor3 = bgColors[selected.rarity]
		p.UIStroke.Color = getBorderColor(bgColors[selected.rarity])
		p.additemlabel.Visible = false
		p.itemname.Text = selected.name
		p.itemname.Visible = true
		p.rarity.Text = selected.rarity
		p.rarity.Visible = true
		p.weight.Text = selected.weight
		p.weight.Visible = true

		selectedInst:Destroy()
		selected, selectedInst = nil, nil
	end)

	if slotData then
		p.BackgroundColor3 = bgColors[slotData.rarity]
		p.UIStroke.Color = getBorderColor(bgColors[slotData.rarity])
		p.additemlabel.Visible = false
		p.itemname.Text = slotData.name
		p.itemname.Visible = true
		p.rarity.Text = slotData.rarity
		p.rarity.Visible = true
		p.weight.Text = slotData.weight
		p.weight.Visible = true
	else
		clearSlot()
	end
end

toptab.Visible = true

local platform = game:GetService("UserInputService").PreferredInput
local keybinds = {}
local bindmap = require(rep:WaitForChild("Keybinds"))

if platform == Enum.PreferredInput.KeyboardAndMouse then
	keybinds = bindmap.PC
elseif platform == Enum.PreferredInput.Gamepad then
	keybinds = bindmap.CONSOLE
end

function isKeycode(obj)
	if typeof(obj) == "EnumItem" then
		return ({pcall(function()
			local x = Enum.KeyCode[obj.Name]
		end)})[1]
	else
		return false
	end
end

function getNextInput()
	local inpt = nil
	local c
	c = game:GetService('UserInputService').InputBegan:Connect(function(input,gpe)
		if input.KeyCode ~= Enum.KeyCode.Unknown then
			inpt = input.KeyCode
		else
			inpt = input.UserInputType
		end
		
		c:Disconnect()
	end)
	
	repeat task.wait() until inpt
	
	return inpt
end

local overrides = remotesF:WaitForChild("getOverrides"):InvokeServer()
for bindname, keycode in keybinds do
	local new = script.keybindItem:Clone()
	new.TextLabel.Text = bindname
	
	if overrides[bindname] then
		new.TextButton.Text = overrides[bindname]
	else
		new.TextButton.Text = keycode.Name
	end
	
	new.Parent = script.Parent.options.keybindsscroller
	
	new.TextButton.MouseButton1Click:Connect(function()
		new.TextButton.Text = "..."
		
		local newinpt = getNextInput()
		
		new.TextButton.Text = newinpt.Name
		remotesF.updtKeybinds:FireServer(bindname, tostring(newinpt.Name))
	end)
end
