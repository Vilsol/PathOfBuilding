#@ SimpleGraphic
-- Path of Building
--
-- Module: Launch
-- Program entry point; loads and runs the Main module within a protected environment
--

APP_NAME = "Path of Building"

SetWindowTitle(APP_NAME)
ConExecute("set vid_mode 8")
ConExecute("set vid_resizable 3")

launch = { }
SetMainObject(launch)

function launch:OnInit()
	-- This is the path to emmy_core.dll. The ?.dll at the end is intentional.
	package.cpath = package.cpath .. ';../.devbox/emmylua/?.so'
	-- package.cpath = package.cpath .. ";C:/Users/someuser/.vscode/extensions/tangzx.emmylua-0.3.28/debugger/emmy/windows/x86/?.dll"
	local dbg = require("emmy_core")
	-- This port must match the Visual Studio Code configuration. Default is 9966.
	dbg.tcpListen("localhost", 9966)
	-- Uncomment the next line if you want Path of Building to block until the debugger is attached
	-- dbg.waitIDE()

	self.devMode = false
	self.installedMode = false
	self.versionNumber = "?"
	self.versionBranch = "?"
	self.versionPlatform = "?"
	self.lastUpdateCheck = GetTime()
	self.subScripts = { }
	local firstRunFile = io.open("first.run", "r")
	if firstRunFile then
		firstRunFile:close()
		os.remove("first.run")
		-- This is a fresh installation
		-- Perform an immediate update to download the latest version
		ConClear()
		ConPrintf("Please wait while we complete installation...\n")
		local updateMode, errMsg = LoadModule("UpdateCheck")
		if not updateMode then
			self.updateErrMsg = errMsg
		elseif updateMode ~= "none" then
			self:ApplyUpdate(updateMode)
			return
		end
	end
	local xml = require("xml")
	local localManXML = xml.LoadXMLFile("manifest.xml") or xml.LoadXMLFile("../manifest.xml")
	if localManXML and localManXML[1].elem == "PoBVersion" then
		for _, node in ipairs(localManXML[1]) do
			if type(node) == "table" then
				if node.elem == "Version" then
					self.versionNumber = node.attrib.number
					self.versionBranch = node.attrib.branch
					self.versionPlatform = node.attrib.platform
				end
			end
		end
	end
	if localManXML and not self.versionBranch and not self.versionPlatform then
		-- Looks like a remote manifest, so we're probably running from a repository
		-- Enable dev mode to disable updates and set user path to be the script path
		self.devMode = true
	end
	local installedFile = io.open("installed.cfg", "r")
	if installedFile then
		self.installedMode = true
		installedFile:close()
	end
	RenderInit()
	ConPrintf("Loading main script...")
	local errMsg
	errMsg, self.main = PLoadModule("Modules/Main")
	if errMsg then
		self:ShowErrMsg("Error loading main script: %s", errMsg)
	elseif not self.main then
		self:ShowErrMsg("Error loading main script: no object returned")
	elseif self.main.Init then
		errMsg = PCall(self.main.Init, self.main)
		if errMsg then
			self:ShowErrMsg("In 'Init': %s", errMsg)
		end
	end

	if not self.devMode and not firstRunFile then
		-- Run a background update check if developer mode is off
		self:CheckForUpdate(true)
	end
end

function launch:CanExit()
	if self.main and self.main.CanExit and not self.promptMsg then
		local errMsg, ret = PCall(self.main.CanExit, self.main)
		if errMsg then
			self:ShowErrMsg("In 'CanExit': %s", errMsg)
			return false
		else
			return ret
		end
	end
	return true
end

function launch:OnExit()
	if self.main and self.main.Shutdown then
		PCall(self.main.Shutdown, self.main)
	end
end

