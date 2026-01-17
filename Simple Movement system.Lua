--this is in startercharacterscripts (underneath the players character in runtime)

local runservice = game:GetService("RunService")--needed for renderstepped
local replicatedStorage = game:GetService("ReplicatedStorage")--for accessing assets
local userinputservice = game:GetService("UserInputService")--for getting player input like shift for sprinting

--parent folders
local assets = replicatedStorage:WaitForChild("assets")--store things in subfolders inside of this parent assets folder
local modules = replicatedStorage:WaitForChild("modules")--keep replicatedstorage clean and put modules in a folder

--runtime accssed objects
local camera = workspace.Camera--camera for changing things like fov
local character = script.Parent--this script is a child of the character, so we can say script.parent
local player = game.Players.LocalPlayer--get the player so we can set max camera zoom distances

--we use WaitForChild because sometimes things arent fully loaded, and the client doesnt think it exists, so WaitForChild waits for it to exists, and doesnt let any further code run till it does
local humanoid:Humanoid = character:WaitForChild("Humanoid")--grab the humanoid of the character so we can change the walkspeed and jumpheight of the player
local animator:Animator = humanoid:WaitForChild("Animator")--get the animator for playing animations
local root = character:WaitForChild("HumanoidRootPart")--every rig has a humanoidrootpart, its good to use for reading position, velocity and rotation data.

--this will be an enum for the player state, enums are names assigned a number value for simplicity. it saves lines in comparison to using
--crouching = false
--sprinting = false
--walking = false, ect
--the player can only poses one of the listed states at a time.

local playerstates = {
	STANDING = 0;
	SPRINTING = 1;
	CROUCHED = 2;
	DEAD = 3;
}

local state = {--store variables in here to keep the global scope of the script clean
	--stored
	lastY = 0;--store lastY (last character y height) to check if the character is going up or down

	--all the values will be stored here while they get used in runtime:
	curFOV = 70;
	curWalkspeed = 16;
	playerstate = playerstates.STANDING;
	activeAnimationTrack = nil;--1. Nil is equal to nothing and is basically just a placeholder. 2. this variable will simply hold the active animation this script is using
	lastastaminausage = 0;--track the last stamina usage, so we know when to start regenerating it
	stamina = 100;--the current stamina the player has
	isFirstPerson = false;--check if we're in first person
	fallingfrom = 0;--track what height we're falling from
	wasFalling = false;--track wether we're falling or not 

	--settings
	--all the following values are used during the case that during their state is the current one; i.e walkspeed during regular walking, crouch_walkspeed during crouching, ect
	walkspeed = 16;--base walkspeed to use during regular walking
	crouch_walkspeed = 8;--walkspeed to be used during crouching
	sprint_walkspeed = 24;--walkspeed to be used whilst sprinting
	crouch_hip_height = -.5; --change hip height so the player can actually fit through smaller areas
	hip_height = 0;--normal hip height
	max_stamina = 100;--a base max stamina
	stamina_loss_rate = 1;--amount of stamina we loose while sprinting and performing other actions
	stamina_regen_timer = 5;--time in seconds after the last stamina usage that we start regenerating stamina
	base_jump_height = 7.2;--base jump height, variances can be + or - from this value
	jump_height_variance = .5;--difference in jump height

	--visual settings
	--things here are visual effects used during their case specified in their name, like above, sprint fov is used while sprinting
	fov = 70;--default fov
	sprint_fov = 120;
	crouch_fov = 60;
}

function lerp(start,stop, percent)
	--This is the lerp formula, a + (b - a) * t, it gets a number between the start and stop at the specified percent
	local epsilon = 0.01--an epsilon is a verry low, but NON-ZERO number
	--the epsilon is important for functions like this (lerp) that will never hit zero, especially in renderstepped usages. 

	local value = start + (stop - start) * percent
	--if the distance between the value and the stop is less then the epsilon, we round:

	local distance = math.abs(stop - value)--get the distance between the stop and the calculated value.

	if distance < epsilon then
		value = stop
	end

	return value--finnally, we return the value and move on.
end

function changeState(newstate)
	--first things first, this function will handle state swapping.
	--it will make sure you cant do things like go from sprinting to crouched, you must go to standing first

	local currentState = state.playerstate--retrieve the current playerstate

	if currentState == newstate then return end--dont allow the player to swap to the same state they currently exist in.

	if currentState == playerstates.SPRINTING and newstate == playerstates.CROUCHED then return end--dont allow the player to go from sprinting to crouched.

	--you would add more checks here for more cases, or perhaps make a table that would list invalid swaps.

	--here we actually apply the state,
	state.playerstate = newstate

	if state.activeAnimationTrack then
		state.activeAnimationTrack:Stop()--stop the current animation
	end
	
	local newtrack
	--loading the new animationtrack depending on what state the player is in
	if newstate == playerstates.CROUCHED then
		newtrack = animator:LoadAnimation(assets.animations.crouch)
	elseif newstate == playerstates.STANDING then
		newtrack = nil
	elseif newstate == playerstates.SPRINTING then
		newtrack = animator:LoadAnimation(assets.animations.sprint)
	end

	if newtrack then--newtrack may not exist if we are just standing (when we set it to nil)
		newtrack:Play()--start the new one and save it
	end

	state.activeAnimationTrack = newtrack--saving it
end

function randecimal(rawmin, rawmax, decimalplaces)
	--roblox has a built in math.random function, but that number only works with integers (whole numbers), so we must build off of that to make one that works with decimals
	--first we convert the minimum and maximum numbers to integers, decimal places is a power of 10 and we multiply the min and max both by that number to keep them similar

	local multiplier = 10^decimalplaces--power of 10

	local min = rawmin * multiplier
	local max = rawmax * multiplier

	--now we get our random number

	local result = math.random(min, max)

	--now we convert it back to a decimal

	local finalvalue = result / multiplier

	--by dividing by decimalplaces we undo the multiplying we did earlier,

	return finalvalue--now we send the value back to where we call it from
end

function returnToDefaultState(LerpPercent)--we make this a function because we use it in more places then one
	changeState(playerstates.STANDING)
	
	--reset fov, walkspeed and hipheight
	local targetFOV = state.fov
	camera.FieldOfView = lerp(camera.FieldOfView, targetFOV, LerpPercent)

	local targetWalkspeed = state.walkspeed
	humanoid.WalkSpeed = lerp(humanoid.WalkSpeed, targetWalkspeed, LerpPercent)
	
	local hipHeight = state.hip_height
	humanoid.HipHeight = lerp(humanoid.HipHeight, hipHeight, LerpPercent)
end

userinputservice.InputBegan:Connect(function(input, gpe)--when you PRESS a key this function fires
	if input.KeyCode == Enum.KeyCode.Space then--on player jump, note that this is before the gpe check, jumping takes roblox's gpe and makes it true.
		--in here, we add a small variance in jump height, nobody in real life can jump the exact same height twice.

		local randMin = state.base_jump_height - state.jump_height_variance
		local randMax = state.base_jump_height + state.jump_height_variance

		--now to get the value

		local newJumpHeight = randecimal(randMin, randMax, 1)--one decimal place (tenths)

		humanoid.JumpHeight = newJumpHeight
	end

	if gpe then return end--gpe stands for GameProcessedEvent. it is true when the player is doing something like typing. we dont want to take inputs if the player didnt mean to send them.
	--we should only take inputs when we know they are intentional, and not while the player is typing in chat

	if input.KeyCode == Enum.KeyCode.LeftShift then--input.Keycode is the key the player pressed. we check and confirm that they pressed the key we want with an equals statement, Enum.KeyCode.KEY
		changeState(playerstates.SPRINTING)
	elseif input.KeyCode == Enum.KeyCode.C then--check if the player pressed c
		if state.playerstate == playerstates.CROUCHED then--now we check if the player is already crouching, if so then stand back up
			changeState(playerstates.STANDING)
		else--if not crouched, then crouch.
			changeState(playerstates.CROUCHED)
		end
	end
	
	if input.KeyCode == Enum.KeyCode.V then
		state.isFirstPerson = not state.isFirstPerson--toggle between being in first person and not being in first person via a not, putting not before a bool flips it, from true -> false or false -> true
	end
end)