function launch:OnFrame()
	if self.main then
		if self.main.OnFrame then
			local errMsg = PCall(self.main.OnFrame, self.main)
			if errMsg then
				self:ShowErrMsg("In 'OnFrame': %s", errMsg)
			end
		end
	end
	self.devModeAlt = self.devMode and IsKeyDown("ALT")
	SetDrawLayer(1000)
	SetViewport()
	if self.promptMsg then
		local r, g, b = unpack(self.promptCol)
		self:DrawPopup(r, g, b, "^0%s", self.promptMsg)
	end
	if self.doRestart then
		local screenW, screenH = GetScreenSize()
		SetDrawColor(0, 0, 0, 0.75)
		DrawImage(nil, 0, 0, screenW, screenH)
		SetDrawColor(1, 1, 1)
		DrawString(0, screenH/2, "CENTER", 24, "FIXED", self.doRestart)
		Restart()
	end
	if not self.devMode and (GetTime() - self.lastUpdateCheck) > 1000*60*60*12 then
		-- Do an update check every 12 hours if the user keeps the program open
		self:CheckForUpdate(true)
	end
end

function launch:OnKeyDown(key, doubleClick)
	if key == "F5" and self.devMode then
		self.doRestart = "Restarting..."
	elseif key == "F6" and self.devMode then
		local before = collectgarbage("count")
		collectgarbage("collect")
		ConPrintf("%dkB => %dkB", before, collectgarbage("count"))
	elseif key == "u" and IsKeyDown("CTRL") then
		if not self.devMode then
			self:CheckForUpdate()
		end
	elseif self.promptMsg then
		self:RunPromptFunc(key)
	else
		if self.main and self.main.OnKeyDown then
			local errMsg = PCall(self.main.OnKeyDown, self.main, key, doubleClick)
			if errMsg then
				self:ShowErrMsg("In 'OnKeyDown': %s", errMsg)
			end
		end
	end
end

function launch:OnKeyUp(key)
	if not self.promptMsg then
		if self.main and self.main.OnKeyUp then
			local errMsg = PCall(self.main.OnKeyUp, self.main, key)
			if errMsg then
				self:ShowErrMsg("In 'OnKeyUp': %s", errMsg)
			end
		end
	end
end

function launch:OnChar(key)
	if self.promptMsg then
		self:RunPromptFunc(key)
	else
		if self.main and self.main.OnChar then
			local errMsg = PCall(self.main.OnChar, self.main, key)
			if errMsg then
				self:ShowErrMsg("In 'OnChar': %s", errMsg)
			end
		end
	end
end

function launch:OnSubCall(func, ...)
	if func == "UpdateProgress" then
		self.updateProgress = string.format(...)
	end
	if _G[func] then
		return _G[func](...)
	end
end

function launch:OnSubError(id, errMsg)
	if self.subScripts[id].type == "UPDATE" then
		self:ShowErrMsg("In update thread: %s", errMsg)
		self.updateCheckRunning = false
	elseif self.subScripts[id].type == "DOWNLOAD" then
		local errMsg = PCall(self.subScripts[id].callback, nil, errMsg)
		if errMsg then
			self:ShowErrMsg("In download callback: %s", errMsg)
		end
	end
	self.subScripts[id] = nil
end

function launch:OnSubFinished(id, ...)
	if self.subScripts[id].type == "UPDATE" then
		self.updateAvailable, self.updateErrMsg = ...
		self.updateCheckRunning = false
		if self.updateCheckBackground and self.updateAvailable == "none" then
			self.updateAvailable = nil
		end
	elseif self.subScripts[id].type == "DOWNLOAD" then
		local errMsg = PCall(self.subScripts[id].callback, ...)
		if errMsg then
			self:ShowErrMsg("In download callback: %s", errMsg)
		end
	elseif self.subScripts[id].type == "CUSTOM" then
		if self.subScripts[id].callback then
			local errMsg = PCall(self.subScripts[id].callback, ...)
			if errMsg then
				self:ShowErrMsg("In subscript callback: %s", errMsg)
			end
		end
	end
	self.subScripts[id] = nil
end

function launch:RegisterSubScript(id, callback)
	if id then
		self.subScripts[id] = {
			type = "CUSTOM",
			callback = callback,
		}
	end
end