userinputservice.InputEnded:Connect(function(input, gpe)--when you RELEASE a key this function fires,
	--do NOT check for gpe this time, because players can simply open chat and that would bypass shutting off things like sprinting while letting go of shift

	--same method of checking keybinds before
	if input.KeyCode == Enum.KeyCode.LeftShift then
		changeState(playerstates.STANDING)--this time, we reset the state back to standing because you only want to be sprinting while you hold shift
	end
end)

runservice.RenderStepped:Connect(function(deltatime)
	--First, renderstepped runs just before each frame, so all the following code gets ran every frame, so we should try to keep it light.
	--Second, deltatime will be used for smoothing, deltatime is the amount of time between frames, it makes it so that if you run on low fps, then you still end up where you expect to be

	local SpeedMultiplier = 5--deltatime is a tiny number, and improving the percent by something like 0.0003 percent per frame is not verry quick, so we multiply.

	local LerpPercent = deltatime * SpeedMultiplier--deltatime * speedMultiplier is just the % we move by toward the target fov
	
	--define theese values so we only set them in one place instead of 3
	local newWalkspeed = state.walkspeed
	local newFOV = state.fov
	local newhipheight = state.hip_height

	if state.playerstate == playerstates.CROUCHED then
		local targetFOV = state.crouch_fov --the fov we wanna go toward
		newFOV = lerp(camera.FieldOfView, targetFOV, LerpPercent)--camera.FieldOfView is the current fov,

		local targetWalkspeed = state.crouch_walkspeed
		newWalkspeed = lerp(humanoid.WalkSpeed, targetWalkspeed, LerpPercent)

		local targetHipHeight = state.crouch_hip_height--find new hip height and save
		newhipheight = lerp(humanoid.HipHeight, targetHipHeight, LerpPercent)
	elseif state.playerstate == playerstates.SPRINTING then
		--first, math.clamp locks a number between a minimum and a maximum number.
		--so, we lock the new stamina between 0 and the max stamina
		state.stamina = math.clamp(state.stamina - state.stamina_loss_rate, 0, state.max_stamina)--consume stamina
		state.lastastaminausage = os.clock()--because we consumed stamina, we must set the stamina use time, otherwise we wont regenerate stamina at the appropriate time.

		if state.stamina == 0 then--if we are out of stamina, then reset
			returnToDefaultState(LerpPercent)
			return--do not run any further code
		end

		local targetFOV = state.sprint_fov --the fov we wanna go toward
		newFOV = lerp(camera.FieldOfView, targetFOV, LerpPercent)--camera.FieldOfView is the current fov,

		local targetWalkspeed = state.sprint_walkspeed --field of view while sprinting
		newWalkspeed = lerp(humanoid.WalkSpeed, targetWalkspeed, LerpPercent)
	else
		returnToDefaultState(LerpPercent)
	end

	if state.playerstate ~= playerstates.CROUCHED then
		local targetHipHeight = state.hip_height
		newhipheight = lerp(humanoid.HipHeight, targetHipHeight, LerpPercent)
	end

	--checking y height
	local yDiff = state.lastY - root.Position.Y--find the difference between the last y value and the new one

	if yDiff < 0 then--we are moving up, so slow walkspeed
		newWalkspeed -= 1--we use -= because that saves us from having to do: newWalkspeed = newWalkspeed - 4
		
		if state.wasFalling then
			local falldist = math.abs(state.fallingfrom - root.Position.Y)
			if falldist > 10 then --if we fall less then 10 studs, do nothing
				humanoid.Health -= falldist / 2--calculate damage to deal
			end
			state.wasFalling = false --reset state
		end
	else--moving down, so increase walkspeed
		newWalkspeed += 1--same principle from above, (operator)= works with all math operators
		
		if not state.wasFalling then
			state.wasFalling = true--set falling to true so that the next function call knows that we're falling
			state.fallingfrom = root.Position.Y--update the fallingfrom position, otherwise the falldist calculation will be off
		end
	end

	state.lastY = root.Position.Y

	--set the new values
	humanoid.WalkSpeed = newWalkspeed
	humanoid.HipHeight = newhipheight
	camera.FieldOfView = newFOV

	if state.lastastaminausage + state.stamina_regen_timer < os.clock() then--check if the endtime on that cooldown for finishing sprinting is over, if so, regenerate stamina.
		--regenerate stamina by twice the loss rate along with locking it between 0 and max stamina
		state.stamina = math.clamp(state.stamina + state.stamina_loss_rate * 2, 0, state.max_stamina)
	end
	
	if state.isFirstPerson then
		player.CameraMaxZoomDistance = 0.5--lock the player in first person
		player.CameraMinZoomDistance = 0.5
		
		local moveSpeed = humanoid.MoveDirection.Magnitude--how much the player is walking/running
		local newoffset = Vector3.new()
		if moveSpeed > 0 then--this line tells us if we are walking or running.
			--Headbob

			local xOffset, yOffset--the x and y offsets for the camera

			if state.playerstate == playerstates.SPRINTING then
				xOffset = math.sin(os.clock() * moveSpeed * 10) / 1.5
				yOffset = math.abs(math.sin(os.clock() * moveSpeed * 10)) 
			elseif state.playerstate == playerstates.CROUCHED then
				xOffset = math.sin(os.clock() * moveSpeed * 5) / 3
				yOffset =math.abs(math.sin(os.clock() * moveSpeed * 5)) / 2
			elseif state.playerstate == playerstates.STANDING then
				xOffset = math.sin(os.clock() * moveSpeed * 7) / 2.5
				yOffset = math.abs(math.sin(os.clock() * moveSpeed * 7)) / 1.5
			end

			--note that we dont use the z offset, thats because it looks really bad and its better for us to just do x and y
			newoffset = Vector3.new(xOffset, yOffset, -1)--a vector3 is a position in 3d space, it can also be used to store 3 values in one object, such as rotation or position.
		end

		--vector3's come with a buildin lerp function so we dont have to deal with that.
		local newheadbob = humanoid.CameraOffset:Lerp(newoffset, LerpPercent)--smooth to the new offset
		humanoid.CameraOffset = newheadbob

		for _,bp:Part in character:GetChildren() do--loop through all player body parts and make them visible
			if bp:IsA("BasePart") then--is the instance we found actually a part?
				if bp.Name ~= "Head" then--make sure its not the head, because we would only see hte head then
					bp.LocalTransparencyModifier = 0--set the transparency modifier to 0
				end
			end
		end
	else
		player.CameraMaxZoomDistance = 128--reset zoom distance if not in first person
		player.CameraMinZoomDistance = 12
	end
	
	if humanoid.Health <= 0 then--if the player is dead then set them to be dead
		state.playerstate = playerstates.DEAD
	end
	
	--lets make animations pause while standing still and play while moving
	if state.activeAnimationTrack then--is there a valid animation?
		if humanoid.MoveDirection.Magnitude > 0 then--is the player walking?
			state.activeAnimationTrack:AdjustSpeed(1)--play animation
		else
			state.activeAnimationTrack:AdjustSpeed(0)--pause animation
		end
	end
	
	print(state.playerstate)
end)