function launch:DownloadPage(url, callback, cookies)
	-- Download the given page in the background, and calls the provided callback function when done:
	-- callback(pageText, errMsg)
	local script = [[
		local url, cookies, connectionProtocol, proxyURL = ...
		ConPrintf("Downloading page at: %s", url)
		local curl = require("lcurl.safe")
		local page = ""
		local easy = curl.easy()
		easy:setopt_url(url)
		easy:setopt(curl.OPT_USERAGENT, "Path of Building/]]..self.versionNumber..[[")
		easy:setopt(curl.OPT_ACCEPT_ENCODING, "")
		if cookies then
			easy:setopt(curl.OPT_COOKIE, cookies)
		end
		if connectionProtocol then
			easy:setopt(curl.OPT_IPRESOLVE, connectionProtocol)
		end
		if proxyURL then
			easy:setopt(curl.OPT_PROXY, proxyURL)
		end
		easy:setopt_writefunction(function(data)
			page = page..data
			return true
		end)
		local _, error = easy:perform()
		local code = easy:getinfo(curl.INFO_RESPONSE_CODE)
		easy:close()
		local errMsg
		if error then
			errMsg = error:msg()
		elseif code ~= 200 then
			errMsg = "Response code: "..code
		elseif #page == 0 then
			errMsg = "No data returned"
		end
		ConPrintf("Download complete. Status: %s", errMsg or "OK")
		if errMsg then
			return nil, errMsg
		else
			return page
		end
	]]
	local id = LaunchSubScript(script, "", "ConPrintf", url, cookies, self.connectionProtocol, self.proxyURL)
	if id then
		self.subScripts[id] = {
			type = "DOWNLOAD",
			callback = callback
		}
	end
end

function launch:ApplyUpdate(mode)
	if mode == "basic" then
		-- Need to revert to the basic environment to fully apply the update
		LoadModule("UpdateApply", "Update/opFile.txt")
		SpawnProcess(GetRuntimePath()..'/Update', 'UpdateApply.lua Update/opFileRuntime.txt')
		Exit()
	elseif mode == "normal" then
		-- Update can be applied while normal environment is running
		LoadModule("UpdateApply", "Update/opFile.txt")
		Restart()
		self.doRestart = "Updating..."
	end
end

function launch:CheckForUpdate(inBackground)
	if self.updateCheckRunning then
		return
	end
	self.updateCheckBackground = inBackground
	self.updateMsg = "Initialising..."
	self.updateProgress = "Checking..."
	self.lastUpdateCheck = GetTime()
	local update = io.open("UpdateCheck.lua", "r")
	local id = LaunchSubScript(update:read("*a"), "GetScriptPath,GetRuntimePath,GetWorkDir,MakeDir", "ConPrintf,UpdateProgress", self.connectionProtocol, self.proxyURL)
	if id then
		self.subScripts[id] = {
			type = "UPDATE"
		}
		self.updateCheckRunning = true
	end
	update:close()
end

function launch:ShowPrompt(r, g, b, str, func)
	self.promptMsg = str
	self.promptCol = {r, g, b}
	self.promptFunc = func or function(key)
		if key == "RETURN" or key == "ESCAPE" then
			return true
		elseif key == "F5" then
			self.doRestart = "Restarting..."
			return true
		end
	end
end

function launch:ShowErrMsg(fmt, ...)
	if not self.promptMsg then
		self:ShowPrompt(1, 0, 0, "^1Error:\n\n^0" .. string.format(fmt, ...) .. "\n\nPress Enter/Escape to Dismiss, or F5 to restart the application.")
	end
end

function launch:RunPromptFunc(key)
	local curMsg = self.promptMsg
	local errMsg, ret = PCall(self.promptFunc, key)
	if errMsg then
		self:ShowErrMsg("In prompt func: %s", errMsg)
	elseif ret and self.promptMsg == curMsg then
		self.promptMsg = nil
	end
end

function launch:DrawPopup(r, g, b, fmt, ...)
	local screenW, screenH = GetScreenSize()
	SetDrawColor(0, 0, 0, 0.5)
	DrawImage(nil, 0, 0, screenW, screenH)
	local txt = string.format(fmt, ...)
	local w = DrawStringWidth(20, "VAR", txt) + 20
	local h = (#txt:gsub("[^\n]","") + 2) * 20
	local ox = (screenW - w) / 2
	local oy = (screenH - h) / 2
	SetDrawColor(1, 1, 1)
	DrawImage(nil, ox, oy, w, h)
	SetDrawColor(r, g, b)
	DrawImage(nil, ox + 2, oy + 2, w - 4, h - 4)
	SetDrawColor(1, 1, 1)
	DrawImage(nil, ox + 4, oy + 4, w - 8, h - 8)
	DrawString(0, oy + 10, "CENTER", 20, "VAR", txt)
end
